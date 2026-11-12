'use strict';
const fs = require('node:fs/promises');
const path = require('node:path');
const { serialize } = require('./compiler');
const { studioPlacement } = require('./studio-placement');
const value = (name, text) => ({ Name: name, ClassName: 'StringValue', Properties: { Value: text } });
function entry(id, name, status, reason, source, objects, assets) {
  return { Name: id, ClassName: 'Configuration', Children: [value('WorldId', id), value('DisplayName', name), value('Status', status), value('Reason', reason), value('ManifestPath', source),
    { Name: 'ObjectCount', ClassName: 'IntValue', Properties: { Value: objects } }, { Name: 'AssetCount', ClassName: 'IntValue', Properties: { Value: assets } }] };
}
async function discoverWorlds(directory, bindings = {}) {
  const files = (await fs.readdir(directory)).filter(f => f.endsWith('.json') && !f.endsWith('.model.json')).sort();
  const worlds = [], ids = new Set(['default']);
  for (const file of files) {
    const filename = path.resolve(directory, file);
    let manifest;
    try { manifest = JSON.parse(await fs.readFile(filename, 'utf8')); } catch (e) { throw new Error(`${filename}: ${e.message}`); }
    if (!manifest || typeof manifest !== 'object' || manifest.version !== 1 || !Array.isArray(manifest.objects) || !manifest.objects.every(o => o && typeof o.id === 'string' && typeof o.asset === 'string' && /\.glb$/i.test(o.asset))) throw new Error(`${filename}: expected a compiled v1 world manifest`);
    const id = Object.hasOwn(manifest, 'id') ? manifest.id : path.basename(file, '.json'), name = manifest.name ?? id;
    if (typeof id !== 'string' || !/^[A-Za-z0-9_][A-Za-z0-9_.:-]*$/.test(id) || typeof name !== 'string' || !name.trim()) throw new Error(`${filename}: invalid world id/name`);
    if (ids.has(id)) throw new Error(`${filename}: duplicate/reserved world ID '${id}'`); ids.add(id);
    const assets = new Set(manifest.objects.map(o => o.asset)).size;
    const placement = studioPlacement(manifest, bindings);
    const record = entry(id, name, placement ? 'asset-dependent' : 'preview-only', placement
      ? `Requires imported Model ServerStorage/BattleWorksAssets/${placement.model} from ${placement.source}; unavailable assets fall back to the test arena.`
      : `${assets} symbolic GLB resources have no Roblox asset mapping or supported placement. Only a single mapped model with uniform scale is supported.`,
      path.relative(path.resolve(__dirname, '../..'), filename).split(path.sep).join('/'), manifest.objects.length, assets);
    if (placement) record.Children.push({ Name: 'Placement', ClassName: 'Configuration', Children: [
      value('InstanceId', placement.id), value('AssetId', placement.assetId), value('Source', placement.source), value('Template', placement.model),
      { Name: 'Position', ClassName: 'Vector3Value', Properties: { Value: placement.position } },
      { Name: 'Rotation', ClassName: 'Vector3Value', Properties: { Value: placement.rotation } },
      { Name: 'Scale', ClassName: 'NumberValue', Properties: { Value: placement.scale } },
    ] });
    worlds.push(record);
  }
  worlds.sort((a, b) => a.Name < b.Name ? -1 : a.Name > b.Name ? 1 : 0);
  return { ClassName: 'Folder', Children: [entry('default', 'Default Test Arena', 'ready', 'Built-in BattleWorks arena; no imported assets required.', '', 0, 0), ...worlds] };
}
async function registerWorlds(directory, output, bindings = {}) {
  const catalog = await discoverWorlds(directory, bindings);
  await fs.mkdir(path.dirname(output), { recursive: true }); await fs.writeFile(output, serialize(catalog)); return catalog;
}
module.exports = { discoverWorlds, registerWorlds };
