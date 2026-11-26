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
  // Assemble the dependency closure after expanding each fixture and its
  // harness so large, unrelated modules stay outside the fixed WASM heap.
  async function buildBundle(tests) {
    const moduleName = file => file.split('/').pop().replace('.luau','');
    const byName = new Map([...sources].map(([file, source]) => [moduleName(file), source]));
    const editorState = await readFile('studio/world-builder/EditorState.luau','utf8');
    byName.set('EditorState', editorState);
    const external = new Set(['PlayerModule', 'ContactsBaseline', 'ContactsBaselineStats']);
    const needed = new Set();
    function include(name) {
      if (needed.has(name)) return;
      needed.add(name);
      if (external.has(name)) return;
      const source = byName.get(name);
      if (!source) throw new Error(`Missing fixture dependency: ${name}`);
      discover(source);
    }
    function discover(source) {
      for (const match of source.matchAll(/require\(([^)]+)\)/g)) {
        const name = match[1].match(/(?:\.|["'])(\w+)["']?$/)?.[1];
        if (name) include(name);
      }
    }
    discover(tests);
    const selected = new Map([...sources].filter(([file]) => needed.has(moduleName(file))));
    let bundle = await readFile('tests/RobloxMock.luau', 'utf8');
    bundle += '\nlocal loaders, cache = {}, {}\nlocal Shell = {}\nlocal require\n';
    for (const file of selected.keys()) {
      const name=file.split('/').pop().replace('.luau','');
      const namespace=file.includes('/shell/')?'Shell':file.includes('/shared/')?'Shared':'Client';
      bundle += `${namespace}[${JSON.stringify(name)}]=${JSON.stringify(name)}\n`;
    }
    bundle += '\nClient.shell=Shell\nClient.UI=Client\n';
    for (const [file, originalSource] of selected) {
      // Preserve historical weapon baselines as explicit assembly data, without
      // changing production simulation modules. Group14 preserves an explicit swap
      // fixture; RestoredLoadouts and subsequent groups exercise live defaults.
      const source = file.endsWith('/VehicleAssemblies.luau') && groupIndex !== null && groupIndex < 14
        ? await readFile('tests/fixtures/LegacyVehicleAssemblies.luau', 'utf8')
        : file.endsWith('/VehicleAssemblies.luau') && groupIndex === 14
          ? await readFile('tests/fixtures/SwappedVehicleAssemblies.luau', 'utf8') : originalSource;
      const name = file.split('/').pop().replace('.luau', '');
      const parent = file.includes('/shell/') ? 'Shell' : file.includes('/shared/') ? 'Shared' : 'Client';
      bundle += `\nloaders[${JSON.stringify(name)}] = function()\nlocal script = { Parent = ${parent}, PlaygroundAutonomy = "PlaygroundAutonomy", PlaygroundDiagnostics = "PlaygroundDiagnostics", PlaygroundBuilder = "PlaygroundBuilder", ProvingGrounds = "ProvingGrounds", RoyaleCharacters = "RoyaleCharacters", BattleRoyale = "BattleRoyale", InnovationLab = "InnovationLab", BWController = "BWController", LocalBattle = "LocalBattle", WorldTestContext = "WorldTestContext", StudioWorldSelector = "StudioWorldSelector", StudioAssetPlacement = "StudioAssetPlacement", WorldObjects = "WorldObjects", DirectionalScanner = "DirectionalScanner", ScannerScene = "ScannerScene", ManualScanner = "ManualScanner", EnvironmentBuilder = "EnvironmentBuilder", PlayerWorldStorage = "PlayerWorldStorage", PlayerWorldService = "PlayerWorldService", EditorAssetCatalog = "EditorAssetCatalog", PracticeTargets = "PracticeTargets", ProjectileSimulation = "ProjectileSimulation" }\n${source}\nend\n`;
    }
    if (needed.has('EditorState')) bundle += `\nloaders.EditorState=function()\n${editorState}\nend\n`;
    bundle += '\nrequire = function(name)\nif name == "PlayerModule" then return { GetControls = function() return defaultControls end } end\nif cache[name] == nil then cache[name] = assert(loaders[name], "Unknown module " .. tostring(name))() end\nreturn cache[name]\nend\n';
    if (needed.has('ContactsBaseline') || needed.has('ContactsBaselineStats')) {
      const revision = 'ae8194090e7c8dc244e347196e5b3ccb9ab2d0e6';
      let baseline;
      if (process.env.BW_CONTACTS_BASELINE) {
        baseline = await readFile(process.env.BW_CONTACTS_BASELINE, 'utf8');
      } else {
        const original = spawnSync('git', ['show', revision + ':src/shared/VehicleContacts.luau'], { encoding: 'utf8' });
        if (original.error || original.status !== 0) throw new Error('Cannot load pinned contact solver baseline. Set BW_CONTACTS_BASELINE to its file path.');
        baseline = original.stdout;
      }
      const { instrumentContactsBaseline } = await import('./instrument-contacts-baseline.mjs');
      for (const [name, source] of [['ContactsBaseline', baseline], ['ContactsBaselineStats', instrumentContactsBaseline(baseline)]]) {
        bundle += `\nloaders.${name}=function()\nlocal script={Parent=Shared}\n${source}\nend\n`;
      }
      bundle += '\nlocal benchmarkContacts=' + String(process.env.BW_CONTACTS_BENCHMARK === '1') + '\n';
    }
    return bundle;
  }
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
    ['ScannerTerrain', 'ScannerScene'],
    ['BWPersonalityFailures'],
    ['ProvingGround'],
    ['TerrainMaterials'],
    ['PlaygroundAutonomyIntegration'],
    ['BWEditorStatus'],
    ['PlaygroundEditorProgramIntegration'],
    ['BWCommandAliases'],
    ['BWTankSource'],
    ['BWRetention'],
    ['VehicleContactsOptimization'],
    ['BusConfiguration'],
    ['PlaygroundPopulation'],
    ['BWEvents', 'BWEventPayloads'],
    ['BWEventStress'],
    ['BWEventAdversarial'],
    ['RetaliatorMesh'],
    ['InnovationLabServer'],
    ['InnovationLabClient'],
    ['InnovationLabTravel'],
    ['InnovationLabEntry'],
    ['TerrainEditorRuntime'],
    ['TunnelEditor'],
    ['TerrainTraversal'],
    ['TerrainResize'],
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
      } else if(suite==='TerrainEditorRuntime'||suite==='TerrainResize'||suite==='TunnelEditor'){
        const harness=await readFile('tests/ServerIntegration.spec.luau','utf8');
        const editor=await readFile('tests/InGameEditorRuntime.spec.luau','utf8');
        tests+='\ndo\n'+harness.slice(0,harness.indexOf('Vector3.one='))+editor.slice(0,editor.indexOf('check(controller.scene.world.Parent'))+await readFile(`tests/${suite}.spec.luau`,'utf8')+'\nend\n';
      } else if(suite==='InnovationLabClient'){
        const source=await readFile('tests/RoyaleClientIntegration.spec.luau','utf8');
        const setup=source.slice(0,source.indexOf('local client=require("RoyaleClient")'));
        tests+='\ndo\n'+setup+await readFile('tests/InnovationLabClient.spec.luau','utf8')+'\nend\n';
      } else if(suite==='PlaygroundAutonomyIntegration'||suite==='PlaygroundEditorProgramIntegration'||suite==='InnovationLabServer'||suite==='InnovationLabTravel'||suite==='InnovationLabEntry'){
        const harness=await readFile('tests/ServerIntegration.spec.luau','utf8');
        let setup=harness.slice(0,harness.indexOf(' require("ServerEntrypoint")'));
        let boot=await readFile('tests/RoyaleServerIntegration.spec.luau','utf8');
        boot=boot.slice(0,boot.indexOf('advance(4)')).replace('require("BattleRoyaleConfig").TankCount=6','').replace('require("BattleRoyaleConfig").Personalities=false','');
        if(suite==='PlaygroundEditorProgramIntegration')boot=boot.replace('require("ServerEntrypoint")','require("BattleRoyaleConfig").TankCount=2\nrequire("ServerEntrypoint")');
        if(suite==='InnovationLabServer')boot=boot.replace('workspace:SetAttribute("BattleWorksGameMode","BattleRoyale")','workspace:SetAttribute("BattleWorksGameMode","InnovationLab")');
        if(suite==='InnovationLabTravel'||suite==='InnovationLabEntry'){
          setup=setup.replace('Heartbeat=heartbeat,IsStudio=function() return true end','Heartbeat=heartbeat,IsStudio=function() return false end');
          const travel=await readFile('tests/InnovationLabTravelSetup.luau','utf8');
          boot=boot.replace('require("ServerEntrypoint")','local labEntry='+String(suite==='InnovationLabEntry')+'\n'+travel+'\nrequire("ServerEntrypoint")');
        }
        if(suite==='PlaygroundAutonomyIntegration'||suite==='PlaygroundEditorProgramIntegration')boot+='\nenterPlayground(first);enterPlayground(second)\n';
        tests+='\ndo\nlocal headlessStartup=false\n'+setup+boot+await readFile('tests/'+suite+'.spec.luau','utf8')+'\nend\n';
      } else if(suite==='RoyaleServerIntegration'||suite==='RoyaleHeadlessServerIntegration'){
        const harness=await readFile('tests/ServerIntegration.spec.luau','utf8');
        let setup=harness.slice(0,harness.indexOf(' require("ServerEntrypoint")'));
        const headless=suite==='RoyaleHeadlessServerIntegration';
        if(headless)setup=setup.replace('Heartbeat=heartbeat,IsStudio=function() return true end','Heartbeat=heartbeat,IsStudio=function() return false end');
        const royale = (await readFile('tests/RoyaleServerIntegration.spec.luau','utf8'))
          .replace('workspace:SetAttribute("BattleWorksGameMode","BattleRoyale")','workspace:SetAttribute("BattleWorksGameMode","Playground")');
        tests+='\ndo\nlocal headlessStartup='+String(headless)+'\n'+setup+royale+'\nend\n';
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
          tests+='\nlocal steeringSource='+JSON.stringify(await readFile('programs/lib/core.bw','utf8')+'\nturn_to(90)')+'\n';
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
    if (group.includes('RetaliatorMesh')) {
      const demo=await readFile('programs/examples/retaliator-mesh.bw','utf8');
      tests='local retaliatorDemo=[====['+demo+']====]\n'+tests;
    }
    const bundle = await buildBundle(tests);
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
