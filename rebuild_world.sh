cd ~/battleworks

# Compile the updated tree JSON
node tools/build-world.js worlds/tree-test.json --output build/worlds/tree-test.json

# Register the updated world
node tools/register-worlds.js
