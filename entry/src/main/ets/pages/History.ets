import { SafePage } from '../components/SafePage';
import { LocalStore } from '../services/LocalStore';
import { SavedPost } from '../models/Models';
import { UiTheme } from '../services/UiTheme';

@Entry
@Component
struct History {
  @StorageLink('layoutDiagnostic') diagnostic: boolean = false;
  @StorageLink('darkTheme') darkTheme: boolean = false;
  @State items: SavedPost[] = [];
  @State message: string = '';
  onPageShow(): void { this.load(); }
  private async load(): Promise<void> {
    try { this.items = await LocalStore.history(); }
    catch (_) { this.message = '浏览记录读取失败'; }
  }
  private confirmClear(): void {
    this.getUIContext().getPromptAction().showDialog({ title: '清空浏览记录？', message: '仅删除本机记录。',
      buttons: [{ text: '取消', color: '#808080' }, { text: '清空', color: '#C54D38' }]
    }).then(async (result) => {
      if (result.index === 1) {
        try { await LocalStore.clearHistory(); this.items = []; } catch (_) { this.message = '清空失败，请重试'; }
      }
    }).catch(() => {});
  }
  build() {
    Stack() {
    SafePage() {
    Stack() {
        Column({ space: 12 }) {
        Row() {
          Button('返回').fontColor(UiTheme.primary(this.darkTheme)).backgroundColor(UiTheme.surface(this.darkTheme)).height(44).onClick(() => this.getUIContext().getRouter().back())
          Text('浏览记录').fontSize(22).fontWeight(FontWeight.Bold).fontColor(UiTheme.primary(this.darkTheme)).layoutWeight(1).margin({ left: 12 })
          Button('清空').height(44).fontColor(UiTheme.warningText(this.darkTheme)).backgroundColor(UiTheme.warningSurface(this.darkTheme)).enabled(this.items.length > 0).onClick(() => this.confirmClear())
        }.width('100%')
        Text('仅保存在本机 · 最近 200 条 · 按最近浏览排序').fontSize(12).fontColor(UiTheme.muted(this.darkTheme)).width('100%')
        if (this.message) { Text(this.message).fontColor(UiTheme.errorText(this.darkTheme)) }
        if (this.items.length === 0) { Text('还没有浏览记录').fontColor(UiTheme.secondary(this.darkTheme)).padding(30) }
        List({ space: 10 }) {
          ForEach(this.items, (item: SavedPost) => {
            ListItem() {
              Column({ space: 7 }) {
                Text(item.postTitle || '社区动态').fontSize(17).fontWeight(FontWeight.Medium).fontColor(UiTheme.primary(this.darkTheme)).maxLines(2)
                Text(item.userName).fontSize(12).fontColor(UiTheme.secondary(this.darkTheme))
                Text(new Date(item.savedAt).toLocaleString()).fontSize(11).fontColor(UiTheme.muted(this.darkTheme))
              }.alignItems(HorizontalAlign.Start).padding(16).width('100%').borderRadius(16).backgroundColor(UiTheme.surface(this.darkTheme))
                .onClick(() => this.getUIContext().getRouter().pushUrl({ url: 'pages/Post', params: { postId: item.postId } }))
            }
          }, (item: SavedPost): string => item.postId)
        }.layoutWeight(1).width('100%')
      }.padding({ left: 16, right: 16, top: 12, bottom: 12 }).width('100%').height('100%').backgroundColor(UiTheme.page(this.darkTheme))
    }.width('100%').height('100%')
    }
    }.width('100%').height('100%').backgroundColor(this.diagnostic ? '#9C27B0' : Color.Transparent)
      .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.BOTTOM])
  }
}
