import { fileIo, fileUri } from '@kit.CoreFileKit';
import { media } from '@kit.MediaKit';
import { image } from '@kit.ImageKit';
import { util } from '@kit.ArkTS';
import { UploadedMedia } from '../models/Models';
export class MediaCache {
  static owns(filesDir: string, path: string): boolean {
    return path.startsWith(filesDir + '/compose_media_') && !path.substring(filesDir.length + 1).includes('/') && !path.includes('..');
  }
  static async stage(filesDir: string, uri: string, video: boolean): Promise<UploadedMedia> {
    const id = util.generateRandomUUID();
    const path = filesDir + '/compose_media_' + id + (video ? '.mp4' : '.image');
    const source = await fileIo.open(uri, fileIo.OpenMode.READ_ONLY);
    try {
      const stat = await fileIo.stat(source.fd);
      if (stat.size <= 0 || stat.size > (video ? 50 : 10) * 1024 * 1024) { throw new Error('媒体大小超出限制'); }
      await fileIo.copyFile(source.fd, path);
    } catch (e) { try { await fileIo.unlink(path); } catch (_) {} throw new Error('媒体副本创建失败，请重新选择'); }
    finally { await fileIo.close(source); }
    const localUri = fileUri.getUriFromPath(path);
    const item: UploadedMedia = { kind: video ? 'video' : 'image', url: '', width: 0, height: 0, videoId: '',
      name: video ? 'video.mp4' : 'image', localUri: localUri, localPath: path, previewUri: video ? '' : localUri,
      uploadState: 'pending', localId: id };
    if (video) {
      try { item.previewUri = await MediaCache.thumbnail(path); } catch (_) { /* Local video remains playable even if thumbnail extraction is unsupported. */ }
    }
    return item;
  }
  private static async thumbnail(path: string): Promise<string> {
    const generator = await media.createAVImageGenerator();
    if (!generator) { throw new Error('当前设备不支持视频缩略图'); }
    const packer = image.createImagePacker();
    let input: fileIo.File | undefined = undefined; let output: fileIo.File | undefined = undefined;
    let pixels: image.PixelMap | undefined = undefined;
    try {
      input = await fileIo.open(path, fileIo.OpenMode.READ_ONLY);
      generator.fdSrc = { fd: input.fd, offset: 0, length: (await fileIo.stat(input.fd)).size };
      pixels = await generator.fetchFrameByTime(0, media.AVImageQueryOptions.AV_IMAGE_QUERY_NEXT_SYNC, { width: 480, height: 270 });
      output = await fileIo.open(path + '.jpg', fileIo.OpenMode.CREATE | fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.TRUNC);
      await packer.packToFile(pixels, output.fd, { format: 'image/jpeg', quality: 80 });
      return fileUri.getUriFromPath(path + '.jpg');
    } finally {
      try { if (pixels) { await pixels.release(); } }
      finally { try { await generator.release(); } finally { try { await packer.release(); }
        finally { if (input) { await fileIo.close(input); } if (output) { await fileIo.close(output); } } } }
    }
  }
  static async remove(filesDir: string, item: UploadedMedia): Promise<void> {
    if (!item.localPath || !MediaCache.owns(filesDir, item.localPath)) { return; }
    try { await fileIo.unlink(item.localPath); } catch (_) {}
    try { await fileIo.unlink(item.localPath + '.jpg'); } catch (_) {}
  }
}
