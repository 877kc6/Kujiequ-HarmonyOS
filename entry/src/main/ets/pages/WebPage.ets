import { SafePage } from '../components/SafePage';
import { window } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { LocalStore } from '../services/LocalStore';
import { webview } from '@kit.ArkWeb';
import { WebParams } from '../models/Models';
import { isOfficialUrl } from '../services/Protocol';
import { Session } from '../services/Session';
import { KuroApi } from '../services/KuroApi';
import { READ_WEB_ACCOUNT, MAP_MOBILE_STYLE, parseWebAccount, connectOfficialSession } from '../services/WebSession';

@Entry
@Component
struct WebPage {
  @StorageLink('layoutDiagnostic') diagnostic: boolean = false;
  private controller: webview.WebviewController = new webview.WebviewController();
  private readonly desktopAgent: string = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36';
  private readonly mobileAgent: string = 'Mozilla/5.0 (Linux; HarmonyOS 7.0; Phone) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/144.0.0.0 Mobile Safari/537.36';
  @State url: string = 'https://www.kurobbs.com/mc/home';
  @State message: string = '';
  @State progress: number = 0;
  @State ready: boolean = false;
  private isMap: boolean = false;
  private pendingTarget: string = '';
  private syncBusy: boolean = false;
  private active: boolean = false;
  private attached: boolean = false;
  private timer: number = -1;
  private connectedToken: string = '';
  private attemptedToken: string = '';
  aboutToAppear(): void {
    const params = this.getUIContext().getRouter().getParams() as WebParams;
    if (params?.url && isOfficialUrl(params.url)) {
      this.url = params.url; this.isMap = /\/mc\/map(?:\/|$)/.test(this.url); this.ready = true;
      if (!this.isMap && Session.token && !/\/(?:mc|pns)\/home(?:$|\?)/.test(this.url)) {
        this.pendingTarget = this.url; this.url = 'https://www.kurobbs.com/mc/home';
      }
    } else { this.message = '只允许打开库街区官方页面'; }
  }
  onPageShow(): void {
    this.active = true; this.mapLayout(true);
    if (this.timer === -1) { this.timer = setInterval(() => { this.syncAccount(); }, 2500); }
  }
  onPageHide(): void {
    this.active = false; this.mapLayout(false);
    if (this.timer !== -1) { clearInterval(this.timer); this.timer = -1; }
    this.attemptedToken = '';
  }
  aboutToDisappear(): void { this.onPageHide(); }
  private async mapLayout(enter: boolean): Promise<void> {
    if (!this.isMap) { return; }
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const win = await window.getLastWindow(context);
      const fullscreen = enter && this.active;
      const background = '#00000000';
      const content = fullscreen || LocalStore.darkTheme ? '#FFFFFF' : '#202329';
      await win.setWindowSystemBarProperties({ statusBarColor: background, navigationBarColor: background,
        statusBarContentColor: content, navigationBarContentColor: content });
    } catch (_) {}
  }
  private async syncAccount(): Promise<void> {
    if (!this.active || !this.attached || this.syncBusy) { return; }
    this.syncBusy = true;
    try {
      if (!isOfficialUrl(this.controller.getUrl())) { return; }
      const scope = this.controller.getUrl().split('/').slice(0, 3).join('/');
      const connection = Session.token + '|' + scope;
      if (Session.token && (this.isMap || this.connectedToken !== connection)) {
        const changed = await this.controller.runJavaScript(connectOfficialSession(Session.token, Session.userId, Session.userName, this.isMap));
        this.connectedToken = connection;
        if (this.pendingTarget) { const target = this.pendingTarget; this.pendingTarget = ''; this.controller.loadUrl(target); return; }
        if (changed === 'true') { this.controller.refresh(); return; }
      }
      const generation = Session.generation;
      const raw = await this.controller.runJavaScript(READ_WEB_ACCOUNT);
      if (!this.active || generation !== Session.generation) { return; }
      const account = parseWebAccount(raw);
      if (!account || account.token === Session.token || account.token === this.attemptedToken) { return; }
      // Never silently replace the encrypted native session with a different
      // website token. Account switching requires explicit logout by the user.
      if (Session.token && Session.userId) { return; }
      this.attemptedToken = account.token;
      await KuroApi.importWebAccount(account.token, account.userId);
      if (this.active) { this.getUIContext().getPromptAction().showToast({ message: '账号已连接，返回后可查看游戏数据' }); }
    } catch (_) {
      AppStorage.setOrCreate('bootMessage', '网页已登录，但未能连接原生账号。可重新打开登录页重试，或使用短信登录。');
    } finally { this.syncBusy = false; }
  }
  onBackPress(): boolean {
    try {
      if (this.attached && this.controller.accessBackward()) { this.controller.backward(); return true; }
    } catch (_) {}
    return false;
  }
  build() {
    Stack() {
    SafePage({ mapMode: this.isMap }) {
    Column() {
      if (this.progress < 100) { Progress({ value: this.progress, total: 100, type: ProgressType.Linear }).color('#D8AC36').width('100%').height(2) }
      if (this.message) { Text(this.message).fontSize(12).fontColor('#A35432').padding(12) }
      if (this.ready) {
        Web({ src: this.url, controller: this.controller })
          .onControllerAttached(() => { this.controller.setCustomUserAgent(this.isMap ? this.mobileAgent : this.desktopAgent); this.attached = true; })
          .javaScriptAccess(true).domStorageAccess(true).fileAccess(false).zoomAccess(true)
          .mixedMode(MixedMode.None).layoutWeight(1).width('100%')
          .onPageEnd(() => {
            if (this.isMap) { this.controller.runJavaScript(MAP_MOBILE_STYLE).catch(() => {}); }
            this.syncAccount();
          })
          .onProgressChange((event) => { if (event) { this.progress = event.newProgress; } })
          .onLoadIntercept((event) => {
            if (!event) { return true; }
            if (!event.data.isMainFrame()) { return false; }
            const target = event.data.getRequestUrl();
            if (!isOfficialUrl(target)) { this.message = '该页面尝试打开外部链接，已停止跳转。可侧滑返回。'; return true; }
            this.message = ''; return false;
          })
          .onSslErrorEventReceive((event) => { event?.handler.handleCancel(); this.message = '网站证书校验失败，已停止加载'; })
      }
    }.width('100%').height('100%').backgroundColor(LocalStore.darkTheme ? '#12151B' : '#F4F5F7')
    }
    }.width('100%').height('100%').backgroundColor(this.diagnostic ? '#9C27B0' : Color.Transparent)
      .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.BOTTOM])
  }
}
