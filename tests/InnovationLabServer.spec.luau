local Hardware=require("BWChassis")
local Programs=require("PlaygroundPrograms")
local BW=require("BWController")
local function tanksNow()
 local count=0
 for _ in royale.options.tanks do count+=1 end
 return count
end
local arena
local walls,floors=0,0
for _,part in created do
 if part.Name=="Arena" then arena=part end
 if part.Name=="Boundary" then walls+=1 end
 if part.Name=="Floor" then floors+=1 end
 check(part.Name~="Target" and part.Name~="Rock" and part.Name~="CenterStick","lab has no Playground obstacles or targets")
end
check(arena:GetAttribute("StartupLayout")=="InnovationLab" and arena:GetAttribute("MapWidth")==150
 and arena:GetAttribute("MapDepth")==150 and walls==4 and floors==1,"the authoritative empty lab loads a 150-stud room")
check(network:GetAttribute("GameMode")=="InnovationLab" and tanksNow()==0 and controls[101].mode=="Menu","lab begins at an empty catalog")
local realClock=os.clock
local wall=realClock()
os.clock=function()return wall end
local requestId=0
local function request(action,id,epoch,frames)
 requestId+=1;wall+=1
 remote.OnServerEvent:Fire(first,action,requestId,id,epoch)
 advance(frames or 3)
end
request("Join","viper")
check(tanksNow()==0 and controls[101].mode=="Menu","unavailable technology cannot start an experiment")
request("Join","retaliator",nil,0)
check(tanksNow()==2 and controls[101].mode=="OnFoot","selecting a working technology spawns two tanks and grants on-foot control")
local mesh,opponent=royale.slots[1].tank,royale.slots[2].tank
check((mesh.state.position-opponent.state.position).Magnitude>35,"spawn points have room to engage")
check(Hardware.retaliatorOperational(mesh.hardware) and BW.running(mesh) and BW.running(opponent),"both programs run with the lab's preset equipment")
local crazy
for _,entry in Programs do if entry.id=="P02" then crazy=entry end end
check(opponent.personality==crazy and opponent.bwSource==crazy.source and not Hardware.retaliatorOperational(opponent.hardware),
 "lab reuses Crazy's exact packaged BW source without equipping it with lab gear")
remote.OnServerEvent:Fire(second,"Join",1,"retaliator")
check(controls[102].mode=="Menu" and tanksNow()==2,"another player cannot reset the owner's experiment")

opponent.state.turretPitch=math.rad(17)
opponent.rattler.cooldown=3
local triggered=false
local firstShotPitch
workspace.Spherecast=function(_,origin,_,delta,params)
 if not triggered and params.FilterDescendantsInstances[1]==opponent.hitbox then
  triggered=true
  firstShotPitch=math.deg(math.atan2(delta.Y,math.sqrt(delta.X^2+delta.Z^2)))
  return {Instance=mesh.hitbox,Position=origin+delta.Unit*.01,Distance=.01}
 end
end
advance(120)
check(opponent.rattler.cooldown>0 and not triggered and math.deg(opponent.state.turretPitch)<16,
 "Crazy starts correcting elevation while the Gatling is still cooling down")
for _=1,600 do
 if mesh.bw.events.sequence>0 then break end
 advance(1)
end
workspace.Spherecast=function()return nil end
check(triggered and mesh.state.health<100 and mesh.bw.events.sequence==1,"Crazy's actual shot drives the live Mesh producer and dispatcher")
check(math.abs(firstShotPitch)<=3,"Crazy corrects an elevated barrel before releasing a near-horizontal round")

local function approach(tank)
 roots[101].CFrame=CFrame.new(tank.state.position+Vector3.new(0,3,0))
end
local originalMesh=mesh.bw
approach(mesh);request("Enter",mesh.id,mesh.state.controlEpoch)
check(controls[101].selected==mesh.id and mesh.state.controlMode=="Manual" and originalMesh.status=="stopped" and not mesh.bw,
 "possession of the experimental tank stops its autonomous program")
