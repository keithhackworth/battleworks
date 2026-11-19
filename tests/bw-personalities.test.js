'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const {build, digest, describe} = require('../tools/build-bw-personalities');
const profiles = require('../programs/personalities/profiles.json');
const countStatements = source => source.split('\n').filter(line => line.trim() && !line.trim().startsWith('#') && !/^\s*(else:|elif\b)/.test(line)).length;
test('expanded personalities are reproducible, editable and keep ordinary source budgets', () => {
 for (const entry of profiles.filter(p => !p.status.startsWith('draft'))) {
  const source = build(entry);
  assert.equal(digest(source), digest(build(entry)));
  assert.ok(countStatements(source) > 0, entry.id);
  assert.ok(Buffer.byteLength(source) <= 262144, entry.id);
  assert.doesNotMatch(source, /map_world\(|find_cover\(|predict_intercept\(|find_path\(/);
  const hints=fs.readFileSync('programs/personalities/'+entry.source,'utf8').split('\n').filter(line=>line.startsWith('# '));
  assert.ok(hints.length>=3, entry.id+' explanatory header and two improvement comments');
 }
});
test('personality constraints fit actual one-bus and multibus topologies without a new allocator', () => {
 for (const entry of profiles) {
  for (const buses of [1,2,4,8]) {
   const sums = Array(buses).fill(0);
   const devices = ['drivetrain','turret','weapon',...Array.from({length:8},(_,i)=>'sensor'+i*45)];
   devices.forEach((name,i)=>{
    const spec=entry.constraints[name.startsWith('sensor')?'sensor*':name];
    assert.ok(spec.min>=0 && spec.max<=100 && spec.min<=spec.max);
    if(spec.forcedZero) assert.equal(spec.max,0);
    const bus=i===0?0:i===1?Math.min(1,buses-1):i===2?Math.min(2,buses-1):buses>=4?3+(i-3)%Math.min(8,buses-3):buses-1;
    sums[bus]+=spec.min;
   });
   sums.forEach(sum=>assert.ok(sum<=100,entry.id+' feasible minimum per actual bus'));
  }
 }
});
test('Crazy has no sensor/target dependency; Tower and Sniper share player BW prediction', () => {
 const crazy=build(profiles.find(p=>p.id==='P02'));
 assert.doesNotMatch(crazy, /Scanner\(|enemy\(|aim_at\(/);
 assert.match(crazy,/fire\(ready.max_burst_seconds\)/);
 for (const id of ['P03','P04']) assert.ok(build(profiles.find(p=>p.id===id)).replace(/\s+/g,' ').includes(fs.readFileSync('programs/lib/prediction.bw','utf8').split('\n').slice(1).join('\n').trim().replace(/\s+/g,' ')));
});
test('Hunter uses approved general source capacity without privileged helpers', () => {
 const entry=profiles.find(p=>p.id==='P06');
 assert.ok(countStatements(build(entry))>128);
 assert.doesNotMatch(fs.readFileSync('src/shared/BWConfig.luau','utf8'),/MaxInstructions=|MaxLines=/);
 assert.match(build(entry),/parents\[next\]/);
});

test('all fifteen reviewed identities retain original sources and reproducible trace manifests', () => {
 assert.equal(profiles.length,15);
 assert.equal(new Set(profiles.map(p=>p.id)).size,15);
 for(const p of profiles){const trace=describe(p);assert.equal(trace.generated_sha256,digest(build(p)));assert.equal(trace.source_sha256.length,64);assert.equal(Object.keys(trace.library_sha256).length,p.libraries.length);}
 const duelist=build(profiles.find(p=>p.id==='P12'));assert.doesNotMatch(duelist,/\.terrain/);
});
