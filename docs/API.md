# 接口实现和验证矩阵

所有原生请求固定发往 `https://api.kurobbs.com`，POST，`application/x-www-form-urlencoded; charset=utf-8`。敏感操作仅在用户点击后执行，不自动重试。

| 功能 | 路径 | 主要参数 | 验证状态 |
| --- | --- | --- | --- |
| 社区列表 | `/forum/list` | gameId, forumId, pageIndex, pageSize, searchType, timeType, topicId | 鸣潮、战双游客请求已实测；见结果 JSON |
| 帖子详情与首批评论 | `/forum/getPostDetail` | postId, isOnlyPublisher, showOrderType | 游客请求已实测 |
| 短信 | `/user/getSmsCode` | mobile, geeTestData | 模拟响应测试；未向真实号码发送 |
| 原生登录 | `/user/sdkLogin` | mobile, code, devCode, gameList | 已编码，未账号联调 |
| 个人资料 | `/user/mineV2` | otherUserId | 已编码，未账号联调 |
| 绑定角色 | `/gamer/role/list` | gameId | 游客鉴权拒绝已实测；未登录联调 |
| 数据终端 | `/gamer/widget/game3/getData`、`/gamer/widget/game2/getData` | gameId, serverId, roleId, userId, type, sizeType | 已编码，未账号联调；当前界面主要适配鸣潮字段 |
| 签到状态 | `/encourage/signIn/initSignInV2` | gameId, serverId, roleId, userId | 已编码，未账号联调 |
| 手动签到 | `/encourage/signIn/v2` | 上述参数加 reqMonth | 已编码，未账号联调；失败后只读核对结果 |
| 点赞 / 取消 | `/forum/like` | forumId, gameId, postId, toUserId, postType, likeType, operateType, postCommentId, postCommentReplyId | 已编码与错误处理测试，未登录联调 |

| 评论分页 | `/forum/comment/getPostCommentListV2` | postId, pageIndex, pageSize, showOrderType, isOnlyPublisher | 游客 HTTPS code 200 |
| 楼中楼分页 | `/forum/comment/getReplyList` | postId, postCommentId, pageIndex, pageSize | 游客 HTTPS code 200 |
| 发表评论 | `/forum/comment/createComment` | postId, forumId, gameId, postType, content, toUserId, chatUserIds | 官方网页协议与模拟测试；未真实写入 |
| 回复评论 / 楼中楼 | `/forum/comment/createReply` | 上述参数加 postCommentId, postCommentReplyId | 官方网页协议与模拟测试；未真实写入 |
| 网页凭证校验 | `/user/mineV2` | 使用网页 token，otherUserId | 已实现；未真实账号验收 |

## 响应约定

- 只有 `code === 200` 且 `success !== false` 才进入成功路径。
- `code === 220` 可能表示凭证过期或风控，不静默重复请求、不把它当网络成功。
- 请求超过时限、HTTP 非 200、JSON 解析失败都保留错误状态，HTTP 对象总在 finally 中释放。
- 帖子和角色 ID 一律使用字符串；避免 JavaScript Number 丢失 64 位编号精度。
- 若切换账号，使用旧账号发起的受保护请求不能覆盖新账号结果。
- `geeTest` 必须明确为 false 才确认短信已发送。需要验证时展示手动极验界面，将 getValidate 的结果作为 geeTestData 提交。验证窗口不接触手机号、短信或登录 token；只有服务器明确 geeTest=false 才提示发送成功。该路径尚未通过真实账号验收。
- 不伪造体力、角色、昵称或签到成功；字段缺失展示空态或提示。

## 协议兼容字段

`source: android` 是资料中要求的服务端请求字段，实际代码完全运行于鸿蒙 ArkTS。安装标识由本机首次启动生成；不复制资料中的设备号、IP、用户 token 或签名。`version: 2.2.0` 是已核对的接口兼容值，不是冒称本应用版本；协议后续变化集中在 KuroApi 修改。

## 来源

截至 2026-10-24 查阅：

