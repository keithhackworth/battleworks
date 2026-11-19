// Node-only development check; no test dependencies are shipped in the Roblox place.
import { readFile, readdir } from 'node:fs/promises';
import { resolve } from 'node:path';
import { pathToFileURL } from 'node:url';
import { spawnSync } from 'node:child_process';
const runtime = process.argv[2];
const syntaxOnly=process.argv[3]==='--syntax';
const groupIndex = syntaxOnly || process.argv[3] === undefined ? null : Number(process.argv[3]);
if (!runtime) throw new Error('Usage: node scripts/check.mjs /path/to/luau-web/src/index.js');
const { LuauState } = await import(pathToFileURL(resolve(runtime)).href);
const editorExports=[];
let state = await LuauState.createAsync({ print: (...args)=>{if(args[0]==='EDITOR_EXPORT')editorExports.push(JSON.parse(args[1]));else console.log(...args);} });
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
  if(syntaxOnly){state.destroy();state=null;process.exit(0);}
  // Native mesh fixtures approach Luau Web's fixed heap. Load their actual
  // production dependency graph, without compiling unrelated UI/server loaders.
  // The full syntax pass and other groups still compile every source file.
  if (groupIndex === 45) {
    const byName = new Map([...sources].map(([file, source]) => [file.split('/').pop().replace('.luau',''), {file, source}]));
    const needed = new Set();
    function include(name) {
      if (needed.has(name)) return;
      const entry=byName.get(name);
      if (!entry) throw new Error(`Missing fixture dependency: ${name}`);
      needed.add(name);
      for (const match of entry.source.matchAll(/require\(([^)]+)\)/g)) {
        const dependency=match[1].match(/(?:\.|["'])(\w+)["']?$/)?.[1];
        if (!dependency) throw new Error(`Unresolved fixture dependency: ${match[0]}`);
        include(dependency);
      }
    }
    const fixture=await readFile('tests/BulkAssetCollision.spec.luau','utf8');
    for (const match of fixture.matchAll(/require\("(\w+)"\)/g)) include(match[1]);
    for (const file of sources.keys()) if (!needed.has(file.split('/').pop().replace('.luau',''))) sources.delete(file);
  }
  let bundle = await readFile('tests/RobloxMock.luau', 'utf8');
  bundle += '\nlocal loaders, cache = {}, {}\nlocal Shell = {}\nlocal require\n';
  for (const file of sources.keys()) {
    const name=file.split('/').pop().replace('.luau','');
    const namespace=file.includes('/shell/')?'Shell':file.includes('/shared/')?'Shared':'Client';
    bundle += `${namespace}[${JSON.stringify(name)}]=${JSON.stringify(name)}\n`;
  }
  bundle += '\nClient.shell=Shell\n';
  for (const [file, originalSource] of sources) {
    // Preserve historical weapon baselines as explicit assembly data, without
    // changing production simulation modules. Group14 preserves an explicit swap
    // fixture; RestoredLoadouts and subsequent groups exercise live defaults.
    const source = file.endsWith('/VehicleAssemblies.luau') && groupIndex !== null && groupIndex < 14
      ? await readFile('tests/fixtures/LegacyVehicleAssemblies.luau', 'utf8')
      : file.endsWith('/VehicleAssemblies.luau') && groupIndex === 14
        ? await readFile('tests/fixtures/SwappedVehicleAssemblies.luau', 'utf8') : originalSource;
    const name = file.split('/').pop().replace('.luau', '');
    const parent = file.includes('/shell/') ? 'Shell' : file.includes('/shared/') ? 'Shared' : 'Client';
    bundle += `\nloaders[${JSON.stringify(name)}] = function()\nlocal script = { Parent = ${parent}, PlaygroundBuilder = "PlaygroundBuilder", RoyaleCharacters = "RoyaleCharacters", BattleRoyale = "BattleRoyale", BWController = "BWController", LocalBattle = "LocalBattle", WorldTestContext = "WorldTestContext", StudioWorldSelector = "StudioWorldSelector", StudioAssetPlacement = "StudioAssetPlacement", WorldObjects = "WorldObjects", DirectionalScanner = "DirectionalScanner", ManualScanner = "ManualScanner", EnvironmentBuilder = "EnvironmentBuilder", PlayerWorldStorage = "PlayerWorldStorage", PlayerWorldService = "PlayerWorldService", EditorAssetCatalog = "EditorAssetCatalog", PracticeTargets = "PracticeTargets", ProjectileSimulation = "ProjectileSimulation" }\n${source}\nend\n`;
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
    ['Multiplayer'],
    ['ApplicationShell'],
    ['ShellServerIntegration'],
    ['ShellClientIntegration'],
    ['InGameWorldEditor'],
    ['InGameEditorRuntime'],
    ['PlayerWorlds'],
    ['PlayerWorldServerIntegration'],
    ['PlayerWorldPublishedIntegration'],
    ['WorldElevation'],
    ['HttpWorldStore'],
    ['RestoredLoadouts'],
    ['WorldEditorSnap'],
    ['StartingPositions'],
    ['WorldTestContext'],
    ['TeamWorldServerIntegration'],
    ['ImportedGeometry'],
    ['FootprintSupport'],
    ['TerrainFaces'],
    ['BulkAssetCollision'],
    ['RoyaleServerIntegration'],
    ['RoyaleClientIntegration'],
    ['BulkBuildingCollision'], // isolate large native geometry fixtures in Luau Web's fixed heap
    ['RoyaleTeamClientIntegration'],
    ['RoyaleHeadlessServerIntegration'],
    ['Playground'],
    ['Aiming'],
    ['MouseModes'],
    ['PlaygroundChat'],
    ['BWCoreAPI'],
    ['BWPersonalities'],
    ['BWLargePrograms'],
    ['ScannerTerrain'],
    ['BWPersonalityFailures'],
    ['ProvingGround'],
    ['TerrainMaterials'],
  ];
  if (groupIndex === null) {
    const worldTests = spawnSync(process.execPath, ['--test', ...(await readdir('tests')).filter(name=>name.endsWith('.test.js')).sort().map(name=>'tests/'+name)], { stdio: 'inherit' });
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
      if(suite==='RoyaleTeamClientIntegration'){
        const source=await readFile('tests/RoyaleClientIntegration.spec.luau','utf8');
        tests+='\ndo\n'+source.replace('IsStudio=function() return false end','IsStudio=function() return true end')+'\nend\n';
      } else if(suite==='RoyaleServerIntegration'||suite==='RoyaleHeadlessServerIntegration'){
        const harness=await readFile('tests/ServerIntegration.spec.luau','utf8');
        let setup=harness.slice(0,harness.indexOf(' require("ServerEntrypoint")'));
        const headless=suite==='RoyaleHeadlessServerIntegration';
        if(headless)setup=setup.replace('Heartbeat=heartbeat,IsStudio=function() return true end','Heartbeat=heartbeat,IsStudio=function() return false end');
        tests+='\ndo\nlocal headlessStartup='+String(headless)+'\n'+setup+await readFile('tests/RoyaleServerIntegration.spec.luau','utf8')+'\nend\n';
      } else if (suite === 'ProvingGround' || suite === 'TerrainMaterials' || suite === 'BWPersonalityFailures' || suite === 'ScannerTerrain' || suite === 'BWLargePrograms' || suite === 'BWPersonalities' || suite === 'BWCoreAPI' || suite === 'Aiming' || suite === 'Playground' || suite === 'StudioAssetPlacement' || suite === 'WorldObjects' || suite === 'InGameEditorRuntime' || suite === 'PlayerWorlds' || suite === 'WorldElevation' || suite === 'StartingPositions' || suite === 'ImportedGeometry' || suite === 'FootprintSupport' || suite === 'TerrainFaces' || suite === 'BulkAssetCollision' || suite === 'BulkBuildingCollision') {
        const harness = await readFile('tests/ServerIntegration.spec.luau', 'utf8');
        const marker = 'Vector3.one=';
        if (!harness.includes(marker)) throw new Error('Transform harness marker changed');
        tests += '\ndo\n' + harness.slice(0, harness.indexOf(marker));
        if(suite==='BWPersonalities'||suite==='BWPersonalityFailures'){
          tests+='\nlocal failureOnly='+String(suite==='BWPersonalityFailures')+'\n';
          const {createRequire}=await import('node:module');
          const {build}=createRequire(import.meta.url)('../tools/build-bw-personalities.js');
          const allProfiles=JSON.parse(await readFile('programs/personalities/profiles.json','utf8'));
          const profiles=allProfiles;
          tests+='\nlocal hunterSource='+JSON.stringify(build(allProfiles.find(p=>p.id==='P06')))+'\n';
          tests+='\nlocal personalityMinimums={'+profiles.map(p=>'['+JSON.stringify(p.id)+']={'+Object.entries(p.constraints).map(([k,v])=>'['+JSON.stringify(k)+']='+v.min).join(',')+'}').join(',')+'}\n';
          tests+='\nlocal personalityTiers={'+profiles.map(p=>'['+JSON.stringify(p.id)+']='+JSON.stringify(p.tier)).join(',')+'}\n';
          tests+='\nlocal personalitySources={'+profiles.map(p=>'['+JSON.stringify(p.id)+']='+JSON.stringify(build(p))).join(',')+'}\n';
        }
        if(suite==='BWCoreAPI'){
          const spec=await readFile('docs/BW_CORE_API_SPEC.md','utf8');
          const examples=[...spec.matchAll(/```text\n([\s\S]*?)```/g)].map(match=>match[1]);
          tests+='\nlocal coreApiExamples={'+examples.map(example=>JSON.stringify(example)).join(',')+'}\n';
        }
        if(suite==='TerrainFaces'){
          const {loadFaces}=await import(pathToFileURL(resolve('tools/glb-collision.js')).href);
          const profile=await loadFaces('GLBs/forest/rocks-ramp.glb');
          const lua=v=>Array.isArray(v)?'{'+v.map(lua).join(',')+'}':JSON.stringify(v);
          tests+='\nlocal nativeProfile={faces='+lua(profile.faces)+',sourceSize='+lua(profile.sourceSize)+'}\n';
        }
        if(suite==='BulkAssetCollision'||suite==='BulkBuildingCollision'){
          const {decodeCatalogModel}=await import(pathToFileURL(resolve('tools/catalog-chunks.js')).href);
          const items=decodeCatalogModel(JSON.parse(await readFile('assets/editor-catalog.model.json','utf8')));
          const models=suite==='BulkAssetCollision'?['Forest/bridge','Forest/fence']:['Surburban/fence','Surburban/building-type-a'];
          const selected=items.filter(i=>models.includes(i.model));
          const lua=v=>v===null?'nil':typeof v==='object'?(Array.isArray(v)?'{'+v.map(lua).join(',')+'}':'{'+Object.entries(v).map(([k,n])=>'['+JSON.stringify(k)+']='+lua(n)).join(',')+'}'):JSON.stringify(v);
          tests+='\nlocal bulkItems='+lua(selected)+'\n';
        }
        tests += await readFile(`tests/${suite==='BWPersonalityFailures'?'BWPersonalities':(suite==='BulkBuildingCollision')?'BulkAssetCollision':suite}.spec.luau`, 'utf8') + '\nend\n';
      } else if (suite === 'BuilderServerIntegration' || suite === 'BuilderPublishedIntegration' || suite === 'PlayerWorldServerIntegration' || suite === 'PlayerWorldPublishedIntegration' || suite === 'TeamWorldServerIntegration') {
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
        const published=suite==='BuilderPublishedIntegration' || suite==='PlayerWorldPublishedIntegration' || suite==='TeamWorldServerIntegration';
        if(published) setup=setup.replace('Heartbeat=heartbeat,IsStudio=function() return true end','Heartbeat=heartbeat,IsStudio=function() return false end');
        if(suite==='TeamWorldServerIntegration')setup=setup.slice(0,setup.indexOf(' check(snapshots[boomerId].tankType'));
        setup=setup.replace(' require("ServerEntrypoint")',(await readFile('tests/BuilderIntegrationSetup.luau','utf8'))+((suite==='PlayerWorldServerIntegration'||suite==='PlayerWorldPublishedIntegration'||suite==='TeamWorldServerIntegration')?'\n'+await readFile('tests/PlayerWorldIntegrationSetup.luau','utf8'):'')+(suite==='TeamWorldServerIntegration'?'\n'+await readFile('tests/TeamWorldSetup.luau','utf8'):'')+'\n require("ServerEntrypoint")');
        tests+='\ndo\nlocal builderCatalog='+lua(catalog)+'\nlocal builderItems='+lua(items)+'\nlocal builderSettings='+lua(manifest.builderSettings)+'\nlocal builderPublished='+String(published)+'\n'+setup;
        tests+=await readFile('tests/'+((suite==='PlayerWorldServerIntegration'||suite==='PlayerWorldPublishedIntegration'||suite==='TeamWorldServerIntegration')?suite:'BuilderServerIntegration')+'.spec.luau','utf8')+'\nend\n';
      } else if (suite === 'SwappedWeapons' || suite === 'RestoredLoadouts' || suite === 'IceWind' || suite === 'Multiplayer' || suite === 'ShellServerIntegration') {
        // Reuse the real server/transform setup, replacing only scenario assertions.
        const harness = await readFile('tests/ServerIntegration.spec.luau', 'utf8');
        const marker = ' local generation=snapshots[boomerId].generation';
        if (!harness.includes(marker)) throw new Error('Server harness marker changed');
        let setup = harness.slice(0, harness.indexOf(marker));
        if (suite === 'Multiplayer' || suite === 'ShellServerIntegration') {
          setup = setup.slice(0, setup.indexOf(' check(snapshots[boomerId].tankType'));
          setup = setup.replace('workspace:SetAttribute("SoloTankPairs",true)', 'workspace:SetAttribute("SoloTankPairs",nil)');
        }
        if (suite === 'ShellServerIntegration') setup=setup.replace(' session.OnServerEvent:Fire(first,"Enter",1)\n session.OnServerEvent:Fire(second,"Enter",1)\n','');
        if (suite === 'IceWind') setup = setup.replace('workspace:SetAttribute("ArenaWeather","Normal")', 'workspace:SetAttribute("ArenaWeather","IceWind")');
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
    for (const {document,items} of editorExports) {
      const {compileDocument}=await import(pathToFileURL(resolve('tools/world-builder/document.js')).href);
      const result=compileDocument(document,items);
      if(result.document.objects.length!==document.objects.length)throw new Error('Editor export lost objects');
      for(const object of document.objects) {
        const actual=result.document.objects.find(o=>o.id===object.id);
        if(actual.asset!==object.asset || actual.hp!==object.hp || actual.solid!==object.solid || actual.destructible!==object.destructible)throw new Error('Editor export lost asset identity or influences');
      }
      console.log('In-game Luau export validated and compiled by existing Node world compiler');
    }
  }
} finally {
  state?.destroy();
}
