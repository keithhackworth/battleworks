-- The production server entrypoint and normal player input/physics execute.
local arena=workspace:FindFirstChild("Arena")
check(arena:GetAttribute("WorldId")=="builder_demo","generated editor world selected by authoritative server")
check(arena:GetAttribute("MapWidth")==160 and arena:GetAttribute("MapDepth")==120,"world dimensions propagated to physics/camera attributes")
local floor=arena:FindFirstChild("Floor")
check(floor.Size.X==170 and floor.Size.Z==130 and floor.Material==Enum.Material.Sand,"authored ground applied")
local scenery=arena:FindFirstChild("WorldScenery")
check(scenery and #scenery:GetChildren()==3,"all generated native placements instantiated together")
check(math.abs(snapshots[boomerId].position.Z-20)<1e-6 and math.abs(snapshots[rattlerId].position.Z-20)<1e-6,"both tanks use authored spawn positions")
check(math.abs(snapshots["102"].position.Z-6)<1e-6,"second player pair uses separate deterministic spawn row")
command.throttle=1
for _=1,180 do tick(false)end
check(snapshots[boomerId].position.X< -5,"normal manual propulsion cannot drive through editor obstacle")
command.throttle=0
local beforeReset=snapshots[boomerId].generation
reset.OnServerEvent:Fire(first);advance(3)
if builderPublished then
 check(snapshots[boomerId].generation==beforeReset,"shared published battle rejects private world reset")
else
 check(math.abs(snapshots[boomerId].position.X+22)<1e-6 and math.abs(snapshots[boomerId].position.Z-20)<1e-6,"battle reset restores authored spawn rather than default arena layout")
end
local previousSize=arena:GetAttribute("MapWidth")
if redraw then redraw.OnServerEvent:Fire(first,Vector2.new(400,400));advance(2)end
check(arena:GetAttribute("MapWidth")==previousSize,"development resize cannot invalidate authored world and spawn validation")
print(string.format("Builder %s production integration passed: %d assertions",if builderPublished then "published" else "Studio",count))
end -- server fixture
