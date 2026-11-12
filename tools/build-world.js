#!/usr/bin/env node
'use strict';
const fs = require('node:fs/promises');
const path = require('node:path');
const { compileFile, serialize } = require('./world/compiler');
async function main(args) {
  if (args.includes('--help') || args.includes('-h')) { console.log('Usage: node tools/build-world.js WORLD.json [--output build/worlds/NAME.json | --validate]'); return; }
  const input = args.shift(); let output, validate = false;
  if (!input || input.startsWith('-')) throw new Error('Expected a world JSON file. Use --help for usage.');
  while (args.length) {
    const arg = args.shift();
    if (arg === '--validate' && !validate) validate = true;
    else if (arg === '--output' && !output && args[0] && !args[0].startsWith('--')) output = args.shift();
    else throw new Error(`Unknown, repeated or incomplete argument '${arg}'. Use --help for usage.`);
  }
  if (validate && output) throw new Error('--validate cannot be combined with --output; validation writes no files.');
  if (output && path.resolve(output) === path.resolve(input)) throw new Error('Output must not overwrite the source world.');
  const manifest = await compileFile(input);
  if (!validate) {
    output ||= path.join('build', 'worlds', path.basename(input));
    await fs.mkdir(path.dirname(output), { recursive: true });
    await fs.writeFile(output, serialize(manifest));
  }
  const s = manifest.stats;
  console.log(`${validate ? 'Validated' : 'Built'} ${input}: ${s.objects} objects, ${s.definitionsUsed} definitions used, ${s.generatedPathSegments} generated path segments${validate ? '' : ` -> ${output}`}`);
}
main(process.argv.slice(2)).catch(error => { console.error(`World compiler: ${error.message}`); process.exitCode = 1; });
