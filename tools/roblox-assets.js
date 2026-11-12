'use strict';
// Native models stay opaque: Rojo reads RBXM/RBXMX; we never reconstruct meshes.
const fs = require('node:fs/promises');
const path = require('node:path');
const os = require('node:os');
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
  const files = new Map();
  for (const entry of await fs.readdir(directory, { withFileTypes: true })) {
    if (!entry.isFile() || !/\.rbxmx?$/i.test(entry.name)) continue;
    const name = entry.name.replace(/\.rbxmx?$/i, '');
    if (files.has(name)) throw new Error(`Duplicate model export '${name}': keep one .rbxm OR .rbxmx file.`);
    files.set(name, path.join(directory, entry.name));
  }
  const missing = [];
  for (const [id, binding] of Object.entries(bindings)) {
    if (!binding || typeof binding.model !== 'string' || !binding.model.trim() || /[\\/:*?"<>|]/.test(binding.model) || ['.', '..'].includes(binding.model)) throw new Error(`Invalid model binding '${id}'.`);
    if (!files.has(binding.model)) missing.push(`${id}: export the existing Studio Model '${binding.model}' to ${path.relative(root, directory)}/${binding.model}.rbxm (or .rbxmx)`);
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
      const model = child(folder, name);
      if (model?.className !== 'Model' || !meshCount(model)) throw new Error(`${file}: export exactly the imported Model itself with MeshPart descendants, not the enclosing Folder or an empty model.`);
    }
    for (const model of children(folder)) if (!files.has(model.name)) throw new Error(`Unexpected asset '${model.name}': keep native .rbxm/.rbxmx exports directly in ${directory}.`);
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
