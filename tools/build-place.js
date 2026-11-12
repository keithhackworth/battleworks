#!/usr/bin/env node
'use strict';
const { validateAssets, buildPlace } = require('./roblox-assets');
async function main(args) {
  if (args.includes('--help')) { console.log('Usage: node tools/build-place.js [--check | --output build/battleworks.rbxl] [--allow-missing-assets]'); return; }
  const options = {}; let check = false;
  while (args.length) {
    const arg = args.shift();
    if (arg === '--check' && !check) check = true;
    else if (arg === '--allow-missing-assets' && !options.allowMissingAssets) options.allowMissingAssets = true;
    else if (arg === '--output' && !options.output && args[0] && !args[0].startsWith('--')) options.output = args.shift();
    else throw new Error(`Unknown or incomplete argument '${arg}'. Use --help.`);
  }
  if (check && options.output) throw new Error('--check does not write a place; do not combine it with --output.');
  const result = await (check ? validateAssets(options) : buildPlace(options));
  for (const missing of result.missing) console.warn(`ASSET NOT PACKAGED: ${missing}`);
  console.log(`${check ? 'Verified' : 'Built'} ${result.models} persistent native models${result.output ? ` -> ${result.output}` : ''}${result.missing.length ? '; explicitly allowed missing assets, tree_test may fall back' : ''}.`);
}
main(process.argv.slice(2)).catch(e => { console.error(`Asset-preserving build: ${e.message}`); process.exitCode = 1; });
