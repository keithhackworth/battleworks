local arena=workspace:FindFirstChild("Arena")
local worlds=network:FindFirstChild("PlayerWorlds")
check(worlds and worlds.OnServerInvoke,"production server exposes saved-world service")
local doc=require("WorldEditorDocument").fresh();doc.id="players_forest"
doc.spawns={{id="start_1",slot=1,position={-45,0,34.5},heading=90},{id="start_2",slot=2,position={45,0,34.5},heading=270},{id="start_3",slot=3,position={-70,0,-70},heading=0},{id="start_4",slot=4,position={70,0,-70},heading=0},{id="start_5",slot=5,position={0,0,80},heading=0}}
doc.objects={{id="wall_1",type="builtin.block",asset="Builtin/BW_block",position={0,0,34.5},rotation={0,0,0},scale=1,bounds={.01,.01,.01},solid=true,destructible=true,hp=75}}
doc.objects[2]={id="ramp_1",type="builtin.bridge",asset="Builtin/BW_bridge",position={0,8,-50},rotation={15,25,-5},scale=1,bounds={.01,.01,.01},solid=true,destructible=true,hp=75}
local result=worlds.OnServerInvoke(first,"Save",{document=doc,revision=0})
check(result.ok and result.temporary and result.document.objects[1].bounds[1]==8,"actual server saves a canonical world in Studio session")
check(arena:GetAttribute("WorldId")=="builder_demo","saving never mutates a running battle")
check(not worlds.OnServerInvoke(second,"Load",doc.id).ok,"production remote scopes saved layouts by player")
check(not worlds.OnServerInvoke(first,"Play",{id=doc.id,revision=1}).ok and arena:GetAttribute("WorldId")=="builder_demo","active battle cannot be replaced")
session.OnServerEvent:Fire(first,"Leave",2);session.OnServerEvent:Fire(second,"Leave",2);advance(61)
local oldScenery=arena:FindFirstChild("WorldScenery")
result=worlds.OnServerInvoke(first,"Play",{id=doc.id,revision=1})
check(result.ok and result.launch,"empty Studio battlefield accepts a validated saved-world launch")
check(oldScenery.destroyed and arena:GetAttribute("WorldId")==doc.id,"world swaps once after staging succeeds")
check(arena:GetAttribute("MapWidth")==230 and arena:GetAttribute("Weather")=="Normal","simulation and replication use saved world dimensions/weather")
local scenery=arena:FindFirstChild("WorldScenery")
local model=scenery:FindFirstChild("wall_1")
check(#scenery:GetChildren()==2 and model:GetAttribute("Health")==75 and model:GetAttribute("Destructible"),"saved world uses existing authoritative durability registry")
local proxy=model:FindFirstChild("WorldObstacleHitbox")
check(proxy and proxy.CanQuery and proxy.Size.X==8,"saved world creates existing projectile/scanner/collision proxy")
local rampModel=scenery:FindFirstChild("ramp_1")
local rampProxy=rampModel:FindFirstChild("WorldObstacleHitbox")
local loaded=worlds.OnServerInvoke(first,"Load",doc.id)
check(loaded.ok and loaded.document.objects[2].position[2]==8 and loaded.document.objects[2].rotation[1]==15 and loaded.document.objects[2].rotation[3]==-5,"save/load preserves elevated pitch/yaw/roll")
check(rampProxy.CFrame.Position.Y>8 and math.abs(rampProxy.CFrame.UpVector.Z)>.1,"saved tilted item loads with an elevated oriented collision proxy")
session.OnServerEvent:Fire(first,"Enter",3);advance(4)
check(snapshots[boomerId] and snapshots[rattlerId] and not snapshots["102"],"saved-world entry preserves owned tank collections without orphaned opponents")
check(math.abs(snapshots[boomerId].position.Z-34.5)<1e-5,"existing tank spawn code consumes saved settings")
command.throttle=1
for _=1,180 do tick(false)end
check(snapshots[boomerId].position.X< -5,"existing server physics blocks movement through player-authored scenery")
local areas=arena:FindFirstChild("Environment")
for slot=1,5 do
 local area=areas:FindFirstChild("StartingPosition"..slot)
 check(area and area:FindFirstChild("Number"..slot),"playable world retains numbered caution starting markings")
 for _,p in area:GetDescendants() do if p:IsA("BasePart") then check(not p.CanCollide and not p.CanQuery,"live starting markings cannot intercept tanks or bullets") end end
end
session.OnServerEvent:Fire(second,"Enter",3)
local third={UserId=103,Name="PlayerThree"};players.PlayerAdded:Fire(third);session.OnServerEvent:Fire(third,"Enter",1);advance(4)
check(snapshots["103"] and math.abs(snapshots["103"].position.X+70)<1e-5 and math.abs(snapshots["103"].position.Z+70)<1e-5,"third player's first tank starts at numbered area 3")
check(snapshots["103:Rattler"] and (snapshots["103:Rattler"].position-snapshots["103"].position).Magnitude>=12,"additional owned tank uses another bay in the same player's starting area")
players.PlayerRemoving:Fire(third);session.OnServerEvent:Fire(second,"Leave",4)
players.PlayerRemoving:Fire(first);advance(4)
check(not snapshots[boomerId] and not snapshots[rattlerId],"disconnect removes every owned tank from saved-world battle")
players.PlayerAdded:Fire(first)
check(#worlds.OnServerInvoke(first,"List").worlds==0,"Studio session saves cleaned when their owner disconnects")
print(string.format("Player worlds production server integration passed: %d assertions",count))
end -- server fixture
