#include "capture_core.h"
#include <array>
#include <cerrno>
#include <fcntl.h>
#include <poll.h>
#include <stdexcept>
#include <unistd.h>
#include <utility>

namespace kujiequ::capture {
namespace {
uint16_t be16(const uint8_t* p) noexcept {
    return static_cast<uint16_t>((static_cast<uint16_t>(p[0]) << 8) | p[1]);
}
}
PacketInfo inspect(const uint8_t* p, size_t n) noexcept {
    PacketInfo info;
    if (!p || n < 1) return info;
    const uint8_t version = p[0] >> 4;
    size_t offset = 0, end = 0;
    uint8_t transport = 0;
    if (version == 4) {
        if (n < 20) return info;
        offset = (p[0] & 15) * 4;
        end = be16(p + 2);
        if (offset < 20 || offset > n || end < offset || end != n) return info;
        info.ipVersion = 4;
        if ((be16(p + 6) & 0x3FFF) != 0) {
            info.protocol = Protocol::Fragment;
            return info;
        }
        transport = p[9];
    } else if (version == 6) {
        if (n < 40 || be16(p + 4) == 0) return info; // No jumbograms.
        offset = 40;
        end = 40 + be16(p + 4);
        if (end != n) return info;
        info.ipVersion = 6;
        transport = p[6];
        // Extension headers are deliberately not parsed as TCP/UDP headers.
        if (transport == 44) { info.protocol = Protocol::Fragment; return info; }
    } else {
        return info;
    }
    const size_t remaining = end - offset;
    if (transport == 6) {
        if (remaining < 20) return info;
        const size_t tcpHeader = (p[offset + 12] >> 4) * 4;
        if (tcpHeader < 20 || tcpHeader > remaining) return info;
        info.protocol = Protocol::Tcp;
    } else if (transport == 17) {
        if (remaining < 8 || be16(p + offset + 4) != remaining) return info;
        info.protocol = Protocol::Udp;
    } else {
        info.protocol = Protocol::Unsupported;
        return info;
    }
    info.sourcePort = be16(p + offset);
    info.destinationPort = be16(p + offset + 2);
    return info;
}

PacketPump::PacketPump(int tunFd, Forward forward) : forward_(std::move(forward)) {
    if (tunFd < 0 || !forward_) throw std::invalid_argument("TUN fd and forwarder required");
    fd_ = fcntl(tunFd, F_DUPFD_CLOEXEC, 0);
    if (fd_ < 0) throw std::runtime_error("TUN descriptor duplication failed");
    if (pipe(wake_) != 0) { closeOwned(); throw std::runtime_error("Wake pipe failed"); }
    for (int fd : wake_) {
        if (fcntl(fd, F_SETFD, FD_CLOEXEC) != 0 || fcntl(fd, F_SETFL, O_NONBLOCK) != 0) {
            closeOwned(); throw std::runtime_error("Wake descriptor setup failed");
        }
    }
}
PacketPump::~PacketPump() { stop(); }
void PacketPump::closeOwned() noexcept {
    if (fd_ >= 0) { close(fd_); fd_ = -1; }
    for (int& fd : wake_) if (fd >= 0) { close(fd); fd = -1; }
}
void PacketPump::start() {
    if (state_.load() != State::Idle || fd_ < 0) throw std::logic_error("Pump is single use");
    state_.store(State::Running);
    try { worker_ = std::thread(&PacketPump::run, this); }
    catch (...) { state_.store(State::ReadError); closeOwned(); throw; }
}
void PacketPump::stop() {
    stopping_.store(true);
    const uint8_t wake = 1;
    if (wake_[1] >= 0) {
        // A full pipe is already readable. poll's timeout also bounds idle wakeup.
        while (write(wake_[1], &wake, 1) < 0 && errno == EINTR) {}
    }
    if (worker_.joinable()) worker_.join();
    if (state_.load() == State::Running || state_.load() == State::Idle) state_.store(State::Stopped);
    closeOwned();
}
Statistics PacketPump::statistics() const noexcept {
    return {packets_.load(), bytes_.load(), tcp_.load(), udp_.load(), other_.load()};
}
void PacketPump::run() noexcept {
    // One fixed buffer. No growing queues or full-payload logs.
    std::array<uint8_t, 65576> buffer{};
    while (!stopping_.load()) {
        pollfd descriptors[2] = {{fd_, POLLIN, 0}, {wake_[0], POLLIN, 0}};
        const int ready = poll(descriptors, 2, 100);
        if (stopping_.load()) break;
        if (ready < 0) {
            if (errno == EINTR) continue;
            state_.store(State::ReadError); return;
        }
        if (ready == 0) continue;
        if (descriptors[1].revents) break;
        if (!(descriptors[0].revents & POLLIN)) {
            if (descriptors[0].revents & (POLLERR | POLLHUP | POLLNVAL)) {
                state_.store(State::ReadError); return;
            }
            continue;
        }
        const ssize_t length = read(fd_, buffer.data(), buffer.size());
        if (length < 0 && (errno == EINTR || errno == EAGAIN || errno == EWOULDBLOCK)) continue;
        if (length <= 0) { state_.store(State::ReadError); return; }
        const size_t size = static_cast<size_t>(length);
        const PacketInfo info = inspect(buffer.data(), size);
        packets_.fetch_add(1); bytes_.fetch_add(size);
        if (info.protocol == Protocol::Tcp) tcp_.fetch_add(1);
        else if (info.protocol == Protocol::Udp) udp_.fetch_add(1);
        else other_.fetch_add(1);
        // Even unknown/fragmented packets must reach the forwarding engine.
        // Classification is diagnostic, never a routing/drop decision.
        try {
            if (!forward_(buffer.data(), size)) { state_.store(State::ForwardError); return; }
        } catch (...) { state_.store(State::ForwardError); return; }
    }
    state_.store(State::Stopped);
}
}
