> 这是早期独立 PacketPump 原型记录。当前 1.6.1-probe 已另行接入限时诊断模块，见 ../../docs/LOCAL_CAPTURE_TEST.md；下面的“未接入应用”指本目录的 PacketPump，不代表当前诊断模块。

# 手机本地抓包开发稿（未接入应用）

2026-10-25。目标：库街区内主动开启捕获 → 用户切换到自己的游戏并打开抽卡历史 → 回到库街区导入记录。没有电脑提取步骤，也不以手动粘贴链接替代最终目标。

**这不是可安装/可用的抓包版本。1.6.0 的应用代码、版本号、权限和更新脚本没有改变。当前无法抓到游戏授权，也无法导入真实抽卡记录。** 上一版仍是用户未实测的基线。

## 已写和已测试

- 自编 C++17 PacketPump：从调用者提供的文件描述符读取 IP 数据包，交给必需的同步转发回调。
- 固定 65,576 字节缓存，没有无限队列、不记录报文正文和凭据。独立线程，唤醒管道，单次生命周期。
- 持有描述符副本，停止会回收副本和唤醒管道，不关闭调用者持有的原始描述符。
- 分类 IPv4/IPv6 的直接 TCP、UDP 报文。分片、IPv6 扩展头、未知协议不猜测端口，仍将原始报文交给转发回调。
- 错误可区分读取失败和转发失败。回调异常被截获；不冒充成功。
- Linux 主机实际编译和 socketpair 数据传输测试通过：字节完整性、重复启动拒绝、重复停止、空闲停止、错误退出、原始描述符保留、截断/畸形数据、100,000 次随机报文输入。

测试回调只是往另一对本地 socket 转发字节，**不是实际 TCP/IP 网络转发器**。主机测试不等于手机 VPN 或游戏验收。代码未复制第三方实现，沿用项目 MIT 许可。

## 尚未实现的关键部分

1. VpnExtensionAbility、ArkTS/N-API 桥接与 Native 构建接入。没有在 module.json5 注册实验 VPN；没有创建系统 VPN 或更改路由。
2. 本地 TCP/IP 转发引擎及上下行数据返回。仅把 TUN 包读取出来不能维持游戏联网；不能把原始 IP 包直接塞到普通 TCP socket 当作完成转发。
3. 目标游戏 HarmonyOS 包标识核实、按应用限制、网络切换、IPv6、DNS、QUIC 的处理。不能用 Android 包名代替实际鸿蒙应用标识。
4. 本地 HTTPS 解密引擎、设备内生成并保管的证书、用户安装信任证书流程、游戏是否信任用户证书的实测。目前没有证书生成/安装功能。没有服务器私钥或会话密钥时，不能靠扫描密文取得 record_id/token。
5. 从真实解密请求确认抽卡授权字段、分区/角色身份、过期处理；然后才接官方记录查询和去重统计。库街区账号 token 不能默认视作抽卡记录授权。
6. 游戏请求必须原样完成；导入成功、超时、用户停止、系统撤销时解除捕获并清除临时凭据。不能只有一个“正在捕获”的计时器。

## 后续接入约束

- 先验证真实数据转发和完整停止清理，再接游戏流量。不要创建没有转发后端的全局默认路由，否则会造成断网。
- `PacketPump` 的 forward 回调必须有界、同步消耗/复制数据；不能在回调里调用同一对象的 stop，也不能再从原始 TUN fd 读取。生命周期函数由同一所属线程调用。
- Pump 不拥有 VPN；宿主发现 ReadError/ForwardError 或退出时，必须销毁 VPN 路由，再收回持有的原始句柄。只有 stop 不足以恢复系统网络。
- 未分类报文不在检测层丢弃。TCP 重组、分片处理、校验和、重传和回包属于后续网络引擎。
- 只在拿到目标请求并成功查询至少一页真实记录后，才能显示“已获取授权”。目前不得显示此状态。
- 捕获由明确的用户动作启动。首次系统授权和证书信任步骤不能靠“随 App 启动脚本”替代。

## 文档核对结果

本轮读取了 OpenHarmony 官方 VPN API 原始文档；它是底层接口参考，仍需用 HarmonyOS API 26 SDK 核对实际声明并在真机验证。

- `startVpnExtensionAbility(want)` 启动 VPN 扩展；在此之后创建连接。
- `createVpnConnection(context).create(config)` 返回虚拟网卡 fd，不是解密后的 HTTP 请求。
- `trustedApplications` 与 routes 共同限定代理应用；不能与 blockedApplications 同时配置。
- `protect(socketFd)` 用于使转发 socket 绕过自己的 VPN，防止回环。
- `destroy()` 清理 VPN 网络；不能仅停掉读包线程。
- 当前读取的 VpnConfig 没有可直接启用 HTTPS 解密的字段。

来源：

- 华为 VPN 指南：https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/net-vpnextension （动态网页未能完整读取）
- OpenHarmony 官方 API：https://github.com/openharmony/docs/blob/master/zh-cn/application-dev/reference/apis-network-kit/js-apis-net-vpnExtension.md （已读取 raw 正文）
- PCAPdroid 官方说明：https://emanuele-f.github.io/PCAPdroid/faq.html
- PCAPdroid HTTPS 说明：https://emanuele-f.github.io/PCAPdroid/tls_decryption.html
- PCAPdroid 解密组件：https://github.com/emanuele-f/PCAPdroid-mitm

PCAPdroid 的 Android 组件不能直接装进鸿蒙原生应用。本轮只参考抓包/解密分层原理，没有下载或移植其代码。

## 复现主机测试

在本目录执行（需要 g++，不是让最终用户用电脑提取数据）：

```sh
g++ -std=c++17 -Wall -Wextra -Werror -pedantic -pthread \
  -fsanitize=address,undefined -fno-omit-frame-pointer -g \
  capture_core.cpp capture_core_test.cpp -o /tmp/kujiequ_capture_core_test
ASAN_OPTIONS=detect_leaks=0 /tmp/kujiequ_capture_core_test
```

当前执行环境的 LeakSanitizer 因无法读取 /proc 任务目录而失败，因此上面关闭了泄漏检测；AddressSanitizer 和 UndefinedBehaviorSanitizer 保持启用并通过。不宣称完成内存泄漏检测。

CMakeLists.txt 提供静态库构建定义，但当前环境没有 cmake/鸿蒙 SDK，**未验证 CMake 配置、N-API 链接、ArkTSCheck、assembleHap 或真机行为**。

## 交付状态

这份开发稿只保存独立底层工作，不替换原应用，不包含伪造的游戏记录或成功提示。完整本地抓包功能仍未完成，需要继续接入上面的关键环节和真机验证后，才适合升级应用版本号。
