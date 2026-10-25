import { asset } from '@kit.AssetStoreKit';
import { util } from '@kit.ArkTS';
import { BusinessError } from '@kit.BasicServicesKit';
import { LoginData } from '../models/Models';

// Credentials never enter Preferences, logs, URL parameters or WebView JavaScript.
export class Session {
  static token: string = '';
  static userId: string = '';
  static userName: string = '';
  static generation: number = 0;
  private static alias: string = 'kujiequ.account.v1';

  private static query(): asset.AssetMap {
    const map: asset.AssetMap = new Map();
    map.set(asset.Tag.ALIAS, new util.TextEncoder().encodeInto(Session.alias));
    return map;
  }
  static async restore(): Promise<void> {
    try {
      const query = Session.query();
      query.set(asset.Tag.RETURN_TYPE, asset.ReturnType.ALL);
      const rows = await asset.query(query);
      if (rows.length === 0) { return; }
      const raw = rows[0].get(asset.Tag.SECRET) as Uint8Array;
      const data = JSON.parse(new util.TextDecoder().decodeWithStream(raw)) as LoginData;
      if (!data.token || !data.userId) { throw new Error('保存的登录信息不完整'); }
      Session.token = data.token; Session.userId = String(data.userId); Session.userName = data.userName;
      Session.generation++;
    } catch (e) {
      if ((e as BusinessError).code !== 24000002) { throw new Error('无法读取安全登录信息，请解锁设备后重试'); }
    }
  }
  static async save(data: LoginData): Promise<void> {
    if (!data.token || !data.userId) { throw new Error('登录响应缺少凭证'); }
    const compact: LoginData = { token: data.token, userId: String(data.userId), userName: data.userName ?? '', headUrl: '' };
    const bytes = new util.TextEncoder().encodeInto(JSON.stringify(compact));
    if (bytes.length > 1024) { throw new Error('登录凭证超出安全存储上限'); }
    const attrs = Session.query();
    attrs.set(asset.Tag.SECRET, bytes);
    attrs.set(asset.Tag.ACCESSIBILITY, asset.Accessibility.DEVICE_UNLOCKED);
    attrs.set(asset.Tag.CONFLICT_RESOLUTION, asset.ConflictResolution.OVERWRITE);
    await asset.add(attrs);
    Session.token = compact.token; Session.userId = compact.userId; Session.userName = compact.userName;
    Session.generation++;
  }
  static async logout(): Promise<void> {
    // Do not claim logout succeeded if deletion of the encrypted credential fails.
    try { await asset.remove(Session.query()); }
    catch (e) { if ((e as BusinessError).code !== 24000002) { throw new Error('删除安全凭证失败，请重试'); } }
    Session.token = ''; Session.userId = ''; Session.userName = ''; Session.generation++;
  }
}
