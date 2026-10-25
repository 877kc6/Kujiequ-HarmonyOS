import { AppBackdrop } from './AppBackdrop';

// Full-window paint with one explicit content inset. No hard-coded system-bar height.
@Component
export struct SafePage {
  @StorageLink('safeTop') safeTop: number = 0;
  @StorageLink('safeBottom') safeBottom: number = 0;
  @StorageLink('safeLeft') safeLeft: number = 0;
  @StorageLink('safeRight') safeRight: number = 0;
  @StorageLink('windowInsetsReady') insetsReady: boolean = false;
  mapMode: boolean = false;
  reserveBottom: boolean = true;
  @StorageLink('layoutDiagnostic') diagnostic: boolean = false;
  @State frameHeight: string = '?';
  @BuilderParam contentBuilder: () => void = this.emptyContent;
  @Builder emptyContent() {}
  build() {
    Stack() {
      if (!this.mapMode) { AppBackdrop() }
      Column() { this.contentBuilder() }
        .width('100%').height('100%')
        .padding({ top: this.mapMode ? 0 : this.safeTop, bottom: this.mapMode || !this.reserveBottom ? 0 : this.safeBottom,
          left: this.mapMode ? 0 : this.safeLeft, right: this.mapMode ? 0 : this.safeRight })
        .visibility(this.insetsReady ? Visibility.Visible : Visibility.Hidden)
      if (this.diagnostic) {
        Column() {
          Text(`布局诊断：页高 ${this.frameHeight} / 底部 ${this.safeBottom.toFixed(1)}vp / 内容预留 ${this.reserveBottom ? '开' : '关'}`).fontSize(11).fontColor('#FFFFFF').padding(6).backgroundColor('#AA000000')
          Blank()
          Text('紫=页面根  蓝=框架  绿=背景  红=内容底部预留').fontSize(10).fontColor('#FFFFFF').padding(4).backgroundColor('#AA000000')
          if (this.reserveBottom && !this.mapMode) { Row().width('100%').height(this.safeBottom).backgroundColor('#FF1744') }
        }.width('100%').height('100%').padding({ top: this.safeTop + 48 }).hitTestBehavior(HitTestMode.None)
      }
    }.width('100%').height('100%').backgroundColor(this.diagnostic ? '#006DFF' : (this.mapMode ? '#1F1E1A' : Color.Transparent))
      .onAreaChange((_oldArea: Area, area: Area) => { this.frameHeight = String(area.height); })
      .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.BOTTOM])
  }
}
