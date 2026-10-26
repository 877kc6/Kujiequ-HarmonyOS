import { Pair, Picture, EditorParagraph, ContentBlock, UploadedMedia, EditorText } from '../models/Models';
import { escapedHtml } from './GameBoards';
export interface UploadCredential { AccessKeyId: string; AccessKeySecret: string; SecurityToken: string; Expiration?: string; }
export interface UploadAddress { Endpoint: string; Bucket: string; FileName: string; }
export interface VideoTicket { uploadAuth: string; uploadAddress: string; videoId: string; }
export interface PlayCredential extends UploadCredential { Region: string; AuthInfo: string; PlayDomain?: string; }
export interface PlayInfo { PlayURL: string; Encrypt?: number; Format?: string; Definition?: string; }
export interface PlayInfoResponse { PlayInfoList?: PlayInfoContainer; Code?: string; }
export interface PlayInfoContainer { PlayInfo: PlayInfo[]; }
export function rpcEncode(value: string): string {
  return encodeURIComponent(value).replace(/[!'()*]/g, (s: string): string => '%' + s.charCodeAt(0).toString(16).toUpperCase());
}
export function canonicalQuery(pairs: Pair[]): string {
  return pairs.slice().sort((a: Pair, b: Pair): number => a.key < b.key ? -1 : a.key > b.key ? 1 : 0)
    .map((p: Pair): string => rpcEncode(p.key) + '=' + rpcEncode(p.value)).join('&');
}
export function ossUploadUrl(address: UploadAddress): string {
  const endpoint = address.Endpoint.replace(/^https?:\/\//i, '').replace(/\/$/, '');
  if (!/^[a-z0-9.-]+\.aliyuncs\.com$/i.test(endpoint) || !/^[a-z0-9-]{3,63}$/.test(address.Bucket) ||
      !address.FileName || address.FileName.startsWith('/') || address.FileName.split('/').includes('..') || /[\r\n?#]/.test(address.FileName)) {
    throw new Error('视频上传地址不受支持');
  }
  return 'https://' + address.Bucket + '.' + endpoint + '/' + address.FileName.split('/').map((v: string): string => rpcEncode(v)).join('/');
}
export function mediaContent(body: string, attachments: UploadedMedia[]): string {
  const node: EditorText = { type: 1, content: body, target: '' };
  const blocks: EditorParagraph[] = [{ contentType: 1, content: body, children: [node] }];
  const pictures: Picture[] = attachments.filter((m: UploadedMedia): boolean => m.kind === 'image').map((m: UploadedMedia): Picture => ({ url: m.url, imgWidth: m.width, imgHeight: m.height }));
  // Official serialized image blocks use contentType 2 and URL/dimensions.
  const text: string[] = [JSON.stringify(blocks[0])];
  pictures.forEach((p: Picture) => {
    const block: ContentBlock = { contentType: 2, url: p.url, imgWidth: p.imgWidth, imgHeight: p.imgHeight };
    text.push(JSON.stringify(block));
  });
  return '[' + text.join(',') + ']';
}
export function mediaHtml(body: string, attachments: UploadedMedia[]): string {
  return escapedHtml(body) + attachments.filter((m: UploadedMedia): boolean => m.kind === 'image')
    .map((m: UploadedMedia): string => '<p><img src="' + m.url.replace(/&/g, '&amp;').replace(/"/g, '&quot;') + '" width="' + m.width + '" height="' + m.height + '"></p>').join('');
}
