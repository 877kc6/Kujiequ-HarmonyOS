"""Project wiring checks. Does not claim to compile ArkTS or validate SDK types."""
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
for p in ROOT.rglob('*'):
    if p.suffix in ('.json', '.json5'):
        json.loads(p.read_text())  # This project's JSON5 deliberately uses JSON syntax.
profile = json.loads((ROOT / 'build-profile.json5').read_text())
product = profile['app']['products'][0]
assert all(product[k] == '26.0.0' for k in ['compileSdkVersion', 'compatibleSdkVersion', 'targetSdkVersion'])
ETSDIR = ROOT / 'entry/src/main/ets'
pages = json.loads((ROOT / 'entry/src/main/resources/base/profile/main_pages.json').read_text())['src']
for p in pages:
    assert (ETSDIR / (p + '.ets')).is_file(), p
refs = set()
for p in ETSDIR.rglob('*.ets'):
    text = p.read_text()
    assert not re.search(r'\b(?:any|eval)\b', text), p
    for imported in re.findall(r"from ['\"]([^'\"]+)['\"]", text):
        assert imported.startswith('@kit.') or imported.startswith('.') or imported == 'libcapture_probe.so', (p, imported)
        if imported.startswith('.'):
            assert (p.parent / (imported + '.ets')).is_file(), (p, imported)
    refs.update(re.findall(r"\$r\('app\.media\.(\w+)'\)", text))
    for route in re.findall(r"url: '(pages/\w+)'", text):
        assert route in pages, route
media = ROOT / 'entry/src/main/resources/base/media'
for ref in refs:
    assert list(media.glob(ref + '.*')), ref
for p in media.glob('*.svg'):
    import xml.etree.ElementTree as ET
    ET.parse(p)
print('PASS: JSON, API 26 configuration, page routes, relative imports, Kit-only native imports, resources and SVG syntax')

# A single full-window host owns insets; no route may toggle the window mode.
assert not any('.expandSafeArea(' in p.read_text() for p in ETSDIR.rglob('*.ets'))
for p in (ETSDIR/'pages').glob('*.ets'):
    assert 'SafePage(' in p.read_text(), p
for p in ETSDIR.rglob('*.ets'):
    if p.name != 'EntryAbility.ets': assert 'setWindowLayoutFullScreen(' not in p.read_text(), p
updater=(ROOT/'Apply_Update.ps1').read_text(encoding='utf-8-sig')
# Full-source updater enumerates all project files, rather than a hard-coded file list.
for marker in ['Get-ChildItem -LiteralPath $source -Recurse -File', 'Copy-Item -LiteralPath $file.FullName', '$backup']:
    assert marker in updater, marker
for f in ['entry/src/main/ets/pages/AccountList.ets','entry/src/main/ets/components/SafePage.ets',
          'entry/src/main/ets/services/AccountData.ets','entry/src/main/resources/base/profile/main_pages.json']:
    assert (ROOT/f).is_file(), f
index=(ETSDIR/'pages/Index.ets').read_text()
assert "Button('主题与背景')" not in index
assert "pages/WebPage" not in (ETSDIR/'pages/AccountList.ets').read_text()
print('PASS: uniform safe-area host, native account route and updater source files')

# @Entry requires a built-in container root, not a custom SafePage root.
for p in (ETSDIR/'pages').glob('*.ets'):
    source=p.read_text()
    if '@Entry' in source:
        assert re.search(r'build\(\)\s*\{\s*Stack\(\)\s*\{\s*SafePage\(',source), p
print('PASS: all Entry pages have native Stack roots')

for p in list((ETSDIR/'pages').glob('*.ets')) + [ETSDIR/'components/SafePage.ets', ETSDIR/'components/AppBackdrop.ets']:
    source=p.read_text()
    assert '.ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.BOTTOM])' in source, p
    assert 'LayoutSafeAreaEdge.TOP' not in source, p
assert 'bottom: this.mapMode || !this.reserveBottom ? 0 : this.safeBottom' in (ETSDIR/'components/SafePage.ets').read_text()
print('PASS: bottom-only layout extension preserves foreground gesture avoidance')

index=(ETSDIR/'pages/Index.ets').read_text()
assert 'SafePage({ reserveBottom: false })' in index
assert 'barBottomMargin: 18 + this.safeBottom' in index
assert "openAccountList('follows')" in index and "profile.fansCount" in index
print('PASS: edge-to-edge main content and independently protected floating controls')

module = json.loads((ROOT/'entry/src/main/module.json5').read_text())['module']
ext = [x for x in module['extensionAbilities'] if x['name'] == 'CaptureProbeAbility']
assert len(ext) == 1 and ext[0]['type'] == 'vpn' and ext[0]['exported'] is False
assert (ROOT/'entry/src/main'/ext[0]['srcEntry']).is_file()
native = json.loads((ROOT/'entry/build-profile.json5').read_text())['buildOption']['externalNativeOptions']
assert (ROOT/'entry'/native['path']).is_file()
package = json.loads((ROOT/'entry/oh-package.json5').read_text())
assert package['dependencies']['libcapture_probe.so'] == 'file:./src/main/cpp/types/libcapture_probe'
vpn = (ETSDIR/'vpnability/CaptureProbeAbility.ets').read_text()
assert 'trustedApplications: [bundleName]' in vpn and 'isDefaultRoute: false' in vpn
assert 'prefixLength: 32' in vpn and 'dnsAddresses' not in vpn
assert 'AppStorage' not in vpn
assert "phase = 'passed'" not in (ETSDIR/'pages/CaptureProbe.ets').read_text()
print('PASS: native diagnostic build wiring, private VPN extension, own-app scope, no default route/DNS, no UI-only success')

# Version 1.8.4 editor behavior guardrails
compose_source = (ROOT / 'entry/src/main/ets/pages/Compose.ets').read_text(encoding='utf-8')
media_source = (ROOT / 'entry/src/main/ets/services/MediaApi.ets').read_text(encoding='utf-8')
assert 'onBackPress(): boolean' in compose_source and 'this.requestLeave(); return true;' in compose_source
assert all(x in compose_source for x in ["value: '继续编辑'", "value: '不保存'", "value: '保存草稿'", '发现已保存的草稿', 'this.discardAndLeave()'])
assert "('/forum/video/prePublish'" not in media_source or '视频上传授权（原生协议重试）' in media_source
print('PASS: 1.8.4 draft exit/restore controls and video 220 recovery are present')
