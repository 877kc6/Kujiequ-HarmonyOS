const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const vm = require('node:vm');
const { stripTypeScriptTypes } = require('node:module');
const root = path.resolve(__dirname, '../entry/src/main/ets');
const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'kujiequ-probe-'));
let create, native, destroy, events, lastConfig;
const kits = {
  '@kit.AbilityKit': {}, '@kit.BasicServicesKit': {},
  '@kit.CoreFileKit': { fileIo: {
    OpenMode: {CREATE: 64, WRITE_ONLY: 1, TRUNC: 512},
    openSync: (p) => ({fd: fs.openSync(p, 'w')}),
    writeSync: (fd, text) => fs.writeSync(fd, text),
    closeSync: f => fs.closeSync(f.fd), renameSync: fs.renameSync,
    readTextSync: p => fs.readFileSync(p, 'utf8')
  }},
  '@kit.NetworkKit': {
    VpnExtensionAbility: class { context = { filesDir: dir, applicationInfo: { name: 'com.kevin.custompackage' } }; },
    vpnExtension: {
      createVpnConnection: () => ({create: c => { lastConfig = c; events.push('create'); return create(); }, destroy: () => { events.push('destroy'); return destroy(); }}),
      stopVpnExtensionAbility: async () => { events.push('stop'); }
    }
  },
  'libcapture_probe.so': { run: (...args) => { events.push('native'); return native(...args); }, cancel: () => events.push('cancel') }
};
const cache = new Map();
function load(file) {
  if (!file.endsWith('.ets')) file += '.ets';
  if (cache.has(file)) return cache.get(file);
  const source = fs.readFileSync(file,'utf8');
  const names = [...source.matchAll(/export (?:default )?(?:class|function) (\w+)/g)].map(m => m[1]);
  let js = stripTypeScriptTypes(source, {mode:'transform'})
    .replace(/import\s*\{([^}]+)\}\s*from\s*['"]([^'"]+)['"];?/g, (_, names, name) => `const {${names}} = require(${JSON.stringify(name)});`)
    .replace(/\bexport (?:default )?/g,'');
  const module = {exports:{}};
  vm.runInNewContext(js + `\nmodule.exports={${names.join(',')}};`, {module, require: n => kits[n] || load(path.resolve(path.dirname(file),n)), Date, Number, Error, JSON, setInterval, clearInterval});
  cache.set(file,module.exports); return module.exports;
}
const model = load(path.join(root,'services/CaptureProbeModel'));
const { CaptureProbeStore } = load(path.join(root,'services/CaptureProbeStore'));
const { CaptureProbeAbility } = load(path.join(root,'vpnability/CaptureProbeAbility'));
const store = new CaptureProbeStore(dir);
const id = '12345678-1234-1234-1234-123456789abc';
const want = {parameters:{probeRunId:id}};
async function waitFor(predicate) {
  for(let n=0;n<200;n++) { if(predicate()) return; await new Promise(r=>setTimeout(r,5)); }
  throw new Error('Timed out');
}
function reset() {
  events = []; lastConfig = undefined;
  create = async () => 7; native = async () => ({code:0,packets:1,bytes:77}); destroy = async () => {};
  for(const file of fs.readdirSync(dir)) fs.unlinkSync(path.join(dir,file));
  store.writeRequest({runId:id,expiresAt:Date.now()+60000,cancelled:false});
}
(async () => {
  try {
    const now = Date.now();
    assert(model.validProbeRequest({runId:id,expiresAt:now+1000,cancelled:false},id,now));
    assert(!model.validProbeRequest({runId:id,expiresAt:now-1,cancelled:false},id,now));
    assert(!model.validProbeRequest({runId:id,expiresAt:now+999999,cancelled:false},id,now));
    assert(!model.validProbeStatus({runId:id,phase:'passed',code:0,packets:NaN,bytes:0,cleaned:true,updatedAt:now},id));
    reset(); let ability = new CaptureProbeAbility(); ability.onCreate(want);
    await waitFor(()=>events.includes('stop'));
    assert.equal(store.status().phase,'passed'); assert.equal(store.status().cleaned,true);
    assert.deepEqual(JSON.parse(JSON.stringify(lastConfig.trustedApplications)),['com.kevin.custompackage']);
    assert.equal(lastConfig.routes[0].destination.prefixLength,32);
    assert.equal(lastConfig.routes[0].isDefaultRoute,false);
    assert.equal(lastConfig.dnsAddresses,undefined);
    assert(events.indexOf('native') < events.indexOf('destroy'));
    reset(); store.cancel(id); ability = new CaptureProbeAbility(); ability.onCreate(want);
    await waitFor(()=>events.includes('stop')); assert(!events.includes('create'));
    assert.equal(store.status().phase,'cancelled');
    reset(); store.writeRequest({runId:id,expiresAt:Date.now()-1,cancelled:false});
    ability = new CaptureProbeAbility(); ability.onCreate(want);
    await waitFor(()=>events.includes('stop')); assert(!events.includes('create'));
    reset(); let release; create = () => new Promise(r=>release=r);
    ability = new CaptureProbeAbility(); ability.onCreate(want);
    await waitFor(()=>events.includes('create')); ability.onDestroy();
    assert(!events.includes('destroy'), 'must not destroy before pending create completes');
    release(7); await waitFor(()=>events.includes('stop'));
    assert(!events.includes('native')); assert(events.includes('destroy'));
    assert.equal(store.status().phase,'cancelled');
    reset(); destroy = async () => { throw new Error('cleanup failed'); };
    ability = new CaptureProbeAbility(); ability.onCreate(want); await waitFor(()=>events.includes('stop'));
    assert.equal(store.status().phase,'cleanup_failed'); assert.equal(store.status().cleaned,false);
    reset(); create = async () => { throw {code:2203002}; };
    ability = new CaptureProbeAbility(); ability.onCreate(want); await waitFor(()=>events.includes('stop'));
    assert.equal(store.status().phase,'failed'); assert.equal(store.status().code,2203002);
    assert(!events.includes('native')); assert(events.includes('destroy'));
    reset(); native = async () => ({code:1,packets:0,bytes:0});
    ability = new CaptureProbeAbility(); ability.onCreate(want); await waitFor(()=>events.includes('stop'));
    assert.equal(store.status().phase,'no_packet');
    reset(); let finish; native = () => new Promise(r=>finish=r);
    ability = new CaptureProbeAbility(); ability.onCreate(want); await waitFor(()=>events.includes('native'));
    store.cancel(id); await waitFor(()=>events.includes('cancel'));
    finish({code:2,packets:0,bytes:0}); await waitFor(()=>events.includes('stop'));
    assert.equal(store.status().phase,'cancelled');
    console.log('PASS: isolated VPN config, request freshness, real private-file IPC simulation, cancel/create race, errors, cleanup receipts');
    console.log('Mock service test only; not ArkTSCheck, N-API linking or device VPN verification');
  } finally { fs.rmSync(dir,{recursive:true,force:true}); }
})().catch(e=>{console.error(e);process.exitCode=1;});
