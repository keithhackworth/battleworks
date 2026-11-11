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
    bundle += `\nloaders[${JSON.stringify(name)}] = function()\nlocal script = { Parent = ${parent}, BWController = "BWController", LocalBattle = "LocalBattle", DirectionalScanner = "DirectionalScanner", ManualScanner = "ManualScanner", EnvironmentBuilder = "EnvironmentBuilder", PracticeTargets = "PracticeTargets", ProjectileSimulation = "ProjectileSimulation" }\n${source}\nend\n`;
  }
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
  ];
  if (groupIndex === null) {
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
      if (suite === 'SwappedWeapons' || suite === 'IceWind') {
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
