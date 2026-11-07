// Node-only development check; no test dependencies are shipped in the Roblox place.
import { readFile, readdir } from 'node:fs/promises';
import { resolve } from 'node:path';
import { pathToFileURL } from 'node:url';
const runtime = process.argv[2];
if (!runtime) throw new Error('Usage: node scripts/check.mjs /path/to/luau-web/src/index.js');
const { LuauState } = await import(pathToFileURL(resolve(runtime)).href);
const state = await LuauState.createAsync({ print: console.log });
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
    state.loadstring(source, file, true); // compile only: Roblox globals aren't needed
    if (!file.includes('init.')) sources.set(file, source);
    if (file === 'src/server/init.server.luau') sources.set('src/server/ServerEntrypoint.luau', source);
  }
  console.log(`Syntax compilation passed: ${files.length} Luau source files`);
  let bundle = await readFile('tests/RobloxMock.luau', 'utf8');
  bundle += '\nlocal loaders, cache = {}, {}\nlocal require\n';
  for (const [file, source] of sources) {
    const name = file.split('/').pop().replace('.luau', '');
    const parent = file.includes('/shared/') ? 'Shared' : 'Client';
    bundle += `\nloaders[${JSON.stringify(name)}] = function()\nlocal script = { Parent = ${parent}, BWController = "BWController", EnvironmentBuilder = "EnvironmentBuilder", PracticeTargets = "PracticeTargets", ProjectileSimulation = "ProjectileSimulation" }\n${source}\nend\n`;
  }
  bundle += '\nrequire = function(name)\nif name == "PlayerModule" then return { GetControls = function() return defaultControls end } end\nif cache[name] == nil then cache[name] = assert(loaders[name], "Unknown module " .. tostring(name))() end\nreturn cache[name]\nend\n';
  bundle += '\ndo\n' + await readFile('tests/Input.spec.luau', 'utf8') + '\nend\n';
  bundle += '\ndo\n' + await readFile('tests/Camera.spec.luau', 'utf8') + '\nend\n';
  bundle += '\ndo\n' + await readFile('tests/Combat.spec.luau', 'utf8') + '\nend\n';
  bundle += '\ndo\n' + await readFile('tests/Projectiles.spec.luau', 'utf8') + '\nend\n';
  bundle += '\ndo\n' + await readFile('tests/BarrelAnimation.spec.luau', 'utf8') + '\nend\n';
  bundle += '\ndo\n' + await readFile('tests/Environment.spec.luau', 'utf8') + '\nend\n';
  bundle += '\ndo\n' + await readFile('tests/Tanks.spec.luau', 'utf8') + '\nend\n';
  bundle += '\ndo\n' + await readFile('tests/Renderer.spec.luau', 'utf8') + '\nend\n';
  bundle += '\ndo\n' + await readFile('tests/Trajectory.spec.luau', 'utf8') + '\nend\n';
  bundle += '\ndo\n' + await readFile('tests/Recoil.spec.luau', 'utf8') + '\nend\n';
  bundle += '\ndo\n' + await readFile('tests/Speed.spec.luau', 'utf8') + '\nend\n';
  bundle += '\ndo\n' + await readFile('tests/BW.spec.luau', 'utf8') + '\nend\n';
  bundle += '\ndo\n' + await readFile('tests/BWBestEffort.spec.luau', 'utf8') + '\nend\n';
  await state.loadstring(bundle, 'input-tests', true)();
} finally {
  state.destroy();
}
