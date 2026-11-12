'use strict';
const fs=require('node:fs/promises');const path=require('node:path');
const {catalog,bindingsFor,generateBuiltins}=require('./catalog');
const {fresh,compileDocument,migrate,serialize}=require('./document');
const {compileFile}=require('../world/compiler');const {discoverWorlds}=require('../world/catalog');
async function read(file,fallback){try{return JSON.parse(await fs.readFile(file,'utf8'));}catch(e){if(e.code==='ENOENT')return fallback;throw e;}}
const validId=id=>typeof id==='string'&&/^[A-Za-z][A-Za-z0-9_-]{0,63}$/.test(id)&&id!=='default';
function guard(id){if(!validId(id))throw new Error('Invalid world ID');return id;}
async function atomic(file,text){await fs.mkdir(path.dirname(file),{recursive:true});const tmp=file+'.pending';await fs.writeFile(tmp,text);await fs.rename(tmp,file);}
class Store {
 constructor(root){this.root=root;this.queue=Promise.resolve();}
 file(id){return path.join(this.root,'worlds/builder',guard(id)+'.json');}
 manifestFile(id){return path.join(this.root,'build/worlds',guard(id)+'.builder.json');}
 async init(){await fs.mkdir(path.join(this.root,'worlds/builder'),{recursive:true});await fs.mkdir(path.join(this.root,'build/worlds'),{recursive:true});await generateBuiltins(this.root);}
 async items(){return catalog(this.root);}
 async discoverAssets(entries){return this.serial(async()=>{
  if(!Array.isArray(entries)||entries.length>2048)throw new Error('Expected up to 2048 Studio model paths');
  const file=path.join(this.root,'worlds/roblox-assets.json'),registry=await read(file,{});
  const seen=new Set();
  for(const entry of entries){
   const asset=require('../world/asset-path').validatePath(entry.path);
   if(seen.has(asset))throw new Error(`Duplicate Studio asset path '${asset}'`);seen.add(asset);
   if(asset.startsWith('Builtin/'))continue;
   if(!Array.isArray(entry.size)||entry.size.length!==3||entry.size.some(n=>typeof n!=='number'||!Number.isFinite(n)||n<=0||n>10000))throw new Error(`Invalid model bounds for '${asset}'`);
   const existing=Object.values(registry).find(b=>(b.path||b.model)===asset);
   if(existing)existing.size=entry.size;
   else {const key='path_'+require('node:crypto').createHash('sha256').update(asset).digest('hex').slice(0,16);registry[key]={source:asset,model:asset,size:entry.size,solid:false,destructible:false,collider:{widthFraction:1,depthFraction:1,heightFraction:1}};}
  }
  require('../world/asset-path').entriesFor(registry);
  await this.transaction([[file,serialize(registry)]]);return {discovered:entries.length};
 });}
 async list(){
  const result=[];for(const name of (await fs.readdir(path.join(this.root,'worlds/builder'))).sort())if(name.endsWith('.json')){const doc=await read(path.join(this.root,'worlds/builder',name));result.push({id:doc.id,name:doc.name,editable:true});}
  for(const entry of await this.legacy())result.push({id:entry.id,name:entry.name,editable:false});return result;
 }
 async legacy(){const result=[];for(const name of (await fs.readdir(path.join(this.root,'worlds'))).sort())if(name.endsWith('.json')&&!name.endsWith('.model.json')){const file=path.join(this.root,'worlds',name),d=await read(file);if(d.version===1&&Array.isArray(d.instances))result.push({id:d.id||path.basename(name,'.json'),name:d.name||name,file});}return result;}
 async get(id){guard(id);const saved=await read(this.file(id));if(saved)return saved;const old=(await this.legacy()).find(w=>w.id===id);if(!old)throw new Error(`Unknown world '${id}'`);let next=`${id.slice(0,50)}_edit`,number=2;while(await read(this.file(next)))next=`${id.slice(0,45)}_edit_${number++}`;return migrate(await compileFile(old.file),await this.items(),next);}
 async transaction(changes){const undo=[];try{for(const [file,value]of changes){let old;try{old=await fs.readFile(file);}catch(e){if(e.code!=='ENOENT')throw e;}undo.push([file,old]);if(value===null)await fs.rm(file,{force:true});else await atomic(file,value);}}catch(e){for(const [file,value]of undo.reverse())if(value===undefined)await fs.rm(file,{force:true});else await atomic(file,value);throw e;}}
 serial(fn){const result=this.queue.then(fn);this.queue=result.catch(()=>{});return result;}
 async save(input,select=false,createOnly=false){return this.serial(async()=>{
  const items=await this.items();const {document,manifest}=compileDocument(input,items);
  if(createOnly&&await read(this.file(document.id)))throw new Error(`World '${document.id}' already exists; choose a new world ID`);
  if((await this.legacy()).some(w=>w.id===document.id))throw new Error('Save a legacy world as a new editable copy with a different ID');
  // Use an isolated manifest view; generated catalog is computed before any writes.
  const manifests=await this.manifests();manifests.set(document.id,manifest);
  const generated=await this.catalogFor(manifests,items);
  const changes=[[this.file(document.id),serialize(document)],[this.manifestFile(document.id),serialize(manifest)],[path.join(this.root,'worlds/studio-worlds.model.json'),serialize(generated)]];
  if(select)changes.push([path.join(this.root,'worlds/selected-world.model.json'),serialize({ClassName:'StringValue',Properties:{Value:document.id}})]);
  await this.transaction(changes);return {document,catalog:generated,selected:select?document.id:undefined};
 });}
 async manifests(){const result=new Map();for(const filename of (await fs.readdir(path.join(this.root,'build/worlds'))).sort())if(filename.endsWith('.json')){const m=await read(path.join(this.root,'build/worlds',filename));if(m?.version===1&&Array.isArray(m.objects))result.set(m.id,m);}return result;}
 async catalogFor(manifests,items){
  // Existing registrar owns the runtime format. Temp files live under build, so
  // no caller paths or executable content reach the runtime.
  const dir=await fs.mkdtemp(path.join(this.root,'build/.builder-catalog-'));
  try{for(const [id,m]of manifests)await fs.writeFile(path.join(dir,encodeURIComponent(id)+'.json'),serialize(m));const c=await discoverWorlds(dir,bindingsFor(items));for(const entry of c.Children){const source=entry.Children.find(n=>n.Name==='ManifestPath');if(source)source.Properties.Value='';}return c;}finally{await fs.rm(dir,{recursive:true,force:true});}
 }
 async publish(id){return this.serial(async()=>{
  const document=await this.get(id),items=await this.items();compileDocument(document,items);
  const used=new Set(document.objects.map(o=>o.type));const missing=items.filter(i=>used.has(i.id)&&!i.packaged);
  if(missing.length)throw new Error('Export native models before publishing: '+missing.map(i=>i.model).join(', '));
  await this.transaction([[path.join(this.root,'worlds/published-world.model.json'),serialize({ClassName:'StringValue',Properties:{Value:id}})]]);return {published:id};
 });}
 async selectDefault(){return this.serial(()=>this.transaction([[path.join(this.root,'worlds/selected-world.model.json'),serialize({ClassName:'StringValue',Properties:{Value:''}})]]));}
 async remove(id,confirmation){guard(id);if(confirmation!==id)throw new Error('Deletion requires confirmation matching the world ID');return this.serial(async()=>{
  if(!await read(this.file(id)))throw new Error('Only builder-created worlds can be deleted');
  const items=await this.items(),manifests=await this.manifests();manifests.delete(id);
  const changes=[[this.file(id),null],[this.manifestFile(id),null],[path.join(this.root,'worlds/studio-worlds.model.json'),serialize(await this.catalogFor(manifests,items))]];
  const selected=await read(path.join(this.root,'worlds/selected-world.model.json'));
  if(selected?.Properties?.Value===id)changes.push([path.join(this.root,'worlds/selected-world.model.json'),serialize({ClassName:'StringValue',Properties:{Value:''}})]);
  const published=await read(path.join(this.root,'worlds/published-world.model.json'));
  if(published?.Properties?.Value===id)changes.push([path.join(this.root,'worlds/published-world.model.json'),serialize({ClassName:'StringValue',Properties:{Value:''}})]);
  await this.transaction(changes);return {deleted:id};
 });}
 async rebuild(){
  const items=await this.items(),changes=[],manifests=new Map();
  for(const entry of await this.legacy()){
   const manifest=await compileFile(entry.file);
   if(manifests.has(manifest.id))throw new Error(`Duplicate world ID '${manifest.id}'`);
   manifests.set(manifest.id,manifest);
   changes.push([path.join(this.root,'build/worlds',path.basename(entry.file)),serialize(manifest)]);
  }
  for(const filename of (await fs.readdir(path.join(this.root,'worlds/builder'))).sort())if(filename.endsWith('.json')){
   const input=await read(path.join(this.root,'worlds/builder',filename));
   if(filename!==input.id+'.json')throw new Error(`Builder filename '${filename}' must match world ID '${input.id}'`);
   const {manifest}=compileDocument(input,items);
   if(manifests.has(manifest.id))throw new Error(`Duplicate world ID '${manifest.id}'`);
   manifests.set(manifest.id,manifest);
   changes.push([this.manifestFile(manifest.id),serialize(manifest)]);
  }
  changes.push([path.join(this.root,'worlds/studio-worlds.model.json'),serialize(await this.catalogFor(manifests,items))]);
  await this.transaction(changes);
 }

}
module.exports={Store,atomic,guard};
