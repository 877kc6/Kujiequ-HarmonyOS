import { KuroApi } from '../services/KuroApi';
import { Session } from '../services/Session';
import { UiTheme } from '../services/UiTheme';
import { Profile, AccountRow } from '../models/Models';
import { SafePage } from '../components/SafePage';

interface UserProfileParams { userId?: string; userName?: string; avatar?: string; }

@Entry
@Component
struct UserProfile {
  @StorageLink('darkTheme') darkTheme: boolean = false;
  @State user: Profile = { userId: '', userName: '', headUrl: '' };
  @State loading: boolean = true;
  @State postsLoading: boolean = false;
  @State followBusy: boolean = false;
  @State message: string = '';
  @State postsMessage: string = '';
  @State following: boolean = false;
  @State followKnown: boolean = false;
  @State followLoading: boolean = false;
  @State trustedProfile: boolean = false;
  @State posts: AccountRow[] = [];
  @State hasNext: boolean = true;
  @State selectedTab: number = 0;
  private userId: string = '';
  private own: boolean = false;
  private page: number = 0;
  private sequence: number = 0;

  aboutToAppear(): void {
    const params = this.getUIContext().getRouter().getParams() as UserProfileParams;
    this.userId = String(params?.userId ?? Session.userId).trim();
    this.own = this.userId === Session.userId;
    // Author metadata comes from the clicked post, not from the signed-in account.
    this.user = { userId: this.userId, userName: params?.userName || '', headUrl: params?.avatar || '' };
    if (!/^\d{1,24}$/.test(this.userId)) {
      this.message = '帖子未提供有效作者 ID，请返回后从帖子详情打开作者主页';
      this.loading = false;
      this.hasNext = false;
      return;
    }
    this.reload();
    this.loadPosts(true);
    this.refreshFollow();
  }
  aboutToDisappear(): void { this.sequence++; }
  onPageShow(): void {
    if (this.userId && !this.own) { this.refreshFollow(); }
    if (this.userId && this.own) { this.reload(); }
  }
  private async refreshFollow(): Promise<void> {
    if (this.own || this.followLoading || !Session.token) { return; }
    const target: string = this.userId;
    this.followLoading = true;
    try {
      const value = await KuroApi.isFollowing(target);
      if (target === this.userId) { this.following = value; this.followKnown = true; }
    } catch (_) {
      if (target === this.userId) { this.followKnown = false; }
    } finally { this.followLoading = false; }
  }
  private async reload(): Promise<void> {
    this.loading = true; this.message = '';
    this.trustedProfile = false;
    try {
      const result = await KuroApi.userProfile(this.userId);
      if (!result || !result.mine || !result.mine.userId) { throw new Error('用户资料暂不可用'); }
      const returnedId: string = String(result.mine.userId);
      if (returnedId !== this.userId) {
        this.message = '服务器未返回这位作者的完整资料，当前显示的是帖子公开的头像和昵称。';
        return;
      }
      this.user = result.mine;
      // Follow state must come from the authenticated follow list, not mineV2.
      this.trustedProfile = true;
    } catch (e) { this.message = '完整资料暂不可用：' + (e as Error).message; }
    finally { this.loading = false; }
  }
  private async loadPosts(reset: boolean): Promise<void> {
    if (this.postsLoading || !/^\d{1,24}$/.test(this.userId)) { return; }
    const seq = ++this.sequence;
    this.postsLoading = true; this.postsMessage = '';
    const next = reset ? 1 : this.page + 1;
    try {
      const result = await KuroApi.accountList('posts', next, this.userId);
      if (seq !== this.sequence) { return; }
      const rows: AccountRow[] = reset ? [] : this.posts.slice();
      let mismatch: boolean = false;
      result.rows.forEach((post: AccountRow): void => {
        if (post.ownerId !== this.userId) { mismatch = true; return; }
        if (!rows.some((old: AccountRow): boolean => old.key === post.key)) { rows.push(post); }
      });
      if (mismatch) { this.postsMessage = '动态接口返回了其他作者的帖子，已过滤错误数据。'; }
      this.posts = rows;
      if (!this.own && !this.user.userName && rows.length > 0) {
        this.user = { userId: this.userId, userName: rows[0].name, headUrl: rows[0].avatar };
      }
      this.page = next;
      this.hasNext = result.hasNext;
    } catch (e) { if (seq === this.sequence) { this.postsMessage = (e as Error).message || '动态加载失败'; } }
    finally { if (seq === this.sequence) { this.postsLoading = false; } }
  }
  private async toggleFollow(): Promise<void> {
    if (!Session.token) { this.getUIContext().getRouter().pushUrl({ url:'pages/Login' }); return; }
    if (this.followBusy || this.followLoading || this.own || !/^\d{1,24}$/.test(this.userId)) { return; }
    // The author ID is provided by the post, independent of mineV2's broken other-user response.
    // Never submit a follow request against a mismatching profile response.
    const targetId: string = this.userId;
    const nextState: boolean = !this.following;
    this.followBusy = true;
    try {
      await KuroApi.followUser(targetId, nextState);
      if (targetId !== this.userId) { return; }
      this.following = nextState;
      this.followKnown = true;
      AppStorage.setOrCreate('followChangedAt', Date.now());
      this.message = nextState ? '关注成功' : '已取消关注';
    } catch (e) { this.message = '关注操作失败：' + (e as Error).message; }
    finally { this.followBusy = false; }
  }
  @Builder
  postCard(post: AccountRow) {
    Column({ space: 9 }) {
      Row() {
        Text(post.time).fontSize(12).fontColor(UiTheme.muted(this.darkTheme))
        Blank()
        Text('查看详情 ›').fontSize(12).fontColor('#16D9C9')
      }.width('100%')
      Text(post.title).fontSize(17).fontWeight(FontWeight.Medium).fontColor(UiTheme.primary(this.darkTheme)).width('100%')
      if (post.text) { Text(post.text).fontSize(14).fontColor(UiTheme.secondary(this.darkTheme)).maxLines(4).width('100%') }
      if (post.cover) { Image(post.cover).width('100%').height(180).objectFit(ImageFit.Cover).borderRadius(12) }
    }.alignItems(HorizontalAlign.Start).padding(15).borderRadius(18).backgroundColor(UiTheme.surface(this.darkTheme)).width('100%')
      .onClick(() => this.getUIContext().getRouter().pushUrl({ url:'pages/Post', params:{ postId:post.postId } }))
  }
  build() {
    Stack() {
    SafePage() {
      Column({ space: 12 }) {
        Row() {
          Button('返回').onClick(() => this.getUIContext().getRouter().back()).backgroundColor(UiTheme.surface(this.darkTheme)).fontColor(UiTheme.primary(this.darkTheme))
          Blank()
          Text(this.own ? '我的主页' : '用户主页').fontSize(19).fontWeight(FontWeight.Bold).fontColor(UiTheme.primary(this.darkTheme))
          Blank()
          Button('刷新').onClick(() => { this.reload(); this.loadPosts(true); }).backgroundColor(UiTheme.surface(this.darkTheme)).fontColor(UiTheme.primary(this.darkTheme))
        }.width('100%')
        Scroll() {
          Column({ space: 16 }) {
            Row({space:15}) {
              if (this.user.headUrl) { Image(this.user.headUrl).width(76).height(76).borderRadius(38).objectFit(ImageFit.Cover) }
              else { Text('库').width(76).height(76).borderRadius(38).backgroundColor('#16D9C9').fontSize(30).textAlign(TextAlign.Center) }
              Column({space:7}) {
                Text(this.user.userName || '库街区用户').fontSize(24).fontWeight(FontWeight.Bold).fontColor(UiTheme.primary(this.darkTheme))
                Text('用户 ID ' + this.userId).fontSize(12).fontColor(UiTheme.secondary(this.darkTheme))
                if (this.user.signature) { Text(this.user.signature).fontSize(14).fontColor(UiTheme.secondary(this.darkTheme)) }
              }.alignItems(HorizontalAlign.Start).layoutWeight(1)
            }.width('100%')
            Row({space:18}) {
              Text('关注 ' + (this.trustedProfile ? String(this.user.followCount ?? '—') : '—')).fontColor(UiTheme.primary(this.darkTheme))
              Text('粉丝 ' + (this.trustedProfile ? String(this.user.fansCount ?? '—') : '—')).fontColor(UiTheme.primary(this.darkTheme))
            }.width('100%')
            if (this.own) {
              Text('个人资料由库街区 API 读取；编辑资料写入接口尚未验证，暂不支持保存修改。')
                .fontSize(12).fontColor(UiTheme.secondary(this.darkTheme)).width('100%')
            } else {
              Button(this.followLoading && !this.followKnown ? '正在获取关注状态' : (this.followKnown && this.following ? '已关注 · 点击取关' : (this.followKnown ? '+ 关注' : '关注状态未知 · 点击关注'))).width('100%').height(46)
                .enabled(!this.followBusy && !this.followLoading && /^\d{1,24}$/.test(this.userId)).backgroundColor(this.following ? UiTheme.surface(this.darkTheme) : '#16D9C9')
                .fontColor(this.following ? UiTheme.primary(this.darkTheme) : '#101D1C').onClick(() => this.toggleFollow())
            }
            if (this.loading) { LoadingProgress().width(28).height(28) }
            if (this.message) { Text(this.message).fontSize(13).fontColor(UiTheme.secondary(this.darkTheme)) }
            Row() {
              Text('帖子').fontSize(19).fontWeight(FontWeight.Bold).fontColor(UiTheme.primary(this.darkTheme))
              Blank()

            }.width('100%').padding({top:8})
            if (this.postsMessage) {
              Text(this.postsMessage).fontSize(13).fontColor(UiTheme.errorText(this.darkTheme))
              Button('重试帖子').onClick(() => this.loadPosts(this.page === 0))
            }
            ForEach(this.posts, (post: AccountRow) => { this.postCard(post) }, (post: AccountRow): string => post.key)
            if (this.postsLoading) { LoadingProgress().width(28).height(28) }
            else if (!this.postsMessage && this.posts.length === 0) { Text('暂无公开帖子').fontColor(UiTheme.muted(this.darkTheme)).padding(24) }
            else if (this.hasNext && !this.postsMessage) { Button('加载更多帖子').onClick(() => this.loadPosts(false)) }
          }.padding({left:16,right:16,bottom:40}).width('100%').alignItems(HorizontalAlign.Start)
        }.layoutWeight(1).width('100%')
      }.padding({top:12}).width('100%').height('100%')
    }
    }.width('100%').height('100%').backgroundColor(UiTheme.page(this.darkTheme)).ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.BOTTOM])
  }
}
