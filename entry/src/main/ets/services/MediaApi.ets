import { http } from '@kit.NetworkKit';
import { fileIo } from '@kit.CoreFileKit';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { util } from '@kit.ArkTS';
import { image } from '@kit.ImageKit';
import { media } from '@kit.MediaKit';
import { KuroApi } from './KuroApi';
import { Session } from './Session';
import { checked, ApiError } from './Protocol';
import { Envelope, Pair, UploadedMedia } from '../models/Models';
import { UploadCredential, UploadAddress, VideoTicket, PlayCredential, PlayInfoResponse, PlayInfo, canonicalQuery, rpcEncode, ossUploadUrl } from './MediaProtocol';
export class PlaybackError extends Error {}
export class MediaUploadError extends Error {}
interface PlaybackFailure { code?: number | string; }
function playbackFailure(stage: string, error: PlaybackFailure): PlaybackError {
  const raw = error?.code;
  const code = typeof raw === 'number' ? String(raw) : (typeof raw === 'string' && /^[A-Za-z0-9_.-]{1,80}$/.test(raw) ? raw : '未返回错误码');
  return new PlaybackError(stage + '失败（' + code + '），请重试并反馈此提示');
}
function uploadFailure(stage: string, error: PlaybackFailure): MediaUploadError {
  const raw = error?.code;
  const code = typeof raw === 'number' ? String(raw) : (typeof raw === 'string' && /^[A-Za-z0-9_.-]{1,80}$/.test(raw) ? raw : '未返回错误码');
  return new MediaUploadError(stage + '失败（' + code + '），本地预览已保留');
}
interface PlayTicket { playAuth: string; }
interface SendProgress { sendSize: number; totalSize: number; }
export class MediaApi {
  private static encode(text: string): Uint8Array { return new util.TextEncoder().encodeInto(text); }
  private static decode<T>(text: string): T {
    const data = new util.Base64Helper().decodeSync(text);
    return JSON.parse(new util.TextDecoder().decodeWithStream(data)) as T;
  }
  private static async signature(secret: string, text: string): Promise<string> {
    const generator = cryptoFramework.createSymKeyGenerator('HMAC');
    const key = await generator.convertKey({ data: MediaApi.encode(secret) });
    const mac = cryptoFramework.createMac('SHA1');
    await mac.init(key); await mac.update({ data: MediaApi.encode(text) });
    return new util.Base64Helper().encodeToStringSync((await mac.doFinal()).data);
  }
  private static async binary(uri: string, limit: number): Promise<ArrayBuffer> {
    const file = await fileIo.open(uri, fileIo.OpenMode.READ_ONLY);
    try {
      const info = await fileIo.stat(file.fd);
      if (!Number.isSafeInteger(info.size) || info.size <= 0 || info.size > limit) { throw new Error('图片限10 MB，视频限50 MB，请先压缩后选择'); }
      const buffer = new ArrayBuffer(info.size);
      const count = await fileIo.read(file.fd, buffer);
      if (count !== info.size) { throw new Error('媒体读取不完整，请重新选择'); }
      return buffer;
    } finally { await fileIo.close(file); }
  }
  static async uploadImage(uri: string, progress: (value: number) => void): Promise<UploadedMedia> {
    let stage: string = '图片文件读取';
    try {
    const account = Session.userId; const generation = Session.generation;
    if (!Session.token) { throw new MediaUploadError('请先登录'); }
    const data = await MediaApi.binary(uri, 10 * 1024 * 1024);
    stage = '图片格式读取';
    const source = image.createImageSource(data);
    let width: number = 0; let height: number = 0; let mime: string = '';
    try { const info = await source.getImageInfo(); width = info.size.width; height = info.size.height; mime = info.mimeType || ''; }
    finally { await source.release(); }
    if (!['image/jpeg', 'image/png', 'image/webp', 'image/gif'].includes(mime)) { throw new MediaUploadError('请选择 JPG、PNG、WebP 或 GIF 图片'); }
    if (generation !== Session.generation) { throw new MediaUploadError('账号已变化，请重新选择'); }
    const boundary = 'Kujiequ' + util.generateRandomUUID().replace(/-/g, '');
    const extension = mime === 'image/jpeg' ? 'jpg' : mime.substring(6);
    const start = MediaApi.encode('--' + boundary + '\r\nContent-Disposition: form-data; name="files"; filename="image.' + extension + '"\r\nContent-Type: ' + mime + '\r\n\r\n');
    const end = MediaApi.encode('\r\n--' + boundary + '--\r\n');
    const payload = new Uint8Array(start.length + data.byteLength + end.length);
    payload.set(start); payload.set(new Uint8Array(data), start.length); payload.set(end, start.length + data.byteLength);
    stage = '库街区图片上传';
    // Keep the same account/token. Some sessions are accepted by only one
    // protocol source. Retry on business code 220 only, never on other errors.
    const sources: string[] = ['h5', 'android'];
    for (let attempt = 0; attempt < sources.length; attempt++) {
      if (generation !== Session.generation || account !== Session.userId) {
        throw new MediaUploadError('账号已变化，本次附件未加入');
      }
      const headers = KuroApi.headers(sources[attempt]);
      headers['Content-Type'] = 'multipart/form-data; boundary=' + boundary;
      const request = http.createHttp();
      try {
        request.on('dataSendProgress', (event: SendProgress) => {
          if (event.totalSize > 0) { progress(Math.min(99, Math.floor(event.sendSize / event.totalSize * 100))); }
        });
        const response = await request.request('https://api.kurobbs.com/forum/uploadForumImgForH5', {
          method: http.RequestMethod.POST, header: headers,
          extraData: payload.buffer, expectDataType: http.HttpDataType.STRING,
          connectTimeout: 15000, readTimeout: 120000, maxLimit: 1024 * 1024
        });
        if (response.responseCode !== 200) {
          throw new MediaUploadError('图片上传失败（HTTP ' + response.responseCode + '）');
        }
        if (generation !== Session.generation || account !== Session.userId) {
          throw new MediaUploadError('账号已变化，本次附件未加入');
        }
        stage = '图片上传响应';
        const envelope = JSON.parse(response.result as string) as Envelope<string[]>;
        if (envelope.code === 220) {
          if (attempt === 0) { stage = '切换图片上传协议'; continue; }
          throw new MediaUploadError('图片上传被服务器拒绝（220）：已尝试 H5 和原生协议。请重新登录库街区后重试；本地草稿与图片已保留');
        }
        const urls = checked<string[]>(envelope);
        if (!Array.isArray(urls) || !urls[0] || !/^https:\/\//i.test(urls[0])) {
          throw new MediaUploadError('图片上传结果无有效地址');
        }
        progress(100);
        return { kind: 'image', url: urls[0], width: width, height: height, videoId: '', name: 'image.' + extension };
      } finally { request.destroy(); }
    }
    throw new MediaUploadError('图片上传未完成，请重新登录后重试');
    } catch (error) {
      if (error instanceof MediaUploadError) { throw error; }
      throw uploadFailure(stage, error as PlaybackFailure);
    }
  }
  static async uploadVideo(uri: string, gameId: number, progress: (value: number) => void): Promise<UploadedMedia> {
    let stage: string = '视频文件读取';
    try {
    const generation = Session.generation;
    if (!Session.token) { throw new MediaUploadError('请先登录'); }
    const data = await MediaApi.binary(uri, 50 * 1024 * 1024);
    stage = '视频元数据读取';
    const extractor = await media.createAVMetadataExtractor();
    let file: fileIo.File | undefined = undefined;
    let duration: number = 0; let width: number = 0; let height: number = 0;
    try {
      file = await fileIo.open(uri, fileIo.OpenMode.READ_ONLY);
      extractor.fdSrc = { fd: file.fd, offset: 0, length: data.byteLength };
      const metadata = await extractor.fetchMetadata();
      duration = Number(metadata.duration || 0) / 1000; width = Number(metadata.videoWidth || 0); height = Number(metadata.videoHeight || 0);
    } finally { try { await extractor.release(); } finally { if (file) { await fileIo.close(file); } } }
    if (!(duration > 0) || !(width > 0) || !(height > 0)) { throw new MediaUploadError('无法读取视频信息，请选择有效视频'); }
    if (generation !== Session.generation) { throw new MediaUploadError('账号已变化，请重新选择'); }
    const magic = new Uint8Array(data, 0, Math.min(12, data.byteLength));
    if (magic.length < 12 || magic[4] !== 102 || magic[5] !== 116 || magic[6] !== 121 || magic[7] !== 112 ||
        (magic[8] === 113 && magic[9] === 116)) { throw new MediaUploadError('当前请选择 MP4 视频，其他格式请先转换'); }
    const name = 'video.mp4';
    stage = '库街区视频上传授权';
    const ticketPairs: Pair[] = [
      { key: 'videoName', value: name }, { key: 'duration', value: String(duration) },
      { key: 'size', value: String(data.byteLength) }, { key: 'gameId', value: String(gameId) }
    ];
    let ticket: VideoTicket;
    try {
      ticket = await KuroApi.post<VideoTicket>('/forum/video/prePublish', ticketPairs, true, '', 'h5');
    } catch (error) {
      const failure = error as ApiError;
      if (failure.code !== 220 || generation !== Session.generation) {
        throw new MediaUploadError(error instanceof Error ? error.message : '视频上传授权失败，请重试');
      }
      // Only retry a rejected authorization. Never repeat a successful OSS PUT.
      stage = '视频上传授权（原生协议重试）';
      try {
        ticket = await KuroApi.post<VideoTicket>('/forum/video/prePublish', ticketPairs, true, '', 'android');
      } catch (second) {
        if ((second as ApiError).code === 220) {
          throw new MediaUploadError('视频上传授权被拒绝（220）：H5 与原生协议均失败，请重新登录后重试。视频仍保留在编辑页');
        }
        throw new MediaUploadError(second instanceof Error ? second.message : '视频上传授权重试失败，请重试');
      }
    }
    if (generation !== Session.generation) { throw new MediaUploadError('账号已变化，视频上传已取消'); }
    stage = '视频上传凭证解码';
    const auth = MediaApi.decode<UploadCredential>(ticket.uploadAuth);
    const address = MediaApi.decode<UploadAddress>(ticket.uploadAddress);
    const url = ossUploadUrl(address); const date = new Date().toUTCString(); const type = 'video/mp4';
    if (!auth.AccessKeyId || !auth.AccessKeySecret || !auth.SecurityToken || !ticket.videoId) { throw new MediaUploadError('视频上传授权不完整'); }
    stage = '视频上传签名';
    const signature = await MediaApi.signature(auth.AccessKeySecret, 'PUT\n\n' + type + '\n' + date + '\nx-oss-security-token:' + auth.SecurityToken + '\n/' + address.Bucket + '/' + address.FileName);
    stage = '视频对象存储上传';
    const request = http.createHttp();
    try {
      request.on('dataSendProgress', (event: SendProgress) => { if (event.totalSize > 0) { progress(Math.min(99, Math.floor(event.sendSize / event.totalSize * 100))); } });
      const response = await request.request(url, { method: http.RequestMethod.PUT,
        header: { 'Content-Type': type, 'Date': date, 'x-oss-security-token': auth.SecurityToken, 'Authorization': 'OSS ' + auth.AccessKeyId + ':' + signature },
        extraData: data, expectDataType: http.HttpDataType.STRING, connectTimeout: 15000, readTimeout: 120000, maxLimit: 1024 * 1024 });
      if (response.responseCode !== 200) { throw new MediaUploadError('视频上传失败（HTTP ' + response.responseCode + '），可重新选择重试'); }
      if (generation !== Session.generation) { throw new MediaUploadError('账号已变化，本次视频未加入'); }
      progress(100); return { kind: 'video', url: '', width: width, height: height, videoId: ticket.videoId, name: name };
    } finally { request.destroy(); }
    } catch (error) {
      if (error instanceof MediaUploadError) { throw error; }
      throw uploadFailure(stage, error as PlaybackFailure);
    }
  }
  static async playback(videoId: string): Promise<string> {
    let stage: string = '视频编号校验';
    try {
    if (!/^[a-zA-Z0-9_-]{8,128}$/.test(videoId)) { throw new Error('视频编号无效'); }
    stage = '库街区播放授权';
    const ticket = await KuroApi.post<PlayTicket>('/forum/video/refreshPlayCode', [{ key: 'videoId', value: videoId }], false, '', 'h5');
    stage = '播放凭证解码';
    const auth = MediaApi.decode<PlayCredential>(ticket.playAuth);
    if (!auth.AccessKeyId || !auth.AccessKeySecret || !auth.SecurityToken || !auth.AuthInfo || !/^[a-z]{2}-[a-z0-9-]+$/.test(auth.Region)) { throw new PlaybackError('播放凭证缺少必要字段，暂时无法获取播放地址'); }
    const pairs: Pair[] = [
      { key: 'Action', value: 'GetPlayInfo' }, { key: 'Version', value: '2017-03-21' }, { key: 'Format', value: 'JSON' },
      { key: 'AccessKeyId', value: auth.AccessKeyId }, { key: 'SecurityToken', value: auth.SecurityToken },
      { key: 'AuthInfo', value: auth.AuthInfo }, { key: 'VideoId', value: videoId }, { key: 'Formats', value: 'mp4,m3u8' },
      { key: 'StreamType', value: 'video' }, { key: 'ResultType', value: 'Single' }, { key: 'OutputType', value: 'cdn' },
      { key: 'Timestamp', value: new Date().toISOString().replace(/\.\d{3}Z$/, 'Z') },
      { key: 'SignatureMethod', value: 'HMAC-SHA1' }, { key: 'SignatureVersion', value: '1.0' },
      { key: 'SignatureNonce', value: util.generateRandomUUID() }
    ];
    stage = '播放请求签名';
    const canonical = canonicalQuery(pairs);
    const signature = await MediaApi.signature(auth.AccessKeySecret + '&', 'GET&%2F&' + rpcEncode(canonical));
    const request = http.createHttp();
    try {
      stage = '点播地址请求';
      const response = await request.request('https://vod.' + auth.Region + '.aliyuncs.com/?' + canonical + '&Signature=' + rpcEncode(signature),
        { method: http.RequestMethod.GET, expectDataType: http.HttpDataType.STRING, connectTimeout: 15000, readTimeout: 20000, maxLimit: 1024 * 1024 });
      if (response.responseCode !== 200) {
        let provider: PlayInfoResponse | undefined = undefined;
        try { provider = JSON.parse(response.result as string) as PlayInfoResponse; } catch (_) {}
        const providerCode = provider?.Code;
        const safe = providerCode && /^[A-Za-z0-9_.-]{1,80}$/.test(providerCode) ? ' / ' + providerCode : '';
        throw new PlaybackError('点播服务拒绝请求（HTTP ' + response.responseCode + safe + '），请重试并反馈此提示');
      }
      stage = '播放地址解析';
      const data = JSON.parse(response.result as string) as PlayInfoResponse;
      const list = data.PlayInfoList?.PlayInfo || [];
      const playable = list.find((p: PlayInfo): boolean => (!p.Encrypt || p.Encrypt === 0) && /^https:\/\//i.test(p.PlayURL));
      if (!playable) { throw new PlaybackError(list.length ? '返回的视频流未提供未加密的 HTTPS 播放地址，暂不支持本机播放' : '点播服务未返回视频流，请稍后重试'); }
      return playable.PlayURL;
    } finally { request.destroy(); }
    } catch (error) {
      if (error instanceof PlaybackError) { throw error; }
      throw playbackFailure(stage, error as PlaybackFailure);
    }
  }
}