request("Auto",mesh.id,mesh.state.controlEpoch)
check(mesh.bw and mesh.bw~=originalMesh and mesh.state.controlMode=="Auto" and Hardware.retaliatorOperational(mesh.hardware),
 "Auto starts the built-in experiment from a clean invocation")
request("Exit",mesh.id,mesh.state.controlEpoch)
check(controls[101].mode=="OnFoot" and BW.running(mesh),"exiting restores autonomous behavior")
local Motion=require("VehicleMotion")
local Recoil=require("RattlerRecoil")
opponent.state.position=Vector3.new(69,0,-10)
opponent.state.yaw=-math.pi/2
Motion.setVelocity(opponent.state,Vector3.new(26,0,0))
Recoil.kick(opponent.state,0,Vector3.new(-1,0,0))
advance(4)
approach(opponent);request("Enter",opponent.id,opponent.state.controlEpoch)
check(controls[101].selected==opponent.id and opponent.state.controlMode=="Manual" and not opponent.bw and not mesh.occupant,
 "the host can switch to Crazy while the previously occupied tank runs autonomously")
local reverse=require("InputCommand").neutral();reverse.throttle=-1
local beforeReverse=opponent.state.position.X
wall+=1;input.OnServerEvent:Fire(first,reverse,opponent.id,controls[101].epoch);advance(120)
check(opponent.state.grounded and opponent.state.position.X<beforeReverse-3,
 "a player can reverse Crazy off the wall after a recoil-driven collision")
opponent.state.position=Vector3.new(70,2,70)
opponent.state.yaw=-3*math.pi/4
opponent.state.lift=2
Motion.setVelocity(opponent.state,Vector3.new(16,-4,16))
wall+=1;input.OnServerEvent:Fire(first,reverse,opponent.id,controls[101].epoch);advance(120)
check(opponent.state.grounded and opponent.state.position.X<65 and opponent.state.position.Z<65,
 "manual reverse also clears a two-wall landing in a corner")

local priorId=mesh.id
for index=1,5 do
 local old={royale.slots[1].tank,royale.slots[2].tank}
 local invocations={old[1].bw,old[2].bw}
 request("Menu")
 check(tanksNow()==0 and controls[101].mode=="Menu" and #royale.slots==0,"returning to the catalog retires the experiment")
 for i,tank in old do
  local vm=invocations[i]
  check(tank.hitbox.destroyed and (not vm or vm.status=="stopped" and not vm.devices:busy()),"retired tank has no live BW or hitbox")
 end
 request("Join","retaliator",nil,if index==1 then 0 else nil)
 local nextTank=royale.slots[1].tank
 check(tanksNow()==2 and nextTank.id~=priorId and nextTank.bw.events.sequence==0,"restart replaces the roster with fresh IDs and a clean event runtime")
 if index==1 then
  request("Enter",old[1].id,old[1].state.controlEpoch)
  check(controls[101].mode=="OnFoot" and not nextTank.occupant,"an old experiment ID cannot acquire a new tank")
  local stuck=royale.slots[2].tank
  stuck.state.position=Vector3.new(70,0,-25)
  stuck.state.yaw=-math.pi/2
  stuck.rattler.cooldown=10
  local backedAway=false
  for _=1,360 do
   advance(1)
   local drive=stuck.bw.devices.devices.drivetrain.active
   if drive and drive.instruction.op=="back" and stuck.state.position.X<67 then
    backedAway=true
    break
   end
  end
  check(backedAway,"Crazy detects blocked forward progress and backs away from the boundary")
 end
 priorId=nextTank.id
end
local current=royale.slots[1].tank
approach(current);request("Enter",current.id,current.state.controlEpoch)
players.PlayerRemoving:Fire(first);advance(5)
check(tanksNow()==0 and #royale.slots==0 and current.hitbox.destroyed and not current.bw,"departure clears the lab world and occupants' controllers")
os.clock=realClock
print("Innovation Lab server integration passed: "..count.." assertions")
end
CFrame.new,CFrame.Angles,CFrame.lookAt=saveNew,saveAngles,saveLookAt
Instance.new,game.GetService=saveInstance,saveService
