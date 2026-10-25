#include "probe.h"
#include <array>
#include <cerrno>
#include <chrono>
#include <cstring>
#include <arpa/inet.h>
#include <poll.h>
#include <sys/socket.h>
#include <unistd.h>

namespace kujiequ::probe {
namespace {
uint16_t u16(const uint8_t* p) { return static_cast<uint16_t>((p[0] << 8) | p[1]); }
struct Socket {
    int fd = socket(AF_INET, SOCK_DGRAM | SOCK_CLOEXEC, 0);
    ~Socket() { if (fd >= 0) close(fd); }
};
}
bool matches(const uint8_t* p, size_t n, const std::string& marker) noexcept {
    if (!p || n < 28 || (p[0] >> 4) != 4 || p[9] != 17) return false;
    const size_t header = (p[0] & 15) * 4;
    if (header < 20 || header + 8 > n || u16(p + 2) != n || (u16(p + 6) & 0x3FFF)) return false;
    if (p[16] != 198 || p[17] != 18 || p[18] != 0 || p[19] != 2) return false;
    if (u16(p + header + 2) != PORT || u16(p + header + 4) != n - header) return false;
    if (marker.empty() || n - header - 8 != marker.size()) return false;
    return memcmp(p + header + 8, marker.data(), marker.size()) == 0;
}
Result waitForPacket(int fd, const std::string& marker, std::atomic<bool>& cancel,
    const std::function<int()>& send, int timeoutMs) {
    Result result;
    if (fd < 0 || marker.empty() || marker.size() > 128 || timeoutMs <= 0 || timeoutMs > 3000 || !send) {
        result.code = ReadError; return result;
    }
    std::array<uint8_t, 2048> packet{};
    auto deadline = std::chrono::steady_clock::now() + std::chrono::milliseconds(timeoutMs);
    auto nextSend = std::chrono::steady_clock::now();
    int sent = 0;
    while (std::chrono::steady_clock::now() < deadline) {
        if (cancel.load()) { result.code = Cancelled; return result; }
        auto now = std::chrono::steady_clock::now();
        if (sent < 4 && now >= nextSend) {
            const int code = send();
            if (code != Matched) { result.code = code; return result; }
            ++sent; nextSend = now + std::chrono::milliseconds(250);
        }
        pollfd descriptor{fd, POLLIN, 0};
        const int ready = poll(&descriptor, 1, 50);
        if (cancel.load()) { result.code = Cancelled; return result; }
        if (ready < 0) {
            if (errno == EINTR) continue;
            result.code = ReadError; return result;
        }
        if (ready == 0) continue;
        if (!(descriptor.revents & POLLIN)) { result.code = ReadError; return result; }
        const ssize_t size = read(fd, packet.data(), packet.size());
        if (size < 0 && (errno == EINTR || errno == EAGAIN || errno == EWOULDBLOCK)) continue;
        if (size <= 0) { result.code = ReadError; return result; }
        ++result.packets; result.bytes += static_cast<uint32_t>(size);
        if (matches(packet.data(), static_cast<size_t>(size), marker)) {
            result.code = Matched; return result;
        }
    }
    return result;
}
Result run(int fd, const std::string& marker, std::atomic<bool>& cancel) {
    if (cancel.load()) return {Cancelled, 0, 0};
    Socket udp;
    if (udp.fd < 0) return {SocketError, 0, 0};
    sockaddr_in source{}; source.sin_family = AF_INET;
    inet_pton(AF_INET, SOURCE, &source.sin_addr);
    // Binding the VPN-only source prevents falling back to a normal interface.
    if (bind(udp.fd, reinterpret_cast<sockaddr*>(&source), sizeof(source)) != 0) return {BindError, 0, 0};
    sockaddr_in destination{}; destination.sin_family = AF_INET; destination.sin_port = htons(PORT);
    inet_pton(AF_INET, DESTINATION, &destination.sin_addr);
    return waitForPacket(fd, marker, cancel, [&] {
        auto n = sendto(udp.fd, marker.data(), marker.size(), MSG_DONTWAIT,
            reinterpret_cast<sockaddr*>(&destination), sizeof(destination));
        return n == static_cast<ssize_t>(marker.size()) ? Matched : SendError;
    });
}
}
