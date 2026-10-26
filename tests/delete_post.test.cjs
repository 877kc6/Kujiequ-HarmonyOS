const assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm');
const {stripTypeScriptTypes}=require('node:module');
const path=require('node:path');
const source=fs.readFileSync(path.resolve(__dirname,'../entry/src/main/ets/services/KuroApi.ets'),'utf8');
const method=source.match(/  static async deletePost\([\s\S]*?\n  \}/)[0].replace('static async deletePost','async function deletePost');
const Session={token:'t',userId:'u',generation:1};let calls=[],owner='u',hook;
class ApiError extends Error{constructor(code,msg){super(msg);this.code=code}}
const KuroApi={detail:async id=>{if(hook)hook();return {postDetail:{postUserId:owner}}},post:async(...args)=>{calls.push(args)}};
const run=vm.runInNewContext(stripTypeScriptTypes(method,{mode:'transform'})+'\ndeletePost',{Session,KuroApi,ApiError,Error,String});
(async()=>{
 await run('123');assert.equal(calls.length,1);assert.equal(calls[0][0],'/forum/more/delete');assert.deepEqual(JSON.parse(JSON.stringify(calls[0][1])),[{key:'deleteType',value:'1'},{key:'id',value:'123'}]);
 calls=[];owner='other';await assert.rejects(()=>run('123'));assert.equal(calls.length,0);
 owner='u';hook=()=>{Session.generation++};await assert.rejects(()=>run('123'));assert.equal(calls.length,0);
 hook=null;Session.token='';await assert.rejects(()=>run('123'));assert.equal(calls.length,0);
 console.log('PASS: deletion endpoint/parameters, author ownership, stale account rejection, no unauthorized writes');
})().catch(e=>{console.error(e);process.exitCode=1});
