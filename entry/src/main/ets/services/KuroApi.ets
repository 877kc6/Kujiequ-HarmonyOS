import { mediaContent, mediaHtml } from './MediaProtocol';
import { publishBoard, postContent, escapedHtml } from './GameBoards';
import { accountPath, accountPairs, accountRows } from './AccountData';
import { http } from '@kit.NetworkKit';
import { Envelope, Pair, FeedData, DetailData, SmsData, LoginData, MineData, Role, WidgetData, SignInfo, SignResult, LikeData, PostDetail, Profile, CommentListData, ReplyListData, CommentResult, EditorText, EditorParagraph, PublishResult, UploadedMedia, Picture, OfficialBanner, AccountListPayload, AccountListResult, AccountRow } from '../models/Models';
import { ApiError, formEncode, checked, chinaMonth } from './Protocol';
import { Session } from './Session';
import { LocalStore } from './LocalStore';

export class KuroApi {
  private static readonly base: string = 'https://api.kurobbs.com';
  static headers(source: string = 'android', credential: string = ''): Record<string, string> {
    const headers: Record<string, string> = {
        'Content-Type': 'application/x-www-form-urlencoded; charset=utf-8',
        'Accept': 'application/json', 'source': source, 'version': '2.2.0',
        'versionCode': '2200', 'devCode': LocalStore.deviceId, 'distinct_id': LocalStore.deviceId,
        'lang': 'zh-Hans', 'countryCode': 'CN', 'User-Agent': 'KujiequHarmony/1.0',
        'Origin': 'https://web-static.kurobbs.com'
      };
    if (credential || Session.token) { headers['token'] = credential || Session.token; }
    return headers;
  }
  static async post<T>(path: string, pairs: Pair[], auth: boolean = false, credential: string = '', source: string = 'android'): Promise<T> {
    if (auth && !Session.token) { throw new ApiError(220, '请先登录库街区账号'); }
    const generation = Session.generation;
    const request = http.createHttp();
    try {
      // source is a server protocol field, not an Android runtime dependency.
      const headers = KuroApi.headers(source, credential);
      const response = await request.request(KuroApi.base + path, {
        method: http.RequestMethod.POST, header: headers, extraData: formEncode(pairs),
        expectDataType: http.HttpDataType.STRING, connectTimeout: 15000, readTimeout: 20000,
        usingCache: false, maxLimit: 5 * 1024 * 1024
      });
      if (response.responseCode !== 200) { throw new ApiError(response.responseCode, `服务暂时不可用（HTTP ${response.responseCode}）`); }
      if (generation !== Session.generation) { throw new ApiError(-3, '账号已切换，请刷新后重试'); }
      let body: Envelope<T>;
      try { body = JSON.parse(response.result as string) as Envelope<T>; }
      catch (_) { throw new ApiError(-2, '服务器返回了无法识别的内容'); }
      return checked<T>(body);
    } finally { request.destroy(); }
  }
  static async accountList(kind: string, page: number, requestedUserId: string = ''): Promise<AccountListResult> {
    const loginUserId = Session.userId; const userId = requestedUserId || loginUserId; const generation = Session.generation;
    if (requestedUserId && kind !== 'posts' && kind !== 'fans' && kind !== 'follows') { throw new Error('不支持读取该用户列表'); }
    if (requestedUserId && !/^\d{1,24}$/.test(requestedUserId)) { throw new Error('无效用户编号'); }
    const path = accountPath(kind); const pairs = accountPairs(kind, page, userId);
    let data: AccountListPayload;
    try {
      // Use the same protocol source as native SMS login and profile requests.
      data = await KuroApi.post<AccountListPayload>(path, pairs, true);
    } catch (e) {
      const first = e as ApiError;
      if (first.code !== 220 || generation !== Session.generation) { throw first; }
      // Imported website sessions may require the website protocol source.
      // Only these read-only lists may retry; never retry comments/sign-in/publishing.
      try { data = await KuroApi.post<AccountListPayload>(path, pairs, true, '', 'h5'); }
      catch (secondError) {
        const second = secondError as ApiError;
        if (second.code !== 220 || generation !== Session.generation) { throw second; }
        // A single list rejection must not invalidate a still-working native account.
        let profileValid: boolean = false;
        try {
          const mine = await KuroApi.profile();
          profileValid = String(mine?.mine?.userId || '') === loginUserId;
        } catch (profileError) {
          const profileFailure = profileError as ApiError;
          if (profileFailure.code !== 220) { throw profileFailure; }
        }
        if (generation !== Session.generation) { throw new ApiError(-3, '账号已切换，请刷新'); }
        if (profileValid) { throw new ApiError(221, '账号资料验证正常，但该列表接口拒绝授权（220）。已保留登录，请尝试重新认证。', second.traceId); }
        throw second;
      }
    }
    return accountRows(kind, data);
  }

