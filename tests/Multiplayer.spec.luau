-- Production server callbacks with mocked engine sweeps, never client hit claims.
check(snapshots["101"] and snapshots["102"] and snapshots["101:Rattler"] and snapshots["102:Rattler"],"multiple independently owned tanks per player are preserved")
check(battleStates["101"].multiplayer and battleStates["102"].multiplayer,"shared mode replicated")
check((snapshots["101"].position-snapshots["102"].position).Magnitude>=14,"unique safe spawns")
local Registry=require("TankRenderers")
local replicas={}
local function syncReplicas()
 Registry.sync(replicas,snapshots,function(id,kind,weapon)
  return {tankType=kind,weaponId=weapon,resetPose=function(self,state) self.position=state.position end,destroy=function(self) self.destroyed=true end}
 end)
end
syncReplicas()
local previousReplica=replicas["102"]
local start=snapshots["101"].position
input.OnServerEvent:Fire(second,{throttle=1,steer=0,fire=true,aimMode="Rate",turretX=1,turretY=0},"101")
bwRun.OnServerEvent:Fire(second,"forward(10)",1,"101")
network:FindFirstChild("BWHardware").OnServerEvent:Fire(second,{},"101")
advance(8)
check((snapshots["101"].position-start).Magnitude<1e-6 and not snapshots["101"].bwRunning,"foreign actions cannot control tank")
for _,bad in {false,{}, {throttle=0/0,steer=0,fire=true}, {throttle=1,steer=0,fire="yes"}} do input.OnServerEvent:Fire(first,bad,"101"); advance(3) end
check((snapshots["101"].position-start).Magnitude<1e-6,"invalid commands rejected")
local move={throttle=1,steer=0,fire=false,aimMode="Rate",turretX=1,turretY=0}
local neutral=require("InputCommand").neutral()
input.OnServerEvent:Fire(first,neutral,"101")
input.OnServerEvent:Fire(first,move,"101") -- same timestamp: rate limited
advance(4)
check((snapshots["101"].position-start).Magnitude<1e-6,"packet rate limit rejects same-timestamp commands")
local fake=require("InputCommand").neutral(); fake.damage=1000000; fake.hit="102"; fake.health=0
input.OnServerEvent:Fire(first,fake,"101"); advance(4)
check(snapshots["102"].health==100 and snapshots["101"].health==100,"extra client hit and health claims have no authority")
input.OnServerEvent:Fire(first,move,"101")
local yaw=snapshots["101"].turretYaw
advance(8)
check((snapshots["101"].position-start).Magnitude>0 and snapshots["101"].turretYaw~=yaw,"movement and turret replicated")
advance(120)
local stopped=snapshots["101"].position
advance(60)
check((snapshots["101"].position-stopped).Magnitude<0.01,"stale input expires and vehicle stops")
local boxes={}
for _,p in created do if p.Name=="TankHitbox" and not p.destroyed then boxes[p:GetAttribute("TankId")]=p end end
local hits=0
workspace.Spherecast=function(_,origin,radius,delta,params)
 if params.FilterDescendantsInstances[1]==boxes["101"] and hits<17 then
  hits+=1
  return {Instance=boxes["102"],Position=origin+delta.Unit*.01,Distance=.01}
 end
end
bwRun.OnServerEvent:Fire(first,"fire(8)",2,"101")
local dead=false
for _=1,550 do
 advance(1)
 if snapshots["102"].health<=0 then dead=true; break end
