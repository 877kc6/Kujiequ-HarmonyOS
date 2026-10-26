# 1.6.3 外网测试补充

- 新增独立 internet 模式。路由仍仅本应用的 198.18.0.2/32，不接管全设备或游戏流量。
- 启动顺序：create VPN → native 创建 AF_INET TCP socket → ArkTS await connection.protect(fd) → native 复制此 socket 描述符 → lwIP 接受测试客户端 → 连接固定 1.1.1.1:80 → HEAD /（Host: one.one.one.one）→ 通过原 TUN 返回响应。
- protect 失败会进入失败清理，不继续发请求。不能用保护整个进程来替代，否则同进程内测试客户端可能绕过 VPN。
- 回执 `internetProbePassed=true` 仅表示这一次固定目标明文 HTTP 测试通过，`tlsVerified=false` 始终保留。HTTP 响应可能来自网络代理；它不能证明服务器身份或 TLS 解密成功。
- socket 创建、绑定、连接、发送、读取错误分别沿用现有结果码；全部循环有截止时间、取消检查、有限响应缓冲（8 KiB）。停止/失败后关闭原保护 socket、工作线程中的副本和虚拟网卡。
- 只复制诊断元数据，不保存 HTTP 报文、账号信息或凭据。无重定向跟随、无游戏 API 请求。
- 电脑侧 Native 编译和双向 TCP 回归已通过；新互联网路径缺少真实系统 TUN 的主机环境，须设备验收，不宣称已经可用。

手机更新后打开「测试外网 HTTP 转发」，无需打开游戏，复制完整回执即可。网络禁止明文 HTTP 时，测试可能失败，不要因此回退已通过的本机 TCP 环节。

---

# 1.6.2 TCP 转发测试

## 当前范围

上一版经用户实测确认系统 VPN 及 UDP 读包通路可用。这一版新增用户态 TCP 栈和双向转发的受限集成，尚未完成最终的手机内游戏抓包流程。

数据路径：系统 TCP 客户端（显式绑定 198.18.0.1）→ 系统 TUN（198.18.0.2:49153）→ lwIP → 本机 127.0.0.1 随机端口回显服务 → lwIP → TUN → 原系统 TCP 客户端。至少 32 KB 的运行期随机标识组成的测试数据完全返回且逐字节相同，才设置 passed。没有外部测试服务器，无账号数据，也不保存测试报文。

仅配置本应用 + 198.18.0.2/32 路由，未配置默认路由或 DNS。回显服务和其上游连接只使用 loopback，不需将转发进程整体绕过 VPN（否则同进程的测试客户端也可能绕过）。以后接互联网时必须针对上游 socket 使用系统 protect，当前未实现。

## 手机测试

1. 备份工程，用「一键更新.cmd」更新，DevEco 同步、Clean Project、Run。
2. 我的 → 本地抓包诊断，先运行「基础 UDP 诊断」，应仍为 passed。
3. 再运行「测试 TCP 双向转发」。无需打开游戏，测试最长约 8 秒（不含系统启动/授权等待）。
4. 复制回执。重点看 `testMode=tcp`、`phase=passed`、`code=0`、`cleanupConfirmed=true`。包数/字节数因分段、重传而不同，不设固定值。
5. 重复 TCP 测试一次；另起一次后立即停止，确认不遗留系统 VPN。真机成功前不把该环节标记验收。

`expectedRoundTripBytes` 是目标量，不是伪造的实际流量计数。`packets`/`bytes` 是 TUN 入站 IP 包计数，包含 TCP 头；`phase=passed` 才表示完整内容核对成功。`internetForwardingVerified=false` 和 `gameCaptureImplemented=false` 明确保留。

## 已做的主机验证

`python3 tests/run_tcp_relay_tests.py` 在本地 C/C++ 环境实际编译 lwIP 和转发代码，使用模拟 TUN 数据报通道与真实 loopback TCP 服务，验证：

- 128 KiB 二进制内容逐字节双向一致，分段和 2 KiB 窗口背压；
- 丢失 SYN-ACK 和数据包后的 TCP 重传；
- FIN 到上游的半关闭，重复建立/清理，单栈并发拒绝，提前取消；
- AddressSanitizer/UndefinedBehaviorSanitizer（该环境禁用 LeakSanitizer）。

ArkTS 服务模拟验证 UDP/TCP 分派、非法模式拒绝、取消/创建竞态、失败清理。静态配置检查通过。没有 Huawei SDK，未运行本版 ArkTSCheck、N-API 链接或真实系统 TUN 测试；不能用主机结果替代它们。

## 尚需开发

1. 确认目标游戏真实 HarmonyOS 包标识；转发器扩展多连接及真正外网连接，并通过 protect 避免路由回环。
2. DNS、UDP/QUIC、IPv6、网络切换、后台生命周期等。目前只是受限 IPv4 TCP 测试。
3. HTTPS 解密需独立实现设备内证书/密钥管理、明确的用户信任流程，并实测游戏是否接受用户证书。VPN fd 本身不提供 HTTP 明文，不能从密文扫描取得授权。
4. 只有拿到合法的抽卡历史授权并成功查询真实官方记录，才能实现本地去重/汇总；不得用社区账号 token 顶替。

文档参考：
- https://github.com/lwip-tcpip/lwip/tree/STABLE-2_2_1_RELEASE
- https://github.com/openharmony/docs/blob/master/zh-cn/application-dev/reference/apis-network-kit/js-apis-net-vpnExtension.md
- https://emanuele-f.github.io/PCAPdroid/tls_decryption.html
