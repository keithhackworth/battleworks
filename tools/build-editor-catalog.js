#!/usr/bin/env node
'use strict';
// Package the existing catalog as runtime metadata. Native assets stay native.
const fs=require('node:fs/promises');
const path=require('node:path');
const {catalog}=require('./world-builder/catalog');
async function buildEditorCatalog(root=path.resolve(__dirname,'..')) {
 const items=await catalog(root);
 const result={ClassName:'StringValue',Properties:{Value:JSON.stringify(items)}};
 const output=path.join(root,'assets/editor-catalog.model.json');
 await fs.writeFile(output,JSON.stringify(result,null,2)+'\n');
 return items;
}
if(require.main===module)buildEditorCatalog().then(items=>console.log(`Packaged ${items.length} existing editor catalog entries`)).catch(e=>{console.error(e);process.exitCode=1;});
module.exports={buildEditorCatalog};
