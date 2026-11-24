'use strict';
const test=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs/promises');
const os=require('node:os');
const path=require('node:path');
const {importSfx}=require('../tools/import-sfx');
const json=(body,status=200)=>new Response(JSON.stringify(body),{status,headers:{'content-type':'application/json'}});

test('SFX importer uploads Audio, deduplicates files and retains stable world keys on reimport',async t=>{
 const root=await fs.mkdtemp(path.join(os.tmpdir(),'bw-sfx-'));
 t.after(()=>fs.rm(root,{recursive:true,force:true}));
 const set='SFX/Mechanical';
 await fs.mkdir(path.join(root,set),{recursive:true});
 await fs.writeFile(path.join(root,set,'ferry_horn.wav'),'first');
 await fs.writeFile(path.join(root,set,'horn_copy.wav'),'first');
 const env={ROBLOX_API_KEY:'test-key',ROBLOX_GROUP_ID:'123'};
 let uploads=0;
 const fetcher=async (url,options)=>{
  assert.equal(options.headers['x-api-key'],env.ROBLOX_API_KEY);
  if(options.method==='POST'){
   const request=JSON.parse(options.body.get('request'));
   assert.equal(request.assetType,'Audio');
   assert.equal(request.creationContext.creator.groupId,'123');
   assert.equal(options.body.get('fileContent').type,'audio/wav');
   assert.equal(options.redirect,'manual');
   return json({path:'operations/upload_'+(++uploads)});
  }
  if(url.includes('/operations/'))return json({done:true,response:{assetId:String(40+uploads)}});
  return json({moderationResult:{moderationState:'Approved'}});
 };
 const log=()=>{};
 const [horn,copy]=await importSfx(root,set,{},log,env,fetcher);
 assert.equal(uploads,1);
 assert.equal(horn.name,'Ferry Horn');
 assert.equal(horn.category,'Mechanical');
 assert.equal(copy.assetId,horn.assetId);
 assert.notEqual(horn.key,copy.key);
 await importSfx(root,set,{},log,env,fetcher);
 assert.equal(uploads,1);
 await fs.writeFile(path.join(root,set,'ferry_horn.wav'),'updated');
 const [updated]=await importSfx(root,set+'/ferry_horn.wav',{},log,env,fetcher);
 assert.equal(uploads,2);
 assert.equal(updated.key,horn.key);
 assert.notEqual(updated.assetId,horn.assetId);
 const entries=JSON.parse(JSON.parse(await fs.readFile(path.join(root,'assets/sfx-catalog.model.json'))).Properties.Value);
 assert.equal(entries.length,2);
 assert.equal(entries[0].moderation,'Approved');
});

test('failed uploads do not register a sound and sensitive errors redact the key',async t=>{
 const root=await fs.mkdtemp(path.join(os.tmpdir(),'bw-sfx-bad-'));
 t.after(()=>fs.rm(root,{recursive:true,force:true}));
 await fs.mkdir(path.join(root,'SFX'));
 await fs.writeFile(path.join(root,'SFX/bad.ogg'),'audio');
 const env={ROBLOX_API_KEY:'private-key',ROBLOX_USER_ID:'123'};
 await assert.rejects(importSfx(root,'SFX/bad.ogg',{},()=>{},env,async()=>json({message:'private-key denied'},403)), error=>{
  assert.match(error.message,/403.*redacted/);
  return !error.message.includes(env.ROBLOX_API_KEY);
 });
 await assert.rejects(fs.access(path.join(root,'assets/sfx-catalog.model.json')),{code:'ENOENT'});
});
