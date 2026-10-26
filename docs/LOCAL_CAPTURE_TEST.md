> 1.6.2 新增独立 TCP 双向转发测试，见 [TCP_FORWARDING_TEST.md](TCP_FORWARDING_TEST.md)。下文保留基础 UDP 测试说明。

# 1.6.1-probe 本地抓包连接诊断

这份完整工程在 1.6.0 基础上增加可供 DevEco 构建的真机诊断入口。**尚未实现游戏请求转发、HTTPS 解密、获取抽卡授权、抽卡历史导入。** 不应作为正式抓包功能宣传。上一版的社区、发帖和安全区仍需真实设备验收。

## 你现在怎么测试

1. 解压源码。运行“一键更新.cmd”，选择原 Kujiequ 工程。脚本先备份，再更新源码并合并 VPN/Native 配置，保留包名和签名。也可以直接打开本包的 Kujiequ 文件夹，重新配置你自己的签名。
2. 在 DevEco 的 SDK 管理中确认 HarmonyOS API 26 和对应 Native 工具链已安装；同步工程，执行 Build → Clean Project，再 Run。本包显式构建 arm64-v8a 和 x86_64 两种 ABI。新增 C++ 模块会触发 Native 编译。若编译失败，发完整 Build Output 文本，尤其是第一条 error，不要只发最后一行构建失败。
3. 连接鸿蒙真机并运行。先关闭你正在使用的其他 VPN/代理 VPN；测试结束后自行重新开启。
4. 进入“我的 → 本地抓包诊断 · 开发测试”，点击“开始连接诊断”，按系统提示授权。
5. 不需要打开游戏。读包阶段最多约 3 秒；授权等待最多 60 秒。点击“复制诊断信息”发给开发者。也可以截图结果。
6. 如显示“网卡清理未确认”或“未收到完整回执”，到手机系统 VPN 设置确认并关闭库街区的 VPN。不要把只出现 VPN 图标当作成功。

请一并说明手机 HarmonyOS 版本、是否真机，以及测试前是否开过其他 VPN。诊断文本不含账号 token、手机号或游戏报文。

## 结果含义

| 显示/结果码 | 说明 |
| --- | --- |
| passed / 0 / cleanupConfirmed=true | 本次随机标识的测试 UDP 包从虚拟网卡读到，并已收到 destroy 成功回执。仅证明基础路径，不能证明游戏抓包可用。 |
| no_packet / 1 | 等待结束仍未读到匹配测试包，需要检查系统路由或应用过滤。 |
| cancelled / 2 | 已取消或本轮请求过期。 |
| failed / 3 | Native UDP socket 创建失败。 |
| failed / 4 | 绑定 VPN 专用源地址失败。 |
| failed / 5 | 测试 UDP 包发送失败。 |
| failed / 6 | TUN 读取/参数异常。 |
| failed / 其他数字 | 系统 BusinessError 或本地启动异常；保留原错误码。-1 是无数字错误码，-2 是页面无法写入请求文件。 |
| cleanup_failed | destroy 失败，不能宣布成功或网络资源已清理。 |
| unconfirmed | 在等待期限内没收到完整状态回执；需核查系统 VPN。 |

“已读包数”可能包含本次网卡上的非匹配包；只有逐项匹配目的地址、UDP 端口和本轮随机标识的包才判定通过。不会以计时器结束或包数大于零替代成功。

## 实现

- API 26 ArkTS 页面、VpnExtensionAbility、C++ N-API 异步工作线程。
- `trustedApplications` 只使用当前应用实际包名；不会写死开发者签名配置的包名，不代理游戏或其他应用。
- 诊断地址为 `198.18.0.1/30`，显式目标路由为 `198.18.0.2/32`，不是默认路由；不设置 DNS。只测试 IPv4。
- UDP 绑定诊断网卡专用源地址，最多发送 4 个小测试包；匹配本轮随机标识，无账号或真实 token。
- Native 借用 TUN fd 并持有独立副本，工作完成自动关闭副本；VPN 连接由扩展的 destroy 管理。不引入 Android/Flutter 运行时。
- 页面与 VPN 扩展可能处于不同进程；通过应用私有 filesDir 中两份小 JSON 原子替换通信，不假设 AppStorage 跨进程共享。
- 请求有到期时间和取消标记。停止发生在 create 尚未返回时，等待其返回后再清理，不会先 destroy 再留下迟到的网卡。
- onDestroy 取消 Native 工作；读包本身有固定上限。清理回执写出后尝试停止扩展。

## 本轮验证及限制

已运行：

```sh
node tests/services.test.cjs
node tests/capture_probe.test.cjs
python3 tests/check_project.py
g++ -std=c++17 -Wall -Wextra -Werror -pedantic -pthread \
  -fsanitize=address,undefined -fno-omit-frame-pointer -g \
  entry/src/main/cpp/probe.cpp tests/capture_probe_native_test.cpp \
  -o /tmp/kujiequ_probe_native_test
ASAN_OPTIONS=detect_leaks=0 /tmp/kujiequ_probe_native_test
```

Native 测试用主机 socketpair 模拟 TUN 报文，验证匹配、无关包拒绝、取消、超时、错误和 100,000 次随机报文边界；不是游戏实测。LeakSanitizer 在当前受限主机无法访问所需 /proc 目录，因此单独关闭；ASan/UBSan 仍启用。

尚未运行：Huawei API 26 ArkTSCheck、鸿蒙 Native 链接、assembleHap、Windows 更新脚本执行、真机 VPN 授权/路由/清理。当前没有鸿蒙 SDK 或设备，不声称编译安装成功。本包是诊断源码版，不是已签名 HAP。

后续必须继续实现本地 TCP/IP 转发和 HTTPS 处理，再验证游戏是否信任本地证书，并确认真实记录请求及有效授权。不能从此诊断结果推导“已经能抓 token”。

参考：OpenHarmony 官方 `js-apis-net-vpnExtension.md`、`js-apis-VpnExtensionAbility.md`、`net-vpnExtension.md`，保存在官方 docs 仓库。实际鸿蒙行为以 API 26 SDK 和真机结果为准。
