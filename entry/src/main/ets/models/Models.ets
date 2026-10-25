export interface Envelope<T> { code: number; msg?: string; message?: string; success?: boolean; data: T; traceId?: string; }
export interface Pair { key: string; value: string; }
export interface Picture { url: string; imgWidth?: number; imgHeight?: number; }
export interface Topic { topicId: string | number; topicName: string; }
export interface PostItem {
  postId: string; postTitle: string; postContent: string; userName: string;
  userId: string; userHeadUrl: string; gameId: number; gameForumId: number;
  likeCount: number; commentCount: number; isLike: number; showTime: string;
  imgContent?: Picture[]; coverImages?: Picture[]; postType?: number;
}
export interface FeedData { postList: PostItem[]; hasNext: number; topList?: PostItem[]; }
export interface ContentLink { title: string; url: string; }
export interface ContentBlock { contentType: number; content?: string; url?: string; imgWidth?: number; imgHeight?: number; contentLink?: ContentLink; }
export interface PostDetail {
  id: string; postTitle: string; userName: string; postUserId: string; headCodeUrl: string;
  postTime: string; postContent: ContentBlock[]; likeCount: number; commentCount: number;
  gameForumId: number; gameId: number; postType: number;
}
export interface CommentItem { commentId: string; userName: string; commentTime: string; commentContent: ContentBlock[]; replyCount?: number; userId: string; replyVos?: ReplyItem[]; }
export interface DetailData { gameId: number; isLike: number; postDetail: PostDetail; comment?: CommentItem[]; }
export interface LoginData { token: string; userId: string; userName: string; headUrl: string; }
export interface SmsData { geeTest?: boolean; }
export interface Profile { userId: string; userName: string; headUrl: string; signature?: string; postCount?: number; fansCount?: number; followCount?: number; }
export interface MineData { mine: Profile; }
export interface Role { userId: string | number; gameId: number; serverId: string; serverName: string; roleId: string; roleName: string; gameLevel: string; }
export interface Gauge { name: string; cur?: number; total?: number; refreshTimeStamp?: number; }
export interface WidgetData { roleId?: string; roleName?: string; energyData?: Gauge; livenessData?: Gauge; storeEnergyData?: Gauge; towerData?: Gauge; weeklyData?: Gauge; hasSignIn?: boolean; serverTime?: number; }
export interface SignInfo { isSigIn: boolean; sigInNum: number; nowServerTimes?: string; }
export interface LikeData { success: boolean; }
export interface SignResult { todayList?: Reward; tomorrowList?: Reward; }
export interface Reward { goodsNum?: number; goodsName?: string; }
export interface SavedPost { postId: string; postTitle: string; gameId: number; userName: string; savedAt: number; }
export interface WebParams { url: string; title: string; }
export interface PostParams { postId: string; }

export interface CaptchaProof { lot_number: string; captcha_output: string; pass_token: string; gen_time: string; captcha_id?: string; }

export interface ReplyItem { replyId: string; postCommentId: string; userId: string; userName: string; toUserName?: string; replyTime: string; replyContent: ContentBlock[]; }
export interface CommentListData { postCommentList: CommentItem[]; hasNext?: number; }
export interface ReplyListData { replys: ReplyItem[]; hasNext?: number; }
export interface CommentResult { commentId?: string; replyId?: string; postCommentId?: string; comment?: CommentItem; reply?: ReplyItem; }
export interface EditorText { type: number; content: string; target: string; }
export interface EditorParagraph { contentType: number; content: string; children: EditorText[]; }
export interface WebAccount { token: string; userId: string; }

// Official homepage carousel response, not user feed posts.
export interface OfficialBanner {
  id: number; url: string; msg: string; postId?: string; h5Url?: string;
  postTitle?: string; toAppIOS?: string;
}

export interface AccountNotice {
  id: string; postId?: string; sendUserId?: string; sendUserName?: string; sendUserHeadUrl?: string;
  noticeTitle?: string; noticeContent?: string; showTime?: string; readState?: number;
  postCommentId?: string; postCommentReplyId?: string; noticeStatus?: number;
  sourceStatus?: number; gameId?: number;
}
export interface FollowInfo { id?: string; followUserId: string; followUserName: string; followUserUrl?: string; signature?: string; }
export interface FanInfo { id?: string; userId: string; userName: string; userUrl?: string; signature?: string; }
export interface AccountPageData {
  postList?: PostItem[] | null; dynamic?: PostItem[] | null; noticeVos?: AccountNotice[] | null; fansInfo?: FanInfo[] | null;
  hasNext?: number | boolean; ignoreHistory?: boolean;
  followInfo?: FollowInfo[] | null;
}
export interface AccountRow {
  key: string; postId: string; title: string; text: string; name: string; avatar: string;
  cover: string; time: string; unread: boolean;
}
export type AccountListPayload = AccountPageData | PostItem[] | AccountNotice[] | FanInfo[] | FollowInfo[] | null;
export interface AccountListParams { kind: string; }
export interface AccountListResult { rows: AccountRow[]; hasNext: boolean; }

export interface PublishResult { postId?: string; }
export interface ComposeParams { gameId: number; }
export interface ComposeDraft { title: string; body: string; boardId: number; }
