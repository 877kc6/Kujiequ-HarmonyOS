# 库街区 1.8.4 ArkTS 编译修复

本补丁只修正 `entry/src/main/ets/services/MediaApi.ets` 原 148、157 行 `throw error` / `throw second` 在 ArkTS 下触发 10605087 的问题。失败时转换为 `MediaUploadError`（继承 `Error`）并保留 Error 原始 message。

## 更新

解压本包，运行 `Kujiequ/Update.cmd`，选择旧工程根目录；脚本自动备份后覆盖完整源码。重新用 DevEco Studio 构建 HAP。

**验证边界：** 已核对补丁源码、ZIP 和更新脚本文件；未实际运行 Windows PowerShell、DevEco Studio 或真机上传。
