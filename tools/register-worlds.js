#!/usr/bin/env node
'use strict';
const fs = require('node:fs/promises');
const path = require('node:path');
const { registerWorlds } = require('./world/catalog');
const args = process.argv.slice(2);
async function main() {
  if (args.includes('--help')) { console.log('Usage: node tools/register-worlds.js [build/worlds] [--output worlds/studio-worlds.model.json]'); return; }
  const directory = args[0] && !args[0].startsWith('--') ? args.shift() : 'build/worlds';
  let output = 'worlds/studio-worlds.model.json';
  if (args.length) { if (args.length !== 2 || args[0] !== '--output' || args[1].startsWith('--')) throw new Error('Expected --output FILE.model.json'); output = args[1]; }
  if (!output.endsWith('.model.json')) throw new Error('Studio catalog output must end in .model.json for Rojo');
  const catalogTools=require('./world-builder/catalog');
  const bindings=catalogTools.bindingsFor(await catalogTools.catalog(path.resolve(__dirname,'..')));
  const catalog = await registerWorlds(directory, output, bindings);
  const count = status => catalog.Children.filter(c => c.Children.some(v => v.Name === 'Status' && v.Properties.Value === status)).length;
  console.log(`Registered ${catalog.Children.length} worlds: 1 built-in ready, ${count('preview-only')} preview-only, ${count('asset-dependent')} asset-dependent -> ${output}`);
}
main().catch(e => { console.error(`World catalog: ${e.message}`); process.exitCode = 1; });
