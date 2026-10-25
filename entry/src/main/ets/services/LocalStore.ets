import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import { SavedPost, Profile, ComposeDraft } from '../models/Models';

export class LocalStore {
  private static db?: preferences.Preferences;
  static deviceId: string = '';
  static immersive: boolean = true;
  static materialLevel: string = 'ADAPTIVE';
  static materialThickness: number = 2;
  static themeMode: string = 'system';
  static darkTheme: boolean = false;
  static backgroundImage: string = '';
  static autoSignIn: boolean = true;
  static autoSignAttempts: string[] = [];
  static async init(context: common.Context): Promise<void> {
    LocalStore.db = await preferences.getPreferences(context, { name: 'kujiequ_public' });
    LocalStore.deviceId = await LocalStore.db.get('device_id', '') as string;
    if (!LocalStore.deviceId) {
      LocalStore.deviceId = util.generateRandomUUID(true);
      await LocalStore.db.put('device_id', LocalStore.deviceId);
    }
    LocalStore.immersive = await LocalStore.db.get('immersive', true) as boolean;
    LocalStore.materialLevel = await LocalStore.db.get('material_level', 'ADAPTIVE') as string;
    LocalStore.materialThickness = await LocalStore.db.get('material_thickness', 2) as number;
    LocalStore.darkTheme = await LocalStore.db.get('dark_theme', false) as boolean;
    LocalStore.backgroundImage = await LocalStore.db.get('background_image', '') as string;
    LocalStore.autoSignIn = await LocalStore.db.get('auto_sign_in', true) as boolean;
    const autoAttempts = await LocalStore.db.get('auto_sign_attempts', '[]') as string;
    try { LocalStore.autoSignAttempts = JSON.parse(autoAttempts) as string[]; }
    catch (_) { LocalStore.autoSignAttempts = []; }
    AppStorage.setOrCreate('immersiveEnabled', LocalStore.immersive);
    AppStorage.setOrCreate('materialLevel', LocalStore.materialLevel);
    AppStorage.setOrCreate('materialThickness', LocalStore.materialThickness);
    LocalStore.themeMode = await LocalStore.db.get('theme_mode', 'system') as string;
    AppStorage.setOrCreate('themeMode', LocalStore.themeMode);
    AppStorage.setOrCreate('darkTheme', LocalStore.darkTheme);
    AppStorage.setOrCreate('backgroundImage', LocalStore.backgroundImage);
    AppStorage.setOrCreate('autoSignIn', LocalStore.autoSignIn);
    await LocalStore.db.flush();
  }
  private static ready(): preferences.Preferences {
    if (!LocalStore.db) { throw new Error('本地存储尚未初始化'); }
    return LocalStore.db;
  }
  static async material(enabled: boolean): Promise<void> {
    const db = LocalStore.ready(); await db.put('immersive', enabled); await db.flush(); LocalStore.immersive = enabled; AppStorage.setOrCreate('immersiveEnabled', enabled);
  }
  static async setMaterialLevel(level: string): Promise<void> {
    if (!['ADAPTIVE', 'EXQUISITE', 'GENTLE', 'SMOOTH'].includes(level)) { throw new Error('沉浸光感档位无效'); }
    const db = LocalStore.ready(); await db.put('material_level', level); await db.flush();
    LocalStore.materialLevel = level; AppStorage.setOrCreate('materialLevel', level);
  }
  static async setMaterialThickness(thickness: number): Promise<void> {
    if (thickness < 0 || thickness > 4 || Math.floor(thickness) !== thickness) { throw new Error('材质厚度档位无效'); }
    const db = LocalStore.ready(); await db.put('material_thickness', thickness); await db.flush();
    LocalStore.materialThickness = thickness; AppStorage.setOrCreate('materialThickness', thickness);
  }
  static async setThemeMode(mode: string): Promise<void> {
    const db = LocalStore.ready(); await db.put('theme_mode', mode); await db.flush();
    LocalStore.themeMode = mode; AppStorage.setOrCreate('themeMode', mode);
  }
  static async setDarkTheme(enabled: boolean): Promise<void> {
    const db = LocalStore.ready(); await db.put('dark_theme', enabled); await db.flush();
    LocalStore.darkTheme = enabled; AppStorage.setOrCreate('darkTheme', enabled);
  }
  static async setBackgroundImage(path: string): Promise<void> {
    const db = LocalStore.ready(); await db.put('background_image', path); await db.flush();
    LocalStore.backgroundImage = path; AppStorage.setOrCreate('backgroundImage', path);
  }
  static async setAutoSignIn(enabled: boolean): Promise<void> {
    const db = LocalStore.ready(); await db.put('auto_sign_in', enabled); await db.flush();
    LocalStore.autoSignIn = enabled; AppStorage.setOrCreate('autoSignIn', enabled);
  }
  static hasAutoSignAttempt(key: string): boolean { return LocalStore.autoSignAttempts.includes(key); }
  static async markAutoSignAttempt(key: string): Promise<void> {
    const db = LocalStore.ready();
    const attempts = LocalStore.autoSignAttempts.filter((item: string): boolean => item !== key);
    attempts.push(key);
    LocalStore.autoSignAttempts = attempts.slice(-60);
    await db.put('auto_sign_attempts', JSON.stringify(LocalStore.autoSignAttempts)); await db.flush();
  }
  static async profile(userId: string): Promise<Profile | undefined> {
    if (!userId) { return undefined; }
    const raw = await LocalStore.ready().get('profile_' + userId, '') as string;
    if (!raw) { return undefined; }
    try { const data = JSON.parse(raw) as Profile; return data.userId === userId ? data : undefined; }
    catch (_) { return undefined; }
  }
  static async saveProfile(profile: Profile): Promise<void> {
    const db = LocalStore.ready(); await db.put('profile_' + profile.userId, JSON.stringify(profile)); await db.flush();
  }
  static async composeDraft(key: string): Promise<ComposeDraft> {
    const raw = await LocalStore.ready().get('compose_' + key, '') as string;
    if (!raw) { return { title: '', body: '', boardId: 0 }; }
    try { return JSON.parse(raw) as ComposeDraft; } catch (_) { return { title: '', body: '', boardId: 0 }; }
  }
  static async saveCompose(key: string, draft: ComposeDraft): Promise<void> {
    const db = LocalStore.ready(); await db.put('compose_' + key, JSON.stringify(draft)); await db.flush();
  }
  static async saved(): Promise<SavedPost[]> {
    const raw = await LocalStore.ready().get('saved_posts', '[]') as string;
    try { return JSON.parse(raw) as SavedPost[]; } catch (_) { throw new Error('收藏数据无法读取'); }
  }
  static async history(): Promise<SavedPost[]> {
    const raw = await LocalStore.ready().get('view_history', '[]') as string;
    try { return JSON.parse(raw) as SavedPost[]; } catch (_) { throw new Error('浏览记录无法读取'); }
  }
  static async recordView(post: SavedPost): Promise<void> {
    const list = (await LocalStore.history()).filter((item: SavedPost): boolean => item.postId !== post.postId);
    list.unshift(post);
    const db = LocalStore.ready(); await db.put('view_history', JSON.stringify(list.slice(0, 200))); await db.flush();
  }
  static async clearHistory(): Promise<void> {
    const db = LocalStore.ready(); await db.put('view_history', '[]'); await db.flush();
  }
  static async toggle(post: SavedPost): Promise<boolean> {
    let list = await LocalStore.saved();
    const existed = list.some((p: SavedPost): boolean => p.postId === post.postId);
    list = list.filter((p: SavedPost): boolean => p.postId !== post.postId);
    if (!existed) { list.unshift(post); }
    const db = LocalStore.ready(); await db.put('saved_posts', JSON.stringify(list.slice(0, 300))); await db.flush();
    return !existed;
  }
}
