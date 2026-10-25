#pragma once
#include <atomic>
#include <cstddef>
#include <cstdint>
#include <functional>
#include <thread>

namespace kujiequ::capture {
// This is an IP-packet pump, NOT a TCP/IP stack or a TLS decryptor.
enum class Protocol { Unknown, Tcp, Udp, Fragment, Unsupported };
struct PacketInfo {
    Protocol protocol = Protocol::Unknown;
    uint8_t ipVersion = 0;
    uint16_t sourcePort = 0;
    uint16_t destinationPort = 0;
};
PacketInfo inspect(const uint8_t* packet, size_t size) noexcept;
enum class State { Idle, Running, Stopped, ReadError, ForwardError };
struct Statistics {
    uint64_t packets = 0;
    uint64_t bytes = 0;
    uint64_t tcp = 0;
    uint64_t udp = 0;
    uint64_t unclassified = 0;
};

// A synchronous forwarding callback is mandatory. It must consume/copy the
// packet before returning, be bounded, and must never call stop() on this pump.
// No payloads, IPs, URLs, tokens or packet dumps are retained or logged here.
// Lifecycle methods are called on ONE owning thread. state/stats are thread-safe.
// The caller owns the original TUN fd and the VPN. Pump owns only dup(fd).
// The caller must tear down VPN routes whenever state is no longer Running.
class PacketPump final {
public:
    using Forward = std::function<bool(const uint8_t*, size_t)>;
    PacketPump(int tunFd, Forward forward);
    ~PacketPump();
    PacketPump(const PacketPump&) = delete;
    PacketPump& operator=(const PacketPump&) = delete;
    void start();
    void stop();
    State state() const noexcept { return state_.load(); }
    Statistics statistics() const noexcept;
private:
    void run() noexcept;
    void closeOwned() noexcept;
    int fd_ = -1;
    int wake_[2] = {-1, -1};
    Forward forward_;
    std::thread worker_;
    std::atomic<State> state_{State::Idle};
    std::atomic<bool> stopping_{false};
    std::atomic<uint64_t> packets_{0}, bytes_{0}, tcp_{0}, udp_{0}, other_{0};
};
}
