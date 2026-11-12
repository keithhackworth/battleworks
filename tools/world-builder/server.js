'use strict';
const http=require('node:http');const crypto=require('node:crypto');
const {Store}=require('./store');const {fresh,Materials}=require('./document');
function createServer(store,{token=crypto.randomBytes(32).toString('hex')}={}){
 const server=http.createServer(async(req,res)=>{
  const reply=(code,value)=>{res.writeHead(code,{'Content-Type':'application/json','Cache-Control':'no-store','X-Content-Type-Options':'nosniff'});res.end(JSON.stringify(value));};
  try{
   if(req.headers.origin||!/^127\.0\.0\.1(?::\d+)?$/.test(req.headers.host||''))return reply(403,{error:'Loopback Studio plugin requests only'});
   if(req.url==='/session'&&req.method==='GET')return reply(200,{token});
   if(req.headers['x-bw-token']!==token)return reply(403,{error:'Connect to the builder bridge first'});
   const url=new URL(req.url,'http://127.0.0.1');let body={};
   if(req.method!=='GET'){
    let size=0;const chunks=[];for await(const chunk of req){size+=chunk.length;if(size>2*1024*1024)throw new Error('Request exceeds 2MB');chunks.push(chunk);}
    body=JSON.parse(Buffer.concat(chunks).toString('utf8')||'{}');
   }
   if(url.pathname==='/discover'&&req.method==='POST')return reply(200,await store.discoverAssets(body.assets));
   if(url.pathname==='/catalog'&&req.method==='GET')return reply(200,{items:await store.items(),materials:Materials});
   if(url.pathname==='/worlds'&&req.method==='GET')return reply(200,{worlds:await store.list()});
   if(url.pathname==='/new'&&req.method==='POST'){const doc=fresh(body.id,body.name);require('./document').validate(doc,await store.items());if((await store.list()).some(w=>w.id===doc.id))throw new Error('World ID already exists; choose another');return reply(200,doc);}
   if(url.pathname==='/world'&&req.method==='GET')return reply(200,await store.get(url.searchParams.get('id')));
   if(url.pathname==='/save'&&req.method==='POST')return reply(200,await store.save(body.document,body.select===true,body.createOnly===true));
   if(url.pathname==='/publish'&&req.method==='POST')return reply(200,await store.publish(body.id));
   if(url.pathname==='/default'&&req.method==='POST'){await store.selectDefault();return reply(200,{selected:'default'});}
   if(url.pathname==='/delete'&&req.method==='POST')return reply(200,await store.remove(body.id,body.confirmation));
   if(url.pathname==='/import'&&req.method==='POST')return reply(200,await store.save(body.document,false,true));
   if(url.pathname==='/export-file'&&req.method==='POST'){const document=await store.get(body.id);const file=require('node:path').join(store.root,'build/world-exports',document.id+'.json');await require('./store').atomic(file,require('./document').serialize(document));return reply(200,{path:file});}
   if(url.pathname==='/export'&&req.method==='GET')return reply(200,await store.get(url.searchParams.get('id')));
   reply(404,{error:'Unknown builder operation'});
  }catch(e){reply(400,{error:e.message});}
 });return server;
}
module.exports={createServer};
