import { common, Want } from '@kit.AbilityKit';
import { BusinessError, pasteboard } from '@kit.BasicServicesKit';
import { util } from '@kit.ArkTS';
import { http, vpnExtension } from '@kit.NetworkKit';
import { SafePage } from '../components/SafePage';
import { UiTheme } from '../services/UiTheme';
import { CaptureProbeStore } from '../services/CaptureProbeStore';
import { ProbeStatus, validProbeStatus, probeLabel, probeTerminal } from '../services/CaptureProbeModel';

@Entry
@Component
struct CaptureProbe {
  @StorageLink('darkTheme') darkTheme: boolean = false;
  @StorageLink('layoutDiagnostic') diagnostic: boolean = false;
  @State phase: string = 'idle';
  @State mode: string = 'udp';
  @State busy: boolean = false;
  @State packets: number = 0;
  @State bytes: number = 0;
  @State code: number = 0;
  @State startState: string = 'not_called';
  @State startCode: number = 0;
  @State stopCode: number = 0;
  @State httpsCode: number = 0;
  @State httpsHttpStatus: number = 0;
  private httpsStarted: boolean = false;
  private httpsRequest?: http.HttpRequest;
  @State cleaned: boolean = false;
  @State message: string = '';
  private store?: CaptureProbeStore;
  private bundleName: string = '';
  private moduleName: string = '';
  private runId: string = '';
  private startedAt: number = 0;
  private timer: number = -1;
  private leaving: boolean = false;
  aboutToAppear(): void {
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    this.store = new CaptureProbeStore(context.filesDir);
    this.bundleName = context.abilityInfo.bundleName;
    this.moduleName = context.abilityInfo.moduleName;
    const old = this.store.status();
    if (old && validProbeStatus(old, old.runId)) {
      this.runId = old.runId; this.accept(old);
      if (!probeTerminal(old.phase)) { this.phase = 'unconfirmed'; }
    }
  }
  aboutToDisappear(): void {
    this.leaving = true; this.httpsRequest?.destroy(); this.httpsRequest = undefined;
    if (this.timer >= 0) { clearInterval(this.timer); this.timer = -1; }
    if (this.busy) { this.stop(); }
  }
  private want(): Want { return { deviceId: '', bundleName: this.bundleName, moduleName: this.moduleName, abilityName: 'CaptureProbeAbility', parameters: { probeRunId: this.runId } }; }
  private accept(status: ProbeStatus): void {
    this.mode = status.mode === 'https' ? 'https' : status.mode === 'internet' ? 'internet' : (status.mode === 'tcp' ? 'tcp' : 'udp');
    this.phase = status.phase; this.code = status.code; this.packets = status.packets;
    this.bytes = status.bytes; this.cleaned = status.cleaned;
  }
  private async start(mode: string = 'udp'): Promise<void> {
    if (this.busy) { return; }
    if (!this.store || !this.bundleName || !this.moduleName) {
      this.phase = 'failed'; this.code = -3; this.startCode = -3;
      this.message = '应用上下文信息不完整，系统 VPN 尚未调用。'; return;
    }
    this.mode = mode; this.httpsStarted = false; this.httpsCode = 0; this.httpsHttpStatus = 0;
    this.runId = util.generateRandomUUID(); this.startedAt = Date.now();
    this.phase = 'starting'; this.startState = 'not_called'; this.startCode = 0; this.stopCode = 0; this.busy = true; this.message = '';
    this.packets = 0; this.bytes = 0; this.code = 0; this.cleaned = false;
    try {
      this.store.writeRequest({ runId: this.runId, expiresAt: this.startedAt + 60000, cancelled: false, mode: this.mode });
    } catch (_) {
      this.phase = 'failed'; this.busy = false; this.code = -2;
      this.message = '诊断文件无法写入，未请求启动 VPN。'; return;
    }
    try {
      this.timer = setInterval(() => this.poll(), 250);
      this.startState = 'called';
      await vpnExtension.startVpnExtensionAbility(this.want());
      this.startState = 'resolved';
      if (this.phase === 'starting') { this.phase = 'waiting_extension'; }
      // Returned call does not prove system authorization or extension startup.
    } catch (error) {
      const code = (error as BusinessError).code;
      this.startCode = typeof code === 'number' ? code : -1;
      this.code = this.startCode; this.startState = 'rejected';
      this.phase = 'failed'; this.busy = false;
      this.message = '系统 VPN 启动失败，原始错误码：' + this.startCode;
      if (this.timer >= 0) { clearInterval(this.timer); this.timer = -1; }
      try { this.store?.cancel(this.runId); } catch (_) {}
      // Preserve the startup failure even if cleanup also fails.
      try { await vpnExtension.stopVpnExtensionAbility(this.want()); }
      catch (stopError) {
        const stopCode = (stopError as BusinessError).code;
        this.stopCode = typeof stopCode === 'number' ? stopCode : -1;
      }
    }
  }
  private poll(): void {
    const status = this.store?.status();
    if (status && validProbeStatus(status, this.runId)) {
      this.accept(status);
      if (status.mode === 'https' && status.phase === 'reading' && !this.httpsStarted) { this.testHttps(this.runId); }
      if (probeTerminal(status.phase)) {
        if (this.timer >= 0) { clearInterval(this.timer); this.timer = -1; }
        this.finish(); return;
      }
    }
    if (Date.now() - this.startedAt > 65000) {
      if (this.timer >= 0) { clearInterval(this.timer); this.timer = -1; }
      this.phase = 'unconfirmed'; this.busy = false;
      try { this.store?.cancel(this.runId); } catch (_) {}
      vpnExtension.stopVpnExtensionAbility(this.want()).catch(() => {});
    }
  }
  private async finish(): Promise<void> {
    this.httpsRequest?.destroy(); this.httpsRequest = undefined;
    try { await vpnExtension.stopVpnExtensionAbility(this.want()); } catch (_) {}
    this.busy = false;
  }
  private async stop(): Promise<void> {
    if (!this.runId) { return; }
    this.httpsRequest?.destroy(); this.httpsRequest = undefined;
    try { this.store?.cancel(this.runId); } catch (_) { this.message = '停止标记写入失败，请检查系统 VPN 状态。'; }
    if (!probeTerminal(this.phase)) { this.phase = 'stopping'; }
    try { await vpnExtension.stopVpnExtensionAbility(this.want()); }
    catch (error) {
      const code = (error as BusinessError).code;
      this.code = typeof code === 'number' ? code : -1;
      this.message = '停止请求未确认；请在系统设置中检查此 VPN。';
    }
    // Keep polling the extension's cleanup receipt rather than invent success.
    if (this.leaving) { return; }
    this.poll();
  }
  private async testHttps(runId: string): Promise<void> {
    this.httpsStarted = true;
    const request = http.createHttp(); this.httpsRequest = request;
    try {
      // System TLS verifies the public server certificate. Do not disable CA or hostname checks.
      const response = await request.request('https://one.one.one.one/', {
        method: http.RequestMethod.HEAD, expectDataType: http.HttpDataType.STRING, usingCache: false,
        usingProxy: { host: '198.18.0.2', port: 49153, exclusionList: [] },
        connectTimeout: 10000, readTimeout: 10000, maxLimit: 32768
      });
      if (this.runId !== runId || !this.busy || this.leaving) { return; }
      this.httpsHttpStatus = response.responseCode;
      if (response.responseCode >= 200 && response.responseCode < 600) {
        this.store?.confirmHttps(runId);
        this.message = response.responseCode >= 400 ? 'TLS 连接已验证，测试网页返回 HTTP ' + response.responseCode : '已收到经过 TLS 验证的 HTTPS 响应';
      }
      else { this.message = 'HTTPS 服务返回 HTTP ' + response.responseCode + '，未确认成功'; }
    } catch (error) {
      if (this.runId !== runId || this.leaving) { return; }
      const code = (error as BusinessError).code;
      this.httpsCode = typeof code === 'number' ? code : -1;
      this.message = 'HTTPS 请求未完成（系统错误码 ' + this.httpsCode + '）；系统证书校验保持开启';
    } finally {
      request.destroy(); if (this.httpsRequest === request) { this.httpsRequest = undefined; }
    }
  }
  private async copyReport(): Promise<void> {
    const text = '库街区本地抓包诊断 1.8.2-fix / API26\n' +
      'testMode=' + this.mode + '\nstartCall=' + this.startState + '\nstartCode=' + this.startCode + '\nstopCode=' + this.stopCode +
      '\nbundle=' + this.bundleName + '\nmodule=' + this.moduleName + '\nphase=' + this.phase + '\ncode=' + this.code + '\npackets=' + this.packets +
      '\nbytes=' + this.bytes + '\ncleanupConfirmed=' + this.cleaned +
      '\nrunId=' + this.runId + '\nexpectedRoundTripBytes=' + (this.mode === 'tcp' ? '>=32768' : 'not_applicable') +
      '\ninternetProbePassed=' + (this.mode === 'internet' && this.phase === 'passed' && this.cleaned) +
      '\nhttpsClientCode=' + this.httpsCode + '\nhttpsHttpStatus=' + this.httpsHttpStatus +
      '\ntlsVerified=' + (this.mode === 'https' && this.phase === 'passed' && this.cleaned) + '\ngameCaptureImplemented=false\n';
    try {
      await pasteboard.getSystemPasteboard().setData(pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text));
      this.message = '诊断信息已复制，不包含账号、token 或报文内容。';
    } catch (_) { this.message = '复制失败，可以截取当前诊断结果。'; }
  }
  build() {
    Stack() {
    SafePage() {
      Column({ space: 16 }) {
        Row() {
          Button('返回').height(44).fontColor(UiTheme.primary(this.darkTheme)).backgroundColor(UiTheme.surface(this.darkTheme))
            .onClick(() => this.getUIContext().getRouter().back())
          Text('本地抓包诊断').fontSize(22).fontWeight(FontWeight.Bold).fontColor(UiTheme.primary(this.darkTheme)).margin({ left: 12 })
        }.width('100%')
        Scroll() {
          Column({ space: 16 }) {
            Text('开发测试 · 尚不能导入抽卡记录').fontSize(16).fontWeight(FontWeight.Medium).fontColor(UiTheme.primary(this.darkTheme)).width('100%')
            Text('基础测试核对 UDP 读包；新增 TCP 测试将至少 32 KB 数据经虚拟网卡转发至本机回显服务，只有收到完全一致的返回内容才通过。外网测试会经同一条虚拟网卡路径向 Cloudflare 1.1.1.1:80 发送不含账号数据的 HTTP HEAD 请求。无需打开游戏。')
              .fontSize(14).lineHeight(22).fontColor(UiTheme.secondary(this.darkTheme)).width('100%')
            Column({ space: 12 }) {
              Text((this.mode === 'https' ? 'HTTPS 加密转发 · ' : this.mode === 'internet' ? '外网 HTTP 转发 · ' : (this.mode === 'tcp' ? 'TCP 双向转发 · ' : 'UDP 读包 · ')) + probeLabel(this.phase)).fontSize(18).fontWeight(FontWeight.Medium).fontColor(UiTheme.primary(this.darkTheme)).width('100%')
              Text('已读包数：' + this.packets + '   字节：' + this.bytes).fontColor(UiTheme.body(this.darkTheme)).width('100%')
              Text('系统调用：' + this.startState + '   启动码：' + this.startCode).fontSize(13).fontColor(UiTheme.secondary(this.darkTheme)).width('100%')
              Text('结果码：' + this.code + '   网卡清理：' + (this.cleaned ? '已确认' : '未确认')).fontSize(13).fontColor(UiTheme.secondary(this.darkTheme)).width('100%')
            }.padding(18).width('100%').backgroundColor(UiTheme.surface(this.darkTheme)).borderRadius(18)
            Text('需要系统 VPN 授权。如已开启其他 VPN，请先关闭，诊断后再自行开启。UDP 测试约 3 秒，TCP 测试最多约 8 秒，外网测试最多约 10 秒，授权等待最多 60 秒。TCP 通过仍不代表已完成互联网转发或 HTTPS 解密。')
              .fontSize(13).lineHeight(20).fontColor(UiTheme.secondary(this.darkTheme)).width('100%')
            Button(this.busy ? '诊断进行中' : '基础 UDP 诊断').width('100%').height(48).backgroundColor('#12CFC2').fontColor('#102B2A').enabled(!this.busy)
              .onClick(() => this.start('udp'))
            Button('测试 TCP 双向转发').width('100%').height(48).backgroundColor('#12CFC2').fontColor('#102B2A').enabled(!this.busy)
              .onClick(() => this.start('tcp'))
            Button('测试外网 HTTP 转发').width('100%').height(48).backgroundColor('#12CFC2').fontColor('#102B2A').enabled(!this.busy)
              .onClick(() => this.start('internet'))
            Button('测试 HTTPS 加密转发').width('100%').height(48).backgroundColor('#12CFC2').fontColor('#102B2A').enabled(!this.busy)
              .onClick(() => this.start('https'))
            Text('HTTPS 测试验证系统证书校验下的加密连接转发，最多25秒。它不解密游戏流量，尚不能提取抽卡授权。').fontSize(13).fontColor(UiTheme.secondary(this.darkTheme)).width('100%')
            Button('停止诊断').width('100%').height(44).fontColor(UiTheme.primary(this.darkTheme)).backgroundColor(UiTheme.control(this.darkTheme))
              .enabled(this.busy || this.phase === 'unconfirmed' || this.phase === 'cleanup_failed').onClick(() => this.stop())
            Button('复制诊断信息').width('100%').height(44).fontColor(UiTheme.primary(this.darkTheme)).backgroundColor(UiTheme.surface(this.darkTheme)).onClick(() => this.copyReport())
            if (this.message) { Text(this.message).fontSize(13).fontColor(UiTheme.secondary(this.darkTheme)).width('100%') }
          }.width('100%').padding({ bottom: 20 })
        }.layoutWeight(1).width('100%')
      }.width('100%').height('100%').padding({ left: 20, right: 20, top: 12, bottom: 12 })
    }
    }.width('100%').height('100%').backgroundColor(this.diagnostic ? '#9C27B0' : Color.Transparent)
      .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.BOTTOM])
  }
}
