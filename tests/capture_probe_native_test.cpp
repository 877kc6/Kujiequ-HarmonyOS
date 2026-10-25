#include "../entry/src/main/cpp/probe.h"
#include <cassert>
#include <chrono>
#include <iostream>
#include <random>
#include <sys/socket.h>
#include <thread>
#include <unistd.h>
#include <vector>
using namespace kujiequ::probe;
using namespace std::chrono_literals;
std::vector<uint8_t> packet(const std::string& marker) {
    std::vector<uint8_t> p(28 + marker.size(), 0);
    p[0] = 0x45; p[2] = p.size() >> 8; p[3] = p.size(); p[9] = 17;
    p[16] = 198; p[17] = 18; p[19] = 2;
    p[22] = PORT >> 8; p[23] = PORT & 255; p[24] = (8 + marker.size()) >> 8; p[25] = 8 + marker.size();
    std::copy(marker.begin(), marker.end(), p.begin() + 28); return p;
}
struct Pair {
    int fd[2];
    Pair() { assert(socketpair(AF_UNIX, SOCK_DGRAM, 0, fd) == 0); }
    ~Pair() { close(fd[0]); close(fd[1]); }
};
int main() {
    const std::string marker = "kujiequ_probe:test-unique-run";
    auto p = packet(marker);
    assert(matches(p.data(), p.size(), marker));
    assert(!matches(p.data(), p.size(), "wrong-run"));
    for (size_t n = 0; n < p.size(); ++n) assert(!matches(p.data(), n, marker));
    auto invalid = p; invalid[16] = 199; assert(!matches(invalid.data(), invalid.size(), marker));
    invalid = p; invalid[23] = 42; assert(!matches(invalid.data(), invalid.size(), marker));
    invalid = p; invalid[6] = 0x20; assert(!matches(invalid.data(), invalid.size(), marker));
    invalid = p; invalid[25] = 1; assert(!matches(invalid.data(), invalid.size(), marker));
    invalid = p; invalid[0] = 0x4F; assert(!matches(invalid.data(), invalid.size(), marker));
    assert(!matches(nullptr, 99, marker));
    std::mt19937 rng(20261025);
    for (int i = 0; i < 100000; ++i) {
        std::vector<uint8_t> bytes(rng() % 200);
        for (auto& byte : bytes) byte = rng();
        matches(bytes.data(), bytes.size(), marker);
    }
    std::atomic<bool> cancel{false};
    {
        Pair pair;
        auto result = waitForPacket(pair.fd[0], marker, cancel, [&] {
            auto bad = packet("unrelated-run");
            assert(send(pair.fd[1], bad.data(), bad.size(), 0) == static_cast<ssize_t>(bad.size()));
            assert(send(pair.fd[1], p.data(), p.size(), 0) == static_cast<ssize_t>(p.size()));
            return Matched;
        });
        assert(result.code == Matched && result.packets == 2 && result.bytes > p.size());
    }
    {
        Pair pair;
        auto result = waitForPacket(pair.fd[0], marker, cancel, [] { return Matched; }, 100);
        assert(result.code == Timeout && result.packets == 0);
        result = waitForPacket(pair.fd[0], marker, cancel, [] { return SendError; });
        assert(result.code == SendError);
        auto stopper = std::thread([&] { std::this_thread::sleep_for(30ms); cancel.store(true); });
        auto start = std::chrono::steady_clock::now();
        result = waitForPacket(pair.fd[0], marker, cancel, [] { return Matched; });
        stopper.join();
        assert(result.code == Cancelled && std::chrono::steady_clock::now() - start < 500ms);
    }
    assert(waitForPacket(-1, marker, cancel, [] { return Matched; }).code == ReadError);
    assert(run(-1, marker, cancel).code == Cancelled);
    std::cout << "PASS: exact probe matching, unrelated data rejection, bounded read, timeout, cancel, send error, 100000 random packets\n";
    std::cout << "Host simulation only: not HarmonyOS VPN/SDK/device verification\n";
}
