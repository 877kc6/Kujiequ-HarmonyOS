import { common } from '@kit.AbilityKit';
import { MediaCache } from '../services/MediaCache';
import { PostVideo } from '../components/PostVideo';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { MediaApi, MediaUploadError } from '../services/MediaApi';
import { SafePage } from '../components/SafePage';
import { UiTheme } from '../services/UiTheme';
import { LocalStore } from '../services/LocalStore';
import { Session } from '../services/Session';
import { KuroApi } from '../services/KuroApi';
import { gameBoards, publishBoard, GameBoard } from '../services/GameBoards';
import { ComposeParams, UploadedMedia } from '../models/Models';

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
  @State attachments: UploadedMedia[] = [];
  @State uploading: boolean = false;
  @State progress: number = 0;
  @StorageLink('immersiveEnabled') materialEnabled: boolean = true;
  @StorageLink('materialThickness') materialThickness: number = 2;
  @State preview?: UploadedMedia = undefined;
  private filesDir: string = '';
  private selecting: boolean = false;
  private draftKey: string = '';
  private account: string = '';
  private leaving: boolean = false;
  aboutToAppear(): void { this.filesDir = (this.getUIContext().getHostContext() as common.UIAbilityContext).filesDir; this.restore(); }
  private async restore(): Promise<void> {
    const params = this.getUIContext().getRouter().getParams() as ComposeParams;
    this.gameId = params.gameId === 2 ? 2 : 3; this.boardId = this.gameId === 2 ? 3 : 10;
    this.account = Session.userId; this.draftKey = this.account + '_' + String(this.gameId);
    try {
      const draft = await LocalStore.composeDraft(this.draftKey);
      this.ready = true;
      if (draft.title.trim() || draft.body.trim() || (draft.media && draft.media.length > 0)) {
        this.getUIContext().showAlertDialog({
          title: '发现已保存的草稿', message: '是否加载上次保存的标题、正文、分区和附件？',
          buttons: [
            { value: '加载草稿', action: () => {
              this.title = draft.title; this.body = draft.body;
              this.attachments = Array.isArray(draft.media) ? draft.media : [];
              if (publishBoard(this.gameId, draft.boardId)) { this.boardId = draft.boardId; }
              this.message = '已加载保存的草稿';
            } },
            { value: '不加载', action: () => { this.message = '已开始新帖子，旧草稿暂时保留'; } }
          ]
        });
      }
    } catch (_) { this.ready = true; this.message = '草稿读取失败，请检查本机存储'; }
  }
  private async save(): Promise<void> {
    if (!this.ready) { return; }
    await LocalStore.saveCompose(this.draftKey, { title: this.title, body: this.body, boardId: this.boardId, media: this.attachments });
  }
  private hasContent(): boolean {
    return !!this.title.trim() || !!this.body.trim() || this.attachments.length > 0;
  }
  private async saveAndLeave(): Promise<void> {
    try { await this.save(); this.leaving = true; this.getUIContext().getRouter().back(); }
    catch (_) { this.message = '草稿保存失败，已留在编辑页，请重试'; }
  }
  private async discardAndLeave(): Promise<void> {
    try {
      await LocalStore.saveCompose(this.draftKey, { title: '', body: '', boardId: this.boardId, media: [] });
      const media = this.attachments;
      this.title = ''; this.body = ''; this.attachments = [];
      for (let i = 0; i < media.length; i++) {
        try { await MediaCache.remove(this.filesDir, media[i]); } catch (_) { /* Cache can be reclaimed later. */ }
      }
      this.leaving = true; this.getUIContext().getRouter().back();
    } catch (_) { this.message = '清空草稿失败，未退出，请重试'; }
  }
  private requestLeave(): void {
    if (this.leaving || this.busy || this.uploading || this.selecting || !this.ready) { return; }
    if (!this.hasContent()) { this.leaving = true; this.getUIContext().getRouter().back(); return; }
    this.getUIContext().showAlertDialog({
      title: '退出发布？', message: '保存后，下次进入发布页可以加载草稿；不保存将清空本次内容和本机草稿。',
      buttons: [
        { value: '继续编辑', action: () => {} },
        { value: '不保存', fontColor: '#D84A3E', action: () => { this.discardAndLeave(); } },
        { value: '保存草稿', action: () => { this.saveAndLeave(); } }
      ]
    });
  }
  onBackPress(): boolean {
    if (this.preview) { this.preview = undefined; return true; }
    this.requestLeave(); return true;
  }
  private async send(): Promise<void> {
    if (this.busy || this.uploading || this.selecting || !this.ready) { return; }
    if (!Session.token || Session.userId !== this.account) { this.message = '账号已变化，请返回后重新进入编辑器'; return; }
    this.busy = true; this.message = '';
    try {
      const result = await KuroApi.publish(this.gameId, this.boardId, this.title, this.body, this.attachments);
      this.message = result?.postId ? '服务器已接受发布，可在我的帖子查看。' : '服务器已返回成功，请到我的帖子确认审核或展示状态。';
      const oldMedia = this.attachments;
      this.title = ''; this.body = ''; this.attachments = [];
      try { await this.save(); for (let i = 0; i < oldMedia.length; i++) { await MediaCache.remove(this.filesDir, oldMedia[i]); } } catch (_) { this.message += ' 本机草稿清理失败，请勿重复发送旧草稿。'; }
    } catch (e) { this.message = (e as Error).message + '；草稿保留，请先查看我的帖子确认，避免重复发布。'; }
    finally { this.busy = false; }
  }
  private async upload(item: UploadedMedia): Promise<void> {
    if (!item.localUri) { throw new Error('本地预览文件已失效，请重新选择'); }
    this.progress = 0;
    try {
      const uploaded = item.kind === 'video' ? await MediaApi.uploadVideo(item.localUri, this.gameId, (v: number) => { this.progress = v; }) :
        await MediaApi.uploadImage(item.localUri, (v: number) => { this.progress = v; });
      if (Session.userId !== this.account) { throw new Error('账号已变化，请重新进入编辑器'); }
      uploaded.localUri = item.localUri; uploaded.localPath = item.localPath; uploaded.previewUri = item.previewUri;
      uploaded.localId = item.localId; uploaded.uploadState = 'uploaded';
      this.attachments = this.attachments.map((m: UploadedMedia): UploadedMedia => m.localId === item.localId ? uploaded : m);
    } catch (e) {
      this.attachments = this.attachments.map((m: UploadedMedia): UploadedMedia => {
        if (m.localId === item.localId) { return { kind: m.kind, url: m.url, width: m.width, height: m.height, videoId: m.videoId, name: m.name, localId: m.localId, localUri: m.localUri, localPath: m.localPath, previewUri: m.previewUri, uploadState: 'failed' }; } return m;
      });
      if (e instanceof MediaUploadError) { throw e; }
      throw new MediaUploadError('附件上传未完成，本地预览已保留');
    }
  }
  private async retry(item: UploadedMedia): Promise<void> {
    if (this.uploading || this.busy || Session.userId !== this.account) { return; }
    this.uploading = true;
    try { await this.upload(item); this.message = '上传完成，附件已保存到草稿'; }
    catch (e) { this.message = e instanceof MediaUploadError ? e.message : '上传未完成，本地预览和草稿已保留，可以重试'; }
    finally { this.uploading = false; }
  }
  private async remove(item: UploadedMedia): Promise<void> {
    this.preview = undefined;
    this.attachments = this.attachments.filter((m: UploadedMedia): boolean => (m.localId || m.videoId || m.url) !== (item.localId || item.videoId || item.url));
    try { await MediaCache.remove(this.filesDir, item); } catch (_) { this.message = '本地附件清理失败'; }
  }
  private async pick(video: boolean): Promise<void> {
    if (this.selecting || this.busy || this.uploading || !this.ready) { return; }
    if (!Session.token || Session.userId !== this.account) { this.message = '请先登录当前账号'; return; }
    const images = this.attachments.filter((m: UploadedMedia): boolean => m.kind === 'image').length;
    if (video && this.attachments.some((m: UploadedMedia): boolean => m.kind === 'video')) { this.message = '每篇最多一个视频'; return; }
    if (!video && images >= 9) { this.message = '每篇最多9张图片'; return; }
    this.selecting = true;
    try {
      const options = new photoAccessHelper.PhotoSelectOptions();
      options.MIMEType = video ? photoAccessHelper.PhotoViewMIMETypes.VIDEO_TYPE : photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE;
      options.maxSelectNumber = video ? 1 : 9 - images;
      const selection = await new photoAccessHelper.PhotoViewPicker().select(options);
      if (!selection.photoUris.length) { return; }
      if (Session.userId !== this.account) { throw new Error('账号已变化'); }
      this.uploading = true; this.message = '';
      // Add each local preview before beginning its network request.
      for (let i = 0; i < selection.photoUris.length; i++) {
        const item = await MediaCache.stage(this.filesDir, selection.photoUris[i], video);
        if (Session.userId !== this.account) { await MediaCache.remove(this.filesDir, item); throw new Error('账号已变化'); }
        this.attachments = this.attachments.concat([item]);
        await this.upload(item);
      }
      this.message = '附件已上传并保存到草稿';
    } catch (e) { this.message = e instanceof MediaUploadError ? e.message : '选择或准备附件失败；视频上限50 MB，图片上限10 MB'; }
    finally { this.uploading = false; this.selecting = false; }
  }
  @Builder
  previewMedia() {
    Column({ space: 16 }) {
      Row() {
        Text(this.preview?.kind === 'video' ? '视频预览' : '图片预览').fontSize(22).fontColor('#FFFFFF').layoutWeight(1)
        Button('关闭').height(40).borderRadius(20).onClick(() => this.preview = undefined)
      }.width('100%')
      if (this.preview?.kind === 'image') {
        Image(this.preview.localUri || this.preview.url).width('100%').layoutWeight(1).objectFit(ImageFit.Contain)
      } else if (this.preview?.localUri) {
        Video({ src: this.preview.localUri, previewUri: this.preview.previewUri || '' }).width('100%').layoutWeight(1)
          .controls(true).autoPlay(false).objectFit(ImageFit.Contain).borderRadius(24).clip(true)
      } else if (this.preview?.videoId) {
        PostVideo({ videoId: this.preview.videoId })
        Blank()
      }
    }.padding(18).width('100%').height('100%').backgroundColor('#F5080B10')
  }
  build() {
    Stack() {
      SafePage() {
        Stack() {
          Column({ space: 14 }) {
            Row({ space: 12 }) {
              Button('返回').height(42).borderRadius(21).enabled(!this.busy && !this.uploading && !this.selecting)
                .fontColor(UiTheme.primary(this.darkTheme)).backgroundColor(UiTheme.surface(this.darkTheme))
                .onClick(() => this.requestLeave())
                .systemMaterial(UiTheme.button(this.materialEnabled, this.materialThickness))
              Text(this.gameId === 2 ? '发布 · 战双' : '发布 · 鸣潮').fontSize(22).fontWeight(FontWeight.Bold).fontColor(UiTheme.primary(this.darkTheme)).layoutWeight(1)
              Button(this.busy ? '提交中' : '发布').height(42).borderRadius(21)
                .enabled(!this.busy && !this.uploading && !this.selecting && this.ready && !!this.title.trim() && !!this.body.trim())
                .backgroundColor('#16D9C9').fontColor('#132C2A').onClick(() => this.send())
                .systemMaterial(UiTheme.button(this.materialEnabled, this.materialThickness))
            }.width('100%')
            Scroll() {
              Column({ space: 16 }) {
                Scroll() {
                  Row({ space: 8 }) {
                    ForEach(gameBoards(this.gameId).filter((b: GameBoard): boolean => b.publish), (board: GameBoard) => {
                      Button(board.label).height(38).borderRadius(19).enabled(!this.busy && !this.uploading).fontSize(13)
                        .backgroundColor(this.boardId === board.id ? '#16D9C9' : UiTheme.surface(this.darkTheme))
                        .fontColor(this.boardId === board.id ? '#132C2A' : UiTheme.primary(this.darkTheme)).onClick(() => this.boardId = board.id)
                    }, (board: GameBoard): string => String(board.id))
                  }
                }.height(42).width('100%').scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off)
                TextInput({ text: this.title, placeholder: '标题，最多40字' }).maxLength(40).height(56).borderRadius(20)
                  .backgroundColor(this.darkTheme ? '#ED262B34' : '#EDFFFFFF').fontColor(UiTheme.primary(this.darkTheme))
                  .enabled(!this.busy && !this.uploading).onChange((v: string) => this.title = v)
                TextArea({ text: this.body, placeholder: '写下想分享的内容…' }).maxLength(10000).height(240).borderRadius(24).padding(16)
                  .backgroundColor(this.darkTheme ? '#ED262B34' : '#EDFFFFFF').fontColor(UiTheme.primary(this.darkTheme))
                  .enabled(!this.busy && !this.uploading).onChange((v: string) => this.body = v)
                Column({ space: 12 }) {
                  Row() {
                    Text('附件 ' + this.attachments.length).fontSize(16).fontWeight(FontWeight.Medium).fontColor(UiTheme.primary(this.darkTheme)).layoutWeight(1)
                    Text('点击预览').fontSize(12).fontColor(UiTheme.secondary(this.darkTheme))
                  }.width('100%')
                  if (this.attachments.length) {
                    Scroll() {
                      Row({ space: 12 }) {
                        ForEach(this.attachments, (item: UploadedMedia) => {
                          Column({ space: 8 }) {
                            Stack({ alignContent: Alignment.Bottom }) {
                              if (item.previewUri || item.kind === 'image') {
                                Image(item.previewUri || item.localUri || item.url).width(116).height(100).objectFit(ImageFit.Cover)
                              } else { Text('▶ 视频').width(116).height(100).fontColor(UiTheme.primary(this.darkTheme)).backgroundColor(UiTheme.control(this.darkTheme)) }
                              Text(item.kind === 'video' ? '▶ 视频预览' : '查看图片').fontSize(11).fontColor('#FFFFFF').padding(5).width('100%').backgroundColor('#88000000')
                            }.width(116).height(100).borderRadius(16).clip(true).onClick(() => this.preview = item)
                            Row({ space: 4 }) {
                              Text(item.uploadState === 'failed' ? '上传失败' : item.uploadState === 'pending' ? '待上传' : '已上传').fontSize(11).fontColor(UiTheme.secondary(this.darkTheme))
                              Button('移除').height(28).fontSize(11).borderRadius(14).enabled(!this.busy && !this.uploading).onClick(() => this.remove(item))
                            }
                            if (item.uploadState === 'failed' || item.uploadState === 'pending') {
                              Button('重试上传').height(30).fontSize(11).borderRadius(15).enabled(!this.busy && !this.uploading).onClick(() => this.retry(item))
                            }
                          }.width(124)
                        }, (item: UploadedMedia): string => item.localId || item.videoId || item.url)
                      }
                    }.height(188).width('100%').scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off)
                  }
                  Row({ space: 10 }) {
                    Button('添加图片').height(42).layoutWeight(1).borderRadius(21).backgroundColor('#16D9C9').fontColor('#132C2A')
                      .enabled(this.ready && !this.busy && !this.uploading && !this.selecting).onClick(() => this.pick(false))
                      .systemMaterial(UiTheme.button(this.materialEnabled, this.materialThickness))
                    Button('添加视频').height(42).layoutWeight(1).borderRadius(21).backgroundColor(UiTheme.control(this.darkTheme)).fontColor(UiTheme.primary(this.darkTheme))
                      .enabled(this.ready && !this.busy && !this.uploading && !this.selecting).onClick(() => this.pick(true))
                      .systemMaterial(UiTheme.button(this.materialEnabled, this.materialThickness))
                  }.width('100%')
                  if (this.uploading) {
                    Progress({ value: this.progress, total: 100, type: ProgressType.Linear }).width('100%').color('#16D9C9')
                    Text('上传中 ' + this.progress + '%').fontSize(12).fontColor(UiTheme.secondary(this.darkTheme))
                  }
                  Text('图片最多9张、单张10 MB；MP4视频最多1个、50 MB。视频需添加图片作封面。')
                    .fontSize(12).fontColor(UiTheme.secondary(this.darkTheme)).lineHeight(18).width('100%')
                }.padding(14).width('100%').borderRadius(24).backgroundColor(this.darkTheme ? '#ED262B34' : '#EDFFFFFF')
                if (this.message) { Text(this.message).fontSize(13).fontColor(UiTheme.secondary(this.darkTheme)).padding(12).width('100%').borderRadius(18).backgroundColor(UiTheme.surface(this.darkTheme)) }
              }.width('100%').padding({ bottom: 12 })
            }.layoutWeight(1).width('100%').scrollBar(BarState.Off)
            Button('保存草稿').height(46).borderRadius(23).width('100%').enabled(this.ready && !this.busy && !this.uploading && !this.selecting)
              .fontColor(UiTheme.primary(this.darkTheme)).backgroundColor(UiTheme.surface(this.darkTheme))
              .onClick(async () => { try { await this.save(); this.message = '草稿已保存到本机'; } catch (_) { this.message = '保存失败'; } })
              .systemMaterial(UiTheme.button(this.materialEnabled, this.materialThickness))
          }.padding(16).width('100%').height('100%')
          if (this.preview) { this.previewMedia() }
        }.width('100%').height('100%')
      }
    }.width('100%').height('100%').backgroundColor(this.diagnostic ? '#9C27B0' : Color.Transparent)
      .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.BOTTOM])
  }
}
