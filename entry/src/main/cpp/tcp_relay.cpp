#include "tcp_relay.h"
#include <algorithm>
#include <array>
#include <chrono>
#include <cerrno>
#include <cstring>
#include <mutex>
#include <vector>
#include <arpa/inet.h>
#include <fcntl.h>
#include <poll.h>
#include <sys/socket.h>
#include <unistd.h>
extern "C" {
#include "lwip/init.h"
#include "lwip/ip4.h"
#include "lwip/netif.h"
#include "lwip/tcp.h"
#include "lwip/timeouts.h"
#include "lwip/priv/tcp_priv.h"
u32_t sys_now(void) {
    return static_cast<u32_t>(std::chrono::duration_cast<std::chrono::milliseconds>(
        std::chrono::steady_clock::now().time_since_epoch()).count());
}
}
namespace kujiequ::probe {
namespace {
std::mutex stackMutex;
std::once_flag initialized;
constexpr size_t LIMIT = 65536;
struct Socket {
    int fd = -1;
    ~Socket() { if (fd >= 0) close(fd); }
};
bool nonblock(int fd) {
    const int flags = fcntl(fd, F_GETFL, 0);
    return flags >= 0 && fcntl(fd, F_SETFL, flags | O_NONBLOCK) == 0;
}
bool pending() { return errno == EAGAIN || errno == EWOULDBLOCK || errno == EINTR; }
sockaddr_in address(const char* host, uint16_t port) {
    sockaddr_in a{}; a.sin_family = AF_INET; a.sin_port = htons(port);
    inet_pton(AF_INET, host, &a.sin_addr); return a;
}
}
int inspectConnect(const uint8_t* data, size_t size, size_t& consumed) {
    consumed = 0;
    if (!data || size == 0) return 0;
    const std::string header(reinterpret_cast<const char*>(data), std::min<size_t>(size, 4100));
    const auto end = header.find("\r\n\r\n");
    if (end == std::string::npos) return size > 4096 ? -1 : 0;
    if (end + 4 > 4096 || (header.rfind("CONNECT one.one.one.one:443 HTTP/1.1\r\n", 0) != 0 &&
        header.rfind("CONNECT one.one.one.one:443 HTTP/1.0\r\n", 0) != 0)) return -1;
    consumed = end + 4; return 1;
}
struct TcpRelay::Impl {
    std::unique_lock<std::mutex> lock;
    int tun;
    uint16_t port;
    int protectedSocket;
    bool httpsProxy, connectParsed = false, connectReplied = false;
    netif nic{};
    tcp_pcb* listener = nullptr;
    tcp_pcb* client = nullptr;
    Socket upstream;
    std::vector<uint8_t> outgoing;
    bool added = false, ok = false, broken = false, connecting = false;
    bool clientEof = false, upstreamEof = false, shutWrite = false, sentFin = false;
    uint32_t count = 0, total = 0;
    explicit Impl(int fd, uint16_t p, int upstreamFd, bool proxy) : lock(stackMutex, std::try_to_lock), tun(fd), port(p), protectedSocket(upstreamFd), httpsProxy(proxy) {
        if (!lock.owns_lock() || fd < 0 || p == 0) return;
        std::call_once(initialized, [] { lwip_init(); });
        ip4_addr_t ip, mask, gateway;
        ip4addr_aton(DESTINATION, &ip); ip4addr_aton("255.255.255.252", &mask);
        ip4_addr_set_zero(&gateway);
        if (!netif_add(&nic, &ip, &mask, &gateway, this, init, ip4_input)) return;
        added = true; netif_set_default(&nic); netif_set_up(&nic); netif_set_link_up(&nic);
        tcp_pcb* pcb = tcp_new();
        if (!pcb) return;
        ip_addr_t local; ipaddr_aton(DESTINATION, &local);
        if (tcp_bind(pcb, &local, TCP_PORT) != ERR_OK) { tcp_abort(pcb); return; }
        listener = tcp_listen(pcb);
        if (!listener) { tcp_abort(pcb); return; }
        tcp_arg(listener, this); tcp_accept(listener, accept); ok = true;
    }
    ~Impl() {
        if (!lock.owns_lock()) return;
        if (client) { tcp_arg(client, nullptr); tcp_err(client, nullptr); tcp_abort(client); client = nullptr; }
        if (listener) { tcp_close(listener); listener = nullptr; }
        // This exclusive, single-flow stack must not retain time-wait/half-open
        // PCBs pointing at a removed interface across repeated probes.
        if (added) {
            while (tcp_active_pcbs) tcp_abort(tcp_active_pcbs);
            while (tcp_tw_pcbs) tcp_abort(tcp_tw_pcbs);
            netif_set_down(&nic); netif_remove(&nic);
        }
    }
    static err_t init(netif* n) {
        n->name[0] = 'k'; n->name[1] = 'q'; n->mtu = 1400;
        n->output = output; return ERR_OK;
    }
    static err_t output(netif* n, pbuf* p, const ip4_addr_t*) {
        auto* s = static_cast<Impl*>(n->state);
        std::array<uint8_t, 1600> packet{};
        if (p->tot_len > packet.size()) { s->broken = true; return ERR_IF; }
        pbuf_copy_partial(p, packet.data(), p->tot_len, 0);
        const auto size = write(s->tun, packet.data(), p->tot_len);
        // EAGAIN is loss: lwIP will retransmit. Partial IP packet writes are fatal.
        if (size < 0 && pending()) return ERR_MEM;
        if (size != p->tot_len) { s->broken = true; return ERR_IF; }
        return ERR_OK;
    }
    static void error(void* arg, err_t) {
        if (!arg) return;
        auto* s = static_cast<Impl*>(arg); s->client = nullptr; s->broken = true;
    }
    static err_t receive(void* arg, tcp_pcb*, pbuf* p, err_t err) {
        auto* s = static_cast<Impl*>(arg);
        if (!p) { s->clientEof = true; return ERR_OK; }
        if (err != ERR_OK) return err;
        if (s->outgoing.size() + p->tot_len > LIMIT) return ERR_MEM;
        const size_t start = s->outgoing.size();
        s->outgoing.resize(start + p->tot_len);
        pbuf_copy_partial(p, s->outgoing.data() + start, p->tot_len, 0);
        pbuf_free(p);
        if (s->httpsProxy && !s->connectParsed) {
            size_t consumed = 0;
            const int parsed = inspectConnect(s->outgoing.data(), s->outgoing.size(), consumed);
            if (parsed <= 0) { if (parsed < 0) s->broken = true; return ERR_OK; }
            tcp_recved(s->client, static_cast<u16_t>(consumed));
            s->outgoing.erase(s->outgoing.begin(), s->outgoing.begin() + consumed);
            s->connectParsed = true;
        }
        // Window credit is returned only after the upstream socket accepts data.
        return ERR_OK;
    }
    static err_t accept(void* arg, tcp_pcb* pcb, err_t err) {
        auto* s = static_cast<Impl*>(arg);
        if (err != ERR_OK || s->client) { tcp_abort(pcb); return ERR_ABRT; }
        s->upstream.fd = s->protectedSocket >= 0 ? fcntl(s->protectedSocket, F_DUPFD_CLOEXEC, 0) : socket(AF_INET, SOCK_STREAM, 0);
        if (s->upstream.fd < 0 || !nonblock(s->upstream.fd)) {
            s->broken = true; tcp_abort(pcb); return ERR_ABRT;
        }
        auto a = address(s->protectedSocket >= 0 ? "1.1.1.1" : "127.0.0.1", s->port);
        const int result = connect(s->upstream.fd, reinterpret_cast<sockaddr*>(&a), sizeof(a));
        if (result < 0 && errno != EINPROGRESS) {
            s->broken = true; tcp_abort(pcb); return ERR_ABRT;
        }
        s->connecting = result < 0;
        s->client = pcb; tcp_arg(pcb, s); tcp_err(pcb, error); tcp_recv(pcb, receive);
        return ERR_OK;
    }
    bool tick() {
        if (!ok || broken) return false;
        // Bounded batch leaves time for upstream I/O and TCP retransmit timers.
        for (int i = 0; i < 16; ++i) {
            pollfd f{tun, POLLIN, 0};
            const int ready = poll(&f, 1, 0);
            if (ready < 0) { if (errno == EINTR) break; return false; }
            if (f.revents & (POLLERR | POLLHUP | POLLNVAL)) return false;
            if (!(f.revents & POLLIN)) break;
            std::array<uint8_t, 2048> data{};
            const auto length = read(tun, data.data(), data.size());
            if (length < 0 && pending()) break;
            if (length <= 0) return false;
            ++count; total += static_cast<uint32_t>(length);
            // Only the explicit IPv4 test destination/protocol enters this stack.
            if (length < 20 || data[0] >> 4 != 4 || data[9] != 6 ||
                data[16] != 198 || data[17] != 18 || data[18] != 0 || data[19] != 2) continue;
            pbuf* p = pbuf_alloc(PBUF_RAW, static_cast<u16_t>(length), PBUF_RAM);
            if (!p) continue;
            pbuf_take(p, data.data(), static_cast<u16_t>(length));
            if (nic.input(p, &nic) != ERR_OK) pbuf_free(p);
        }
        sys_check_timeouts();
        if (!client || broken) return !broken;
        if (connecting) {
            pollfd f{upstream.fd, POLLOUT, 0}; poll(&f, 1, 0);
            if (!f.revents) return true;
            int e = 0; socklen_t size = sizeof(e);
            if (getsockopt(upstream.fd, SOL_SOCKET, SO_ERROR, &e, &size) < 0 || e) return false;
            connecting = false;
        }
        if (httpsProxy && !connectReplied) {
            if (!connectParsed) return true;
            static constexpr char response[] = "HTTP/1.1 200 Connection Established\r\n\r\n";
            const err_t e = tcp_write(client, response, sizeof(response) - 1, TCP_WRITE_FLAG_COPY);
            if (e == ERR_MEM) return true;
            if (e != ERR_OK) return false;
            connectReplied = true; tcp_output(client);
        }
        if (!outgoing.empty()) {
            const auto n = send(upstream.fd, outgoing.data(), outgoing.size(), MSG_NOSIGNAL);
            if (n > 0) {
                tcp_recved(client, static_cast<u16_t>(n));
                outgoing.erase(outgoing.begin(), outgoing.begin() + n);
            } else if (n < 0 && !pending()) return false;
        }
        if (clientEof && outgoing.empty() && !shutWrite) {
            shutdown(upstream.fd, SHUT_WR); shutWrite = true;
        }
        const size_t space = std::min<size_t>(tcp_sndbuf(client), 4096);
        if (!upstreamEof && space && tcp_sndqueuelen(client) < TCP_SND_QUEUELEN - 4) {
            std::array<uint8_t, 4096> data{};
            // Peek first so ERR_MEM from lwIP cannot discard already-read bytes.
            const auto n = recv(upstream.fd, data.data(), space, MSG_PEEK);
            if (n > 0) {
                const err_t e = tcp_write(client, data.data(), static_cast<u16_t>(n), TCP_WRITE_FLAG_COPY);
                if (e == ERR_OK) {
                    const auto consumed = recv(upstream.fd, data.data(), n, 0);
                    if (consumed != n) return false;
                    tcp_output(client);
                } else if (e != ERR_MEM) return false;
            } else if (n == 0) upstreamEof = true;
            else if (!pending()) return false;
        }
        if (upstreamEof && !sentFin) {
            const auto e = tcp_shutdown(client, 0, 1);
            if (e == ERR_OK) { sentFin = true; tcp_output(client); }
            else if (e != ERR_MEM) return false;
        }
        return !broken;
    }
};
TcpRelay::TcpRelay(int fd, uint16_t p, int upstreamFd, bool proxy) : impl(std::make_unique<Impl>(fd, p, upstreamFd, proxy)) {}
TcpRelay::~TcpRelay() = default;
bool TcpRelay::ready() const { return impl->ok; }
bool TcpRelay::tick() { return impl->tick(); }
uint32_t TcpRelay::packets() const { return impl->count; }
uint32_t TcpRelay::bytes() const { return impl->total; }

Result runTcp(int fd, const std::string& marker, std::atomic<bool>& cancel) {
    if (cancel.load()) return {Cancelled, 0, 0};
    if (marker.empty() || marker.size() > 128) return {SocketError, 0, 0};
    Socket server, client, echo;
    server.fd = socket(AF_INET, SOCK_STREAM, 0);
    client.fd = socket(AF_INET, SOCK_STREAM, 0);
    if (server.fd < 0 || client.fd < 0 || !nonblock(server.fd) || !nonblock(client.fd)) return {SocketError, 0, 0};
    auto local = address("127.0.0.1", 0);
    if (bind(server.fd, reinterpret_cast<sockaddr*>(&local), sizeof(local)) || listen(server.fd, 1)) return {BindError, 0, 0};
    socklen_t size = sizeof(local);
    if (getsockname(server.fd, reinterpret_cast<sockaddr*>(&local), &size)) return {SocketError, 0, 0};
    TcpRelay relay(fd, ntohs(local.sin_port));
    if (!relay.ready()) return {SocketError, 0, 0};
    auto source = address(SOURCE, 0), target = address(DESTINATION, TCP_PORT);
    if (bind(client.fd, reinterpret_cast<sockaddr*>(&source), sizeof(source))) return {BindError, 0, 0};
    const int connected = connect(client.fd, reinterpret_cast<sockaddr*>(&target), sizeof(target));
    if (connected && errno != EINPROGRESS) return {SocketError, 0, 0};
    bool waiting = connected != 0;
    size_t sent = 0;
    std::string received, response;
    // Enough data to span many TCP segments and exercise window/backpressure.
    std::string payload;
    while (payload.size() < 32768) payload += marker;
    const u32_t start = sys_now();
    int result = Timeout;
    while (sys_now() - start < 8000) {
        if (cancel.load()) { result = Cancelled; break; }
        if (!relay.tick()) { result = ReadError; break; }
        if (echo.fd < 0) {
            echo.fd = accept(server.fd, nullptr, nullptr);
            if (echo.fd >= 0 && !nonblock(echo.fd)) { result = SocketError; break; }
        }
        if (waiting) {
            pollfd p{client.fd, POLLOUT, 0}; poll(&p, 1, 0);
            if (p.revents) {
                int error = 0; socklen_t len = sizeof(error);
                if (getsockopt(client.fd, SOL_SOCKET, SO_ERROR, &error, &len) || error) { result = SocketError; break; }
                waiting = false;
            }
        }
        if (!waiting && sent < payload.size()) {
            const auto n = send(client.fd, payload.data() + sent, payload.size() - sent, MSG_NOSIGNAL);
            if (n > 0) sent += n;
            else if (n < 0 && !pending()) { result = SendError; break; }
        }
        std::array<char, 4096> bytes{};
        if (echo.fd >= 0) {
            if (response.size() < LIMIT - bytes.size()) {
                const auto n = recv(echo.fd, bytes.data(), bytes.size(), 0);
                if (n > 0) response.append(bytes.data(), n);
                else if (n < 0 && !pending()) { result = ReadError; break; }
            }
            if (!response.empty()) {
                const auto n = send(echo.fd, response.data(), response.size(), MSG_NOSIGNAL);
                if (n > 0) response.erase(0, n);
                else if (n < 0 && !pending()) { result = SendError; break; }
            }
        }
        if (!waiting) {
            const auto n = recv(client.fd, bytes.data(), bytes.size(), 0);
            if (n > 0) {
                received.append(bytes.data(), n);
                if (received.size() > payload.size() || payload.compare(0, received.size(), received) != 0) { result = ReadError; break; }
                if (received == payload) { result = Matched; break; }
            } else if (n == 0) { result = ReadError; break; }
            else if (!pending()) { result = ReadError; break; }
        }
        poll(nullptr, 0, 2);
    }
    return {result, relay.packets(), relay.bytes()};
}
Result runInternet(int fd, int protectedSocket, std::atomic<bool>& cancel) {
    if (cancel.load()) return {Cancelled, 0, 0};
    if (protectedSocket < 0) return {SocketError, 0, 0};
    Socket client; client.fd = socket(AF_INET, SOCK_STREAM, 0);
    if (client.fd < 0 || !nonblock(client.fd)) return {SocketError, 0, 0};
    TcpRelay relay(fd, 80, protectedSocket);
    if (!relay.ready()) return {SocketError, 0, 0};
    auto source = address(SOURCE, 0), target = address(DESTINATION, TCP_PORT);
    if (bind(client.fd, reinterpret_cast<sockaddr*>(&source), sizeof(source))) return {BindError, 0, 0};
    const int connected = connect(client.fd, reinterpret_cast<sockaddr*>(&target), sizeof(target));
    if (connected && errno != EINPROGRESS) return {SocketError, 0, 0};
    bool waiting = connected != 0;
    const std::string request = "HEAD / HTTP/1.1\r\nHost: one.one.one.one\r\nConnection: close\r\n\r\n";
    std::string response; size_t sent = 0;
    const u32_t start = sys_now(); int result = Timeout;
    while (sys_now() - start < 10000) {
        if (cancel.load()) { result = Cancelled; break; }
        if (!relay.tick()) { result = ReadError; break; }
        if (waiting) {
            pollfd p{client.fd, POLLOUT, 0}; poll(&p, 1, 0);
            if (p.revents) {
                int error = 0; socklen_t len = sizeof(error);
                if (getsockopt(client.fd, SOL_SOCKET, SO_ERROR, &error, &len) || error) { result = SocketError; break; }
                waiting = false;
            }
        }
        if (!waiting) {
            if (sent < request.size()) {
                const auto n = send(client.fd, request.data() + sent, request.size() - sent, MSG_NOSIGNAL);
                if (n > 0) sent += n;
                else if (n < 0 && !pending()) { result = SendError; break; }
            }
            std::array<char, 1024> b{};
            const auto n = recv(client.fd, b.data(), b.size(), 0);
            if (n > 0) {
                response.append(b.data(), n);
                if (response.size() > 8192) { result = ReadError; break; }
                if (response.find("\r\n\r\n") != std::string::npos) {
                    const bool http = response.compare(0, 9, "HTTP/1.1 ") == 0 || response.compare(0, 9, "HTTP/1.0 ") == 0;
                    result = sent == request.size() && http && response.size() >= 12 && response[9] >= '2' && response[9] <= '3' &&
                        response[10] >= '0' && response[10] <= '9' && response[11] >= '0' && response[11] <= '9' ? Matched : ReadError;
                    break;
                }
            } else if (n == 0) { result = ReadError; break; }
            else if (!pending()) { result = ReadError; break; }
        }
        poll(nullptr, 0, 2);
    }
    return {result, relay.packets(), relay.bytes()};
}

Result runHttpsProxy(int fd, int protectedSocket, std::atomic<bool>& cancel, std::atomic<bool>& confirmed) {
    if (cancel.load()) return {Cancelled, 0, 0};
    if (protectedSocket < 0) return {SocketError, 0, 0};
    TcpRelay relay(fd, 443, protectedSocket, true);
    if (!relay.ready()) return {SocketError, 0, 0};
    const u32_t start = sys_now(); int result = Timeout;
    u32_t failedAt = 0;
    while (sys_now() - start < 25000) {
        if (cancel.load()) { result = Cancelled; break; }
        if (confirmed.load() && relay.packets() > 0) { result = Matched; break; }
        if (!failedAt && !relay.tick()) failedAt = sys_now();
        if (failedAt && sys_now() - failedAt > 1000) { result = ReadError; break; }
        poll(nullptr, 0, 2);
    }
    return {result, relay.packets(), relay.bytes()};
}

}
