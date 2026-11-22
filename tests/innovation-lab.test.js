const assert = require('node:assert/strict');
const fs = require('node:fs');
const test = require('node:test');
const { labModule } = require('../tools/build-bw-personalities');
test('shipped Innovation Lab program matches its editable BW source', () => {
  assert.equal(fs.readFileSync('src/server/InnovationLabProgram.luau', 'utf8'), labModule());
});
