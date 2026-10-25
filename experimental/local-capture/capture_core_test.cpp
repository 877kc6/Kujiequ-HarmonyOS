#include "capture_core.h"
#include <cassert>
#include <chrono>
#include <cstring>
#include <fcntl.h>
#include <iostream>
#include <random>
#include <stdexcept>
#include <sys/socket.h>
#include <unistd.h>
#include <vector>
using namespace kujiequ::capture;
using namespace std::chrono_literals;
namespace {
std::vector<uint8_t> tcp4() {
    std::vector<uint8_t> p(40, 0);
    p[0] = 0x45; p[3] = 40; p[9] = 6;
    p[20] = 0xC0; p[21] = 0x01; p[22] = 0x01; p[23] = 0xBB; p[32] = 0x50;
    return p;
}
std::vector<uint8_t> udp6() {
    std::vector<uint8_t> p(48, 0);
    p[0] = 0x60; p[5] = 8; p[6] = 17; p[41] = 53; p[43] = 53; p[45] = 8;
    return p;
}
template<class Predicate> void await(Predicate pred) {
    for (int i = 0; i < 2000; ++i) {
        if (pred()) return;
        std::this_thread::sleep_for(1ms);
    }
    assert(false && "condition did not complete within two seconds");
}
struct Pair {
    int fd[2];
    explicit Pair(int type = SOCK_DGRAM) { assert(socketpair(AF_UNIX, type, 0, fd) == 0); }
    ~Pair() { for (int f : fd) if (f >= 0) close(f); }
};
void parsing() {
    auto p = tcp4(); auto info = inspect(p.data(), p.size());
    assert(info.protocol == Protocol::Tcp && info.ipVersion == 4 && info.destinationPort == 443);
    for (size_t n = 0; n < p.size(); ++n) assert(inspect(p.data(), n).protocol == Protocol::Unknown);
    p[0] = 0x4F; assert(inspect(p.data(), p.size()).protocol == Protocol::Unknown);
    p = tcp4(); p[32] = 0xF0; assert(inspect(p.data(), p.size()).protocol == Protocol::Unknown);
    p = tcp4(); p[6] = 0x20; assert(inspect(p.data(), p.size()).protocol == Protocol::Fragment);
    p = tcp4(); p[7] = 1; assert(inspect(p.data(), p.size()).protocol == Protocol::Fragment);
    p = tcp4(); p[6] = 0x40; assert(inspect(p.data(), p.size()).protocol == Protocol::Tcp);
    p = udp6(); assert(inspect(p.data(), p.size()).protocol == Protocol::Udp);
    p[45] = 7; assert(inspect(p.data(), p.size()).protocol == Protocol::Unknown);
    p = udp6(); p[6] = 44; assert(inspect(p.data(), p.size()).protocol == Protocol::Fragment);
    p[6] = 0; assert(inspect(p.data(), p.size()).protocol == Protocol::Unsupported);
    assert(inspect(nullptr, 100).protocol == Protocol::Unknown);
    std::mt19937 rng(20261025);
    for (int i = 0; i < 100000; ++i) {
        std::vector<uint8_t> random(rng() % 300);
        for (auto& b : random) b = static_cast<uint8_t>(rng());
        inspect(random.data(), random.size());
    }
}
void pumping() {
    Pair input, output;
    PacketPump pump(input.fd[0], [&](const uint8_t* p, size_t size) {
        return send(output.fd[0], p, size, 0) == static_cast<ssize_t>(size);
    });
    // pump owns a duplicate, not the original descriptor.
    close(input.fd[0]); input.fd[0] = -1;
    pump.start();
    bool rejected = false;
    try { pump.start(); } catch (const std::logic_error&) { rejected = true; }
    assert(rejected);
    for (auto p : {tcp4(), udp6(), std::vector<uint8_t>{0xFF, 0x01}}) {
        assert(send(input.fd[1], p.data(), p.size(), 0) == static_cast<ssize_t>(p.size()));
        uint8_t received[128];
        ssize_t size = -1;
        await([&] { size = recv(output.fd[1], received, sizeof(received), MSG_DONTWAIT); return size >= 0; });
        assert(size == static_cast<ssize_t>(p.size()) && memcmp(received, p.data(), p.size()) == 0);
    }
    pump.stop(); pump.stop();
    assert(pump.state() == State::Stopped);
    auto s = pump.statistics();
    assert(s.packets == 3 && s.bytes == 90 && s.tcp == 1 && s.udp == 1 && s.unclassified == 1);
}
void lifecycle() {
    for (int i = 0; i < 100; ++i) {
        Pair pair;
        PacketPump pump(pair.fd[0], [](const uint8_t*, size_t) { return true; });
        pump.start(); pump.stop();
        assert(fcntl(pair.fd[0], F_GETFD) >= 0);
        assert(pump.state() == State::Stopped);
    }
    Pair pair;
    PacketPump idle(pair.fd[0], [](const uint8_t*, size_t) { return true; });
    idle.start();
    auto start = std::chrono::steady_clock::now();
    idle.stop();
    assert(std::chrono::steady_clock::now() - start < 1s);
    bool rejected = false;
    try { PacketPump invalid(pair.fd[0], {}); } catch (const std::invalid_argument&) { rejected = true; }
    assert(rejected);
    PacketPump unstarted(pair.fd[0], [](const uint8_t*, size_t) { return true; });
    unstarted.stop();
    rejected = false;
    try { unstarted.start(); } catch (const std::logic_error&) { rejected = true; }
    assert(rejected);
}
void failures() {
    for (bool throws : {false, true}) {
        Pair pair;
        PacketPump pump(pair.fd[0], [throws](const uint8_t*, size_t) -> bool {
            if (throws) throw std::runtime_error("forward failure");
            return false;
        });
        pump.start(); auto p = tcp4();
        assert(send(pair.fd[1], p.data(), p.size(), 0) == static_cast<ssize_t>(p.size()));
        await([&] { return pump.state() == State::ForwardError; });
        pump.stop(); assert(pump.state() == State::ForwardError);
    }
    Pair stream(SOCK_STREAM);
    PacketPump pump(stream.fd[0], [](const uint8_t*, size_t) { return true; });
    pump.start(); close(stream.fd[1]); stream.fd[1] = -1;
    await([&] { return pump.state() == State::ReadError; });
    pump.stop(); assert(pump.state() == State::ReadError);
}
}
int main() {
    parsing(); pumping(); lifecycle(); failures();
    std::cout << "PASS: packet bounds/fuzz, byte-exact forwarding, lifecycle, idle stop, failure handling\n";
    std::cout << "HOST TEST ONLY: no HarmonyOS VPN, game traffic, TLS decryption or authorization extraction tested\n";
}
