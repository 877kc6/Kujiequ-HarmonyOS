#pragma once
#include "probe.h"
#include <memory>
namespace kujiequ::probe {
// A deliberately restricted first integration: one IPv4 TCP flow to the
// reserved test address, forwarded to an ephemeral loopback echo service.
// No game/default route, DNS interception, TLS termination or credential log.
constexpr uint16_t TCP_PORT = 49153;
// 0: incomplete, 1: accepted fixed target, -1: rejected. No arbitrary proxying.
int inspectConnect(const uint8_t* data, size_t size, size_t& consumed);
class TcpRelay {
public:
    TcpRelay(int tunFd, uint16_t loopbackPort, int protectedSocket = -1, bool httpsProxy = false);
    ~TcpRelay();
    TcpRelay(const TcpRelay&) = delete;
    TcpRelay& operator=(const TcpRelay&) = delete;
    bool ready() const;
    bool tick();
    uint32_t packets() const;
    uint32_t bytes() const;
private:
    struct Impl;
    std::unique_ptr<Impl> impl;
};
Result runHttpsProxy(int fd, int protectedSocket, std::atomic<bool>& cancel, std::atomic<bool>& confirmed);
Result runInternet(int fd, int protectedSocket, std::atomic<bool>& cancel);
Result runTcp(int fd, const std::string& marker, std::atomic<bool>& cancel);
}
