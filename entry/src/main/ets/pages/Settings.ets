import { SafePage } from '../components/SafePage';
import { UiTheme } from '../services/UiTheme';
import { webview } from '@kit.ArkWeb';
import { LocalStore } from '../services/LocalStore';
import { common, ConfigurationConstant } from '@kit.AbilityKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { fileIo } from '@kit.CoreFileKit';
import { window } from '@kit.ArkUI';

@Entry
@Component
struct Settings {
  @StorageLink('layoutDiagnostic') diagnostic: boolean = false;
  @StorageLink('immersiveEnabled') materialEnabled: boolean = true;
  @StorageLink('materialLevel') materialLevel: string = 'ADAPTIVE';
  @StorageLink('materialThickness') materialThickness: number = 2;
  @StorageLink('themeMode') themeMode: string = 'system';
  @StorageLink('darkTheme') darkTheme: boolean = false;
  @StorageLink('backgroundImage') wallpaperPath: string = '';
  @StorageLink('autoSignIn') autoSignIn: boolean = true;
  @State busy: boolean = false;
  @State message: string = '';

  private async changeImmersive(value: boolean): Promise<void> {
    try { await LocalStore.material(value); }
    catch (e) { this.message = (e as Error).message; }
  }
  private async changeLevel(value: string): Promise<void> {
    try { await LocalStore.setMaterialLevel(value); }
    catch (e) { this.message = (e as Error).message; }
  }
  private async changeThickness(value: number): Promise<void> {
    try { await LocalStore.setMaterialThickness(value); }
    catch (e) { this.message = (e as Error).message; }
  }
  private async changeAutoSignIn(value: boolean): Promise<void> {
    try { await LocalStore.setAutoSignIn(value); }
    catch (e) { this.message = (e as Error).message; }
  }
  private async changeTheme(mode: string): Promise<void> {
    try {
      await LocalStore.setThemeMode(mode);
      const dark = mode === 'dark';
      if (mode !== 'system') { await LocalStore.setDarkTheme(dark); }
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      context.setColorMode(mode === 'system' ? ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET : (dark ? ConfigurationConstant.ColorMode.COLOR_MODE_DARK : ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT));
      if (mode === 'system') {
        LocalStore.darkTheme = context.config.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
        AppStorage.setOrCreate('darkTheme', LocalStore.darkTheme);
      }
      const activeWindow = await window.getLastWindow(context);
      const barContent = LocalStore.darkTheme ? '#F3F4F6' : '#202329';
      await activeWindow.setWindowSystemBarProperties({ statusBarColor: '#00000000', statusBarContentColor: barContent,
        navigationBarColor: '#00000000', navigationBarContentColor: barContent });
    } catch (e) { this.message = (e as Error).message; }
  }
  private async chooseBackground(): Promise<void> {
    if (this.busy) { return; }
    this.busy = true; this.message = '';
    let source: fileIo.File | undefined = undefined;
    let target: fileIo.File | undefined = undefined;
    try {
      const picker = new photoAccessHelper.PhotoViewPicker();
      const options = new photoAccessHelper.PhotoSelectOptions();
      options.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE;
      options.maxSelectNumber = 1;
      const result = await picker.select(options);
      if (!result.photoUris.length) { return; }
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const extensionMatch = result.photoUris[0].match(/\.(jpg|jpeg|png|webp|heic)(?:\?|$)/i);
      const suffix = extensionMatch && extensionMatch.length > 1 ? extensionMatch[1] : 'jpg';
      const targetPath = `${context.filesDir}/kujiequ_background_${Date.now()}.${suffix}`;
      source = fileIo.openSync(result.photoUris[0], fileIo.OpenMode.READ_ONLY);
      target = fileIo.openSync(targetPath, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE);
      fileIo.copyFileSync(source.fd, target.fd);
      fileIo.closeSync(source); source = undefined;
      fileIo.closeSync(target); target = undefined;
      const oldPath = LocalStore.backgroundImage;
      await LocalStore.setBackgroundImage(targetPath);
      if (oldPath && oldPath.indexOf(`${context.filesDir}/kujiequ_background_`) === 0) {
        try { fileIo.unlinkSync(oldPath); } catch (_) {}
      }
      this.message = '背景图片已应用到应用页面';
    } catch (e) { this.message = '选择背景失败：' + (e as Error).message; }
    finally {
      if (source) { try { fileIo.closeSync(source); } catch (_) {} }
      if (target) { try { fileIo.closeSync(target); } catch (_) {} }
      this.busy = false;
    }
  }
  private async removeBackground(): Promise<void> {
    const oldPath = LocalStore.backgroundImage;
    try {
      await LocalStore.setBackgroundImage('');
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      if (oldPath && oldPath.indexOf(`${context.filesDir}/kujiequ_background_`) === 0) { try { fileIo.unlinkSync(oldPath); } catch (_) {} }
      this.message = '已恢复默认背景';
    } catch (e) { this.message = (e as Error).message; }
  }
  private async clearWebSession(): Promise<void> {
    try {
      const choice = await this.getUIContext().getPromptAction().showDialog({
        title: '清除网页登录', message: '将清除应用内网页的登录状态。已连接的原生账号请在“我的”中退出。',
        buttons: [{ text: '取消', color: UiTheme.secondary(this.darkTheme) }, { text: '清除', color: '#AD4E43' }]
      });
      if (choice.index !== 1) { return; }
      webview.WebCookieManager.clearAllCookiesSync(); webview.WebStorage.deleteAllData();
      this.message = '网页登录状态已清除';
    } catch (_) { this.message = '清除失败，请稍后重试'; }
  }
  @Builder
  pageHeader() {
    Row() {
      Button('‹ 返回').constraintSize({ minHeight: 44 }).alignSelf(ItemAlign.Start).fontColor(UiTheme.primary(this.darkTheme))
        .backgroundColor(UiTheme.control(this.darkTheme)).onClick(() => this.getUIContext().getRouter().back())
        .systemMaterial(UiTheme.button(this.materialEnabled, this.materialThickness))
    }.width('100%').padding({ left: 12, right: 12 })
  }
  build() {
    Stack() {
    SafePage() {
    Navigation() {
      Stack() {
            Scroll() {
          Column({ space: 14 }) {
            Column({ space: 4 }) {
              Text('外观设置').fontSize(27).fontWeight(FontWeight.Bold).fontColor(UiTheme.primary(this.darkTheme)).width('100%')
              Text('按你的习惯调整库街区').fontSize(12).fontColor(UiTheme.muted(this.darkTheme)).width('100%')
            }.alignItems(HorizontalAlign.Start).width('100%').margin({ bottom: 3 })

            Column({ space: 12 }) {
              Row() {
                Column({ space: 4 }) {
                  Text('主题模式').fontSize(16).fontWeight(FontWeight.Medium).fontColor(UiTheme.primary(this.darkTheme))
                  Text('立即应用到所有原生页面').fontSize(11).fontColor(UiTheme.muted(this.darkTheme))
                }.alignItems(HorizontalAlign.Start)
                Blank()
                Text(this.darkTheme ? '深色' : '浅色').fontSize(11).fontColor('#A67E17')
              }.width('100%')
              Row({ space: 8 }) {
                Button('浅色').constraintSize({ minHeight: 44 }).layoutWeight(1).fontSize(11).fontColor((this.themeMode === 'light') ? '#29251A' : UiTheme.secondary(this.darkTheme)).backgroundColor((this.themeMode === 'light') ? '#16D9C9' : UiTheme.control(this.darkTheme)).onClick(() => this.changeTheme('light'))
                Button('深色').constraintSize({ minHeight: 44 }).layoutWeight(1).fontSize(11).fontColor((this.themeMode === 'dark') ? '#29251A' : UiTheme.secondary(this.darkTheme)).backgroundColor((this.themeMode === 'dark') ? '#16D9C9' : UiTheme.control(this.darkTheme)).onClick(() => this.changeTheme('dark'))
                Button('跟随系统').constraintSize({ minHeight: 44 }).layoutWeight(1).fontSize(11).fontColor((this.themeMode === 'system') ? '#29251A' : UiTheme.secondary(this.darkTheme)).backgroundColor((this.themeMode === 'system') ? '#16D9C9' : UiTheme.control(this.darkTheme)).onClick(() => this.changeTheme('system'))
              }.width('100%')
            }.padding(15).width('100%').backgroundColor(UiTheme.surface(this.darkTheme)).borderRadius(18)

            Row() {
              Column({ space: 5 }) {
                Text('打开 App 自动签到').fontSize(15).fontWeight(FontWeight.Medium).fontColor(UiTheme.primary(this.darkTheme))
                Text('仅鸣潮首个绑定角色；今日已签到或状态不明时不重复提交').fontSize(10).fontColor(UiTheme.muted(this.darkTheme)).width('100%')
              }.alignItems(HorizontalAlign.Start).layoutWeight(1)
              Toggle({ type: ToggleType.Switch, isOn: this.autoSignIn }).selectedColor('#D4AC39')
                .onChange((value: boolean) => this.changeAutoSignIn(value))
            }.padding(15).width('100%').backgroundColor(UiTheme.surface(this.darkTheme)).borderRadius(18)

            Column({ space: 12 }) {
              Row() {
                Column({ space: 4 }) {
                  Text('页面背景').fontSize(16).fontWeight(FontWeight.Medium).fontColor(UiTheme.primary(this.darkTheme))
                  Text('选择一张图片作为全局背景').fontSize(11).fontColor(UiTheme.muted(this.darkTheme))
                }.alignItems(HorizontalAlign.Start)
                Blank()
                if (this.wallpaperPath) {
                  Image(`file://${this.wallpaperPath}`).width(48).height(48).borderRadius(12).objectFit(ImageFit.Cover)
                } else {
                  Text('默认').fontSize(11).fontColor(UiTheme.muted(this.darkTheme)).padding(8).backgroundColor(UiTheme.control(this.darkTheme)).borderRadius(10)
                }
              }.width('100%')
              Row({ space: 8 }) {
                Button(this.busy ? '正在读取…' : (this.wallpaperPath ? '更换图片' : '从相册选择'))
                  .constraintSize({ minHeight: 44 }).layoutWeight(1).fontSize(12).fontColor('#29251A').backgroundColor('#16D9C9')
                  .enabled(!this.busy).onClick(() => this.chooseBackground())
                  .systemMaterial(UiTheme.button(this.materialEnabled, this.materialThickness))
                if (this.wallpaperPath) {
                  Button('恢复默认').constraintSize({ minHeight: 44 }).fontSize(12).fontColor(UiTheme.secondary(this.darkTheme))
                    .backgroundColor(UiTheme.control(this.darkTheme)).onClick(() => this.removeBackground())
                    .systemMaterial(UiTheme.button(this.materialEnabled, this.materialThickness))
                }
              }.width('100%')
            }.padding(15).width('100%').backgroundColor(UiTheme.surface(this.darkTheme)).borderRadius(18)

            Column({ space: 12 }) {
              Row() {
                Column({ space: 4 }) {
                  Text('沉浸光感').fontSize(16).fontWeight(FontWeight.Medium).fontColor(UiTheme.primary(this.darkTheme))
                  Text('控制底部 HDS 页签的系统材质等级').fontSize(11).fontColor(UiTheme.muted(this.darkTheme))
                }.alignItems(HorizontalAlign.Start)
                Blank()
                Toggle({ type: ToggleType.Switch, isOn: this.materialEnabled })
                  .selectedColor('#D4AC39').systemMaterial(UiTheme.button(this.materialEnabled, this.materialThickness))
                  .onChange((value: boolean) => this.changeImmersive(value))
              }.width('100%')
              Row({ space: 5 }) {
                Button('自适应').constraintSize({ minHeight: 44 }).layoutWeight(1).fontSize(11).fontColor((this.materialLevel === 'ADAPTIVE') ? '#29251A' : UiTheme.secondary(this.darkTheme)).backgroundColor((this.materialLevel === 'ADAPTIVE') ? '#16D9C9' : UiTheme.control(this.darkTheme)).onClick(() => this.changeLevel('ADAPTIVE'))
                Button('精致').constraintSize({ minHeight: 44 }).layoutWeight(1).fontSize(11).fontColor((this.materialLevel === 'EXQUISITE') ? '#29251A' : UiTheme.secondary(this.darkTheme)).backgroundColor((this.materialLevel === 'EXQUISITE') ? '#16D9C9' : UiTheme.control(this.darkTheme)).onClick(() => this.changeLevel('EXQUISITE'))
                Button('柔和').constraintSize({ minHeight: 44 }).layoutWeight(1).fontSize(11).fontColor((this.materialLevel === 'GENTLE') ? '#29251A' : UiTheme.secondary(this.darkTheme)).backgroundColor((this.materialLevel === 'GENTLE') ? '#16D9C9' : UiTheme.control(this.darkTheme)).onClick(() => this.changeLevel('GENTLE'))
                Button('流畅').constraintSize({ minHeight: 44 }).layoutWeight(1).fontSize(11).fontColor((this.materialLevel === 'SMOOTH') ? '#29251A' : UiTheme.secondary(this.darkTheme)).backgroundColor((this.materialLevel === 'SMOOTH') ? '#16D9C9' : UiTheme.control(this.darkTheme)).onClick(() => this.changeLevel('SMOOTH'))
              }.width('100%')
              Text('精致效果更明显；低算力设备可能发热，可选自适应。').fontSize(10).fontColor(UiTheme.muted(this.darkTheme)).width('100%')
            }.padding(15).width('100%').backgroundColor(UiTheme.surface(this.darkTheme)).borderRadius(18)

            Column({ space: 12 }) {
              Column({ space: 4 }) {
                Text('控件材质厚度').fontSize(16).fontWeight(FontWeight.Medium).fontColor(UiTheme.primary(this.darkTheme))
                Text('应用于支持沉浸光感的按钮和标题栏').fontSize(11).fontColor(UiTheme.muted(this.darkTheme))
              }.alignItems(HorizontalAlign.Start).width('100%')
              Row({ space: 5 }) {
                Button('超薄').constraintSize({ minHeight: 44 }).layoutWeight(1).fontSize(11).fontColor((this.materialThickness === 0) ? '#29251A' : UiTheme.secondary(this.darkTheme)).backgroundColor((this.materialThickness === 0) ? '#16D9C9' : UiTheme.control(this.darkTheme)).onClick(() => this.changeThickness(0))
                Button('薄').constraintSize({ minHeight: 44 }).layoutWeight(1).fontSize(11).fontColor((this.materialThickness === 1) ? '#29251A' : UiTheme.secondary(this.darkTheme)).backgroundColor((this.materialThickness === 1) ? '#16D9C9' : UiTheme.control(this.darkTheme)).onClick(() => this.changeThickness(1))
                Button('标准').constraintSize({ minHeight: 44 }).layoutWeight(1).fontSize(11).fontColor((this.materialThickness === 2) ? '#29251A' : UiTheme.secondary(this.darkTheme)).backgroundColor((this.materialThickness === 2) ? '#16D9C9' : UiTheme.control(this.darkTheme)).onClick(() => this.changeThickness(2))
                Button('厚').constraintSize({ minHeight: 44 }).layoutWeight(1).fontSize(11).fontColor((this.materialThickness === 3) ? '#29251A' : UiTheme.secondary(this.darkTheme)).backgroundColor((this.materialThickness === 3) ? '#16D9C9' : UiTheme.control(this.darkTheme)).onClick(() => this.changeThickness(3))
                Button('超厚').constraintSize({ minHeight: 44 }).layoutWeight(1).fontSize(11).fontColor((this.materialThickness === 4) ? '#29251A' : UiTheme.secondary(this.darkTheme)).backgroundColor((this.materialThickness === 4) ? '#16D9C9' : UiTheme.control(this.darkTheme)).onClick(() => this.changeThickness(4))
              }.width('100%')
            }.padding(15).width('100%').backgroundColor(UiTheme.surface(this.darkTheme)).borderRadius(18)

            Text('系统材质只在 HarmonyOS 支持的组件和设备上生效；网页内部由官网自行控制外观。')
              .fontSize(11).fontColor(UiTheme.muted(this.darkTheme)).width('100%').lineHeight(18).padding({ left: 3, right: 3 })
            Row({ space: 12 }) {
              Column({ space: 5 }) {
                Text('底部布局诊断（临时）').fontSize(15).fontColor(UiTheme.primary(this.darkTheme))
                Text('仅排查底部横条时打开，截图后关闭。').fontSize(11).fontColor(UiTheme.muted(this.darkTheme))
              }.alignItems(HorizontalAlign.Start).layoutWeight(1)
              Toggle({ type: ToggleType.Switch, isOn: this.diagnostic }).onChange((enabled: boolean) => { this.diagnostic = enabled; })
            }.padding(15).width('100%').backgroundColor(UiTheme.surface(this.darkTheme)).borderRadius(18)
            Button('清除网页登录状态').constraintSize({ minHeight: 44 }).width('100%').fontColor(UiTheme.warningText(this.darkTheme))
              .backgroundColor(UiTheme.warningSurface(this.darkTheme)).onClick(() => this.clearWebSession())
              .systemMaterial(UiTheme.button(this.materialEnabled, this.materialThickness))
            if (this.message) { Text(this.message).fontColor(UiTheme.errorText(this.darkTheme)).fontSize(12).width('100%') }
            Row().width('100%').height(90)
          }.width('100%').padding({ left: 18, right: 18, top: 14, bottom: 20 })
        }.scrollBar(BarState.Auto).width('100%').height('100%').backgroundColor(UiTheme.page(this.darkTheme))
      }.width('100%').height('100%')
    }.title(this.pageHeader).titleMode(NavigationTitleMode.Mini).hideBackButton(true).hideToolBar(true).mode(NavigationMode.Stack).width('100%').height('100%')
    }
    }.width('100%').height('100%').backgroundColor(this.diagnostic ? '#9C27B0' : Color.Transparent)
      .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.BOTTOM])
  }
}
