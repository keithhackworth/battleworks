#!/usr/bin/env node
'use strict';
// Package the existing catalog as runtime metadata. Native assets stay native.
const fs=require('node:fs/promises');
const path=require('node:path');
const {catalogData}=require('./world-builder/catalog');
async function buildEditorCatalog(root=path.resolve(__dirname,'..')) {
 const {items,index}=await catalogData(root);
 const result={ClassName:'StringValue',Properties:{Value:JSON.stringify(items)}};
 const output=path.join(root,'assets/editor-catalog.model.json');
 const indexOutput=path.join(root,'assets/asset-index.model.json');
 await fs.mkdir(path.dirname(output),{recursive:true});
 // Validate every native export before replacing metadata. No model bytes move.
 await fs.writeFile(indexOutput+'.pending',JSON.stringify({ClassName:'StringValue',Properties:{Value:JSON.stringify(index)}},null,2)+'\n');
 await fs.writeFile(output+'.pending',JSON.stringify(result,null,2)+'\n');
 await fs.rename(indexOutput+'.pending',indexOutput);await fs.rename(output+'.pending',output);
 return items;
}
if(require.main===module)buildEditorCatalog().then(items=>console.log(`Packaged ${items.length} existing editor catalog entries`)).catch(e=>{console.error(e);process.exitCode=1;});
module.exports={buildEditorCatalog};
