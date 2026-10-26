const fs=require('node:fs'), os=require('node:os'), path=require('node:path'), assert=require('node:assert/strict'), vm=require('node:vm');
const {stripTypeScriptTypes}=require('node:module');
const dir=fs.mkdtempSync(path.join(os.tmpdir(),'kujiequ-cache-'));let id=0,opened=0,closed=0;
const io={OpenMode:{READ_ONLY:0},open:async uri=>{opened++;return {fd:fs.openSync(uri.replace(/^file:\/\//,''),'r')}},
 stat:async fd=>fs.fstatSync(fd),copyFile:async(fd,p)=>fs.writeFileSync(p,fs.readFileSync(fd)),close:async f=>{closed++;fs.closeSync(f.fd)},unlink:async p=>fs.unlinkSync(p)};
const kits={'@kit.CoreFileKit':{fileIo:io,fileUri:{getUriFromPath:p=>'file://'+p}},'@kit.MediaKit':{media:{createAVImageGenerator:async()=>{throw Error('unsupported thumbnail')}}},'@kit.ImageKit':{image:{}},'@kit.ArkTS':{util:{generateRandomUUID:()=>String(++id)}}};
let js=stripTypeScriptTypes(fs.readFileSync(path.resolve(__dirname,'../entry/src/main/ets/services/MediaCache.ets'),'utf8'),{mode:'transform'}).replace(/import\s*\{([^}]+)\}\s*from\s*['"]([^'"]+)['"];?/g,(_,n,p)=>`const {${n}}=kits[${JSON.stringify(p)}] || {};`).replace('export class','class');
const {MediaCache}=vm.runInNewContext(js+'\n({MediaCache})',{kits,Error,console});
(async()=>{
 try{
  const source=path.join(dir,'selected.jpg');fs.writeFileSync(source,'selected bytes');
  const item=await MediaCache.stage(dir,source,false);
  assert.equal(item.uploadState,'pending');assert(item.localUri.startsWith('file://'+dir+'/compose_media_'));assert.equal(item.previewUri,item.localUri);
  assert.equal(fs.readFileSync(item.localPath,'utf8'),'selected bytes');assert.equal(opened,closed);
  fs.unlinkSync(source);assert(fs.existsSync(item.localPath),'preview must survive loss of original picker URI');
  await MediaCache.remove(dir,{localPath:path.join(dir,'unrelated')});
  assert(!MediaCache.owns(dir,dir+'/compose_media_../secret'));
  const video=await MediaCache.stage(dir,item.localUri,true);assert.equal(video.kind,'video');assert.equal(video.previewUri,'');assert(fs.existsSync(video.localPath));
  await MediaCache.remove(dir,item);assert(!fs.existsSync(item.localPath));await MediaCache.remove(dir,video);assert.equal(opened,closed);
  console.log('PASS: local preview before upload, independent copy, draft URI durability, thumbnail fallback, owned-file cleanup, traversal rejection, descriptors closed');
 }finally{fs.rmSync(dir,{recursive:true,force:true})}
})().catch(e=>{console.error(e);process.exitCode=1});
