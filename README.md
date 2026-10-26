1.8.13: Fix follow relation persistence across navigation by checking the authenticated /user/follow list on profile entry; refresh own-account follow/fan lists whenever shown; open native UserProfile from follow/fan rows; after successful follow/unfollow publish followChangedAt. A server-verified mineV2 other-user profile is still required to display other-user counts. Follow state check is limited to 15 pages; an unknown result is not treated as proof of not following. Native DevEco build and server tests are still required.

1.8.12: Fix follow button being disabled by mismatched profile response. Follow action uses post author ID; success is confirmed by API. Hide unverified counts, remove dynamic count label, rename user feed heading to Posts. Full stranger-profile and counts still depend on verified API.

1.8.11 author-page fallback (API 26)
- Keeps the clicked author's public ID/name/avatar when mineV2 returns a different account.
- Loads and filters author timeline by returned post owner ID.
- Follow actions remain disabled unless verified user profile data is returned.
- The backend currently returns mismatched profile identity for tested otherUserId; complete statistics cannot be validated.
- DevEco Studio build and device tests are still required.

1.8.10: User profile request/result ID validation, per-post author verification, and follow safety guards. A mismatched API response is shown as an error rather than another account.

Kujiequ 1.8.9: Native user timeline and profile navigation
=======================================================
- Author avatar and name open the corresponding native user profile.
- User profile reads real account data, follow state, and user-specific posts with pagination.
- Post cards open the selected post; follow button calls the existing API.
- Own and other user profiles use distinct actions; no delete controls for other authors.
- Profile editing is not yet available: unverified write APIs are not used.
- Update.cmd: success closes, errors remain visible in Update.log.
- Build/run and backend API behavior have not been verified on device.

# 库街区 Kujiequ

HarmonyOS 原生 ArkTS/ArkUI 社区客户端，目标 HarmonyOS API 26。

## v1.8.7 原生用户资料与关注

- 点击帖子作者头像打开原生个人主页。
- 关注/取关通过项目接入的用户接口请求。
- 修复版本号回退：`versionCode` 从错误的 10807 改为 1008007，以便从 1.8.6 覆盖安装并保留应用数据。
- 编辑个人资料的写入接口尚未验证完成。

## v1.8.6 界面更新

- 帖子图片全屏预览：关闭按钮下移并避让系统状态栏，取消底部冗余说明。
- 视频播放器：沉浸式浮层播放/暂停与画面展开按钮，沿用项目现有 HDS 材质。
- 保留账号、帖子、评论、发帖草稿和现有网络功能。
- **未实现真正的游戏流量抓取、HTTPS 解密或抽卡授权提取。**

视觉设计参考 [HarmonyX](https://github.com/haohaoai0/HarmonyX) 所公开的 HDS 导航与沉浸样式；本次采用独立实现，不直接复制其源码。

## 安装 / 更新

解压完整压缩包，进入 `Kujiequ`，双击 `Update.cmd`，选择旧工程根目录。脚本备份后覆盖源码，成功后自动退出。

## 测试状态

源码静态检查和压缩包完整性检查不等于编译通过。请在 DevEco Studio API 26 环境编译，并在真机检验图片预览与视频播放。


### Windows one-click updater troubleshooting

Run `Update.cmd` from the extracted `Kujiequ` folder and select the **existing** project root. On success, the window closes automatically. On failure, the window stays open and writes `Update.log` beside `Update.cmd`. Attach that log when reporting a failed update. The updater does not replace `.git` or local build caches.


# Kujiequ 1.8.7 - Native profile and follow

- Tapping an author avatar opens an ArkUI-native profile page (no WebView).
- The profile is loaded with `/user/mineV2` and displays name, avatar, biography and counters.
- Follow/unfollow uses `/user/followUser` with operateType 1 or 2. Server state is refreshed after mutation.
- The plus button was removed from the home top-right header. The existing bottom Publish tab remains.
- The My-page profile header opens the native user profile.
- Profile editing has **not** been enabled: a verified write endpoint for nickname/biography is still required. No fake local-only save.
- UI work is an incremental implementation, not a complete HarmonyX clone. Reuse of third-party sources needs licensing review.
- API response compatibility and HarmonyOS compilation still require device-side verification.


### 登录保持说明（1.8.9）

本机已使用 HarmonyOS AssetStore 保存登录凭证并在启动时恢复。1.8.9 阻止网页凭证静默替换已登录的原生账号。若服务器使 Token 失效，客户端不能保证永久登录，且尚未实现官方验证过的刷新机制；届时需重新认证。不要卸载应用或清除数据以免丢失本地草稿。


### 1.8.9 compile hotfix (2026-10-26)
- Fix `UserProfile.ets` ArkTS 10505001 at line 143: do not chain `width`, `height`, or `backgroundColor` on the custom `SafePage` component; apply full-size style to the outer `Stack` instead.
- Preserve user-profile timeline from 1.8.8 and session guard from 1.8.9. No versionCode bump (remains 1008009). Requires DevEco Studio compilation to confirm.


## 1.8.14 评论体验更新

- 评论及回复新增作者头像和原生个人主页跳转。
- 评论增加选图、上传以及图文提交尝试，图片评论请求体需要真机服务端验证。
- 删除评论接口尚未得到可靠验证，本版不提供会误删或假删除的操作。
