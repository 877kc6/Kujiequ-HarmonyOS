import { uiMaterial } from '@kit.ArkUI';
import { hdsMaterial } from '@kit.UIDesignKit';

export class UiTheme {
  private static materials: uiMaterial.Material[] = [];
  static button(enabled: boolean, thickness: number = 2): uiMaterial.Material {
    if (!enabled) { return uiMaterial.Material.empty; }
    const index = Math.max(0, Math.min(4, thickness));
    if (UiTheme.materials[index]) { return UiTheme.materials[index]; }
    const material = new uiMaterial.ImmersiveMaterial({
      style: UiTheme.immersiveStyle(thickness),
      interactive: true,
      lightEffect: { color: '#FFF3C2' }
    });
    UiTheme.materials[index] = material;
    return material;
  }
  static immersiveStyle(thickness: number): uiMaterial.ImmersiveStyle {
    switch (thickness) {
      case 0: return uiMaterial.ImmersiveStyle.ULTRA_THIN;
      case 1: return uiMaterial.ImmersiveStyle.THIN;
      case 3: return uiMaterial.ImmersiveStyle.THICK;
      case 4: return uiMaterial.ImmersiveStyle.ULTRA_THICK;
      default: return uiMaterial.ImmersiveStyle.REGULAR;
    }
  }
  static hdsLevel(level: string): hdsMaterial.MaterialLevel {
    switch (level) {
      case 'EXQUISITE': return hdsMaterial.MaterialLevel.EXQUISITE;
      case 'GENTLE': return hdsMaterial.MaterialLevel.GENTLE;
      case 'SMOOTH': return hdsMaterial.MaterialLevel.SMOOTH;
      default: return hdsMaterial.MaterialLevel.ADAPTIVE;
    }
  }
  static page(_dark: boolean): string { return '#00000000'; }
  static base(dark: boolean): string { return dark ? '#12151B' : '#F4F5F7'; }
  static surface(dark: boolean): string { return dark ? '#E0262B34' : '#D9FFFFFF'; }
  static control(dark: boolean): string { return dark ? '#FF303640' : '#ECEEF1'; }
  static primary(dark: boolean): string { return dark ? '#F3F4F6' : '#202329'; }
  static body(dark: boolean): string { return dark ? '#D7DCE4' : '#414750'; }
  static secondary(dark: boolean): string { return dark ? '#B5BDC8' : '#747B86'; }
  static muted(dark: boolean): string { return dark ? '#929BA8' : '#939AA4'; }
  static divider(dark: boolean): string { return dark ? '#FF414752' : '#E7E9ED'; }
  static accentSurface(dark: boolean): string { return dark ? '#FF3A3324' : '#FFF7DF'; }
  static errorSurface(dark: boolean): string { return dark ? '#FF3A2624' : '#FFF1E8'; }
  static errorText(dark: boolean): string { return dark ? '#FFFFAA93' : '#A35432'; }
  static warningSurface(dark: boolean): string { return dark ? '#FF392725' : '#FFF0ED'; }
  static warningText(dark: boolean): string { return dark ? '#FFFFA89B' : '#AD4E43'; }
}
