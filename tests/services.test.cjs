// Node 24+, no downloaded test dependencies. These are logic/contract tests,
// not the DevEco ArkTS compiler or a device UI test.
const { stripTypeScriptTypes } = require('node:module');
const vm = require('node:vm');
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const base = path.join(__dirname, '../entry/src/main/ets');
let response = { responseCode: 200, result: '{"code":200,"data":{},"success":true}' };
let captured, destroyed = 0, pending, assetError = null, requestHook = null;
const assetRows = new Map();
const asset = {
  Tag: { ALIAS: 1, SECRET: 2, RETURN_TYPE: 3, ACCESSIBILITY: 4, CONFLICT_RESOLUTION: 5 },
  Accessibility: { DEVICE_UNLOCKED: 1 }, ReturnType: { ALL: 1 }, ConflictResolution: { OVERWRITE: 1 },
  add: async (m) => { if (assetError) throw assetError; assetRows.set(Buffer.from(m.get(1)).toString(), m); },
  query: async (m) => { const r = assetRows.get(Buffer.from(m.get(1)).toString()); if (!r) throw {code:24000002}; return [r]; },
  remove: async (m) => { if (assetError) throw assetError; if (!assetRows.delete(Buffer.from(m.get(1)).toString())) throw {code:24000002}; }
};
const store = new Map();
const kits = {
  '@kit.BasicServicesKit': {}, '@kit.AbilityKit': {},
  '@kit.NetworkKit': { http: { RequestMethod: {POST: 'POST'}, HttpDataType: {STRING: 0}, createHttp: () => ({
    request: async (url, options) => { captured = { url, options }; if (requestHook) return requestHook(url,options); if (pending) return pending; return response; },
    destroy: () => { destroyed++; }
  }) } },
  '@kit.AssetStoreKit': { asset },
  '@kit.ArkTS': { util: {
    TextEncoder: class { encodeInto(s) { return new TextEncoder().encode(s); } },
    TextDecoder: class { decodeWithStream(b) { return new TextDecoder().decode(b); } },
    generateRandomUUID: () => 'local-uuid'
  } },
  '@kit.ArkData': { preferences: { getPreferences: async () => ({get: async (k,d) => store.has(k) ? store.get(k) : d, put: async (k,v) => store.set(k,v), flush: async () => {} }) } }
};
const appState = new Map();
const AppStorage = {setOrCreate: (k,v) => appState.set(k,v),get: k => appState.get(k)};
const cache = new Map();
function load(name) {
  const f = name.endsWith('.ets') ? name : name + '.ets';
  if (cache.has(f)) return cache.get(f);
  const source = fs.readFileSync(f, 'utf8');
  const names = [...source.matchAll(/export (?:async )?(?:class|function|const) (\w+)/g)].map(m => m[1]);
  let js = stripTypeScriptTypes(source, { mode: 'transform' });
  js = js.replace(/import\s*\{([^}]+)\}\s*from\s*['"]([^'"]+)['"];?/g, (_, names, mod) => `const {${names}} = require(${JSON.stringify(mod)});`)
    .replace(/\bexport\s+(?=class|function|async|const)/g, '') + `\nmodule.exports={${names.join(',')}};`;
  const module = {exports:{}};
  const req = n => kits[n] || load(path.resolve(path.dirname(f), n));
  vm.runInNewContext(js, {module, require:req, AppStorage, Date, Map, Array, String, Error, JSON, Uint8Array, encodeURIComponent, RegExp}, {filename:f});
  cache.set(f,module.exports); return module.exports;
}
(async () => {
  const P = load(path.join(base,'services/Protocol'));
  assert.equal(P.formEncode([{key:'x',value:'中 文&=+'}]), 'x=%E4%B8%AD%20%E6%96%87%26%3D%2B');
  assert.equal(P.chinaMonth(Date.parse('2026-10-31T16:05:00Z')), '11');
  assert.equal(P.chinaMonth(Date.parse('2026-12-31T17:00:00Z')), '01');
  assert.throws(() => P.checked({code:200,success:false,data:{}}));
  assert.throws(() => P.checked({code:220,data:{}}), e => e.code === 220);
  for (const u of ['http://www.kurobbs.com','https://www.kurobbs.com.evil.test/','https://www.kurobbs.com@evil.test/','file:///a','javascript:alert(1)']) assert.equal(P.isOfficialUrl(u),false);
  assert.equal(P.isOfficialUrl('https://www.kurobbs.com/mc/home'),true);
  assert.throws(() => P.officialPostUrl(3,'12?token=secret'));
  const { Session } = load(path.join(base,'services/Session'));
  const { LocalStore } = load(path.join(base,'services/LocalStore'));
  const { KuroApi } = load(path.join(base,'services/KuroApi'));
  await LocalStore.init({});
  await Session.restore(); assert.equal(Session.token,'');
  await Session.save({token:'private-test-token',userId:'123',userName:'Kevin',headUrl:''});
  Session.token=''; await Session.restore(); assert.equal(Session.token,'private-test-token');
  assert(!JSON.stringify([...store]).includes('private-test-token'));
  response={responseCode:200,result:JSON.stringify({code:200,data:{postList:[],hasNext:0},success:true})};
  await KuroApi.feed(3,9,1,1);
  assert.equal(captured.url,'https://api.kurobbs.com/forum/list');
  assert.equal(captured.options.header.token,'private-test-token');
  assert(captured.options.extraData.includes('forumId=9'));
  assert.equal(destroyed,1);
  response={responseCode:503,result:'unavailable'};
  await assert.rejects(KuroApi.feed(3,9,1,1)); assert.equal(destroyed,2);
  response={responseCode:200,result:'not json'};
  await assert.rejects(KuroApi.feed(3,9,1,1)); assert.equal(destroyed,3);
  response={responseCode:200,result:JSON.stringify({code:200,data:{geeTest:true}})};
  await assert.rejects(KuroApi.sms('13800000000'),e => e.code === 412);
  response={responseCode:200,result:JSON.stringify({code:200,data:{}})};
  await assert.rejects(KuroApi.sms('13800000000'));
  response={responseCode:200,result:JSON.stringify({code:200,data:{geeTest:false}})};
  await KuroApi.sms('13800000000');
  await assert.rejects(KuroApi.sms('123'));
  let resolve;
  pending=new Promise(r => {resolve=r});
  const authRequest=KuroApi.roles(3);
  Session.generation++;
  resolve({responseCode:200,result:'{"code":200,"data":[]}'});
  await assert.rejects(authRequest,e => e.code === -3); pending=null;
  const post={postId:'1561771205557829632',postTitle:'Test',gameId:3,userName:'Test',savedAt:1};
  assert.equal(await LocalStore.toggle(post),true); assert.equal((await LocalStore.saved()).length,1);
  assert.equal(await LocalStore.toggle(post),false); assert.equal((await LocalStore.saved()).length,0);
  assetError={code:24000001}; await assert.rejects(Session.logout()); assert.equal(Session.token,'private-test-token');
  assetError=null; await Session.logout(); assert.equal(Session.token,'');
  await assert.rejects(KuroApi.roles(3), e => e.code === 220);
  const proof=P.normalizeCaptchaProof(JSON.stringify({lot_number:'lot',captcha_output:'a+b&c',pass_token:'pass',gen_time:'1792850000',unexpected:'discard'}));
  assert(!proof.includes('unexpected'));
  assert.throws(() => P.normalizeCaptchaProof('{bad'));
  assert.throws(() => P.normalizeCaptchaProof('{"lot_number":"x"}'));
  response={responseCode:200,result:JSON.stringify({code:200,data:{geeTest:false}})};
  await KuroApi.sms('13800000000',proof);
  const form=new URLSearchParams(captured.options.extraData);
  assert.equal(form.get('geeTestData'),proof);
  assert.equal(form.get('mobile'),'13800000000');
  const { parseWebAccount, READ_WEB_ACCOUNT, MAP_MOBILE_STYLE, connectOfficialSession } = load(path.join(base,'services/WebSession'));
  let reads=0;
  const webStore={getItem:k => {reads++; return k==='auth_token'?'safe-token':JSON.stringify({userId:'123'});}};
  assert.equal(vm.runInNewContext(READ_WEB_ACCOUNT,{location:{href:'https://www.kurobbs.com.evil.test/'},localStorage:webStore}), '');
  assert.equal(reads,0);
  const mapStorage=new Map();
  const mapScript=connectOfficialSession('test-token','123','test-user',true);
  const mapContext={location:{href:'https://web-static.kurobbs.com/resource/map/main'},localStorage:{getItem:k=>mapStorage.get(k)||null,setItem:(k,v)=>mapStorage.set(k,v)}};
  assert.equal(vm.runInNewContext(mapScript,mapContext),true);
  assert.equal(JSON.parse(mapStorage.get('AKI_MAP_USER_PROFILE')).profile.token,'test-token');
  assert.equal(vm.runInNewContext(mapScript,mapContext),false);
  const rejectedStore=new Map();
  assert.equal(vm.runInNewContext(mapScript,{location:{href:'https://evil.test/'},localStorage:{getItem:k=>null,setItem:(k,v)=>rejectedStore.set(k,v)}}),false);
  assert.equal(rejectedStore.size,0);

  assert.equal(JSON.parse(vm.runInNewContext(READ_WEB_ACCOUNT,{location:{href:'https://www.kurobbs.com/mc/home'},localStorage:webStore})).token,'safe-token');
  assert.equal(vm.runInNewContext(MAP_MOBILE_STYLE,{location:{href:'https://www.kurobbs.com/mc/home'}}),undefined);
  assert.equal(parseWebAccount('not-json'), undefined);
  assert.equal(parseWebAccount(JSON.stringify({token:'a\\r\\n',userId:'bad'})), undefined);
  assert.equal(parseWebAccount(JSON.stringify(JSON.stringify({token:'web-session-token',userId:'123'}))).userId, '123');
  await LocalStore.material(false); assert.equal(appState.get('immersiveEnabled'), false);
  const mine={userId:'123',userName:'Kevin',headUrl:'https://example.test/avatar.png'};
  response={responseCode:200,result:JSON.stringify({code:200,data:{mine}})};
  await KuroApi.importWebAccount('verified-web-token','123');
  assert.equal(Session.token,'verified-web-token');
  assert.equal(captured.options.header.token,'verified-web-token');
  assert.equal((await LocalStore.profile('123')).headUrl,mine.headUrl);
  assert(!JSON.stringify([...store]).includes('verified-web-token'));
  response={responseCode:200,result:JSON.stringify({code:220,data:{}})};
  await assert.rejects(KuroApi.importWebAccount('invalid-web-token','123'));
  assert.equal(Session.token,'verified-web-token');
  response={responseCode:200,result:JSON.stringify({code:200,data:{mine:{...mine,userId:'456'}}})};
  await assert.rejects(KuroApi.importWebAccount('wrong-account-token','123'));
  assert.equal(Session.token,'verified-web-token');
  response={responseCode:200,result:'{"code":200,"data":{"postCommentList":[],"hasNext":0}}'};
  await KuroApi.comments('123',2);
  assert.equal(new URLSearchParams(captured.options.extraData).get('pageIndex'),'2');
  response={responseCode:200,result:'{"code":200,"data":{"postCommentId":"456"}}'};
  const detailPost={id:'123',gameForumId:9,gameId:3,postUserId:'789'};
  await KuroApi.comment(detailPost,' 评论 & 测试 ');
  assert(captured.url.endsWith('/forum/comment/createComment'));
  let body=new URLSearchParams(captured.options.extraData);
  assert.deepEqual(JSON.parse(body.get('content')), [{contentType:1,content:'评论 & 测试',children:[{type:1,content:'评论 & 测试',target:''}]}]);
  await KuroApi.comment(detailPost,'楼中楼','456','789','987');
  assert(captured.url.endsWith('/forum/comment/createReply'));
  body=new URLSearchParams(captured.options.extraData);
  assert.equal(body.get('postCommentId'),'456'); assert.equal(body.get('postCommentReplyId'),'987');
  assert.throws(() => KuroApi.comment(detailPost,'   '));
  assert.throws(() => KuroApi.comment(detailPost,'x'.repeat(1001)));
  // History is bounded, deduplicated and ordered by the most recent view.
  await LocalStore.recordView(post);
  await LocalStore.recordView({...post,postTitle:'Updated',savedAt:2});
  assert.equal((await LocalStore.history()).length,1);
  assert.equal((await LocalStore.history())[0].postTitle,'Updated');
  for (let i=0;i<205;i++) await LocalStore.recordView({...post,postId:String(i),savedAt:i});
  const history = await LocalStore.history();
  assert.equal(history.length,200); assert.equal(history[0].postId,'204');
  assert.equal(history.at(-1).postId,'5');
  await LocalStore.clearHistory(); assert.deepEqual(await LocalStore.history(),[]);
  const banners=[{id:2520,url:'https://example.test/banner.jpg',msg:'档案回顾',postId:'1560299094190395392'}];
  response={responseCode:200,result:JSON.stringify({code:200,data:banners})};
  assert.deepEqual(await KuroApi.banners(3),banners);
  assert(captured.url.endsWith('/forum/getBannerList'));
  body=new URLSearchParams(captured.options.extraData);
  assert.equal(body.get('gameId'),'3'); assert.equal(body.get('forumId'),'0');
  const A=load(path.join(base,'services/AccountData'));
  const endpointCases=[
    ['following','/forum/dynamic/list','dynamic'],['posts','/forum/getMinePost','postList'],
    ['comments','/user/notice/comment/page','noticeVos'],['likes','/user/notice/like/page','noticeVos'],
    ['mentions','/user/notice/chat/page','noticeVos'],['fans','/user/fans','fansInfo'],
    ['historyComments','/user/center/myComment','noticeVos'],['collects','/user/center/myCollect','postList'],
    ['system','/user/notice/help/page','noticeVos'],['follows','/user/follow','followInfo']
  ];
  for(const [kind,endpoint,key] of endpointCases) {
    response={responseCode:200,result:JSON.stringify({code:200,data:{[key]:[],hasNext:0}})};
    const accountResult=await KuroApi.accountList(kind,2);
    assert.equal(accountResult.rows.length,0); assert.equal(accountResult.hasNext,false);
    assert.equal(captured.url,'https://api.kurobbs.com'+endpoint);
    const params=new URLSearchParams(captured.options.extraData);
    assert.equal(params.get((kind==='fans'||kind==='follows')?'pageNo':'pageIndex'),'2');
    assert.equal(params.get('pageSize'),'20');
    assert.equal(captured.options.header.token,Session.token);
    assert.equal(captured.options.header.source,'android');
    if(kind==='posts'||kind==='fans'||kind==='follows') { assert.equal(params.get('type'),'1'); assert.equal(params.get('otherUserId'),Session.userId); }
    if(kind==='collects'||kind==='historyComments') assert.equal(params.get('viewUserId'),Session.userId);
  }
  assert.throws(()=>A.accountPath('untrusted'));
  assert.throws(()=>A.accountRows('posts',{noticeVos:[]}));
  const notice={id:'n1',postId:'123',sendUserName:'User',noticeTitle:'Reply',noticeContent:'Hello',readState:1};
  assert.equal(A.accountRows('comments',{noticeVos:[notice],hasNext:0}).rows[0].unread,true);
  assert.equal(A.accountRows('comments',{noticeVos:[{...notice,noticeStatus:1}]}).rows[0].postId,'');
  assert.equal(A.accountRows('fans',{fansInfo:[{userId:'123',userName:'Fan',signature:'Hi'}]}).rows[0].title,'Fan');
  assert.equal(A.accountRows('posts',{postList:[{postId:'123',postTitle:'Mine',coverImages:[{url:'https://test.test/a.jpg'}]}]}).rows[0].cover,'https://test.test/a.jpg');
  response={responseCode:200,result:JSON.stringify({code:220,msg:'expired',data:{}})};
  await assert.rejects(KuroApi.accountList('comments',1), e=>e.code===220);
  const readSources=[];
  requestHook=(url,options)=> {
    readSources.push(options.header.source);
    return {responseCode:200,result:JSON.stringify(options.header.source==='android' ? {code:220,msg:'source rejected'} : {code:200,data:{noticeVos:[],hasNext:0}})};
  };
  assert.equal((await KuroApi.accountList('comments',1)).rows.length,0);
  assert.deepEqual(readSources,['android','h5']);
  requestHook=(url,options)=>({responseCode:200,result:JSON.stringify(url.endsWith('/user/mineV2') ? {code:200,data:{mine:{userId:Session.userId}}} : {code:220,msg:'not authorized'})});
  const preservedToken=Session.token;
  await assert.rejects(KuroApi.accountList('likes',1),e=>e.code===221);
  assert.equal(Session.token,preservedToken);
  requestHook=()=>({responseCode:200,result:JSON.stringify({code:503,msg:'service busy'})});
  await assert.rejects(KuroApi.accountList('mentions',1),e=>e.code===503);
  requestHook=null;
  assert.throws(()=>P.checked({code:220,msg:'服务端原始授权提示'}),e=>e.message==='服务端原始授权提示');
  for(const kind of ['mentions','comments','likes','system','posts','following','collects','fans','follows']) {
    for(const empty of [null,{},[],{hasNext:0}]) {
      const result=A.accountRows(kind,empty);
      assert.equal(result.rows.length,0); assert.equal(result.hasNext,false);
    }
  }
  assert.equal(A.accountRows('mentions',[notice]).rows[0].key,'n1');
  assert.equal(A.accountRows('mentions',{noticeVos:null,hasNext:0}).rows.length,0);
  assert.equal(A.accountRows('follows',{followInfo:[{followUserId:'88',followUserName:'Following',followUserUrl:'https://test.test/a'}]}).rows[0].title,'Following');
  assert.equal(A.accountRows('mentions',{noticeVos:Array(20).fill(notice),hasNext:true}).hasNext,true);
  assert.throws(()=>A.accountRows('mentions',{unexpected:[notice]}),e=>e.message.includes('unexpected'));
  assert.throws(()=>A.accountRows('mentions',{noticeVos:{nested:[]}}));
  assert.throws(()=>A.accountRows('mentions',[{unknown:'bad'}]));
  const B=load(path.join(base,'services/GameBoards'));
  assert.deepEqual(Array.from(B.gameBoards(2),x=>x.label),['推荐','伊甸闲庭','攻略','同人图','同人文']);
  assert(!B.gameBoards(2).some(x=>x.label.includes('今州')));
  assert.equal(B.publishBoard(2,10),false); assert.equal(B.publishBoard(2,3),true);
  assert.throws(()=>KuroApi.publish(2,10,'Title','Body'));
  assert.equal(B.escapedHtml('<a>&'),'<p>&lt;a&gt;&amp;</p>');
  await LocalStore.saveCompose('123_2',{title:'Draft',body:'Text',boardId:3});
  assert.equal((await LocalStore.composeDraft('123_2')).title,'Draft');
  response={responseCode:200,result:JSON.stringify({code:200,data:{postId:'123'}})};
  await KuroApi.publish(2,3,' Title ','Body & text');
  assert(captured.url.endsWith('/forum/postPublish'));
  const publishParams=new URLSearchParams(captured.options.extraData);
  assert.equal(publishParams.get('gameForumId'),'3'); assert.equal(publishParams.get('gameId'),'2');
  assert.equal(publishParams.get('postTitle'),'Title');
  assert.equal(JSON.parse(publishParams.get('content'))[0].children[0].content,'Body & text');
  console.log('PASS: independent game board names/IDs, native text publishing contract and local drafts');
  console.log('PASS: empty/root-array/object list shapes, unknown schema diagnostics and following users');
  console.log('PASS: source compatibility fallback, profile validation and preservation of valid sessions');
  console.log('PASS: nine native account endpoint contracts, parameters, normalization and API failure handling');
  console.log('PASS: protocol encoding, China timezone, URL restrictions, encrypted session lifecycle, favorites, API errors, captcha gating, stale account responses, resource cleanup, verified web import, trusted-origin script, profile cache, material broadcast, comment/reply forms, history ordering/cap, official banner request');
})().catch(e => {console.error(e); process.exitCode=1;});
