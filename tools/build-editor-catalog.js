#!/usr/bin/env node
'use strict';
// Package the existing catalog as runtime metadata. Native assets stay native.
const fs=require('node:fs/promises');
const path=require('node:path');
const {catalogData}=require('./world-builder/catalog');
async function buildEditorCatalog(root=path.resolve(__dirname,'..')) {
 const {items,index,collisionReport}=await catalogData(root);
 const result=require('./catalog-chunks').catalogModel(items);
 const output=path.join(root,'assets/editor-catalog.model.json');
 const indexOutput=path.join(root,'assets/asset-index.model.json');
 await fs.mkdir(path.dirname(output),{recursive:true});
 // Validate every native export before replacing metadata. No model bytes move.
 await fs.writeFile(indexOutput+'.pending',JSON.stringify({ClassName:'StringValue',Properties:{Value:JSON.stringify(index)}},null,2)+'\n');
 await fs.writeFile(output+'.pending',JSON.stringify(result,null,2)+'\n');
 if(collisionReport)await fs.writeFile(path.join(root,'assets/collision-report.json'),JSON.stringify(collisionReport,null,2)+'\n');
 await fs.rename(indexOutput+'.pending',indexOutput);await fs.rename(output+'.pending',output);
 return items;
}
if(require.main===module)buildEditorCatalog().then(async items=>{
 console.log(`Packaged ${items.length} editor catalog entries`);
 try{
  const report=JSON.parse(await fs.readFile(path.resolve(__dirname,'../assets/collision-report.json'),'utf8'));
  console.log(`Collision profiles: ${report.summary.faces} GLB faces, ${report.summary.sampled} native sampling fallbacks, ${report.summary.unavailable} unavailable models. Details: assets/collision-report.json`);
  for(const asset of report.assets)if(asset.reason)console.log(`  ${asset.asset}: ${asset.reason}`);
 }catch(e){if(e.code!=='ENOENT')throw e;}
}).catch(e=>{console.error(e);process.exitCode=1;});
module.exports={buildEditorCatalog};
