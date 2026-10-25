#pragma once
#include <atomic>
#include <cstddef>
#include <cstdint>
#include <functional>
#include <string>

namespace kujiequ::probe {
constexpr const char* SOURCE = "198.18.0.1";
constexpr const char* DESTINATION = "198.18.0.2";
constexpr uint16_t PORT = 49152;
enum Code { Matched = 0, Timeout = 1, Cancelled = 2, SocketError = 3,
    BindError = 4, SendError = 5, ReadError = 6 };
struct Result { int code = Timeout; uint32_t packets = 0; uint32_t bytes = 0; };
bool matches(const uint8_t* data, size_t size, const std::string& marker) noexcept;
// fd is borrowed and must have one reader. Used on a worker thread only.
Result waitForPacket(int fd, const std::string& marker, std::atomic<bool>& cancel,
    const std::function<int()>& send, int timeoutMs = 3000);
Result run(int fd, const std::string& marker, std::atomic<bool>& cancel);
}
