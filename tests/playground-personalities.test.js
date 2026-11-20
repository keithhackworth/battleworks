const test=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const {playgroundModule}=require('../tools/build-bw-personalities');
test('shipped Playground sources match editable BW sources and libraries',()=>{
 assert.equal(fs.readFileSync('src/server/PlaygroundPrograms.luau','utf8'),playgroundModule());
 assert.equal((playgroundModule().match(/\{id="P\d\d"/g)||[]).length,15);
});
test('Crazy Bunny variant queues movement and blind native bursts on one thread',()=>{
 const source=fs.readFileSync('programs/variants/02-crazy-bunny.bw','utf8');
 assert.doesNotMatch(source,/with thread|Scanner\(|enemy\(|aim_at\(/);
 assert.match(source,/fire\(ready.max_burst_seconds\)/);
 assert.match(source,/turn_right\(/);
 assert.match(source,/wait_for_clock\(/);
});