- 功能参考：https://github.com/MrCashmere/hyoushe （闭源，仅功能参考，未复用实现）
- 接口资料：https://github.com/TomyJan/Kuro-API-Collection ，master tree `764c90fe3a77d3d9b1dae422f7f7b98740d19031`，MPL-2.0；本工程以接口字段为依据独立实现，未捆绑其文档或源码。
- 官方页面：https://www.kurobbs.com/ ，用于确认社区和地图入口。
- 华为 SDK：https://developer.huawei.com/consumer/cn/sdk
- 构建配置：https://developer.huawei.com/consumer/cn/doc/doccenter-deveco-studio/ide-hmos-hvigor-build-profile-app
- HDS Tabs：https://developer.huawei.com/consumer/cn/doc/harmonyos-references/ui-design-hdstabs
- Asset Store：https://developer.huawei.com/consumer/cn/doc/harmonyos-references/js-apis-asset

华为动态文档正文在本环境检索不完整。HDS 与 Asset 的具体签名参考了官方文档镜像中的示例，并保留官方原始入口；最终应以本机 API 26 SDK 类型声明和 ArkTSCheck 为准。

## 1.1.0 新增参考

- 官方网页自身静态资源：post-detail-DP5kdU8b.js、comment-reply-dialog-BMYg4x0A.js、index-DCU6Kl-8.js。仅用于核对协议，不捆绑官方源码。
- [华为沉浸光感开启方式与生效范围](https://developer.huawei.com/consumer/cn/doc/HarmonyOS-Guides/arkts-immersive-light-sense-enable)
- 系统明确限定正文区普通 Button 不生效，Navigation 标题栏、底部 Tabs 和指定弹窗等区域有相应支持。`Material.empty` 才是显式关闭，不能将 undefined 等同关闭。

## 1.4.0 官方轮播与页面入口

`POST /forum/getBannerList`：gameId、forumId=0，返回 OfficialBanner[]；已进行无账号只读探测。官方网页首页使用同一路径与参数。显示 url、msg，按 postId 打开详情，h5Url 只允许可信官方来源。

消息类别、关注、个人帖子/评论/粉丝/收藏与发帖本版采用官方网页路由，不能算作原生接口实现。受保护路由先在公开官方页连接登录态再导航，凭证不进入 URL 或日志。

## 1.5.0 原生账号列表

| 内容 | 接口 | 数据数组 | 附加参数 |
|---|---|---|---|
| 关注动态 | /forum/dynamic/list | dynamic | 无 |
| 我的帖子 | /forum/getMinePost | postList | type=1,otherUserId,searchType=1 |
| 评论回复 | /user/notice/comment/page | noticeVos | type=2 |
| 点赞 | /user/notice/like/page | noticeVos | scan=0 |
| @我 | /user/notice/chat/page | noticeVos | 无 |
| 粉丝 | /user/fans | fansInfo | type=1,otherUserId,pageNo |
| 我的历史评论 | /user/center/myComment | noticeVos | viewUserId |
| 官方收藏 | /user/center/myCollect | postList | viewUserId |
| 系统消息 | /user/notice/help/page | noticeVos | type=3 |

均 POST，token 只通过请求头传递。pageSize=20，除粉丝 pageNo 外均使用 pageIndex。返回 hasNext 有值时遵从服务端；缺失时按满页判断；空页终止。字段与请求参数来自官方前端各列表模块及 useListRequester。需真实账号验证，未声称官方开放 API、接口稳定性或写入能力。

## 1.5.4 列表结构兼容

官方useListRequester先检查data本身是否为数组，再访问指定数据字段；本版兼容这两种结构。仅成功空响应（空对象、空数组、null、分页元数据或指定列表字段null）视为无记录。未知非空字段不吞掉，仅显示字段名，不记录原始数据。

我的关注：POST /user/follow，type=1，otherUserId，pageNo/pageSize；数组followInfo；字段followUserId、followUserName、followUserUrl、signature。来源是当前官方my-follows与center-user-item前端模块。
