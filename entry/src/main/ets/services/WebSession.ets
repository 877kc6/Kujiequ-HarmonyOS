import { WebAccount } from '../models/Models';

// Run only through runJavaScript in a verified official top-level document.
// No JavaScript proxy, network interception, credential logging or credential URL.
export const READ_WEB_ACCOUNT: string = `(() => {
  if (!/^https:\\/\\/(?:www|web-static)\\.kurobbs\\.com(?:\\/|$)/i.test(location.href)) return '';
  const map = location.href.includes('/resource/map/') || location.href.includes('/mc/map');
  const token = localStorage.getItem(map ? 'AKI_MAP_USER_TOKEN' : 'auth_token') || '';
  if (!token) return '';
  let auth = {}; try { auth = JSON.parse(localStorage.getItem(map ? 'AKI_MAP_USER_INFO' : 'auth') || '{}'); } catch (_) {}
  return JSON.stringify({token: token, userId: String(auth.userId || '')});
})()`;

export function parseWebAccount(raw: string): WebAccount | undefined {
  if (!raw || raw.length > 8192) { return undefined; }
  let value: string = raw;
  try {
    // ArkWeb may encode the JavaScript string result as a JSON string.
    if (value.charAt(0) === '"') { value = JSON.parse(value) as string; }
    if (!value) { return undefined; }
    const account = JSON.parse(value) as WebAccount;
    if (typeof account.token !== 'string' || !account.token || account.token.length > 2048 || /[\r\n]/.test(account.token)) { return undefined; }
    if (typeof account.userId !== 'string' || (account.userId && !/^\d{1,24}$/.test(account.userId))) { return undefined; }
    return account;
  } catch (_) { return undefined; }
}

export const MAP_MOBILE_STYLE: string = `(() => {
  if (!/^https:\\/\\/(?:www\\.kurobbs\\.com\\/mc\\/map(?:\\/|$)|web-static\\.kurobbs\\.com\\/resource\\/map\\/)/i.test(location.href)) return;
  let viewport = document.querySelector('meta[name="viewport"]');
  if (viewport) viewport.content = 'width=device-width,initial-scale=1,minimum-scale=0.5,maximum-scale=3,user-scalable=yes,viewport-fit=cover';
  let style = document.getElementById('harmony-map-touch');
  if (!style) { style = document.createElement('style'); style.id = 'harmony-map-touch'; document.head.appendChild(style); }

  style.textContent = 'input{font-size:16px!important}';
})()`;

// Credentials stay inside the official site's origin and never enter a URL or log.
export function connectOfficialSession(token: string, userId: string, userName: string, map: boolean): string {
  const profile = JSON.stringify({ token: token, userId: userId, userName: userName });
  return `(() => {
    const map = ${map ? 'true' : 'false'};
    const official = /^https:\\/\\/www\\.kurobbs\\.com(?:\\/|$)/i.test(location.href);
    const mapOrigin = /^https:\\/\\/web-static\\.kurobbs\\.com\\/resource\\/map\\//i.test(location.href);
    if (!official && !mapOrigin) return false;
    const key = map ? 'AKI_MAP_USER_TOKEN' : 'auth_token';
    const profile = JSON.parse(${JSON.stringify(profile)});
    if (map && official) {
      if (window.__kujiequMapAuthHandler) window.removeEventListener('message', window.__kujiequMapAuthHandler);
      const message = JSON.stringify({uidType:'token', profile:profile});
      window.__kujiequMapAuthHandler = function(event) {
        if (event.origin !== 'https://web-static.kurobbs.com' || event.data !== 'getToken') return;
        const frames = Array.from(document.querySelectorAll('iframe'));
        if (!frames.some(frame => frame.contentWindow === event.source && /^https:\\/\\/web-static\\.kurobbs\\.com\\/resource\\/map\\//i.test(frame.src))) return;
        event.source.postMessage(message, 'https://web-static.kurobbs.com');
      };
      window.addEventListener('message', window.__kujiequMapAuthHandler);
      document.querySelectorAll('iframe').forEach(frame => {
        if (/^https:\\/\\/web-static\\.kurobbs\\.com\\/resource\\/map\\//i.test(frame.src) && frame.contentWindow) frame.contentWindow.postMessage(message, 'https://web-static.kurobbs.com');
      });
      return false;
    }
    const persisted = JSON.stringify({profile:profile,token:profile.token});
    if (localStorage.getItem(key) === ${JSON.stringify(token)} && (!map || localStorage.getItem('AKI_MAP_USER_PROFILE') === persisted)) return false;
    if (map) localStorage.setItem('AKI_MAP_USER_PROFILE', persisted);
    localStorage.setItem(key, ${JSON.stringify(token)});
    localStorage.setItem(map ? 'AKI_MAP_USER_INFO' : 'auth', ${JSON.stringify(profile)});
    return true;
  })()`;
}
