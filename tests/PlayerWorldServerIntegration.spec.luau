local arena=workspace:FindFirstChild("Arena")
local worlds=network:FindFirstChild("PlayerWorlds")
check(worlds and worlds.OnServerInvoke,"production server exposes saved-world service")
local doc=require("WorldEditorDocument").fresh();doc.id="players_forest"
local H=require("WorldHeightfield")
doc.settings.terrain=H.new(230,230)
H.brush(doc.settings.terrain,230,230,Vector3.new(-27,0,34.5),"Raise",20,7,1,0,1)
H.brush(doc.settings.terrain,230,230,Vector3.new(45,0,-35),"Lower",22,12,1,0,1)
doc.settings.terrain.water=table.create(doc.settings.terrain.columns*doc.settings.terrain.rows,0)
doc.settings.terrain.water[1]=H.WaterOffset+20
doc.settings.terrain.water[2]=H.WaterOffset+21
do
 local field=doc.settings.terrain
 local startX,startZ=H.cell(field,230,230,8,24)
 local endX,endZ=H.cell(field,230,230,24,48)
 for z=startZ,endZ do for x=startX,endX do
  field.water[z*field.columns+x+1]=H.WaterOffset+32
 end end
end
local savedHeights=table.concat(doc.settings.terrain.heights,",")
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
check(result.ok and result.launch,"empty Studio battlefield accepts a validated saved-world launch: "..tostring(result.message))
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
check(table.concat(loaded.document.settings.terrain.heights,",")==savedHeights,"server save and reload preserves the sculpted hill and pit exactly")
check(rampProxy.CFrame.Position.Y>8 and math.abs(rampProxy.CFrame.UpVector.Z)>.1,"saved tilted item loads with an elevated oriented collision proxy")
session.OnServerEvent:Fire(first,"Enter",3);advance(4)
check(snapshots[boomerId] and snapshots[rattlerId] and not snapshots["102"],"saved-world entry preserves owned tank collections without orphaned opponents")
check(math.abs(snapshots[boomerId].position.Z-34.5)<1e-5,"existing tank spawn code consumes saved settings")
command.throttle=1
local peak=snapshots[boomerId].position.Y
for _=1,180 do tick(false);peak=math.max(peak,snapshots[boomerId].position.Y)end
check(peak>2,"tank climbs the saved hill during the production playtest")
check(snapshots[boomerId].position.X< -5,"existing server physics blocks movement through player-authored scenery")
local areas=arena:FindFirstChild("Environment")
local surface=areas:FindFirstChild("AuthoredTerrain")
check(surface and #surface:GetChildren()>0 and not arena:FindFirstChild("Floor").CanQuery,"terrain displaces the flat collision floor")
local wedges=0
local shallow,deep
for _,part in surface:GetChildren() do
 if part.Name=="WaterSurface" then
  if not shallow or part.CFrame.Position.Y<shallow.CFrame.Position.Y then shallow=part end
  if not deep or part.CFrame.Position.Y>deep.CFrame.Position.Y then deep=part end
  continue
 end
 check(part.CanCollide and part.CanQuery,"terrain surfaces participate in engine collision and queries")
 if part.Shape==Enum.PartType.Wedge then wedges+=1 end
end
check(wedges>0,"raised and lowered ground generate native sloped triangle surfaces")
check(shallow and deep and shallow.CFrame.Position.Y<deep.CFrame.Position.Y and shallow.Color[1]>deep.Color[1],"water darkens as depth increases through the half-hull cutoff")
do
 local env=require("Environment").create(Vector2.new(230,230),"Normal")
 env.terrainSettings=loaded.document.settings
 local tank=Sim.new(Vector3.new(45,0,-35),"Rattler")
 local neutral=require("InputCommand").neutral()
 for _=1,120 do Sim.step(tank,neutral,1/60,Vector2.new(230,230),env) end
 check(tank.position.Y< -4 and math.abs(tank.position.Y-tank.groundHeight)<.05,
  "a tank settles on the saved pit below the old flat floor")
end
for slot=1,5 do
 local area=areas:FindFirstChild("StartingPosition"..slot)
 check(area and area:FindFirstChild("Number"..slot),"playable world retains numbered caution starting markings")
 for _,p in area:GetDescendants() do if p:IsA("BasePart") then check(not p.CanCollide and not p.CanQuery,"live starting markings cannot intercept tanks or bullets") end end
end
session.OnServerEvent:Fire(second,"Enter",3)
local third={UserId=103,Name="PlayerThree"};players.PlayerAdded:Fire(third);session.OnServerEvent:Fire(third,"Enter",1);advance(4)
check(snapshots["103"] and math.abs(snapshots["103"].position.X+70)<1e-5 and math.abs(snapshots["103"].position.Z+70)<1e-5,"third player's first tank starts at numbered area 3")
check(snapshots["103:Rattler"] and (snapshots["103:Rattler"].position-snapshots["103"].position).Magnitude>=12,"additional owned tank uses another bay in the same player's starting area")
do
 local entered
 for _=1,180 do
  time+=1/60;input.OnServerEvent:Fire(second,command,"102");heartbeat:Fire(1/60)
  if snapshots["102"].deepWaterRemaining then entered=snapshots["102"].position.X;break end
 end
 check(entered and snapshots["102"].health>0,"server starts the countdown as the tank drives into deep water")
 for _=1,60 do
  time+=1/60;input.OnServerEvent:Fire(second,command,"102");heartbeat:Fire(1/60)
 end
 check(snapshots["102"].health>0 and snapshots["102"].position.X<entered and snapshots["102"].deepWaterRemaining<3,"tank keeps driving while the server counts down")
 advance(135)
 check(snapshots["102"].health==0,"server destroys a tank that stays in deep water")
end
players.PlayerRemoving:Fire(third);session.OnServerEvent:Fire(second,"Leave",4)
players.PlayerRemoving:Fire(first);advance(4)
check(not snapshots[boomerId] and not snapshots[rattlerId],"disconnect removes every owned tank from saved-world battle")
players.PlayerAdded:Fire(first)
check(#worlds.OnServerInvoke(first,"List").worlds==0,"Studio session saves cleaned when their owner disconnects")
print(string.format("Player worlds production server integration passed: %d assertions",count))
end -- server fixture
