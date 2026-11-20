const test=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const {spawnSync}=require('node:child_process');
test('single-file manual matches the actual in-game reference and current API appendix',()=>{
 const result=spawnSync(process.execPath,['tools/build-bw-manual.mjs','--check'],{encoding:'utf8'});
 if(result.error)throw result.error;
 assert.equal(result.status,0,result.stderr||result.stdout);
 const manual=fs.readFileSync('docs/BW_MANUAL.txt','utf8');
 for(const required of ['COMMAND: forward','function travel(distance):','get_tank_state','material_depth','Immutable aliases for built-in commands'])assert.ok(manual.includes(required),required);
 assert.ok(Buffer.byteLength(manual)>50000);
});
