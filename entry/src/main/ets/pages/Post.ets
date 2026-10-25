import { SafePage } from '../components/SafePage';
import { ApiError } from '../services/Protocol';
import { UiTheme } from '../services/UiTheme';
import { DetailData, ContentBlock, CommentItem, PostParams, SavedPost, ReplyItem } from '../models/Models';
import { KuroApi } from '../services/KuroApi';
import { Session } from '../services/Session';
import { LocalStore } from '../services/LocalStore';
import { officialPostUrl, isOfficialUrl } from '../services/Protocol';

@Entry
@Component
struct Post {
  @StorageLink('layoutDiagnostic') diagnostic: boolean = false;
  @StorageLink('immersiveEnabled') materialEnabled: boolean = true;
  @StorageLink('materialThickness') materialThickness: number = 2;
  @StorageLink('darkTheme') darkTheme: boolean = false;
  @State detail?: DetailData = undefined;
  @State busy: boolean = false;
  @State liking: boolean = false;
  @State saving: boolean = false;
  @State liked: boolean = false;
  @State saved: boolean = false;
  @State message: string = '';
  @State comments: CommentItem[] = [];
  @State commentPage: number = 1;
  @State moreComments: boolean = true;
  @State commentsBusy: boolean = false;
  @State draft: string = '';
  @State sending: boolean = false;
  @State replyCommentId: string = '';
  @State replyUserId: string = '';
  @State replyId: string = '';
  @State replyName: string = '';
  @State expandedCommentId: string = '';
  @State replies: ReplyItem[] = [];
  @State replyPage: number = 1;
  @State moreReplies: boolean = true;
  @State repliesBusy: boolean = false;
  @State updatesAvailable: boolean = false;
  private polling: number = -1;
  private visible: boolean = false;
  private requestVersion: number = 0;
  onPageShow(): void {
    this.visible = true;
    if (this.polling === -1) { this.polling = setInterval(() => { this.checkUpdates(); }, 30000); }
  }
  onPageHide(): void { this.visible = false; this.requestVersion++; if (this.polling !== -1) { clearInterval(this.polling); this.polling = -1; } }
  aboutToDisappear(): void { this.onPageHide(); }
  private async checkUpdates(): Promise<void> {
    if (!this.visible || this.busy || this.commentsBusy || this.sending || this.liking) { return; }
    const version = this.requestVersion;
    try {
      const data = await KuroApi.detail(this.currentPostId);
      if (!this.visible || version !== this.requestVersion || !this.detail) { return; }
      this.updatesAvailable = this.updatesAvailable || data.postDetail.commentCount !== this.detail.postDetail.commentCount;
      this.detail = data; this.liked = data.isLike === 1;
    } catch (_) { /* A background failure must not interrupt reading or editing. */ }
  }
  private async loadComments(reset: boolean): Promise<void> {
    if (this.commentsBusy) { return; } this.commentsBusy = true; this.requestVersion++;
    try {
      const page = reset ? 1 : this.commentPage + 1;
      const data = await KuroApi.comments(this.currentPostId, page);
      if (!Array.isArray(data?.postCommentList)) { throw new Error('评论响应格式变化，请稍后重试'); }
      const list = data.postCommentList;
      this.comments = reset ? list : this.comments.concat(list.filter((c: CommentItem): boolean => !this.comments.some((old: CommentItem): boolean => old.commentId === c.commentId)));
      this.commentPage = page; this.moreComments = list.length >= 20 && data.hasNext !== 0;
      if (reset) { this.updatesAvailable = false; }
    } catch (e) { this.message = '评论：' + (e as Error).message; }
    finally { this.commentsBusy = false; }
  }
  private async loadReplies(comment: CommentItem, reset: boolean): Promise<void> {
    if (this.repliesBusy) { return; } this.repliesBusy = true;
    if (reset) { this.expandedCommentId = comment.commentId; this.replyPage = 0; this.replies = comment.replyVos ?? []; }
    try {
      const page = this.replyPage + 1;
      const data = await KuroApi.replies(this.currentPostId, comment.commentId, page);
      if (!Array.isArray(data?.replys)) { throw new Error('回复响应格式变化'); }
      this.replies = reset ? data.replys : this.replies.concat(data.replys.filter((r: ReplyItem): boolean => !this.replies.some((old: ReplyItem): boolean => old.replyId === r.replyId)));
      this.replyPage = page; this.moreReplies = data.replys.length >= 20 && data.hasNext !== 0;
    } catch (e) { this.message = '回复：' + (e as Error).message; }
    finally { this.repliesBusy = false; }
  }
  private target(commentId: string, userId: string, name: string, replyId: string = ''): void {
    this.replyCommentId = commentId; this.replyUserId = userId; this.replyName = name; this.replyId = replyId;
  }
  private async send(): Promise<void> {
    if (this.sending || !this.detail || !this.draft.trim()) { return; }
    if (!Session.token) { this.getUIContext().getRouter().pushUrl({ url: 'pages/Login' }); return; }
    this.sending = true; this.requestVersion++; this.message = '';
    try {
      const result = await KuroApi.comment(this.detail.postDetail, this.draft, this.replyCommentId, this.replyUserId, this.replyId);
      if (!result?.commentId && !result?.replyId && !result?.postCommentId && !result?.comment?.commentId && !result?.reply?.replyId) {
        throw new Error('提交结果未确认，请先刷新查看，避免重复发送');
      }
      this.draft = ''; this.target('', '', ''); this.message = '已提交，显示时间以服务器审核为准';
      await this.loadComments(true);
      const parent = this.comments.find((c: CommentItem): boolean => c.commentId === this.expandedCommentId);
      if (parent) { await this.loadReplies(parent, true); }
    } catch (e) { this.message = (e as Error).message + ((e as ApiError).code ? `（业务码 ${(e as ApiError).code}）` : '') + '；草稿已保留，请先刷新确认是否已发送。'; }
    finally { this.sending = false; }
  }
  private currentPostId: string = '';
  aboutToAppear(): void {
    this.currentPostId = (this.getUIContext().getRouter().getParams() as PostParams).postId ?? '';
    this.load();
  }
  private async load(): Promise<void> {
    if (this.busy) { return; } this.busy = true; this.message = '';
    try {
      const detail = await KuroApi.detail(this.currentPostId);
      if (!detail?.postDetail || !Array.isArray(detail.postDetail.postContent)) { throw new Error('帖子格式已变化，请前往官方网页查看'); }
      this.detail = detail; this.liked = detail.isLike === 1;
      const viewed = detail.postDetail;
      LocalStore.recordView({ postId: this.currentPostId, postTitle: viewed.postTitle, gameId: detail.gameId,
        userName: viewed.userName, savedAt: Date.now() }).catch(() => {});
      if (this.comments.length === 0) { this.comments = detail.comment ?? []; }
      await this.loadComments(true);
      const list = await LocalStore.saved(); this.saved = list.some((p: SavedPost): boolean => p.postId === this.currentPostId);
    } catch (e) { this.message = (e as Error).message; }
    finally { this.busy = false; }
  }
  private official(): void {
    if (!this.detail) { return; }
    this.getUIContext().getRouter().pushUrl({ url: 'pages/WebPage', params: { url: officialPostUrl(this.detail.gameId, this.currentPostId), title: '官方帖子' } });
  }
  private async like(): Promise<void> {
    if (!this.detail || this.liking) { return; } this.liking = true; this.requestVersion++;
    try {
      const expected = !this.liked;
      await KuroApi.like(this.detail.postDetail, this.liked);
      // Refresh server truth instead of inventing counts locally.
      const detail = await KuroApi.detail(this.currentPostId); this.detail = detail; this.liked = detail.isLike === 1;
      if (this.liked !== expected) { this.message = '点赞状态尚未同步，请稍后刷新'; }
    } catch (e) { this.message = (e as Error).message; }
    finally { this.liking = false; }
  }
  private async favorite(): Promise<void> {
    if (!this.detail || this.saving) { return; } this.saving = true;
    const d = this.detail.postDetail;
    try { this.saved = await LocalStore.toggle({ postId: this.currentPostId, postTitle: d.postTitle, gameId: this.detail.gameId, userName: d.userName, savedAt: Date.now() }); }
    catch (e) { this.message = (e as Error).message; }
    finally { this.saving = false; }
  }
  @Builder
  blocks(content: ContentBlock[]) {
    ForEach(content, (block: ContentBlock) => {
      if (block.contentType === 1 && block.content) {
        Text(block.content).fontSize(16).fontColor(UiTheme.body(this.darkTheme)).lineHeight(27).width('100%').copyOption(CopyOptions.InApp)
      } else if ((block.contentType === 2 || block.contentType === 4) && block.url && /^https:\/\//i.test(block.url)) {
        Image(block.url).width('100%').aspectRatio(block.imgWidth && block.imgHeight ? block.imgWidth / block.imgHeight : 1).objectFit(ImageFit.Contain).borderRadius(10)
      } else if (block.contentType === 3 && block.contentLink) {
        Button(block.contentLink.title || '查看链接').constraintSize({ minHeight: 44 }).fontColor('#A67E17').backgroundColor(UiTheme.accentSurface(this.darkTheme))
          .onClick(() => {
            if (block.contentLink && isOfficialUrl(block.contentLink.url)) {
              this.getUIContext().getRouter().pushUrl({ url: 'pages/WebPage', params: { url: block.contentLink.url, title: block.contentLink.title } });
            } else { this.message = '该链接指向外部网站，请在官方帖子内查看'; }
          }).systemMaterial(UiTheme.button(this.materialEnabled, this.materialThickness))
      } else { Text('此内容请前往官方帖子查看').fontSize(12).fontColor(UiTheme.muted(this.darkTheme)) }
    })
  }
  @Builder
  pageHeader() {
    Row() {
        Button('‹ 返回').constraintSize({ minHeight: 44 }).fontColor(UiTheme.primary(this.darkTheme)).backgroundColor(UiTheme.control(this.darkTheme)).onClick(() => this.getUIContext().getRouter().back()).systemMaterial(UiTheme.button(this.materialEnabled, this.materialThickness))
        Blank()
        Button('官方原帖').constraintSize({ minHeight: 44 }).fontColor('#A67E17').backgroundColor(UiTheme.accentSurface(this.darkTheme)).enabled(this.detail !== undefined).onClick(() => this.official()).systemMaterial(UiTheme.button(this.materialEnabled, this.materialThickness))
      }.width('100%').padding(14)
  }
  build() {
    Stack() {
    SafePage() {
    Navigation() {
    Stack() {
    Column() {
      if (this.message) { Text(this.message).fontSize(13).fontColor(UiTheme.errorText(this.darkTheme)).padding(12).width('100%') }
      if (this.busy) { LoadingProgress().width(36).height(36) }
      if (this.detail) {
        Scroll() {
          Column({ space: 18 }) {
            Text(this.detail.postDetail.postTitle || '社区动态').fontSize(27).fontWeight(FontWeight.Bold).fontColor(UiTheme.primary(this.darkTheme)).width('100%')
            Text(`${this.detail.postDetail.userName} · ${this.detail.postDetail.postTime}`).fontSize(13).fontColor(UiTheme.muted(this.darkTheme)).width('100%')
            this.blocks(this.detail.postDetail.postContent)
            Row({ space: 12 }) {
              Button(`${this.liked ? '已赞' : '点赞'} ${this.detail.postDetail.likeCount ?? 0}`).constraintSize({ minHeight: 44 }).enabled(!this.liking).backgroundColor('#16D9C9').fontColor('#202329').onClick(() => this.like()).systemMaterial(UiTheme.button(this.materialEnabled, this.materialThickness))
              Button(this.saved ? '已收藏' : '收藏到本机').constraintSize({ minHeight: 44 }).enabled(!this.saving).backgroundColor(UiTheme.control(this.darkTheme)).fontColor(UiTheme.primary(this.darkTheme)).onClick(() => this.favorite()).systemMaterial(UiTheme.button(this.materialEnabled, this.materialThickness))
            }
            Divider().color(UiTheme.divider(this.darkTheme))
            Text(`评论 ${this.detail.postDetail.commentCount ?? 0}`).fontSize(20).fontWeight(FontWeight.Bold).fontColor(UiTheme.primary(this.darkTheme)).width('100%')
            Button(this.updatesAvailable ? '有评论更新 · 点击查看' : '刷新评论').constraintSize({ minHeight: 44 }).onClick(() => this.loadComments(true)).backgroundColor(UiTheme.accentSurface(this.darkTheme)).fontColor('#A67E17').systemMaterial(UiTheme.button(this.materialEnabled, this.materialThickness))
            ForEach(this.comments, (comment: CommentItem) => {
              Column({ space: 10 }) {
                Text(`${comment.userName} · ${comment.commentTime}`).fontColor(UiTheme.muted(this.darkTheme)).fontSize(12).width('100%')
                this.blocks(comment.commentContent ?? [])
                Row({ space: 8 }) {
                  Button('回复').constraintSize({ minHeight: 44 }).fontSize(13).backgroundColor(UiTheme.surface(this.darkTheme)).fontColor(UiTheme.secondary(this.darkTheme)).onClick(() => this.target(comment.commentId, comment.userId, comment.userName)).systemMaterial(UiTheme.button(this.materialEnabled, this.materialThickness))
                  if (comment.replyCount) { Button(`${comment.replyCount} 条回复`).constraintSize({ minHeight: 44 }).fontSize(13).backgroundColor(UiTheme.surface(this.darkTheme)).fontColor('#A67E17').onClick(() => this.loadReplies(comment, true)).systemMaterial(UiTheme.button(this.materialEnabled, this.materialThickness)) }
                }
                if (this.expandedCommentId === comment.commentId) {
                  ForEach(this.replies, (reply: ReplyItem) => {
                    Column({ space: 8 }) {
                      Text(`${reply.userName}${reply.toUserName ? ' 回复 ' + reply.toUserName : ''} · ${reply.replyTime}`).fontSize(12).fontColor(UiTheme.muted(this.darkTheme)).width('100%')
                      this.blocks(reply.replyContent ?? [])
                      Button('回复').constraintSize({ minHeight: 44 }).fontSize(12).fontColor(UiTheme.secondary(this.darkTheme)).backgroundColor(UiTheme.surface(this.darkTheme)).onClick(() => this.target(comment.commentId, reply.userId, reply.userName, reply.replyId)).systemMaterial(UiTheme.button(this.materialEnabled, this.materialThickness))
                    }.width('100%').padding(10).borderRadius(10).backgroundColor(UiTheme.control(this.darkTheme))
                  }, (reply: ReplyItem): string => reply.replyId)
                  if (this.moreReplies) { Button(this.repliesBusy ? '加载中…' : '更多回复').constraintSize({ minHeight: 44 }).enabled(!this.repliesBusy).onClick(() => this.loadReplies(comment, false)).systemMaterial(UiTheme.button(this.materialEnabled, this.materialThickness)) }
                  Button('收起回复').constraintSize({ minHeight: 44 }).fontSize(12).onClick(() => { this.expandedCommentId = ''; }).systemMaterial(UiTheme.button(this.materialEnabled, this.materialThickness))
                }
              }.padding(16).width('100%').backgroundColor(UiTheme.surface(this.darkTheme)).borderRadius(12)
            }, (comment: CommentItem): string => comment.commentId)
            if (this.moreComments) { Button(this.commentsBusy ? '加载中…' : '加载更多评论').constraintSize({ minHeight: 44 }).enabled(!this.commentsBusy).onClick(() => this.loadComments(false)).systemMaterial(UiTheme.button(this.materialEnabled, this.materialThickness)) }
          }.padding(20).width('100%')
        }.layoutWeight(1).width('100%')
      } else if (!this.busy) { Button('重新加载').constraintSize({ minHeight: 44 }).onClick(() => this.load()).systemMaterial(UiTheme.button(this.materialEnabled, this.materialThickness)) }
      if (this.detail) {
        Column({ space: 6 }) {
          if (this.replyName) { Button(`回复 ${this.replyName} · 点击取消`).constraintSize({ minHeight: 44 }).fontSize(12).fontColor('#A67E17').backgroundColor(UiTheme.accentSurface(this.darkTheme)).onClick(() => this.target('', '', '')).systemMaterial(UiTheme.button(this.materialEnabled, this.materialThickness)) }
          Row({ space: 8 }) {
            TextInput({ placeholder: this.replyName ? `回复 ${this.replyName}` : '说点什么…', text: this.draft }).maxLength(1000).layoutWeight(1).height(48).enabled(!this.sending).onChange((value: string) => { this.draft = value; })
            Button(this.sending ? '发送中' : '发送').constraintSize({ minHeight: 44 }).enabled(!this.sending && this.draft.trim().length > 0).backgroundColor('#16D9C9').fontColor('#202329').onClick(() => this.send()).systemMaterial(UiTheme.button(this.materialEnabled, this.materialThickness))
          }.width('100%')
        }.width('100%').padding(12).backgroundColor(UiTheme.page(this.darkTheme))
      }
    }.height('100%').width('100%').backgroundColor(UiTheme.page(this.darkTheme))
    }.width('100%').height('100%')
    }.title(this.pageHeader).titleMode(NavigationTitleMode.Mini).hideBackButton(true).hideToolBar(true).mode(NavigationMode.Stack).width('100%').height('100%')
    }
    }.width('100%').height('100%').backgroundColor(this.diagnostic ? '#9C27B0' : Color.Transparent)
      .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.BOTTOM])
  }
}
