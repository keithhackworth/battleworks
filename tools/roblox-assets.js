'use strict';
// Native models stay opaque: Rojo reads RBXM/RBXMX; we never reconstruct meshes.
const fs = require('node:fs/promises');
const path = require('node:path');
const os = require('node:os');
const {validatePath}=require('./world/asset-path');
const {nativeExports}=require('./world-builder/catalog');
const { spawnSync } = require('node:child_process');
const ROOT = path.resolve(__dirname, '..');
function rojo(args) {
  const run = spawnSync('rojo', args, { encoding: 'utf8', maxBuffer: 16 * 1024 * 1024 });
  if (run.error) throw run.error;
  if (run.status !== 0) throw new Error(`rojo ${args[0]} failed: ${run.stderr || run.stdout}`);
}
const children = node => node.children || [];
const child = (node, name) => children(node).find(n => n.name === name);
function meshCount(node) { return Number(node.className === 'MeshPart') + children(node).reduce((n, c) => n + meshCount(c), 0); }
async function exists(file) { try { await fs.access(file); return true; } catch (e) { if (e.code === 'ENOENT') return false; throw e; } }
async function validateAssets(options = {}) {
  const projectFile = path.resolve(options.projectFile || path.join(ROOT, 'default.project.json'));
  const root = path.dirname(projectFile);
  const project = JSON.parse(await fs.readFile(projectFile, 'utf8'));
  const mount = project.tree?.ServerStorage?.BattleWorksAssets;
  if (!mount?.$path) throw new Error('ServerStorage/BattleWorksAssets must mount a persistent model directory using $path.');
  if (mount.$ignoreUnknownInstances !== true) throw new Error('Keep $ignoreUnknownInstances=true while existing Studio-only imports are being exported.');
  const directory = path.resolve(root, mount.$path);
  const bindings = JSON.parse(await fs.readFile(options.bindingsFile || path.join(root, 'worlds/roblox-assets.json'), 'utf8'));
  const files = new Map((await nativeExports(directory)).map(entry=>[entry.path,entry.file]));
  const missing = [];
  for (const [id, binding] of Object.entries(bindings)) {
    if(!binding)throw new Error(`Invalid model binding '${id}'`);
    try{validatePath(binding.path||binding.model);}catch(e){throw new Error(`Invalid model binding '${id}': ${e.message}`);}
    const assetPath=binding.path||binding.model;
    if (!files.has(assetPath)) missing.push(`${id}: export the existing Studio Model '${assetPath}' to ${path.relative(root, directory)}/${assetPath}.rbxm (or .rbxmx)`);
  }
  if (missing.length && !options.allowMissingAssets) throw new Error(`Persistent asset exports missing:\n${missing.join('\n')}\nKeep the existing Studio imports/place backup. Export and verify them before rebuilding. No output was replaced.`);
  const temporary = await fs.mkdtemp(path.join(os.tmpdir(), 'bw-assets-check-'));
  try {
    const sourcemap = path.join(temporary, 'map.json');
    rojo(['sourcemap', projectFile, '--include-non-scripts', '--output', sourcemap]);
    const map = JSON.parse(await fs.readFile(sourcemap, 'utf8'));
    const folder = child(child(map, 'ServerStorage') || {}, 'BattleWorksAssets');
    if (folder?.className !== 'Folder') throw new Error('Build is missing ServerStorage/BattleWorksAssets Folder.');
    for (const [name, file] of files) {
      let model=folder;for(const segment of name.split('/'))model=child(model||{},segment);
      if (model?.className !== 'Model' || !meshCount(model)) throw new Error(`${file}: export exactly the imported Model itself with MeshPart descendants, not the enclosing Folder or an empty model.`);
    }
    const walk=(parent,prefix='')=>{for(const node of children(parent)){
      const full=prefix+node.name;
      if(!prefix&&Object.hasOwn(mount,node.name))continue; // explicitly mounted built-ins
      if(node.className==='Folder')walk(node,full+'/');
      else if(!files.has(full))throw new Error(`Unexpected asset '${full}': export a native model at the same relative path inside ${directory}.`);
    }};walk(folder);
    return { projectFile, directory, files: [...files.values()], models: files.size, missing };
  } finally { await fs.rm(temporary, { recursive: true, force: true }); }
}
async function buildPlace(options = {}) {
  const output = path.resolve(options.output || path.join(ROOT, 'build/battleworks.rbxl'));
  if (!/\.rbxlx?$/.test(output)) throw new Error('Place output must end in .rbxl or .rbxlx.');
  const assets = await validateAssets(options);
  if (assets.missing.length && await exists(output)) throw new Error('Refusing to overwrite an existing place while asset exports are missing. Choose a new output path for an explicit --allow-missing-assets build.');
  await fs.mkdir(path.dirname(output), { recursive: true });
  // Build beside the destination, so a failed build cannot truncate its old place.
  const temporary = await fs.mkdtemp(path.join(path.dirname(output), '.bw-build-'));
  try {
    const pending = path.join(temporary, 'place' + path.extname(output));
    rojo(['build', assets.projectFile, '--output', pending]);
    await fs.rename(pending, output);
    return { ...assets, output };
  } finally { await fs.rm(temporary, { recursive: true, force: true }); }
}
module.exports = { validateAssets, buildPlace };
