> 1.8.4 状态：新增视频授权220回退及手动草稿保存/加载确认；仍需真机测试。

> 1.7.1补充：修复可变长度HMAC密钥导入，播放失败显示环节/错误码，不再笼统推测视频审核。公开接口路径已经主机只读验证，鸿蒙运行仍待用户复测。

# 1.7.0-media-preview 开发与验收说明

本版原生 ArkTS/ArkUI，HarmonyOS API 26。没有加入 Android、Flutter 或网页视频播放器。不是已验证可发布的正式版，未提供已签名 HAP。

## 已加入的媒体代码

- 帖子详情读取 postDetail.videoId，调用库街区 `/forum/video/refreshPlayCode` 获取本视频短期授权；使用授权允许的 GetPlayInfo 请求取得未加密 HTTPS 播放地址，交给系统 ArkUI Video 播放。
- 视频未审核/不可播放时尊重 canPlay/reason。不尝试绕过 DRM。私有加密视频需要专用 SDK，目前会提示暂不支持。播放地址不写入本地草稿或日志；离开页面停止播放，回到页面不自动播放。
- PhotoViewPicker 选择图片/视频，不申请读取整个图库。图片通过 `/forum/uploadForumImgForH5` multipart `files` 上传。允许 JPEG/PNG/WebP/GIF，单张10 MiB，最多9张。
- MP4 通过 `/forum/video/prePublish` 获取临时 uploadAuth/uploadAddress/videoId；临时凭据签名 OSS PUT，不向 OSS 发送库街区 token。一次一个视频、50 MiB。当前完整读取文件后上传，故设置此上限；未做断点续传和分片重试。
- 视频发帖需要先添加一张图片作封面。上传成功后把图像内容、封面、videoId/videoName、postType=2 提交 `/forum/postPublish`。图片帖子沿用 postType=1。尚未实现话题选择。
- 图片/视频附件元数据随账号及游戏草稿保存，上传失败保留此前已成功附件。原始图库 URI 和云端临时密钥不持久保存。移除只是从草稿移除，不会自动调用云端删除。
- 发布及上传均不自动重试，避免重复发布或不受控上传。视频成功上传后仍需官方转码、审核，不能把上传成功当成帖子立即可见。

## 验收步骤

1. 一键更新.cmd → 选择旧 Kujiequ 工程 → DevEco 同步、Clean Project、Run。
2. 打开一个官方视频帖，点播放视频，验证实际画面、声音、原生进度控制；离开帖子后检查声音停止。
3. 编辑器先选择一张小 JPG，确认上传、预览、移除、保存/恢复草稿。若要发帖，先用一张小图及清楚的测试文字，发布后到我的帖子确认。
4. 选择小 MP4（建议先10秒以内）及封面，确认上传进度、草稿恢复，再自行发布检查转码审核状态。
5. 发生编译错误请提供 DevEco 错误文本；发生接口拒绝请反馈操作步骤和错误码，勿发送播放授权、OSS临时凭据、库街区token。

没有真实登录账号在本环境中上传或发布任何内容。本版没有 Huawei SDK、设备或运行中的 HarmonyOS 模拟器，因此没有完成 ArkTSCheck/assembleHap、播放器兼容性或真实账号接口验收。Node 测试是请求合同/资源清理模拟，不能替代真机结果。

## 本地抓包进度

用户已实测通过1.6.1 UDP、1.6.2本机TCP双向、1.6.3固定目标外网HTTP诊断。本版保留原诊断，不把媒体升级伪装成游戏抓包升级。诊断文本仍标记模块1.6.3。

游戏流量转发、DNS/UDP/IPv6、多连接支持、HTTPS代理和证书信任、抽卡历史授权识别及查询尚未完成，`gameCaptureImplemented=false` 仍有效。VPN fd 只返回网络数据包，无法从TLS密文中直接扫描出 record_id。完整游戏抓包必须继续实现可保持游戏联网的转发层和本机TLS代理，并在真机确认游戏是否信任用户证书；目前不能保证最终兼容性。

## 来源与许可

只研究公开官方客户端的接口格式，未复制播放器/上传SDK代码或打包第三方密钥。

- 库街区官方客户端资源：https://www.kurobbs.com/assets/useAliPlayerInit-BXcgM9LX.js （prePublish、refreshPlayCode、refreshUploadCode）
- https://www.kurobbs.com/assets/useAliPlayerVideoIdState-DjZzywGr.js （videoId/playAuth）
- https://www.kurobbs.com/assets/useConfig-DLqk4N_9.js （图片上传 files）
- https://www.kurobbs.com/assets/new-video-article-C-N2VeeI.js （视频发文字段与临时上传授权）
- https://help.aliyun.com/en/oss/developer-reference/include-signatures-in-the-authorization-header （OSS临时凭据签名）
- https://api.aliyun.com/document/vod （GetPlayInfo）
- https://help.aliyun.com/zh/vod/developer-reference/integrated-harmonyos-next-player-sdk （专用加密播放兼容性说明；未集成此付费SDK）
- 官方 OpenHarmony interface_sdk-js 的 MediaKit、ImageKit、NetworkKit、CryptoFramework 类型声明用于接口核对，仍以本机 Huawei SDK 26 编译结果为准。