end
check(dead and hits==17,"server projectile damage destroys another player's tank")
check(not boxes["102"].CanQuery and snapshots["102"].fatalWeapon=="Gatling","wreck and damage attribution replicated")
local generation=snapshots["102"].generation
reset.OnServerEvent:Fire(second); advance(5)
check(snapshots["102"].health==0,"reset cannot bypass respawn delay")
local Settings=require("WorldSettings")
local savedBlocked=Settings.blocked
Settings.blocked=function() return true end -- engine-independent occupied-map fixture
advance(185)
check(snapshots["102"].health==0 and snapshots["102"].generation==generation and not boxes["102"].CanQuery,"occupied map defers respawn without reviving inside a body")
Settings.blocked=savedBlocked
advance(65)
check(snapshots["102"].health==100 and snapshots["102"].generation==generation+1 and boxes["102"].CanQuery,"automatic respawn restores health and hitbox with new generation")
check(not snapshots["102"].firing and not snapshots["102"].bwRunning,"respawn clears old control state")
syncReplicas()
check(previousReplica.destroyed and replicas["102"]~=previousReplica and replicas["102"].generation==generation+1,"respawn snapshot replaces renderer by generation")
local old=snapshots["102:Rattler"].generation
select.OnServerEvent:Fire(second,"Rattler"); advance(5)
check(battleStates["102"].selected=="102:Rattler" and snapshots["102:Rattler"].generation==old and snapshots["102"].health==100,"selection retains independent owned tanks and lifecycle")
local ownPosition=snapshots["102"].position
input.OnServerEvent:Fire(second,move,"102"); advance(5)
check((snapshots["102"].position-ownPosition).Magnitude<1e-6,"manual input only controls selected owned tank")
local retaliated=false
workspace.Spherecast=function(_,origin,radius,delta,params)
 if params.FilterDescendantsInstances[1]==boxes["102:Rattler"] and not retaliated then
  retaliated=true
  return {Instance=boxes["101:Rattler"],Position=origin+delta.Unit*.01,Distance=.01}
 end
end
bwRun.OnServerEvent:Fire(second,"fire()",1,"102:Rattler"); advance(80)
check(retaliated and snapshots["101:Rattler"].health==75,"second player damages first player through authoritative cannon impact")
local third={UserId=103,Name="Late"}
Settings.blocked=function() return true end
players.PlayerAdded:Fire(third); session.OnServerEvent:Fire(third,"Enter",1); advance(5)
check(snapshots["103"].waitingForSpawn and snapshots["103:Rattler"].waitingForSpawn,"late join waits safely when all spawn candidates are blocked")
local waitingPosition=snapshots["103"].position
advance(15)
check((snapshots["103"].position-waitingPosition).Magnitude==0 and snapshots["103"].health==0,"waiting tank does not enter movement/contact simulation")
Settings.blocked=savedBlocked
advance(185)
check(not snapshots["103"].waitingForSpawn and snapshots["103"].health==100 and snapshots["103:Rattler"].health==100,"late join retries safely when spawn space becomes available")
check(snapshots["103"] and snapshots["101"] and snapshots["102"],"late join snapshot includes running battle")
for _,id in {"101","102"} do check((snapshots["103"].position-snapshots[id].position).Magnitude>=14,"late join avoids existing tanks") end
workspace.Spherecast=function() return nil end
bwRun.OnServerEvent:Fire(first,"fire(8)",3,"101"); advance(3)
local inFlight={}
for _,p in created do if p.Name=="Shell_101" and not p.destroyed then table.insert(inFlight,p) end end
check(#inFlight>0,"disconnect fixture has live server projectiles")
local disconnectedReplica=replicas["101"]
players.PlayerRemoving:Fire(first); advance(5)
syncReplicas()
check(not replicas["101"] and not replicas["101:Rattler"] and disconnectedReplica.destroyed,"disconnect snapshot removes remote renderers")
for _,model in inFlight do check(model.destroyed,"disconnect destroys every owned in-flight projectile") end
check(not snapshots["101"] and not snapshots["101:Rattler"] and not battleStates["101"] and boxes["101"].destroyed and boxes["101:Rattler"].destroyed,"disconnect removes tank, hitbox and ownership")
players.PlayerAdded:Fire(first); session.OnServerEvent:Fire(first,"Enter",1); advance(5)
check(snapshots["101"] and snapshots["101"].health==100,"rejoin creates fresh owned tank")
players.PlayerRemoving:Fire(first); players.PlayerRemoving:Fire(second); players.PlayerRemoving:Fire(third); advance(5)
check(next(snapshots)==nil and next(battleStates)==nil,"all disconnects leave no tanks or battle state")
os.clock=savedClock
print(string.format("Multiplayer integration passed: %d assertions",count))
end
CFrame.new,CFrame.Angles,CFrame.lookAt=saveNew,saveAngles,saveLookAt
Instance.new,game.GetService=saveInstance,saveService
