#include "napi/native_api.h"
#include "probe.h"
#include "tcp_relay.h"
#include <atomic>
#include <fcntl.h>
#include <memory>
#include <string>
#include <unistd.h>
#include <sys/socket.h>

namespace {
std::atomic<bool> busy{false};
std::atomic<bool> cancelled{false};
std::atomic<bool> httpsConfirmed{false};
int internetSocket = -1;
struct Job {
    napi_async_work work = nullptr;
    napi_deferred deferred = nullptr;
    int fd = -1;
    std::string marker;
    bool tcp = false;
    bool https = false;
    int upstream = -1;
    kujiequ::probe::Result result;
    ~Job() { if (fd >= 0) close(fd); if (upstream >= 0) close(upstream); }
};
napi_value Fail(napi_env env, const char* message) {
    napi_throw_error(env, "CAPTURE_PROBE", message); return nullptr;
}
void Execute(napi_env, void* raw) {
    auto* job = static_cast<Job*>(raw);
    try { job->result = job->https ? kujiequ::probe::runHttpsProxy(job->fd, job->upstream, cancelled, httpsConfirmed) : job->upstream >= 0 ? kujiequ::probe::runInternet(job->fd, job->upstream, cancelled) : job->tcp ? kujiequ::probe::runTcp(job->fd, job->marker, cancelled) :
        kujiequ::probe::run(job->fd, job->marker, cancelled); }
    catch (...) { job->result = {kujiequ::probe::ReadError, 0, 0}; }
}
void Number(napi_env env, napi_value object, const char* key, uint32_t value) {
    napi_value number; napi_create_uint32(env, value, &number); napi_set_named_property(env, object, key, number);
}
void Complete(napi_env env, napi_status status, void* raw) {
    std::unique_ptr<Job> job(static_cast<Job*>(raw));
    busy.store(false);
    if (status != napi_ok) job->result.code = kujiequ::probe::Cancelled;
    napi_value result; napi_create_object(env, &result);
    Number(env, result, "code", job->result.code);
    Number(env, result, "packets", job->result.packets);
    Number(env, result, "bytes", job->result.bytes);
    napi_resolve_deferred(env, job->deferred, result);
    napi_delete_async_work(env, job->work);
}
napi_value RunImpl(napi_env env, napi_callback_info info, bool tcp, bool internet = false, bool https = false) {
    size_t count = 2; napi_value args[2];
    if (napi_get_cb_info(env, info, &count, args, nullptr, nullptr) != napi_ok || count != 2) return Fail(env, "Expected fd and run identifier");
    int32_t fd = -1;
    char marker[129]{}; size_t length = 0;
    if (napi_get_value_int32(env, args[0], &fd) != napi_ok || fd < 0 ||
        napi_get_value_string_utf8(env, args[1], nullptr, 0, &length) != napi_ok || length < 1 || length > 128) return Fail(env, "Invalid probe arguments");
    if (napi_get_value_string_utf8(env, args[1], marker, sizeof(marker), &length) != napi_ok) return Fail(env, "Invalid run identifier");
    if (busy.exchange(true)) return Fail(env, "Probe already running");
    cancelled.store(false);
    auto job = std::make_unique<Job>();
    job->fd = fcntl(fd, F_DUPFD_CLOEXEC, 0);
    if (job->fd < 0) { busy.store(false); return Fail(env, "Cannot duplicate TUN descriptor"); }
    job->marker.assign(marker, length);
    job->tcp = tcp; job->https = https; httpsConfirmed.store(false);
    if (internet) {
        job->upstream = internetSocket >= 0 ? fcntl(internetSocket, F_DUPFD_CLOEXEC, 0) : -1;
        if (job->upstream < 0) { busy.store(false); return Fail(env, "No protected Internet socket"); }
    }
    napi_value name, promise;
    napi_create_string_utf8(env, "KujiequVpnProbe", NAPI_AUTO_LENGTH, &name);
    if (napi_create_promise(env, &job->deferred, &promise) != napi_ok ||
        napi_create_async_work(env, nullptr, name, Execute, Complete, job.get(), &job->work) != napi_ok) {
        busy.store(false); return Fail(env, "Cannot create probe worker");
    }
    if (napi_queue_async_work(env, job->work) != napi_ok) {
        napi_delete_async_work(env, job->work); busy.store(false); return Fail(env, "Cannot start probe worker");
    }
    job.release(); return promise;
}
napi_value Run(napi_env env, napi_callback_info info) { return RunImpl(env, info, false); }
napi_value RunTcp(napi_env env, napi_callback_info info) { return RunImpl(env, info, true); }
napi_value PrepareInternet(napi_env env, napi_callback_info) {
    if (busy.load() || internetSocket >= 0) return Fail(env, "Probe socket already active");
    internetSocket = socket(AF_INET, SOCK_STREAM, 0);
    if (internetSocket < 0) return Fail(env, "Cannot prepare Internet socket");
    napi_value value; napi_create_int32(env, internetSocket, &value); return value;
}
napi_value CloseInternet(napi_env env, napi_callback_info) {
    if (internetSocket >= 0) { close(internetSocket); internetSocket = -1; }
    napi_value value; napi_get_undefined(env, &value); return value;
}
napi_value RunInternet(napi_env env, napi_callback_info info) { return RunImpl(env, info, true, true); }
napi_value RunHttps(napi_env env, napi_callback_info info) { return RunImpl(env, info, true, true, true); }
napi_value ConfirmHttps(napi_env env, napi_callback_info) {
    if (busy.load()) httpsConfirmed.store(true);
    napi_value value; napi_get_undefined(env, &value); return value;
}
napi_value Cancel(napi_env env, napi_callback_info) {
    cancelled.store(true); napi_value result; napi_get_undefined(env, &result); return result;
}
void Cleanup(void*) { cancelled.store(true); if (internetSocket >= 0) { close(internetSocket); internetSocket = -1; } }
napi_value Init(napi_env env, napi_value exports) {
    napi_property_descriptor properties[] = {
        {"runHttps", nullptr, RunHttps, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"confirmHttps", nullptr, ConfirmHttps, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"prepareInternet", nullptr, PrepareInternet, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"closeInternet", nullptr, CloseInternet, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"runInternet", nullptr, RunInternet, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"run", nullptr, Run, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"runTcp", nullptr, RunTcp, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"cancel", nullptr, Cancel, nullptr, nullptr, nullptr, napi_default, nullptr}
    };
    napi_define_properties(env, exports, 8, properties);
    napi_add_env_cleanup_hook(env, Cleanup, nullptr);
    return exports;
}
}
static napi_module module = {1, 0, nullptr, Init, "capture_probe", nullptr, {0}};
extern "C" __attribute__((constructor)) void RegisterCaptureProbe() { napi_module_register(&module); }