  static publish(gameId: number, boardId: number, title: string, body: string, attachments: UploadedMedia[] = []): Promise<PublishResult> {
    if (!publishBoard(gameId, boardId)) { throw new Error('请选择本游戏的发布分区'); }
    if (!title.trim() || title.trim().length > 40 || !body.trim() || body.length > 10000) { throw new Error('标题需1–40字，正文需1–10000字'); }
    if (attachments.some((m: UploadedMedia): boolean => !!m.uploadState && m.uploadState !== 'uploaded')) { throw new Error('请先完成附件上传，或移除上传失败的附件'); }
    const videos = attachments.filter((m: UploadedMedia): boolean => m.kind === 'video');
    const images = attachments.filter((m: UploadedMedia): boolean => m.kind === 'image');
    if (attachments.length > 10 || videos.length > 1 || images.length > 9 || attachments.some((m: UploadedMedia): boolean =>
      (m.kind !== 'video' && m.kind !== 'image') || (m.kind === 'image' && !/^https:\/\//i.test(m.url)) || (m.kind === 'video' && !/^[a-zA-Z0-9_-]{8,128}$/.test(m.videoId)))) { throw new Error('附件格式或数量无效'); }
    if (videos.length && images.length === 0) { throw new Error('视频帖子需要选择一张图片作为封面'); }
    const video = videos.length ? videos[0] : undefined;
    const cover = images.length ? images[0] : undefined;
    const covers: Picture[] = cover ? [{ url: cover.url, imgWidth: cover.width, imgHeight: cover.height }] : [];
    return KuroApi.post<PublishResult>('/forum/postPublish', [
      { key: 'gameId', value: String(gameId) }, { key: 'gameForumId', value: String(boardId) },
      { key: 'postTitle', value: title.trim() }, { key: 'content', value: attachments.length ? mediaContent(body.trim(), attachments) : postContent(body.trim()) },
      { key: 'h5Content', value: attachments.length ? mediaHtml(body.trim(), attachments) : escapedHtml(body.trim()) }, { key: 'newH5Content', value: attachments.length ? mediaHtml(body.trim(), attachments) : escapedHtml(body.trim()) },
      { key: 'postType', value: video ? '2' : '1' }, { key: 'isCopyright', value: '0' }, { key: 'isAiContent', value: 'false' },
      { key: 'publishType', value: '0' }, { key: 'publishTime', value: '' }, { key: 'showRange', value: '0' },
      { key: 'draftId', value: '' }, { key: 'topicIdStr', value: '' }, { key: 'chatUserIds', value: '' },
      { key: 'coverImageInfo', value: JSON.stringify(covers) },
      { key: 'videoId', value: video?.videoId || '' }, { key: 'videoName', value: video?.name || '' }
    ], true);
  }
  static async deletePost(id: string): Promise<void> {
    if (!Session.token || !Session.userId) { throw new ApiError(220, '请先登录'); }
    const owner = Session.userId; const generation = Session.generation;
    const detail = await KuroApi.detail(id);
    if (generation !== Session.generation || String(detail.postDetail.postUserId) !== owner) { throw new Error('只能删除当前账号自己的帖子'); }
    await KuroApi.post<LikeData>('/forum/more/delete', [{ key: 'deleteType', value: '1' }, { key: 'id', value: id }], true);
  }
  static banners(gameId: number): Promise<OfficialBanner[]> {
    return KuroApi.post<OfficialBanner[]>('/forum/getBannerList', [
      { key: 'gameId', value: String(gameId) }, { key: 'forumId', value: '0' }
    ]);
  }
  static feed(gameId: number, forumId: number, page: number, sort: number): Promise<FeedData> {
    return KuroApi.post<FeedData>('/forum/list', [
      { key: 'gameId', value: String(gameId) }, { key: 'forumId', value: String(forumId) },
      { key: 'pageIndex', value: String(page) }, { key: 'pageSize', value: '20' },
      { key: 'searchType', value: String(sort) }, { key: 'timeType', value: '0' }, { key: 'topicId', value: '0' }
    ]);
  }
  static detail(id: string): Promise<DetailData> {
    if (!/^\d{1,24}$/.test(id)) { throw new ApiError(-1, '帖子编号无效'); }
    return KuroApi.post<DetailData>('/forum/getPostDetail', [{ key: 'postId', value: id }, { key: 'isOnlyPublisher', value: '0' }, { key: 'showOrderType', value: '2' }]);
  }
  static async sms(mobile: string, geeTestData: string = ''): Promise<void> {
    if (!/^1\d{10}$/.test(mobile)) { throw new Error('请输入中国大陆 11 位手机号'); }
    const data = await KuroApi.post<SmsData>('/user/getSmsCode', [{ key: 'mobile', value: mobile }, { key: 'geeTestData', value: geeTestData }]);
    if (data?.geeTest !== false) { throw new ApiError(412, '需要完成人机验证，请在下方验证窗口中手动操作。'); }
  }
  static async login(mobile: string, code: string): Promise<void> {
    if (!/^1\d{10}$/.test(mobile) || !/^\d{4,8}$/.test(code)) { throw new Error('请检查手机号和短信验证码'); }
    const data = await KuroApi.post<LoginData>('/user/sdkLogin', [
      { key: 'mobile', value: mobile }, { key: 'code', value: code },
      { key: 'devCode', value: LocalStore.deviceId }, { key: 'gameList', value: '' }
    ]);
    await Session.save(data);
  }
  static async importWebAccount(token: string, userId: string): Promise<Profile> {
    if (!token || token.length > 2048 || /[\r\n]/.test(token)) { throw new Error('网页登录凭证格式异常'); }
    const generation = Session.generation;
    const data = await KuroApi.post<MineData>('/user/mineV2', [{ key: 'otherUserId', value: userId }], false, token);
    if (generation !== Session.generation) { throw new Error('账号已变化，请重新打开登录页'); }
    if (!data?.mine?.userId) { throw new Error('网页登录尚未取得可用的社区账号'); }
    const mine = data.mine; mine.userId = String(mine.userId);
    if (userId && String(mine.userId) !== userId) { throw new Error('账号校验不一致'); }
    await Session.save({ token: token, userId: String(mine.userId), userName: mine.userName, headUrl: mine.headUrl });
    await LocalStore.saveProfile(mine);
    AppStorage.setOrCreate('bootMessage', '网页登录已同步，请查看角色数据');
    return mine;
  }
  static comments(postId: string, page: number): Promise<CommentListData> {
    return KuroApi.post<CommentListData>('/forum/comment/getPostCommentListV2', [
      { key: 'postId', value: postId }, { key: 'pageIndex', value: String(page) }, { key: 'pageSize', value: '20' },
      { key: 'showOrderType', value: '3' }, { key: 'isOnlyPublisher', value: '0' }
    ]);
  }
  static replies(postId: string, commentId: string, page: number): Promise<ReplyListData> {
    return KuroApi.post<ReplyListData>('/forum/comment/getReplyList', [
      { key: 'postId', value: postId }, { key: 'postCommentId', value: commentId },
      { key: 'pageIndex', value: String(page) }, { key: 'pageSize', value: '20' }
    ]);
  }
  static comment(post: PostDetail, text: string, commentId: string = '', toUserId: string = '', replyId: string = '', imageUrl: string = ''): Promise<CommentResult> {
    const trimmed = text.trim();
    if ((!trimmed && !imageUrl) || trimmed.length > 1000) { throw new Error('请输入 1–1000 字评论'); }
    const textNode: EditorText = { type: 1, content: trimmed, target: '' };
    const content: EditorParagraph[] = trimmed ? [{ contentType: 1, content: trimmed, children: [textNode] }] : [];
    if (imageUrl) { content.push({ contentType: 2, content: '', children: [], url: imageUrl }); }
    const params: Pair[] = [
      { key: 'postId', value: post.id }, { key: 'forumId', value: String(post.gameForumId) },
      { key: 'gameId', value: String(post.gameId) }, { key: 'postType', value: String(post.postType || 1) },
      { key: 'content', value: JSON.stringify(content) }, { key: 'toUserId', value: toUserId || String(post.postUserId) },
      { key: 'chatUserIds', value: '' }
    ];
    if (commentId) { params.push({ key: 'postCommentId', value: commentId }); params.push({ key: 'postCommentReplyId', value: replyId }); }
    // Never retry writes automatically; an interrupted response may have committed.
    return KuroApi.post<CommentResult>(commentId ? '/forum/comment/createReply' : '/forum/comment/createComment', params, true);
  }
  static profile(): Promise<MineData> {
    return KuroApi.post<MineData>('/user/mineV2', [{ key: 'otherUserId', value: Session.userId }], true);
  }
  static userProfile(userId: string): Promise<MineData> {
    if (!/^\d{1,24}$/.test(userId)) { return Promise.reject(new Error('Invalid user ID')); }
    return KuroApi.post<MineData>('/user/mineV2', [{ key: 'otherUserId', value: userId }], true);
  }
  // Resolve relations from the signed-in account's follow list. The mineV2 other-user
  // response is unreliable on current servers and must not determine this state.
  static async isFollowing(userId: string): Promise<boolean> {
    if (!/^\d{1,24}$/.test(userId)) { throw new Error('Invalid follow target'); }
    const sessionId: string = Session.userId;
    for (let page: number = 1; page <= 15; page++) {
      const result = await KuroApi.accountList('follows', page, sessionId);
      if (sessionId !== Session.userId) { throw new Error('Account changed'); }
      if (result.rows.some((item: AccountRow): boolean => item.ownerId === userId)) { return true; }
      if (!result.hasNext) { return false; }
    }
    throw new Error('Follow list is too long to verify; please refresh later');
  }
  static followUser(userId: string, follow: boolean): Promise<LikeData> {
    if (!/^\d{1,24}$/.test(userId) || userId === Session.userId) { return Promise.reject(new Error('Invalid follow target')); }
    return KuroApi.post<LikeData>('/user/followUser', [
      { key: 'followUserId', value: userId }, { key: 'operateType', value: follow ? '1' : '2' }
    ], true);
  }
  static roles(gameId: number): Promise<Role[]> { return KuroApi.post<Role[]>('/gamer/role/list', [{ key: 'gameId', value: String(gameId) }], true); }
  private static roleParams(role: Role): Pair[] {
    return [{ key: 'gameId', value: String(role.gameId) }, { key: 'serverId', value: role.serverId }, { key: 'roleId', value: String(role.roleId) }, { key: 'userId', value: Session.userId }];
  }
  static widget(role: Role): Promise<WidgetData> {
    return KuroApi.post<WidgetData>(`/gamer/widget/game${role.gameId}/getData`, KuroApi.roleParams(role).concat([{ key: 'type', value: '2' }, { key: 'sizeType', value: '1' }]), true);
  }
  static signInfo(role: Role): Promise<SignInfo> { return KuroApi.post<SignInfo>('/encourage/signIn/initSignInV2', KuroApi.roleParams(role), true); }
  static sign(role: Role): Promise<SignResult> {
    return KuroApi.post<SignResult>('/encourage/signIn/v2', KuroApi.roleParams(role).concat([{ key: 'reqMonth', value: chinaMonth() }]), true);
  }
  static like(post: PostDetail, already: boolean): Promise<LikeData> {
    return KuroApi.post<LikeData>('/forum/like', [
      { key: 'forumId', value: String(post.gameForumId) }, { key: 'gameId', value: String(post.gameId) },
      { key: 'postId', value: post.id }, { key: 'toUserId', value: String(post.postUserId) },
      { key: 'postType', value: String(post.postType ?? 1) }, { key: 'likeType', value: '1' },
      { key: 'operateType', value: already ? '2' : '1' }, { key: 'postCommentId', value: '0' }, { key: 'postCommentReplyId', value: '0' }
    ], true);
  }
}
