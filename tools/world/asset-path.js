'use strict';
function validatePath(value){
 if(typeof value!=='string'||!value||value.length>512||value!==value.trim()||/[\\\x00-\x1f:]/.test(value)||value.startsWith('/')||value.endsWith('/'))throw new Error(`Invalid asset path '${value}': use a relative forward-slash path inside BattleWorksAssets`);
 const segments=value.split('/');if(segments.some(s=>!s||s==='.'||s==='..'||s!==s.trim()))throw new Error(`Invalid asset path '${value}': empty, dot and parent segments are forbidden`);
 return value;
}
function entriesFor(bindings){const paths=new Set();return Object.entries(bindings).map(([id,b])=>{
 if(!b||typeof (b.path||b.model)!=='string'||(b.source!==undefined&&typeof b.source!=='string'))throw new Error(`Invalid Roblox asset binding '${id}'`);
 const asset=validatePath(b.path||b.model);if(paths.has(asset))throw new Error(`Duplicate logical asset path '${asset}'`);paths.add(asset);
 return {id,source:b.source||asset,model:asset,...(b.collider?{collider:b.collider}:{})};
});}
function resolveAsset(resource,bindings){
 validatePath(resource);const entries=entriesFor(bindings);
 // A slash-qualified path has a unique exact meaning. Legacy GLB paths remain
 // aliases only when they match exactly one registered source.
 const exact=resource.includes('/')?entries.filter(b=>b.model===resource):[];
 if(exact.length)return exact[0];
 const candidates=entries.filter(b=>b.source===resource||b.id===resource||(!resource.includes('/')&&b.model.split('/').at(-1)===resource));
 const unique=[...new Map(candidates.map(b=>[b.model,b])).values()];
 if(unique.length>1)throw new Error(`Ambiguous asset '${resource}'. Use a full path: ${unique.map(b=>b.model).sort().join(', ')}`);
 return unique[0]||null;
}
module.exports={validatePath,entriesFor,resolveAsset};
