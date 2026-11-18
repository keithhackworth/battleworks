'use strict';
const prefix='BattleWorksChunks:v1:';const limit=170000;
function catalogModel(value){
 const raw=JSON.stringify(value);if(raw.length<=limit)return {ClassName:'StringValue',Properties:{Value:raw}};
 const chunks=[];for(let i=0;i<raw.length;){let end=Math.min(i+limit,raw.length);const last=raw.charCodeAt(end-1);if(end<raw.length&&last>=0xd800&&last<=0xdbff)end--;chunks.push({Name:'Chunk'+String(chunks.length+1).padStart(4,'0'),ClassName:'StringValue',Properties:{Value:raw.slice(i,end)}});i=end;}
 return {ClassName:'StringValue',Properties:{Value:prefix+chunks.length},Children:chunks};
}
function decodeCatalogModel(model){const raw=model.Properties.Value;return JSON.parse(raw.startsWith(prefix)?Array.from({length:Number(raw.slice(prefix.length))},(_,i)=>model.Children.find(c=>c.Name==='Chunk'+String(i+1).padStart(4,'0')).Properties.Value).join(''):raw);}
module.exports={catalogModel,decodeCatalogModel};
