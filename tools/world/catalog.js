'use strict';
const fs = require('node:fs/promises');
const path = require('node:path');
const { serialize } = require('./compiler');
const { studioPlacements, placementIssue } = require('./studio-placement');
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
    if (!manifest || typeof manifest !== 'object' || manifest.version !== 1 || !Array.isArray(manifest.objects) || !manifest.objects.every(o => o && typeof o.id === 'string' && typeof o.asset === 'string')) throw new Error(`${filename}: expected a compiled v1 world manifest`);
    const id = Object.hasOwn(manifest, 'id') ? manifest.id : path.basename(file, '.json'), name = manifest.name ?? id;
    if (typeof id !== 'string' || !/^[A-Za-z0-9_][A-Za-z0-9_.:-]*$/.test(id) || typeof name !== 'string' || !name.trim()) throw new Error(`${filename}: invalid world id/name`);
    if (ids.has(id)) throw new Error(`${filename}: duplicate/reserved world ID '${id}'`); ids.add(id);
    const assets = new Set(manifest.objects.map(o => o.asset)).size;
    const placements = studioPlacements(manifest, bindings);
    const record = entry(id, name, placements ? 'asset-dependent' : 'preview-only', placements
      ? `Requires imported Models in ServerStorage/BattleWorksAssets: ${[...new Set(placements.map(p => p.model))].join(', ')}; unavailable assets fall back to the test arena.`
      : placementIssue(manifest, bindings),
      path.relative(path.resolve(__dirname, '../..'), filename).split(path.sep).join('/'), manifest.objects.length, assets);
    if (manifest.builderSettings) record.Children.push(value('BuilderSettings', JSON.stringify(manifest.builderSettings)));
    const nodes=[];
    for (const placement of placements || []) {
      const fields = [
      value('InstanceId', placement.id), value('AssetId', placement.assetId), value('Source', placement.source), value('Template', placement.model),
      { Name: 'Position', ClassName: 'Vector3Value', Properties: { Value: placement.position } },
      { Name: 'Rotation', ClassName: 'Vector3Value', Properties: { Value: placement.rotation } },
      { Name: 'Scale', ClassName: 'NumberValue', Properties: { Value: placement.scale } },
      ];
      if (placement.interaction) {
        const v = placement.interaction;
        fields.push({ Name: 'Solid', ClassName: 'BoolValue', Properties: { Value: v.solid } },
          { Name: 'Destructible', ClassName: 'BoolValue', Properties: { Value: v.destructible } },
          { Name: 'Health', ClassName: 'NumberValue', Properties: { Value: v.hp } },
          { Name: 'ColliderFractions', ClassName: 'Vector3Value', Properties: { Value: [v.collider.widthFraction, v.collider.heightFraction, v.collider.depthFraction] } });
      }
      nodes.push({ Name: `item_${nodes.length}`, ClassName: 'Configuration', Children: fields });
    }
    if (nodes.length===1) record.Children.push({...nodes[0],Name:'Placement'});
    else if (nodes.length) record.Children.push({Name:'Placements',ClassName:'Folder',Children:nodes});
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
