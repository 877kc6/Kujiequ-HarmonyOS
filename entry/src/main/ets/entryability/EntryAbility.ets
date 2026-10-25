import { Configuration, ConfigurationConstant, UIAbility } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { LocalStore } from '../services/LocalStore';
import { Session } from '../services/Session';

export default class EntryAbility extends UIAbility {
  private mainWindow?: window.Window;
  private updateInsets(win: window.Window): void {
    const system = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
    const gesture = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR);
    const cutout = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_CUTOUT);
    const ui = win.getUIContext();
    AppStorage.setOrCreate('safeTop', ui.px2vp(Math.max(system.topRect.height, cutout.topRect.height)));
    AppStorage.setOrCreate('safeBottom', ui.px2vp(Math.max(system.bottomRect.height, gesture.bottomRect.height)));
    AppStorage.setOrCreate('safeLeft', ui.px2vp(Math.max(system.leftRect.width, cutout.leftRect.width)));
    AppStorage.setOrCreate('safeRight', ui.px2vp(Math.max(system.rightRect.width, cutout.rightRect.width)));
    AppStorage.setOrCreate('windowInsetsReady', true);
  }
  onWindowStageDestroy(): void {
    this.mainWindow?.off('avoidAreaChange'); this.mainWindow = undefined;
  }

  onConfigurationUpdate(config: Configuration): void {
    if (LocalStore.themeMode === 'system' && config.colorMode !== undefined) {
      LocalStore.darkTheme = config.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
      AppStorage.setOrCreate('darkTheme', LocalStore.darkTheme);
      this.context.windowStage.getMainWindow().then((win: window.Window) => {
        const content = LocalStore.darkTheme ? '#F3F4F6' : '#202329';
        win.setWindowSystemBarProperties({ statusBarColor: '#00000000', navigationBarColor: '#00000000', statusBarContentColor: content, navigationBarContentColor: content }).catch(() => {});
      }).catch(() => {});
    }
  }
  onWindowStageCreate(stage: window.WindowStage): void { this.start(stage); }
  private async start(stage: window.WindowStage): Promise<void> {
    AppStorage.setOrCreate('windowInsetsReady', false);
    try {
      await LocalStore.init(this.context);
      await Session.restore();
      if (LocalStore.themeMode === 'system') { LocalStore.darkTheme = this.context.config.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK; AppStorage.setOrCreate('darkTheme', LocalStore.darkTheme); }
    } catch (e) { AppStorage.setOrCreate('bootMessage', (e as Error).message); }
    try {
      const win = await stage.getMainWindow();
      const barContent = LocalStore.darkTheme ? '#F3F4F6' : '#202329';
      await win.setWindowSystemBarProperties({ statusBarColor: '#00000000', statusBarContentColor: barContent, navigationBarColor: '#00000000', navigationBarContentColor: barContent });
    } catch (_) { /* System default safe area remains valid. */ }
    await stage.loadContent('pages/Index');
    try {
      const win = await stage.getMainWindow(); this.mainWindow = win;
      await win.setWindowLayoutFullScreen(true);
      this.updateInsets(win);
      win.on('avoidAreaChange', () => { this.updateInsets(win); });
    } catch (_) {
      // If the device rejects fullscreen, keep its automatic avoidance rather than a hidden UI.
      try { await this.mainWindow?.setWindowLayoutFullScreen(false); } catch (_) {}
      AppStorage.setOrCreate('safeTop', 0); AppStorage.setOrCreate('safeBottom', 0);
      AppStorage.setOrCreate('safeLeft', 0); AppStorage.setOrCreate('safeRight', 0);
      AppStorage.setOrCreate('windowInsetsReady', true);
    }
    try {
      this.context.setColorMode(LocalStore.themeMode === 'system' ? ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET : (LocalStore.themeMode === 'dark' ? ConfigurationConstant.ColorMode.COLOR_MODE_DARK : ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT));
      if (LocalStore.themeMode === 'system') { this.onConfigurationUpdate(this.context.config); }
    } catch (_) { /* Explicit palette values remain the visual source of truth. */ }
  }
}
