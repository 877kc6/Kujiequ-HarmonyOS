import { SafePage } from '../components/SafePage';
import { UiTheme } from '../services/UiTheme';
import { LocalStore } from '../services/LocalStore';
import { Session } from '../services/Session';
import { KuroApi } from '../services/KuroApi';
import { gameBoards, publishBoard, GameBoard } from '../services/GameBoards';
import { ComposeParams } from '../models/Models';

@Entry
@Component
struct Compose {
  @StorageLink('darkTheme') darkTheme: boolean = false;
  @StorageLink('layoutDiagnostic') diagnostic: boolean = false;
  @State gameId: number = 3;
  @State boardId: number = 10;
  @State title: string = '';
  @State body: string = '';
  @State message: string = '';
  @State busy: boolean = false;
  @State ready: boolean = false;
  private draftKey: string = '';
  private account: string = '';
  aboutToAppear(): void { this.restore(); }
  private async restore(): Promise<void> {
    const params = this.getUIContext().getRouter().getParams() as ComposeParams;
    this.gameId = params.gameId === 2 ? 2 : 3; this.boardId = this.gameId === 2 ? 3 : 10;
    this.account = Session.userId; this.draftKey = this.account + '_' + String(this.gameId);
    try {
      const draft = await LocalStore.composeDraft(this.draftKey);
      this.title = draft.title; this.body = draft.body;
      if (publishBoard(this.gameId, draft.boardId)) { this.boardId = draft.boardId; }
      this.ready = true;
    } catch (_) { this.message = '草稿读取失败，暂不覆盖本地草稿'; }
  }
  private async save(): Promise<void> {
    if (!this.ready) { return; }
    await LocalStore.saveCompose(this.draftKey, { title: this.title, body: this.body, boardId: this.boardId });
  }
  onBackPress(): boolean { if (this.busy) { return true; } this.save().catch(() => {}); return false; }
  private async send(): Promise<void> {
    if (this.busy || !this.ready) { return; }
    if (!Session.token || Session.userId !== this.account) { this.message = '账号已变化，请返回后重新进入编辑器'; return; }
    this.busy = true; this.message = '';
    try {
      await this.save();
      const result = await KuroApi.publish(this.gameId, this.boardId, this.title, this.body);
      this.message = result?.postId ? '服务器已接受发布，可在我的帖子查看。' : '服务器已返回成功，请到我的帖子确认审核或展示状态。';
      this.title = ''; this.body = '';
      try { await this.save(); } catch (_) { this.message += ' 本机草稿清理失败，请勿重复发送旧草稿。'; }
    } catch (e) { this.message = (e as Error).message + '；草稿保留，请先查看我的帖子确认，避免重复发布。'; }
    finally { this.busy = false; }
  }
  build() {
    Stack() {
      SafePage() {
        Column({ space: 14 }) {
          Row({ space: 12 }) {
            Button('返回').height(44).enabled(!this.busy).fontColor(UiTheme.primary(this.darkTheme)).backgroundColor(UiTheme.surface(this.darkTheme))
              .onClick(async () => { try { await this.save(); this.getUIContext().getRouter().back(); } catch (_) { this.message = '草稿保存失败，请勿退出'; } })
            Text(this.gameId === 2 ? '发布 · 战双' : '发布 · 鸣潮').fontSize(23).fontWeight(FontWeight.Bold).fontColor(UiTheme.primary(this.darkTheme)).layoutWeight(1)
            Button('发布').height(44).enabled(!this.busy && this.ready && !!this.title.trim() && !!this.body.trim()).backgroundColor('#16D9C9').fontColor('#132C2A').onClick(() => this.send())
          }.width('100%')
          Scroll() {
            Row({ space: 8 }) {
              ForEach(gameBoards(this.gameId).filter((b: GameBoard): boolean => b.publish), (board: GameBoard) => {
                Button(board.label).height(40).enabled(!this.busy).fontSize(13).backgroundColor(this.boardId === board.id ? '#16D9C9' : UiTheme.surface(this.darkTheme))
                  .fontColor(UiTheme.primary(this.darkTheme)).onClick(() => this.boardId = board.id)
              }, (board: GameBoard): string => String(board.id))
            }
          }.height(44).scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off)
          TextInput({ text: this.title, placeholder: '标题，最多40字' }).maxLength(40).enabled(!this.busy).onChange((v: string) => this.title = v)
          TextArea({ text: this.body, placeholder: '写下想分享的内容…' }).maxLength(10000).layoutWeight(1).enabled(!this.busy).onChange((v: string) => this.body = v)
          Text('原生文字发帖 · 暂不支持图片、视频与话题').fontSize(12).fontColor(UiTheme.muted(this.darkTheme)).width('100%')
          if (this.message) { Text(this.message).fontSize(13).fontColor(UiTheme.secondary(this.darkTheme)).width('100%') }
          Button('保存草稿').width('100%').enabled(this.ready && !this.busy).fontColor(UiTheme.primary(this.darkTheme)).backgroundColor(UiTheme.surface(this.darkTheme))
            .onClick(async () => { try { await this.save(); this.message = '草稿已保存到本机'; } catch (_) { this.message = '保存失败'; } })
        }.padding(16).width('100%').height('100%')
      }
    }.width('100%').height('100%').backgroundColor(this.diagnostic ? '#9C27B0' : Color.Transparent)
      .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.BOTTOM])
  }
}
