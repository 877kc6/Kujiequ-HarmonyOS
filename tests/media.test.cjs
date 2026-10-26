const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const crypto = require('node:crypto');
const {stripTypeScriptTypes} = require('node:module');
const root = path.resolve(__dirname,'../entry/src/main/ets');
let bytes = new Uint8Array([1,2,3,4]);
let requests = [], closed = 0, released = 0, protectedAccount = 'u1';
let response = {responseCode:200,result:JSON.stringify({code:200,data:['https://prod-alicdn-community.kurobbs.com/forum/x.jpg']})};
const session = {userId:'u1',token:'test-token',generation:1};
const kits = {
 '@kit.ArkTS':{util:{TextEncoder:class{encodeInto(s){return new TextEncoder().encode(s)}},TextDecoder:class{decodeWithStream(b){return new TextDecoder().decode(b)}},Base64Helper:class{decodeSync(s){return new Uint8Array(Buffer.from(s,'base64'))}encodeToStringSync(b){return Buffer.from(b).toString('base64')}},generateRandomUUID:()=> 'local-uuid'}},
 '@kit.CryptoArchitectureKit':{cryptoFramework:{createSymKeyGenerator:alg=>({convertKey:async d=>{ if(alg==='HMAC|SHA1' && d.data.length!==20) throw {code:401}; assert.equal(alg,'HMAC','variable-length cloud credentials require HMAC'); return d; }}),createMac:()=>{let secret,parts=[];return{init:async k=>{secret=k.data},update:async d=>parts.push(d.data),doFinal:async()=>({data:new Uint8Array(crypto.createHmac('sha1',secret).update(Buffer.concat(parts)).digest())})}}}},
 '@kit.CoreFileKit':{fileIo:{OpenMode:{READ_ONLY:0},open:async()=>({fd:3}),stat:async()=>({size:bytes.length}),read:async(_fd,b)=>{new Uint8Array(b).set(bytes);return bytes.length},close:async()=>{closed++}}},
 '@kit.ImageKit':{image:{createImageSource:()=>({getImageInfo:async()=>({size:{width:100,height:200},mimeType:'image/jpeg'}),release:async()=>{released++}})}},
 '@kit.MediaKit':{media:{createAVMetadataExtractor:async()=>({fetchMetadata:async()=>({duration:'10000',videoWidth:'1920',videoHeight:'1080'}),release:async()=>{released++}})}},
 '@kit.NetworkKit':{http:{RequestMethod:{POST:'POST',GET:'GET',PUT:'PUT'},HttpDataType:{STRING:0},createHttp:()=>({on:()=>{},request:async(url,options)=>{requests.push({url,options});return response},destroy:()=>{}})}}
};
const cache=new Map();
function load(file){
 file=path.resolve(file.endsWith('.ets')?file:file+'.ets');if(cache.has(file))return cache.get(file);
 if(file.endsWith('/Session.ets'))return {Session:session};
 if(file.endsWith('/LocalStore.ets'))return {LocalStore:{deviceId:'device'}};
 if(file.endsWith('/KuroApi.ets'))return {KuroApi:{headers:()=>({'token':session.token,'version':'2.2.0','versionCode':'2200','source':'h5'}),post:async p=>p.endsWith('/prePublish')?{videoId:'12345678video',uploadAuth:Buffer.from(JSON.stringify({AccessKeyId:'AK',AccessKeySecret:'SECRET',SecurityToken:'TEMP'})).toString('base64'),uploadAddress:Buffer.from(JSON.stringify({Endpoint:'oss-cn-shanghai.aliyuncs.com',Bucket:'bucket',FileName:'test/video.mp4'})).toString('base64')}:{playAuth:Buffer.from(JSON.stringify({AccessKeyId:'AK',AccessKeySecret:'SECRET',SecurityToken:'TEMP',AuthInfo:'AUTH',Region:'cn-shanghai'})).toString('base64')}}};
 let source=fs.readFileSync(file,'utf8');let names=[...source.matchAll(/export (?:class|function) (\w+)/g)].map(x=>x[1]);
 let js=stripTypeScriptTypes(source,{mode:'transform'}).replace(/import\s*\{([^}]+)\}\s*from\s*['"]([^'"]+)['"];?/g,(_,n,p)=>`const {${n}} = require(${JSON.stringify(p)});`).replace(/\bexport /g,'');
 const module={exports:{}};vm.runInNewContext(js+`\nmodule.exports={${names.join(',')}}`,{module,require:n=>kits[n]||load(path.resolve(path.dirname(file),n)),console,JSON,Date,Number,Error,Uint8Array,ArrayBuffer,encodeURIComponent});cache.set(file,module.exports);return module.exports;
}
(async()=>{
 const protocol=load(root+'/services/MediaProtocol');
 assert.equal(protocol.canonicalQuery([{key:'Z',value:'!*()'},{key:'A',value:'a b'}]),'A=a%20b&Z=%21%2A%28%29');
 assert.throws(()=>protocol.ossUploadUrl({Endpoint:'evil.test',Bucket:'bucket',FileName:'a'}));
 assert.throws(()=>protocol.ossUploadUrl({Endpoint:'oss-cn-shanghai.aliyuncs.com',Bucket:'bucket',FileName:'../secret'}));
 assert.equal(protocol.ossUploadUrl({Endpoint:'http://oss-cn-shanghai.aliyuncs.com',Bucket:'bucket',FileName:'a b.mp4'}),'https://bucket.oss-cn-shanghai.aliyuncs.com/a%20b.mp4');
 let blocks=JSON.parse(protocol.mediaContent('<text>',[{kind:'image',url:'https://cdn/x',width:12,height:34,videoId:'',name:'x'}]));
 assert.equal(blocks[1].contentType,2);assert.equal(blocks[1].imgWidth,12);
 assert(protocol.mediaHtml('<script>',[]).includes('&lt;script&gt;'));
 const {MediaApi}=load(root+'/services/MediaApi');
 let progress=0;let item=await MediaApi.uploadImage('photo://selected',v=>progress=v);
 assert.equal(item.url,'https://prod-alicdn-community.kurobbs.com/forum/x.jpg');assert.equal(progress,100);assert.equal(closed,1);assert.equal(released,1);
 let req=requests.at(-1);assert.equal(req.options.header.token,'test-token');assert.equal(req.options.header.version,'2.2.0');assert.equal(req.options.header.versionCode,'2200');assert(req.url.endsWith('/forum/uploadForumImgForH5'));
 let multipart=Buffer.from(req.options.extraData);assert(multipart.includes(Buffer.from([1,2,3,4])));assert(multipart.includes(Buffer.from('name="files"')));
 bytes=new Uint8Array([0,0,0,16,102,116,121,112,105,115,111,109,0,0,0,0]);
 response={responseCode:200,result:''};
 const video=await MediaApi.uploadVideo('photo://video',3,v=>progress=v);
 assert.equal(video.videoId,'12345678video');assert.equal(progress,100);
 req=requests.at(-1);assert.equal(req.options.method,'PUT');assert.equal(req.options.header.token,undefined);
 assert.equal(req.url,'https://bucket.oss-cn-shanghai.aliyuncs.com/test/video.mp4');
 const expected=crypto.createHmac('sha1','SECRET').update('PUT\n\nvideo/mp4\n'+req.options.header.Date+'\nx-oss-security-token:TEMP\n/bucket/test/video.mp4').digest('base64');
 assert.equal(req.options.header.Authorization,'OSS AK:'+expected);
 response={responseCode:200,result:JSON.stringify({PlayInfoList:{PlayInfo:[{PlayURL:'https://media.test/enc.mp4',Encrypt:1},{PlayURL:'https://media.test/a.mp4',Encrypt:0}]}})};
 assert.equal(await MediaApi.playback('12345678video'),'https://media.test/a.mp4');
 req=requests.at(-1);assert(!req.options.header,'account token must not be sent to VOD');
 const parsed=new URL(req.url);const signature=parsed.searchParams.get('Signature');parsed.searchParams.delete('Signature');
 const canonical=protocol.canonicalQuery([...parsed.searchParams].map(([key,value])=>({key,value})));
 assert.equal(signature,crypto.createHmac('sha1','SECRET&').update('GET&%2F&'+protocol.rpcEncode(canonical)).digest('base64'));
 response={responseCode:200,result:JSON.stringify({PlayInfoList:{PlayInfo:[{PlayURL:'https://media.test/enc.mp4',Encrypt:1}]}})};
 await assert.rejects(()=>MediaApi.playback('12345678video'));
 session.token='';await assert.rejects(()=>MediaApi.uploadImage('photo://selected',()=>{}));
 session.token='test-token';bytes=new Uint8Array([1,2,3,4]);response={responseCode:200,result:JSON.stringify({code:102,msg:'server internal detail not exposed'})};
 await assert.rejects(()=>MediaApi.uploadImage('photo://selected',()=>{}),e=>e.message.includes('图片上传响应失败（102）')&&!e.message.includes('server internal'));

 response={responseCode:403,result:JSON.stringify({Code:'SignatureDoesNotMatch',Message:'do not expose server details'})};
 await assert.rejects(()=>MediaApi.playback('12345678video'),e=>e.message.includes('HTTP 403 / SignatureDoesNotMatch') && !e.message.includes('server details'));
 console.log('PASS: canonical signing, OSS host/path restrictions, serialized images/HTML escaping, native multipart bytes, cleanup, temporary playback credentials, encrypted-video rejection');
})().catch(e=>{console.error(e);process.exitCode=1});
