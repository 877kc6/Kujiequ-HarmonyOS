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
    if (this.accountId !== Session.userId) { this.rows = []; this.page = 0; this.accountId = Session.userId; }
    if (this.loggedIn && this.page === 0) { this.load(true); }
  }
  onPageHide(): void { this.sequence++; this.busy = false; this.refreshing = false; }
  private async load(reset: boolean): Promise<void> {
    if (this.busy || !Session.token) { this.refreshing = false; return; }
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
  private open(item: AccountRow): void {
    if (/^\d{1,24}$/.test(item.postId)) { this.getUIContext().getRouter().pushUrl({ url: 'pages/Post', params: { postId: item.postId } }); }
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
        if (item.unread) { Text('未读').fontSize(11).fontColor('#119A8E') }
      }.width('100%')
      Text(item.title).fontSize(17).fontWeight(FontWeight.Medium).fontColor(UiTheme.primary(this.darkTheme)).width('100%')
      if (item.text) { Text(item.text).fontSize(14).fontColor(UiTheme.secondary(this.darkTheme)).width('100%').maxLines(8) }
      if (item.cover) { Image(item.cover).height(170).width('100%').objectFit(ImageFit.Cover).borderRadius(12) }
      if (item.postId) { Text('查看帖子及评论  ›').fontSize(12).fontColor('#119A8E').width('100%') }
    }.padding(16).width('100%').borderRadius(18).backgroundColor(UiTheme.surface(this.darkTheme)).onClick(() => this.open(item))
  }
  build() {
    Stack() {
    SafePage() {
      Column({ space: 12 }) {
        Row({ space: 12 }) {
          Button('返回').height(44).fontColor(UiTheme.primary(this.darkTheme)).backgroundColor(UiTheme.surface(this.darkTheme)).onClick(() => this.getUIContext().getRouter().back())
          Text(this.title).fontSize(24).fontWeight(FontWeight.Bold).fontColor(UiTheme.primary(this.darkTheme)).layoutWeight(1)
          Button('刷新').height(44).enabled(!this.busy && this.loggedIn).fontColor(UiTheme.primary(this.darkTheme)).backgroundColor(UiTheme.surface(this.darkTheme)).onClick(() => this.load(true))
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
