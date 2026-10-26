import { AccountPageData, AccountRow, AccountListResult, Pair, PostItem, AccountListPayload, AccountNotice, FanInfo, FollowInfo } from '../models/Models';

export function accountTitle(kind: string): string {
  switch (kind) {
    case 'following': return '关注动态';
    case 'posts': return '我的帖子';
    case 'comments': return '评论和回复';
    case 'likes': return '收到的点赞';
    case 'mentions': return '@我的';
    case 'fans': return '粉丝';
    case 'follows': return '我的关注';
    case 'historyComments': return '我的历史评论';
    case 'collects': return '官方收藏';
    case 'system': return '系统消息';
    default: throw new Error('不支持的列表类型');
  }
}
export function accountPath(kind: string): string {
  switch (kind) {
    case 'following': return '/forum/dynamic/list';
    case 'posts': return '/forum/getMinePost';
    case 'comments': return '/user/notice/comment/page';
    case 'likes': return '/user/notice/like/page';
    case 'mentions': return '/user/notice/chat/page';
    case 'fans': return '/user/fans';
    case 'follows': return '/user/follow';
    case 'historyComments': return '/user/center/myComment';
    case 'collects': return '/user/center/myCollect';
    case 'system': return '/user/notice/help/page';
    default: throw new Error('不支持的列表类型');
  }
}
export function accountPairs(kind: string, page: number, userId: string): Pair[] {
  accountPath(kind);
  const pairs: Pair[] = [{ key: (kind === 'fans' || kind === 'follows') ? 'pageNo' : 'pageIndex', value: String(page) }, { key: 'pageSize', value: '20' }];
  if (kind === 'posts' || kind === 'fans' || kind === 'follows') {
    pairs.push({ key: 'type', value: '1' }); pairs.push({ key: 'otherUserId', value: userId });
  }
  if (kind === 'posts') { pairs.push({ key: 'searchType', value: '1' }); }
  if (kind === 'historyComments' || kind === 'collects') { pairs.push({ key: 'viewUserId', value: userId }); }
  if (kind === 'comments') { pairs.push({ key: 'type', value: '2' }); }
  if (kind === 'system') { pairs.push({ key: 'type', value: '3' }); }
  if (kind === 'likes') { pairs.push({ key: 'scan', value: '0' }); }
  return pairs;
}
function postRows(posts: PostItem[]): AccountRow[] {
  return posts.map((post: PostItem): AccountRow => {
    const pictures = post.coverImages || post.imgContent || [];
    return { key: String(post.postId), postId: String(post.postId), title: post.postTitle || '社区动态',
      text: typeof post.postContent === 'string' ? post.postContent : '', name: post.userName || '', avatar: post.userHeadUrl || '',
      cover: pictures.length ? pictures[0].url : '', time: post.showTime || '', unread: false, ownerId: String(post.userId || '') };
  });
}
// The official requester accepts a root array as well as an object field.
// Empty successful payloads must not be mistaken for a changed API schema.
function emptyPayload(data: AccountPageData, field: string): boolean {
  return Object.keys(data).every((key: string): boolean => [field, 'hasNext', 'ignoreHistory', 'total', 'pageIndex', 'pageNo', 'pageSize'].includes(key));
}
function shapeError(data: AccountPageData): Error {
  const keys = Object.keys(data).filter((key: string): boolean => /^[a-zA-Z_][a-zA-Z0-9_]{0,40}$/.test(key)).slice(0, 8).join(', ');
  return new Error('暂未识别列表结构，返回字段：' + (keys || '无') + '。请反馈此提示，不需要重复登录。');
}
export function accountRows(kind: string, payload: AccountListPayload): AccountListResult {
  accountPath(kind);
  if (payload === null || payload === undefined) { return { rows: [], hasNext: false }; }
  if (typeof payload !== 'object') { throw new Error('列表返回类型异常，请反馈此提示'); }
  const rootArray: boolean = Array.isArray(payload);
  const data = rootArray ? {} as AccountPageData : payload as AccountPageData;
  let rows: AccountRow[];
  if (kind === 'following' || kind === 'posts' || kind === 'collects') {
    const posts = rootArray ? payload as PostItem[] : (kind === 'following' ? data.dynamic : data.postList);
    if (posts == null && emptyPayload(data, kind === 'following' ? 'dynamic' : 'postList')) { return { rows: [], hasNext: false }; }
    if (!Array.isArray(posts)) { throw shapeError(data); }
    rows = postRows(posts);
  } else if (kind === 'fans') {
    const fans = rootArray ? payload as FanInfo[] : data.fansInfo;
    if (fans == null && emptyPayload(data, 'fansInfo')) { return { rows: [], hasNext: false }; }
    if (!Array.isArray(fans)) { throw shapeError(data); }
    rows = fans.map((fan: FanInfo): AccountRow => ({ key: String(fan.userId), postId: '', title: fan.userName || '库街区用户',
      text: fan.signature || '', name: 'ID ' + String(fan.userId), avatar: fan.userUrl || '', cover: '', time: '', unread: false, ownerId: String(fan.userId) }));
  } else if (kind === 'follows') {
    const follows = rootArray ? payload as FollowInfo[] : data.followInfo;
    if (follows == null && emptyPayload(data, 'followInfo')) { return { rows: [], hasNext: false }; }
    if (!Array.isArray(follows)) { throw shapeError(data); }
    rows = follows.map((user: FollowInfo): AccountRow => ({ key: String(user.followUserId), postId: '', title: user.followUserName || '库街区用户',
      text: user.signature || '', name: 'ID ' + String(user.followUserId), avatar: user.followUserUrl || '', cover: '', time: '', unread: false, ownerId: String(user.followUserId) }));
  } else {
    const notices = rootArray ? payload as AccountNotice[] : data.noticeVos;
    if (notices == null && emptyPayload(data, 'noticeVos')) { return { rows: [], hasNext: false }; }
    if (!Array.isArray(notices)) { throw shapeError(data); }
    rows = notices.map((notice: AccountNotice, index: number): AccountRow => ({ key: String(notice.id || notice.postCommentId || notice.postCommentReplyId || (kind + '_' + String(index) + '_' + String(notice.postId || '') + '_' + String(notice.showTime || ''))),
      postId: notice.noticeStatus || notice.sourceStatus ? '' : String(notice.postId || ''),
      title: notice.noticeTitle || (kind === 'likes' ? '赞了你的内容' : '消息'), text: notice.noticeContent || '',
      name: notice.sendUserName || '库街区', avatar: notice.sendUserHeadUrl || '', cover: '', time: notice.showTime || '', unread: notice.readState === 1 }));
  }
  if (rows.some((row: AccountRow): boolean => !row.key || row.key === 'undefined' || row.key === 'null')) { throw new Error('列表数据缺少必要字段，请反馈此提示，不需要重复登录。'); }
  return { rows: rows, hasNext: rows.length > 0 && (data.hasNext === undefined ? rows.length >= 20 : data.hasNext === 1 || data.hasNext === true) };
}
