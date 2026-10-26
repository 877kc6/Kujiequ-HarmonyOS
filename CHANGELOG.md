## 1.8.14
- 评论作者头像、作者主页导航。
- 图文评论上传流程（实际 API 接受情况待验证）。
- 评论删除接口待确认，未冒用帖子删除 API。

1.8.13: Fix follow relation persistence across navigation by checking the authenticated /user/follow list on profile entry; refresh own-account follow/fan lists whenever shown; open native UserProfile from follow/fan rows; after successful follow/unfollow publish followChangedAt. A server-verified mineV2 other-user profile is still required to display other-user counts. Follow state check is limited to 15 pages; an unknown result is not treated as proof of not following. Native DevEco build and server tests are still required.

1.8.12: Fix follow button being disabled by mismatched profile response. Follow action uses post author ID; success is confirmed by API. Hide unverified counts, remove dynamic count label, rename user feed heading to Posts. Full stranger-profile and counts still depend on verified API.

1.8.11 author-page fallback (API 26)
- Keeps the clicked author's public ID/name/avatar when mineV2 returns a different account.
- Loads and filters author timeline by returned post owner ID.
- Follow actions remain disabled unless verified user profile data is returned.
- The backend currently returns mismatched profile identity for tested otherUserId; complete statistics cannot be validated.
- DevEco Studio build and device tests are still required.

1.8.10: User profile request/result ID validation, per-post author verification, and follow safety guards. A mismatched API response is shown as an error rather than another account.

## 1.8.9 - Session safety correction

- Prevent official-webpage token synchronization from silently overwriting an already signed-in native account.
- Preserve secure AssetStore credential storage and manual account switching.
- No claim of server-side token refresh: expired credentials still require an officially supported renewal or manual sign-in.

Kujiequ 1.8.8: Native user timeline and profile navigation
=======================================================
- Author avatar and name open the corresponding native user profile.
- User profile reads real account data, follow state, and user-specific posts with pagination.
- Post cards open the selected post; follow button calls the existing API.
- Own and other user profiles use distinct actions; no delete controls for other authors.
- Profile editing is not yet available: unverified write APIs are not used.
- Update.cmd: success closes, errors remain visible in Update.log.
- Build/run and backend API behavior have not been verified on device.

## 1.8.7 build fix (2026-10-26)
- Fix AppScope/app.json5 versionCode: 10807 -> 1008007 (previous v1.8.6 used 1008006).
- Update.cmd banner now identifies 1.8.7.
- No changes to app functionality.

## 1.8.7
# Kujiequ 1.8.7 - Native profile and follow

- Tapping an author avatar opens an ArkUI-native profile page (no WebView).
- The profile is loaded with `/user/mineV2` and displays name, avatar, biography and counters.
- Follow/unfollow uses `/user/followUser` with operateType 1 or 2. Server state is refreshed after mutation.
- The plus button was removed from the home top-right header. The existing bottom Publish tab remains.
- The My-page profile header opens the native user profile.
- Profile editing has **not** been enabled: a verified write endpoint for nickname/biography is still required. No fake local-only save.
- UI work is an incremental implementation, not a complete HarmonyX clone. Reuse of third-party sources needs licensing review.
- API response compatibility and HarmonyOS compilation still require device-side verification.

# Changelog

## 1.8.6 (2026-10-26)
- UI: 图片预览关闭按钮避让状态栏；移除底部提示。
- UI: 视频播放器改用沉浸式浮层按钮，接入现有 HDS 材质。
- Updates: Update.cmd 继续沿用自动备份替换、完成自动关闭流程。
- Scope: 本版不包含真实游戏流量代理或 HTTPS 解密。

## 1.8.5 compile hotfix (2026-10-26)

- Fix ArkTS 10605999 at Post.ets image preview handler: optional URL now has a string fallback.
- Version remains 1.8.5; no behavioral or protocol changes intended.
- Build must still be verified in DevEco Studio.

## 1.8.5 (2026-10-26)

- Fix history comment list key generation when notice IDs are absent; endpoint response still requires device verification.
- Tap inline post images for enlarged fullscreen viewer.
- Simplify video playback controls with explicit play/pause and expand/collapse buttons.
- Fix ZIP text filename encoding and Update.cmd auto-close; retain the backup and rollback updater.
- Game traffic forwarding, DNS, TLS trust and authorized gacha-history integration are NOT implemented; probe-only VPN remains unchanged.

## 1.8.4 编译修复（2026-10-26）

- 修复 `services/MediaApi.ets` 视频授权异常分支抛出任意类型值而触发的 ArkTS 10605087 错误（原第 148、157 行）。
- 保持图片/视频上传功能以及草稿行为不变；未经过 DevEco Studio 或真实服务器验证。
- 完整源码包附带 `Update.cmd` 一键备份与替换。

## 1.8.4 (2026-10-26)
- 视频预发布授权 220 提供一次协议源回退，不重试已提交的 OSS PUT。
- 发布页退出三选项：继续编辑、不保存（清除持久化草稿及缓存）、保存草稿。
- 重新进入发布页询问是否加载已保存草稿；非主动保存不写入持久化草稿。
- 同步版本号、README、更新脚本和更新说明。
- 本版本尚未在 DevEco Studio 与真实服务器验证。

# 更新记录（Changelog）

## 1.8.3 — 图片上传 220 处理调整
- 当 `uploadForumImgForH5` 返回业务码 220 时，保留当前会话并仅尝试一次另一种协议标识。
- 两次均返回 220 时提供明确提示；失败保留本地预览、附件草稿。
- 同步项目 README、更新文档与完整源码包。**尚未完成真实服务器及 DevEco 编译验证。**

## 1.8.2 — ArkTS 编译错误修复
- 移除 `AccountList.ets` 中不受 API 26 支持的 `ClickEvent.stopPropagation()`。
- 帖子打开入口与删除操作分离，降低误触风险。

## 1.8.1 — 上传、删除及 HTTPS 诊断
- 上传请求头补齐公共参数；上传失败显示阶段和错误码。
- 自己的帖子增加删除入口与二次确认，核对作者身份后调用服务端接口。
- HTTPS 测试区分 HTTP 响应状态与 TLS 验证，不再把 404 直接视作 TLS 失败。

## 1.8.0-preview — 媒体预览
- 图片、视频先建立本地预览，再尝试上传；支持失败重试及草稿。
- 视频播放、帖子界面及 HTTPS 加密转发测试持续完善。

历史更早版本规划见 [NEXT_VERSION.md](NEXT_VERSION.md)。


### 1.8.9 compile hotfix (2026-10-26)
- Fix `UserProfile.ets` ArkTS 10505001 at line 143: do not chain `width`, `height`, or `backgroundColor` on the custom `SafePage` component; apply full-size style to the outer `Stack` instead.
- Preserve user-profile timeline from 1.8.8 and session guard from 1.8.9. No versionCode bump (remains 1008009). Requires DevEco Studio compilation to confirm.
