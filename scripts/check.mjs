// Node-only development check; no test dependencies are shipped in the Roblox place.
import { readFile, readdir } from 'node:fs/promises';
import { resolve } from 'node:path';
import { pathToFileURL } from 'node:url';
import { spawnSync } from 'node:child_process';
const runtime = process.argv[2];
const groupIndex = process.argv[3] === undefined ? null : Number(process.argv[3]);
if (!runtime) throw new Error('Usage: node scripts/check.mjs /path/to/luau-web/src/index.js');
const { LuauState } = await import(pathToFileURL(resolve(runtime)).href);
let state = await LuauState.createAsync({ print: console.log });
try {
  const files = [];
  async function walk(dir) {
    for (const entry of await readdir(dir, { withFileTypes: true })) {
      const path = `${dir}/${entry.name}`;
      if (entry.isDirectory()) await walk(path);
      else if (path.endsWith('.luau')) files.push(path);
    }
  }
  await walk('src');
  const pluginFiles=await readdir('studio/world-builder');
  for(const file of pluginFiles) if(file.endsWith('.luau')) {const source=await readFile('studio/world-builder/'+file,'utf8');state.loadstring(source,'studio/world-builder/'+file,true);}
  const sources = new Map();
  for (const file of files) {
    const source = await readFile(file, 'utf8');
    if (groupIndex === null) state.loadstring(source, file, true); // compile only: Roblox globals aren't needed
    if (!file.includes('init.')) sources.set(file, source);
    if (file === 'src/server/init.server.luau') sources.set('src/server/ServerEntrypoint.luau', source);
  }
  if (groupIndex === null) console.log(`Syntax compilation passed: ${files.length} Luau source files`);
  let bundle = await readFile('tests/RobloxMock.luau', 'utf8');
  bundle += '\nlocal loaders, cache = {}, {}\nlocal require\n';
  for (const [file, originalSource] of sources) {
    // Preserve historical weapon baselines as explicit assembly data, without
    // changing production simulation modules. Group14 tests the real live swap.
    const source = file.endsWith('/VehicleAssemblies.luau') && groupIndex !== null && groupIndex < 14
      ? await readFile('tests/fixtures/LegacyVehicleAssemblies.luau', 'utf8') : originalSource;
    const name = file.split('/').pop().replace('.luau', '');
    const parent = file.includes('/shared/') ? 'Shared' : 'Client';
    bundle += `\nloaders[${JSON.stringify(name)}] = function()\nlocal script = { Parent = ${parent}, BWController = "BWController", LocalBattle = "LocalBattle", StudioWorldSelector = "StudioWorldSelector", StudioAssetPlacement = "StudioAssetPlacement", WorldObjects = "WorldObjects", DirectionalScanner = "DirectionalScanner", ManualScanner = "ManualScanner", EnvironmentBuilder = "EnvironmentBuilder", PracticeTargets = "PracticeTargets", ProjectileSimulation = "ProjectileSimulation" }\n${source}\nend\n`;
  }
  bundle += `\nloaders.EditorState=function()\n${await readFile('studio/world-builder/EditorState.luau','utf8')}\nend\n`;
  bundle += '\nrequire = function(name)\nif name == "PlayerModule" then return { GetControls = function() return defaultControls end } end\nif cache[name] == nil then cache[name] = assert(loaders[name], "Unknown module " .. tostring(name))() end\nreturn cache[name]\nend\n';
  // Mock UI/event fixtures deliberately retain references. Isolate groups so
  // the fixed-size Luau Web heap doesn't accumulate unrelated service graphs.
  const groups = [
    ['Input', 'Camera'],
    ['Combat', 'Projectiles', 'BarrelAnimation', 'Environment', 'Tanks'],
    ['Renderer'],
    ['ServerIntegration'],
    ['Trajectory', 'Recoil', 'Speed'],
    ['BW', 'BWBestEffort', 'Battle', 'DamageEffects', 'Scanner'],
    ['BW02'],
    ['BWExecution'],
    ['BWHandbook'],
    ['BWLoops'],
    ['BWScanLoops'],
    ['BWConstants'],
    ['BWSteering'],
    ['VehicleComponents'],
    ['SwappedWeapons'],
    ['LiveRuntimeExamples'],
    ['BWEditor'],
    ['BWFunctions'],
    ['PhysicsForces', 'PhysicsBW'],
    ['IceWind'],
    ['StudioWorldSelector', 'StudioAssetPlacement', 'WorldObjects', 'WorldBuilderState', 'WorldSettings', 'AssetPaths'],
    ['BuilderServerIntegration'],
    ['BuilderPublishedIntegration'],
  ];
  if (groupIndex === null) {
    const worldTests = spawnSync(process.execPath, ['--test', 'tests/world-compiler.test.js', 'tests/asset-persistence.test.js', 'tests/world-builder.test.js', 'tests/asset-paths.test.js'], { stdio: 'inherit' });
    if (worldTests.error) throw worldTests.error;
    if (worldTests.status !== 0) throw new Error('World compiler tests failed');
    state.destroy(); state = null;
    for (let i = 0; i < groups.length; i++) {
      const child = spawnSync(process.execPath, [process.argv[1], runtime, String(i)], { stdio: 'inherit' });
      if (child.status !== 0) throw new Error(`Test group ${groups[i].join(', ')} failed (${child.status})`);
    }
  } else {
    const group = groups[groupIndex];
    if (!group) throw new Error('Invalid test group');
    let tests = '';
    for (const suite of group) {
      if (suite === 'StudioAssetPlacement' || suite === 'WorldObjects') {
        const harness = await readFile('tests/ServerIntegration.spec.luau', 'utf8');
        const marker = 'Vector3.one=';
        if (!harness.includes(marker)) throw new Error('Transform harness marker changed');
        tests += '\ndo\n' + harness.slice(0, harness.indexOf(marker));
        tests += await readFile(`tests/${suite}.spec.luau`, 'utf8') + '\nend\n';
      } else if (suite === 'BuilderServerIntegration' || suite === 'BuilderPublishedIntegration') {
        const {default:doc}=await import(pathToFileURL(resolve('tools/world-builder/document.js')).href);
        const {default:cat}=await import(pathToFileURL(resolve('tools/world-builder/catalog.js')).href);
        const {default:worldCatalog}=await import(pathToFileURL(resolve('tools/world/catalog.js')).href);
        const {mkdtemp,writeFile,rm}=await import('node:fs/promises');
        const {tmpdir}=await import('node:os');
        const items=cat.builtinCatalog();
        const document=JSON.parse(await readFile('worlds/builder/builder_demo.json','utf8'));
        const {manifest}=doc.compileDocument(document,items);
        const dir=await mkdtemp(resolve(tmpdir(),'bw-builder-runtime-'));
        let catalog;
        try {await writeFile(resolve(dir,'world.json'),JSON.stringify(manifest));catalog=await worldCatalog.discoverWorlds(dir,cat.bindingsFor(items));}finally{await rm(dir,{recursive:true,force:true});}
        const lua=v=>v===null?'nil':typeof v==='object'?(Array.isArray(v)?'{'+v.map(lua).join(',')+'}':'{'+Object.entries(v).map(([k,n])=>'['+JSON.stringify(k)+']='+lua(n)).join(',')+'}'):JSON.stringify(v);
        const harness=await readFile('tests/ServerIntegration.spec.luau','utf8');
        let setup=harness.slice(0,harness.indexOf(' local generation=snapshots[boomerId].generation'));
        setup=setup.replace('math.abs(snapshots[boomerId].yaw+snapshots[rattlerId].yaw)','math.abs(math.abs(snapshots[boomerId].yaw-snapshots[rattlerId].yaw)%(math.pi*2)-math.pi)');
        const published=suite==='BuilderPublishedIntegration';
        if(published) setup=setup.replace('Heartbeat=heartbeat,IsStudio=function() return true end','Heartbeat=heartbeat,IsStudio=function() return false end');
        setup=setup.replace(' require("ServerEntrypoint")',(await readFile('tests/BuilderIntegrationSetup.luau','utf8'))+'\n require("ServerEntrypoint")');
        tests+='\ndo\nlocal builderCatalog='+lua(catalog)+'\nlocal builderItems='+lua(items)+'\nlocal builderSettings='+lua(manifest.builderSettings)+'\nlocal builderPublished='+String(published)+'\n'+setup;
        tests+=await readFile('tests/BuilderServerIntegration.spec.luau','utf8')+'\nend\n';
      } else if (suite === 'SwappedWeapons' || suite === 'IceWind') {
        // Reuse the real server/transform setup, replacing only scenario assertions.
        const harness = await readFile('tests/ServerIntegration.spec.luau', 'utf8');
        const marker = ' local generation=snapshots[boomerId].generation';
        if (!harness.includes(marker)) throw new Error('Server harness marker changed');
        let setup = harness.slice(0, harness.indexOf(marker));
        if (suite === 'IceWind') setup = setup.replace('workspace:SetAttribute("ArenaWeather","Normal")', 'workspace:SetAttribute("ArenaWeather",nil)');
        tests += '\ndo\n' + setup;
        tests += await readFile(`tests/${suite}.spec.luau`, 'utf8') + '\nend\n';
      } else tests += '\ndo\n' + await readFile(`tests/${suite}.spec.luau`, 'utf8') + '\nend\n';
    }
    if (group.includes('BWExecution') || group.includes('LiveRuntimeExamples')) {
      const docs = await readFile('docs/BW_RUNTIME.md', 'utf8');
      const examples = [...docs.matchAll(/```python\n([\s\S]*?)```/g)].map(match => match[1]);
      tests += '\ndo\nlocal examples = {' + examples.map(source => '[====[' + source + ']====]').join(',') + '}\n';
      tests += await readFile('tests/BWRuntimeExamples.luau', 'utf8') + '\nend\n';
    }
    await state.loadstring(bundle + tests, group.join('-'), true)();
  }
} finally {
  state?.destroy();
}
