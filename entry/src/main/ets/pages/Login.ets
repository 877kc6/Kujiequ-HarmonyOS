import { SafePage } from '../components/SafePage';
import { Session } from '../services/Session';
import { UiTheme } from '../services/UiTheme';
import { KuroApi } from '../services/KuroApi';
import { ApiError, normalizeCaptchaProof } from '../services/Protocol';
import { HumanCaptcha } from '../components/HumanCaptcha';

@Entry
@Component
struct Login {
  @StorageLink('layoutDiagnostic') diagnostic: boolean = false;
  @StorageLink('immersiveEnabled') materialEnabled: boolean = true;
  @StorageLink('materialThickness') materialThickness: number = 2;
  @StorageLink('darkTheme') darkTheme: boolean = false;
  @State mobile: string = '';
  @State code: string = '';
  @State agreed: boolean = false;
  @State busy: boolean = false;
  @State message: string = '';
  @State seconds: number = 0;
  @State captchaVisible: boolean = false;
  private captchaMobile: string = '';
  private timer: number = -1;
  private active: boolean = true;
  onPageShow(): void { if (Session.token) { this.getUIContext().getRouter().back(); } }
  aboutToAppear(): void { this.active = true; }
  aboutToDisappear(): void { this.active = false; if (this.timer !== -1) { clearInterval(this.timer); this.timer = -1; } this.mobile = ''; this.code = ''; this.captchaVisible = false; this.captchaMobile = ''; }
  private async sms(): Promise<void> {
    if (this.busy || this.seconds > 0 || !this.agreed) { return; }
    this.busy = true; this.message = '';
    try {
      await KuroApi.sms(this.mobile.trim());
      if (!this.active) { return; }
      this.message = '验证码已发送'; this.seconds = 60;
      this.timer = setInterval(() => { this.seconds--; if (this.seconds <= 0) { clearInterval(this.timer); this.timer = -1; } }, 1000);
    } catch (e) {
      this.message = (e as Error).message;
      if (this.active && (e as ApiError).code === 412) { this.captchaMobile = this.mobile.trim(); this.captchaVisible = true; }
    }
    finally { this.busy = false; }
  }
  private async captchaComplete(raw: string): Promise<void> {
    if (!this.active || this.busy || !this.agreed || !this.captchaVisible) { return; }
    this.busy = true; this.captchaVisible = false;
    try {
      const proof = normalizeCaptchaProof(raw);
      await KuroApi.sms(this.captchaMobile, proof);
      if (!this.active) { return; }
      this.message = '验证已通过，验证码已发送，请填写短信验证码'; this.seconds = 60;
      this.timer = setInterval(() => { this.seconds--; if (this.seconds <= 0) { clearInterval(this.timer); this.timer = -1; } }, 1000);
    } catch (e) { this.message = '未能确认短信发送：' + (e as Error).message + '。可以重新验证或使用官方桌面网页。'; }
    finally { this.busy = false; this.captchaMobile = ''; }
  }
  private async login(): Promise<void> {
    if (this.busy || !this.agreed) { return; }
    this.busy = true; this.message = '';
    try { await KuroApi.login(this.mobile.trim(), this.code.trim()); this.code = ''; this.mobile = ''; AppStorage.setOrCreate('bootMessage', ''); if (this.active) { this.getUIContext().getRouter().back(); } }
    catch (e) { this.message = (e as Error).message; }
    finally { this.busy = false; }
  }
  @Builder
  pageHeader() {
    Row() {
      Button('‹ 返回').constraintSize({ minHeight: 44 }).alignSelf(ItemAlign.Start).fontColor(UiTheme.primary(this.darkTheme)).backgroundColor(UiTheme.control(this.darkTheme)).enabled(!this.busy).onClick(() => this.getUIContext().getRouter().back()).systemMaterial(UiTheme.button(this.materialEnabled, this.materialThickness))
    }.width('100%').padding({ left: 12, right: 12 })
  }
  build() {
    Stack() {
    SafePage() {
    Navigation() {
    Stack() {
    Scroll() {
      Column({ space: 20 }) {
        Text('连接你的库街区').fontSize(30).fontWeight(FontWeight.Bold).fontColor(UiTheme.primary(this.darkTheme)).width('100%').margin({ top: 24 })
        Text('短信验证码登录').fontSize(14).fontColor(UiTheme.muted(this.darkTheme)).width('100%')
        TextInput({ placeholder: '中国大陆手机号', text: this.mobile }).enabled(!this.busy && !this.captchaVisible).type(InputType.PhoneNumber).maxLength(11).height(52).onChange((v: string) => { this.mobile = v; })
        Row({ space: 10 }) {
          TextInput({ placeholder: '短信验证码', text: this.code }).type(InputType.Number).maxLength(8).height(52).layoutWeight(1).onChange((v: string) => { this.code = v; })
          Button(this.seconds > 0 ? `${this.seconds}s` : '获取验证码').constraintSize({ minHeight: 44 }).enabled(this.agreed && !this.busy && !this.captchaVisible && this.seconds === 0).backgroundColor('#FFF0BD').fontColor('#8C6C16').onClick(() => this.sms()).systemMaterial(UiTheme.button(this.materialEnabled, this.materialThickness))
        }
        Row({ space: 8 }) {
          Checkbox().enabled(!this.busy && !this.captchaVisible).select(this.agreed).selectedColor('#D4AC39').onChange((v: boolean) => { this.agreed = v; })
          Text('我知晓这是非官方客户端，并同意将手机号和验证码直接提交给库街区完成登录。').fontSize(12).fontColor(UiTheme.secondary(this.darkTheme)).layoutWeight(1)
        }.width('100%')
        Button(this.busy ? '处理中…' : '登录').constraintSize({ minHeight: 44 }).width('100%').height(50).enabled(this.agreed && !this.busy && !this.captchaVisible).backgroundColor('#16D9C9').fontColor('#202329').onClick(() => this.login()).systemMaterial(UiTheme.button(this.materialEnabled, this.materialThickness))
        if (this.message) { Text(this.message).fontSize(13).fontColor(UiTheme.errorText(this.darkTheme)).width('100%').lineHeight(22) }
        if (this.captchaVisible) {
          HumanCaptcha({ onComplete: (proof: string): void => { this.captchaComplete(proof); } })
          Button('取消验证').constraintSize({ minHeight: 44 }).backgroundColor(UiTheme.control(this.darkTheme)).fontColor(UiTheme.secondary(this.darkTheme)).onClick(() => { this.captchaVisible = false; this.captchaMobile = ''; }).systemMaterial(UiTheme.button(this.materialEnabled, this.materialThickness))
        }
        Button('备用：打开官方桌面网页').constraintSize({ minHeight: 44 }).width('100%').backgroundColor(UiTheme.surface(this.darkTheme)).fontColor(UiTheme.secondary(this.darkTheme))
          .onClick(() => this.getUIContext().getRouter().pushUrl({ url: 'pages/WebPage', params: { url: 'https://www.kurobbs.com/mc/home', title: '官方库街区登录' } })).systemMaterial(UiTheme.button(this.materialEnabled, this.materialThickness))
        Text('凭证使用系统关键资产服务加密保存在本机，不保存密码和短信验证码。\n官方网页登录完成后，会尝试校验凭证并安全连接原生账号。\n需要验证时请在本页手动完成极验。只有库街区确认发送成功后才开始短信倒计时。若服务仍拒绝，使用官方桌面网页；若凭证校验失败可返回本页重试。').fontSize(12).fontColor(UiTheme.muted(this.darkTheme)).width('100%').lineHeight(22)
      }.padding(24).width('100%')
    }.align(Alignment.TopStart).width('100%').height('100%').backgroundColor(UiTheme.page(this.darkTheme))
    }.width('100%').height('100%')
    }.title(this.pageHeader).titleMode(NavigationTitleMode.Mini).hideBackButton(true).hideToolBar(true).mode(NavigationMode.Stack).width('100%').height('100%')
    }
    }.width('100%').height('100%').backgroundColor(this.diagnostic ? '#9C27B0' : Color.Transparent)
      .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.BOTTOM])
  }
}
