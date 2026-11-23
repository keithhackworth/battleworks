'use strict';
const fs=require('node:fs/promises');
const path=require('node:path');
const {validatePath}=require('../world/asset-path');

const hiddenAssetFile=root=>path.join(root,'assets/hidden-editor-assets.model.json');
async function readHiddenAssets(root){
 let source;
 try{source=await fs.readFile(hiddenAssetFile(root),'utf8');}
 catch(error){if(error.code==='ENOENT')return [];throw error;}
 const values=JSON.parse(JSON.parse(source).Properties.Value);
 if(!Array.isArray(values))throw new Error('Invalid hidden editor asset list');
 return values.map(validatePath);
}
module.exports={hiddenAssetFile,readHiddenAssets};
