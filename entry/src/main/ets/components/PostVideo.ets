import { MediaApi, PlaybackError } from '../services/MediaApi';
import { UiTheme } from '../services/UiTheme';
@Component
export struct PostVideo {
  @StorageLink('darkTheme') darkTheme: boolean = false;
  @StorageLink('immersiveEnabled') materialEnabled: boolean = true;
  @StorageLink('materialThickness') materialThickness: number = 2;
  @Prop videoId: string = '';
  @Prop cover: string = '';
  @Prop canPlay: boolean = true;
  @Prop reason: string = '';
  @Prop @Watch('visibilityChanged') active: boolean = true;
  @State inView: boolean = false;
  private appeared: boolean = false;
  @State source: string = '';
  @State loading: boolean = false;
  @State playing: boolean = false;
  @State expanded: boolean = false;
  @State error: string = '';
  private player: VideoController = new VideoController();
  private generation: number = 0;
  aboutToAppear(): void { this.appeared = true; this.load(); }
  private visibilityChanged(): void {
    if (!this.active) { this.player.pause(); this.playing = false; }
    else if (this.appeared && this.inView && !this.source) { this.load(); }
  }
  aboutToDisappear(): void { this.appeared = false; this.generation++; this.player.stop(); this.playing = false; }
  private async load(): Promise<void> {
    if (this.loading || !this.canPlay) { return; }
    this.player.stop(); this.playing = false;
    this.source = '';
    this.loading = true; this.error = ''; const generation = ++this.generation;
    try { const source = await MediaApi.playback(this.videoId); if (generation === this.generation) { this.source = source; } }
    catch (error) { if (generation === this.generation) { this.error = error instanceof PlaybackError ? error.message : '播放请求未完成，请重试'; } }
    finally { if (generation === this.generation) { this.loading = false; } }
  }
  build() {
    Column({ space: 10 }) {
      if (!this.canPlay) { Text(this.reason || '视频暂不可播放，可能仍在审核').fontColor(UiTheme.secondary(this.darkTheme)) }
      else {
        if (this.source) {
          Stack({ alignContent: Alignment.Center }) {
            Video({ src: this.source, previewUri: this.cover, controller: this.player })
              .width('100%').height(this.expanded ? 430 : 240).controls(false).autoPlay(false)
              .objectFit(ImageFit.Contain).backgroundColor('#05070A')
              .onError(() => { this.player.stop(); this.playing = false; this.error = '播放失败，请重试'; })
            if (!this.playing) {
              Button('▶').width(64).height(64).borderRadius(32)
                .fontSize(25).fontColor(Color.White).backgroundColor('#B0252930')
                .onClick(() => { this.player.start(); this.playing = true; })
                .systemMaterial(UiTheme.button(this.materialEnabled, this.materialThickness))
            }
            Column() {
              Blank()
              Row({ space: 12 }) {
                Button(this.playing ? 'Ⅱ' : '▶').width(44).height(44).borderRadius(22)
                  .fontColor(Color.White).backgroundColor('#AA262B32')
                  .onClick(() => { if (this.playing) { this.player.pause(); this.playing = false; }
                    else { this.player.start(); this.playing = true; } })
                  .systemMaterial(UiTheme.button(this.materialEnabled, this.materialThickness))
                Text(this.playing ? '正在播放' : '已暂停').fontSize(13).fontColor('#E6FFFFFF')
                Blank()
                Button(this.expanded ? '⤡' : '⤢').width(44).height(44).borderRadius(22)
                  .fontSize(22).fontColor(Color.White).backgroundColor('#AA262B32')
                  .onClick(() => { this.expanded = !this.expanded; })
                  .systemMaterial(UiTheme.button(this.materialEnabled, this.materialThickness))
              }.width('100%').padding({ left: 12, right: 12, bottom: 12 })
            }.width('100%').height('100%')
          }.width('100%').height(this.expanded ? 430 : 240).borderRadius(18).clip(true)
        } else if (this.cover) { Image(this.cover).width('100%').height(220).objectFit(ImageFit.Contain) }
        if (this.loading) { LoadingProgress().width(26).height(26) }
        if (this.error) {
          Button('重试播放').height(40).borderRadius(20).enabled(!this.loading).onClick(() => this.load()).backgroundColor('#16D9C9').fontColor('#132C2A')
        }
        if (this.error) { Text(this.error).fontSize(13).fontColor(UiTheme.secondary(this.darkTheme)).width('100%') }
      }
    }.width('100%').borderRadius(18).clip(true)
      .onVisibleAreaChange([0.5], (_visible: boolean, ratio: number) => {
        this.inView = ratio >= 0.5;
        if (!this.inView) { this.player.pause(); this.playing = false; }
      })
  }
}
