import { ApiError } from '../services/Protocol';
import { AccountListParams, AccountRow } from '../models/Models';
import { accountTitle } from '../services/AccountData';
import { KuroApi } from '../services/KuroApi';
import { Session } from '../services/Session';
import { UiTheme } from '../services/UiTheme';
import { SafePage } from '../components/SafePage';

@Entry
@Component
struct AccountList {
  @StorageLink('layoutDiagnostic') diagnostic: boolean = false;
  @StorageLink('darkTheme') darkTheme: boolean = false;
  @State kind: string = 'following';
  @State title: string = '';
  @State rows: AccountRow[] = [];
  @State busy: boolean = false;
  @State message: string = '';
  @State authRejected: boolean = false;
  @State hasNext: boolean = true;
  @State deletingId: string = '';
  private postsStamp: number = 0;
  @State refreshing: boolean = false;
  @State loggedIn: boolean = false;
  private page: number = 0;
  private sequence: number = 0;
  private accountId: string = '';
  aboutToAppear(): void {
    const params = this.getUIContext().getRouter().getParams() as AccountListParams;
    try { this.kind = params.kind; this.title = accountTitle(this.kind); }
    catch (_) { this.message = '无法打开此列表'; }
  }
  onPageShow(): void {
    this.loggedIn = !!Session.token;
    const stamp = AppStorage.get<number>('myPostsChangedAt') || 0;
    if (this.kind === 'posts' && stamp !== this.postsStamp) { this.page = 0; this.postsStamp = stamp; }
    if (this.accountId !== Session.userId) { this.rows = []; this.page = 0; this.accountId = Session.userId; }
    if (this.loggedIn) { this.load(true); }
  }
  onPageHide(): void { this.sequence++; this.busy = false; this.refreshing = false; }
  private async load(reset: boolean, afterDelete: boolean = false): Promise<void> {
    if (this.busy || !Session.token || (!!this.deletingId && !afterDelete)) { this.refreshing = false; return; }
    const seq = ++this.sequence; const user = Session.userId; const next = reset ? 1 : this.page + 1;
    this.busy = true; this.message = ''; this.authRejected = false;
    try {
      const result = await KuroApi.accountList(this.kind, next);
      if (seq !== this.sequence || user !== Session.userId) { return; }
      const merged: AccountRow[] = reset ? [] : this.rows.slice();
      result.rows.forEach((item: AccountRow): void => { if (!merged.some((old: AccountRow): boolean => old.key === item.key)) { merged.push(item); } });
      this.rows = merged; this.page = next; this.hasNext = result.hasNext;
    } catch (e) { if (seq === this.sequence) { this.message = (e as Error).message || '请求失败，请重试'; this.authRejected = (e as ApiError).code === 220 || (e as ApiError).code === 221; } }
    finally { if (seq === this.sequence) { this.busy = false; this.refreshing = false; } }
  }
  private openPerson(item: AccountRow): void {
    const target: string = String(item.ownerId || item.key);
    if (!/^\d{1,24}$/.test(target)) { this.message = '这条记录没有有效用户 ID'; return; }
    this.getUIContext().getRouter().pushUrl({ url: 'pages/UserProfile', params: {
      userId: target, userName: item.title, avatar: item.avatar
    } });
  }
  private open(item: AccountRow): void {
    if (/^\d{1,24}$/.test(item.postId)) { this.getUIContext().getRouter().pushUrl({ url: 'pages/Post', params: { postId: item.postId } }); }
  }
  private confirmDelete(item: AccountRow): void {
    if (this.kind !== 'posts' || this.deletingId || this.busy || this.accountId !== Session.userId) { return; }
    this.getUIContext().showAlertDialog({ title: '删除帖子', message: '确认删除这篇帖子？服务器删除后无法通过本应用恢复。',
      primaryButton: { value: '取消', action: () => {} },
      secondaryButton: { value: '删除', fontColor: '#D84A3E', action: () => this.removePost(item) } });
  }
  private async removePost(item: AccountRow): Promise<void> {
    if (this.deletingId || this.kind !== 'posts' || this.accountId !== Session.userId) { return; }
    this.deletingId = item.postId; const account = Session.userId;
    try {
      await KuroApi.deletePost(item.postId);
      if (account !== Session.userId) { return; }
      AppStorage.setOrCreate('myPostsChangedAt', Date.now());
      this.rows = this.rows.filter((r: AccountRow): boolean => r.postId !== item.postId);
      await this.load(true, true); this.message = '帖子已删除';
    } catch (e) { if (account === Session.userId) { this.message = (e as Error).message + '；请刷新确认服务器状态，避免重复操作'; } }
    finally { this.deletingId = ''; }
  }
  @Builder
  card(item: AccountRow) {
    Column({ space: 10 }) {
      Row({ space: 10 }) {
        if (item.avatar) { Image(item.avatar).width(36).height(36).borderRadius(18).objectFit(ImageFit.Cover) }
        Column({ space: 4 }) {
          Text(item.name).fontSize(13).fontColor(UiTheme.primary(this.darkTheme))
          if (item.time) { Text(item.time).fontSize(11).fontColor(UiTheme.muted(this.darkTheme)) }
        }.alignItems(HorizontalAlign.Start).layoutWeight(1)
        if (this.kind === 'posts' && item.postId) {
          Button(this.deletingId === item.postId ? '删除中' : '删除').height(32).borderRadius(16).fontSize(12)
            .fontColor('#D84A3E').backgroundColor(UiTheme.warningSurface(this.darkTheme)).enabled(!this.deletingId && !this.busy)
            .onClick(() => { this.confirmDelete(item); })
        }
        if (this.kind === 'fans' || this.kind === 'follows') {
          Text('查看主页 ›').fontSize(13).fontColor('#16D9C9').onClick(() => this.openPerson(item))
        }
        if (item.unread) { Text('未读').fontSize(11).fontColor('#119A8E') }
      }.width('100%').onClick(() => {
        if (this.kind === 'fans' || this.kind === 'follows') { this.openPerson(item); }
      })
      Text(item.title).fontSize(17).fontWeight(FontWeight.Medium).fontColor(UiTheme.primary(this.darkTheme)).width('100%')
      if (item.text) { Text(item.text).fontSize(14).fontColor(UiTheme.secondary(this.darkTheme)).width('100%').maxLines(8) }
      if (item.cover) { Image(item.cover).height(170).width('100%').objectFit(ImageFit.Cover).borderRadius(12) }
      if (this.kind === 'fans' || this.kind === 'follows') {
        Button(this.kind === 'follows' ? '打开主页 · 取关' : '打开主页 · 关注')
          .fontColor(UiTheme.primary(this.darkTheme)).backgroundColor(UiTheme.control(this.darkTheme))
          .onClick(() => this.openPerson(item))
      }
      if (item.postId) { Text('查看帖子及评论  ›').fontSize(12).fontColor('#119A8E').width('100%').onClick(() => this.open(item)) }
    }.padding(16).width('100%').borderRadius(18).backgroundColor(UiTheme.surface(this.darkTheme))
  }
  build() {
    Stack() {
    SafePage() {
      Column({ space: 12 }) {
        Row({ space: 12 }) {
          Button('返回').height(44).fontColor(UiTheme.primary(this.darkTheme)).backgroundColor(UiTheme.surface(this.darkTheme)).onClick(() => this.getUIContext().getRouter().back())
          Text(this.title).fontSize(24).fontWeight(FontWeight.Bold).fontColor(UiTheme.primary(this.darkTheme)).layoutWeight(1)
          Button('刷新').height(44).enabled(!this.busy && !this.deletingId && this.loggedIn).fontColor(UiTheme.primary(this.darkTheme)).backgroundColor(UiTheme.surface(this.darkTheme)).onClick(() => this.load(true))
        }.padding({ left: 16, right: 16 }).width('100%')
        if (!this.loggedIn) {
          Text('登录后查看账号内容').fontColor(UiTheme.secondary(this.darkTheme)).padding(24)
          Button('登录').backgroundColor('#16D9C9').fontColor('#142B29').onClick(() => this.getUIContext().getRouter().pushUrl({ url: 'pages/Login' }))
        }
        if (this.kind === 'fans') { Text('粉丝列表 · 暂不判定新增').fontSize(12).fontColor(UiTheme.muted(this.darkTheme)) }
        if (this.message) {
          Text(this.message).fontColor(UiTheme.errorText(this.darkTheme)).fontSize(13).padding({ left: 16, right: 16 })
          if (this.authRejected) {
            Button('重新认证').backgroundColor('#16D9C9').fontColor('#142B29')
              .onClick(() => { this.page = 0; this.getUIContext().getRouter().pushUrl({ url: 'pages/Login' }); })
          }
          Button('重试').enabled(!this.busy).onClick(() => this.load(this.page === 0))
        }
        Refresh({ refreshing: $$this.refreshing }) {
          List({ space: 12 }) {
            ForEach(this.rows, (item: AccountRow) => { ListItem() { this.card(item) } }, (item: AccountRow): string => item.key)
            ListItem() {
              Column({ space: 12 }) {
                if (this.busy) { LoadingProgress().width(28).height(28) }
                else if (this.loggedIn && !this.message) {
                  if (this.rows.length === 0) { Text('暂无内容').fontColor(UiTheme.muted(this.darkTheme)) }
                  else if (this.hasNext) { Button('加载更多').fontColor(UiTheme.primary(this.darkTheme)).backgroundColor(UiTheme.control(this.darkTheme)).onClick(() => this.load(false)) }
                  else { Text('已显示全部可读取记录').fontSize(12).fontColor(UiTheme.muted(this.darkTheme)) }
                }
              }.padding(24).width('100%')
            }
          }.width('100%').height('100%').padding({ left: 16, right: 16 })
        }.onRefreshing(() => this.load(true)).width('100%').layoutWeight(1)
      }.padding({ top: 12 }).width('100%').height('100%')
    }
    }.width('100%').height('100%').backgroundColor(this.diagnostic ? '#9C27B0' : Color.Transparent)
      .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.BOTTOM])
  }
}
