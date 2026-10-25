import { Envelope, Pair, CaptchaProof } from '../models/Models';

export class ApiError extends Error {
  code: number;
  traceId: string;
  constructor(code: number, message: string, traceId: string = '') {
    super(message); this.code = code; this.traceId = traceId;
  }
}
export function formEncode(pairs: Pair[]): string {
  return pairs.map((p: Pair): string => `${encodeURIComponent(p.key)}=${encodeURIComponent(p.value)}`).join('&');
}
export function checked<T>(body: Envelope<T>): T {
  if (!body || typeof body.code !== 'number') { throw new ApiError(-2, '接口响应格式异常'); }
  if (body.code === 220) { throw new ApiError(220, body.msg || body.message || '服务器未接受此登录凭证，请重新认证（220）', body.traceId ?? ''); }
  if (body.code !== 200 || body.success === false) {
    throw new ApiError(body.code, body.msg ?? body.message ?? '请求未成功', body.traceId ?? '');
  }
  return body.data;
}
export function chinaMonth(now: number = Date.now()): string {
  return String(new Date(now + 8 * 3600000).getUTCMonth() + 1).padStart(2, '0');
}
export function officialPostUrl(gameId: number, postId: string): string {
  if (!/^\d{1,24}$/.test(postId)) { throw new ApiError(-1, '帖子编号无效'); }
  return `https://www.kurobbs.com/${gameId === 2 ? 'pns' : 'mc'}/post/${postId}`;
}
export function isOfficialUrl(url: string): boolean {
  return /^https:\/\/(www\.kurobbs\.com|web-static\.kurobbs\.com)(\/|$)/i.test(url);
}
export function errorText(error: Error): string { return error.message || '网络暂时不可用，请稍后重试'; }

// Normalize only the documented validation fields; do not forward arbitrary JS input.
export function normalizeCaptchaProof(raw: string): string {
  if (raw.length > 16384) { throw new Error('验证结果过长，请重新验证'); }
  let proof: CaptchaProof;
  try { proof = JSON.parse(raw) as CaptchaProof; }
  catch (_) { throw new Error('验证结果无效，请重新验证'); }
  if (!proof || typeof proof.lot_number !== 'string' || !proof.lot_number ||
    typeof proof.captcha_output !== 'string' || !proof.captcha_output ||
    typeof proof.pass_token !== 'string' || !proof.pass_token ||
    typeof proof.gen_time !== 'string' || !/^\d{1,16}$/.test(proof.gen_time)) {
    throw new Error('验证结果不完整，请重新验证');
  }
  const clean: CaptchaProof = {
    lot_number: proof.lot_number, captcha_output: proof.captcha_output,
    pass_token: proof.pass_token, gen_time: proof.gen_time,
    captcha_id: '3f7e2d848ce0cb7e7d019d621e556ce2'
  };
  return JSON.stringify(clean);
}
