-- Execute production model creation/animation with numeric transform stand-ins.
-- These assertions validate anchors/lifecycle, not rasterized Roblox appearance.
local count=0
local function check(ok,message) assert(ok,message); count+=1 end
local saveNew,saveAngles,saveLookAt= CFrame.new,CFrame.Angles,CFrame.lookAt
local saveInstance,saveService=Instance.new,game.GetService
local created,garbage={},{}
local identity={1,0,0,0,1,0,0,0,1}
local mt={}
local function frame(p,m) return setmetatable({p=p,m=m or identity},mt) end
local function rotate(m,v)
 return Vector3.new(m[1]*v.X+m[2]*v.Y+m[3]*v.Z,m[4]*v.X+m[5]*v.Y+m[6]*v.Z,m[7]*v.X+m[8]*v.Y+m[9]*v.Z)
end
mt.__index=function(f,key)
 if key=="Position" then return f.p end
 if key=="RightVector" then return Vector3.new(f.m[1],f.m[4],f.m[7]) end
 if key=="UpVector" then return Vector3.new(f.m[2],f.m[5],f.m[8]) end
 if key=="LookVector" then return Vector3.new(-f.m[3],-f.m[6],-f.m[9]) end
 if key=="PointToWorldSpace" then return function(self,v) return self.p+rotate(self.m,v) end end
end
mt.__mul=function(a,b)
 local m={}
 for row=0,2 do for col=0,2 do
  m[row*3+col+1]=0
  for k=0,2 do m[row*3+col+1]+=a.m[row*3+k+1]*b.m[k*3+col+1] end
 end end
 return frame(a.p+rotate(a.m,b.p),m)
end
CFrame.new=function(x,y,z) return frame(if type(x)=="number" then Vector3.new(x,y,z) else x or Vector3.zero) end
CFrame.Angles=function(x,y,z)
 local cx,sx,cy,sy,cz,sz=math.cos(x),math.sin(x),math.cos(y),math.sin(y),math.cos(z),math.sin(z)
 return frame(Vector3.zero,{1,0,0,0,cx,-sx,0,sx,cx})*frame(Vector3.zero,{cy,0,sy,0,1,0,-sy,0,cy})*frame(Vector3.zero,{cz,-sz,0,sz,cz,0,0,0,1})
end
CFrame.lookAt=function(position,target)
 local f=(target-position).Unit
 local r=Vector3.new(-f.Z,0,f.X).Unit
 local u=Vector3.new(r.Y*f.Z-r.Z*f.Y,r.Z*f.X-r.X*f.Z,r.X*f.Y-r.Y*f.X)
 return frame(position,{r.X,u.X,-f.X,r.Y,u.Y,-f.Y,r.Z,u.Z,-f.Z})
end
Vector3.one=Vector3.new(1,1,1)
Instance.new=function(class)
 local p=saveInstance(class)
 p.Play=function(self) self.played=true end
 p.Destroy=function(self)
  for _,child in self.children do child:Destroy() end
  self.destroyed=true; self.Parent=nil
 end
 setmetatable(p,{__newindex=function(self,key,value)
  rawset(self,key,value)
  if key=="Parent" and value and value.children then table.insert(value.children,self) end
 end})
 table.insert(created,p); return p
end
local tweenService={Create=function(_,p,info,goal) return {Play=function() end,Completed=signal()} end}
local debris={AddItem=function(_,p,lifetime) table.insert(garbage,{part=p,lifetime=lifetime}) end}
game.GetService=function(self,name)
 if name=="TweenService" then return tweenService end
 if name=="Debris" then return debris end
 return saveService(self,name)
end
local Renderer=require("TankRenderer")
local Sim=require("TankSimulation")
local function named(renderer,name)
 local matches={}
 for _,p in renderer.model:GetChildren() do if p.Name==name then table.insert(matches,p) end end
 return matches
end
local boomer=Renderer.new("boomer","Boomer")
local state=Sim.new(Vector3.zero)
boomer:resetPose(state); boomer:update(state,1/60)
check(#boomer.treads==56 and #named(boomer,"RoadWheel")==8,"Boomer keeps original treads and exposed wheels")
check(boomer.cannon.Size.X==6 and boomer.cannon.Size.Y==1.6,"Boomer cannon dimensions preserved")
check(boomer.chassis.Color[1]==245 and boomer.chassis.Color[2]==116,"Boomer retains orange paint")
boomer:fire(); boomer:update(state,0.1)
check(boomer.barrelBulge.Transparency<1 and boomer.recoil>0,"Boomer retains swelling and recoil")
boomer:update(state,0.3)
check(boomer.barrelBulge.Transparency==1 and boomer.cannon.Size.Y==1.6,"Boomer swelling restores original cannon")
state.bodyPitch=0.2; state.bodyRoll=0.1; state.bounce=0.3
boomer:resetPose(state); boomer:update(state,1/60)
check(boomer.muzzleFrame.LookVector.Y>0.15,"shared turret inherits suspension tilt")
local rattler=Renderer.new("rattler","Rattler")
local rs=Sim.new(Vector3.new(0,10,0),"Rattler"); rs.lift=10; rs.firing=true
rattler:resetPose(rs); rattler:update(rs,1/60)
check(#named(rattler,"GatlingBarrel")==6 and #named(rattler,"GatlingBore")==6,"Rattler has six recognizable Gatling tubes and bores")
check(rattler.chassis.Color[1]==25 and rattler.chassis.Color[2]==144,"Rattler has distinct green body")
check(#rattler.treads==0 and #named(rattler,"RoadWheel")==4 and #named(rattler,"ChunkyTire")==4,"Rattler has four wheels and no track belts")
local bore=named(rattler,"GatlingBore")[1]
local previous=bore.CFrame.Position
rattler:update(rs,0.1)
check((bore.CFrame.Position-previous).Magnitude>0.1,"Gatling barrels visibly rotate while firing")
check(named(rattler,"RoadWheel")[1].CFrame.Position.Y>11,"flight raises the complete tank including tracks")
local speed=rattler.rotorSpeed
rs.firing=false
for _=1,60 do rattler:update(rs,1/60) end
check(rattler.rotorSpeed<speed*0.01,"rotor coasts down after firing stops")
rs.position=Vector3.new(0,24,0); rs.bodyPitch=0; rs.bodyRoll=0
rattler:resetPose(rs); rattler:update(rs,1/60)
check(math.abs(rattler.muzzleFrame.LookVector.Y+math.sin(math.rad(35)))<1e-5,"airborne Gatling assembly visibly points down at configured launch angle")
rs.position=Vector3.new(0,10,0)
rs.bodyPitch=0; rs.bodyRoll=0; rs.aimRecoilYaw=0.06; rs.aimRecoilPitch=-0.03
rattler:resetPose(rs); rattler:update(rs,1/60)
local _,physicalDirection=Sim.shotPose(rs)
check((rattler.muzzleFrame.LookVector-physicalDirection).Magnitude<1e-6,"visible barrel and authoritative direction use the same recoil pose")
local beforeSpoke=named(rattler,"WheelSpoke")[1].CFrame.Position
rs.speed=10; rs.steeringAngle=0.4
for _=1,20 do rattler:update(rs,1/60) end
check((named(rattler,"WheelSpoke")[1].CFrame.Position-beforeSpoke).Magnitude>0.1,"Rattler's tires and visible spokes roll with travel")
local wheelDiscs=named(rattler,"RoadWheel")
check(math.abs(wheelDiscs[1].CFrame.RightVector.Z)>0.1 and math.abs(wheelDiscs[2].CFrame.RightVector.Z)<1e-5,"front wheels steer while rear wheels stay aligned")
-- Full vehicle roll must move the wheel silhouette, not just tilt hidden body panels.
rs.position=Vector3.new(0,4,0); rs.lift=4; rs.speed=0; rs.steeringAngle=0
rs.bodyPitch=0; rs.bodyRoll=0; rs.groundRoll=0; rs.flightRoll=0
rattler:resetPose(rs)
local originalPosition=rs.position
rattler:fire({serial=101,roll=math.rad(10)})
rattler:update(rs,1/60)
local left=named(rattler,"RoadWheel")[1].CFrame.Position.Y
local right=named(rattler,"RoadWheel")[3].CFrame.Position.Y
check(right-left>2,"positive shot jolt visibly lifts one wheel pair over two studs above the other")
check(rattler.chassis.CFrame.UpVector.X< -0.25 and rattler.turret.CFrame.UpVector.X< -0.25,"hull and turret share the pronounced roll")
local _,physical=Sim.shotPose(rs)
check((rattler.muzzleFrame.LookVector-physical).Magnitude<1e-6,"exaggerated body roll preserves authoritative barrel direction")
check((rattler.position-originalPosition).Magnitude<1e-6,"visual rocking does not change the approved sideways movement or hop height")
rattler:fire({serial=102,roll=-math.rad(10)})
rattler:update(rs,1/60)
left=named(rattler,"RoadWheel")[1].CFrame.Position.Y
right=named(rattler,"RoadWheel")[3].CFrame.Position.Y
check(left-right>2,"next opposite shot visibly rocks the entire vehicle the other way")
local hold=rattler.rockHold
rattler:fire({serial=101,roll=math.rad(10)})
check(rattler.visualRollKick<0 and rattler.rockHold==hold,"stale shot metadata cannot overwrite the newer lurch")
for _=1,120 do rattler:update(rs,1/60) end
check(math.abs(rattler.visualRollKick)<1e-5,"visual wrestling settles after firing stops")
Renderer.shot(Vector3.zero,Vector3.new(0,0,-1),"Rattler")
local sounds,smoke,flashes=0,0,0
for _,p in created do
 if p.ClassName=="Sound" and p.played then sounds+=1 end
 if p.Name=="RattlerSmoke" then smoke+=1 end
 if p.Name=="RattlerFlash" then flashes+=1 end
end
check(sounds==2 and smoke==1 and flashes==1,"Rattler emits layered audio, smoke and muzzle flash")
Renderer.shot(Vector3.zero,Vector3.new(0,0,-1),"Boomer")
local sparks=0
for _,p in created do if p.Name=="MuzzleSpark" then sparks+=1 end end
check(sparks==12,"Boomer keeps its twelve-spark muzzle burst")
rs.position=Vector3.zero; rs.lift=0; rs.landingSerial=1
rattler:update(rs,1/60)
check(rattler.position.Y==0,"Rattler landing snaps vertical pose to ground instead of smoothing the slam away")
local dust=0
for _,p in created do if p.Name=="RattlerLandingDust" then dust+=1 end end
check(dust==8,"hard landing emits a pronounced radial dust burst")
rattler:update(rs,1/60)
local repeatedDust=0
for _,p in created do if p.Name=="RattlerLandingDust" then repeatedDust+=1 end end
check(repeatedDust==8,"landing effects happen once per landing")
for _,item in garbage do check(item.lifetime<=0.8,"weapon effects have bounded cleanup time"); item.part:Destroy() end
state.health=25; boomer:update(state,1/60)
check(boomer.healthLabel.Text:find("25/100",1,true)~=nil and boomer.healthBar.Size.X.Scale==0.25,"numeric HP and proportional health bar follow snapshot")
state.health=0; boomer:update(state,1/60)
local deathPuffs=0
for _,p in created do if p.Name=="TankDestruction" then deathPuffs+=1 end end
check(deathPuffs==16 and boomer.chassis.Transparency==0 and boomer.chassis.Color[1]==117,"death emits exaggerated burst and leaves visible wreck")
boomer:update(state,1/60)
local again=0
for _,p in created do if p.Name=="TankDestruction" then again+=1 end end
check(again==deathPuffs and boomer.healthBar.Size.X.Scale==0,"wreck does not repeat explosion on later snapshots")
-- Whole assemblies stay together while the turret and wheels separate from hull.
check(#boomer.death.groups==11,"Boomer ejects turret, eight road wheels and both tread assemblies")
local turretStart=boomer.turret.CFrame.Position
local wheelStart=named(boomer,"RoadWheel")[1].CFrame.Position
for _=1,24 do boomer:update(state,1/60) end
check(boomer.turret.CFrame.Position.Y-turretStart.Y>10,"turret flies dramatically above hull")
check((named(boomer,"RoadWheel")[1].CFrame.Position-wheelStart).Magnitude>3,"road wheels scatter visibly")
check(boomer.chassis.Color[1]==boomer.chassis.Color[2]-3 and boomer.cannon.Color[1]==117,"hull and detached weapon are grey")
local shapes=0
for _,p in created do
 if p.Name=="TankFireball" or p.Name=="TankShockwave" then
  shapes+=1; check(p.Anchored and not p.CanQuery and not p.CanCollide,"blast cannot affect authoritative collisions")
 end
end
check(shapes==2,"one large fireball and expanding shockwave per death")
for _=1,240 do boomer:update(state,1/60) end
local settled=boomer.turret.CFrame.Position
boomer:update(state,1/60)
check((boomer.turret.CFrame.Position-settled).Magnitude<1e-6,"flying turret falls, bounces and settles without endless motion")
check(boomer.barrelBulge.Transparency==1,"wreck cannot show firing bulges")
rs.health=0; rattler:update(rs,1/60)
check(#rattler.death.groups==5,"Rattler ejects complete Gatling turret and all four tire assemblies")
for _=1,18 do rattler:update(rs,1/60) end
check(rattler.turret.CFrame.Position.Y>12,"Rattler turret also launches well above chassis")
rs.health=100; rattler:update(rs,1/60)
check(rattler.death==nil and rattler.chassis.Color[1]==25,"restored health restores green model and animation anchors")
local wreckPart=boomer.death.groups[1].parts[1].part
boomer:destroy(); rattler:destroy()
check(boomer.model.destroyed and rattler.model.destroyed and bore.destroyed and wreckPart.destroyed,"model destruction removes all attached barrel geometry")
-- Progressive mixed injuries and weapon-selected collapse, using real model pieces.
do
 local Effects=require("DamageEffects")
 local damaged=Renderer.new("injured","Boomer")
 local injury=Sim.new(Vector3.zero,"Boomer"); local schedule=Effects.new(injury)
 damaged:resetPose(injury); damaged:update(injury,1/60)
 injury.health=50; Effects.record(schedule,injury,"Cannon",50,Vector3.new(0,2,0))
 for _=1,60 do Effects.step(schedule,injury,1/60); damaged:update(injury,1/60) end
 check(injury.smokeBurst and damaged.smokeFolder and damaged.smokeEmitters,"replicated cannon injury creates native smoke emitters")
 local dense=damaged.smokeEmitters.dense
 local volume=damaged.smokeVolume
 local armor=damaged.turret:GetAttribute("ArmorSize")
 check(volume.Transparency==1 and not volume.CanQuery and not volume.CanCollide,"emission volume is invisible and cannot block combat")
 check((volume.CFrame.Position-damaged.turret.CFrame.Position).Magnitude<0.5,"smoke is centered on turret rather than cannon muzzle")
 check(volume.Size.X>armor.X and volume.Size.Y>armor.Y and volume.Size.Z>armor.Z,"smoke blankets complete turret bounds including edges and base")
 check(dense.Texture:find("smoke_main.dds",1,true) and dense.ShapeStyle==Enum.ParticleEmitterShapeStyle.Volume,"textured smoke emits throughout turret volume")
 check(dense.Enabled and dense.emitted==28 and dense.Rate==48,"burst starts with bounded fill and continuous soft billowing")
 check(dense.Transparency.Keypoints[1].Value==1 and dense.Transparency.Keypoints[3].Value==1 and dense.Size.Keypoints[3].Value>dense.Size.Keypoints[1].Value,"smoke expands and fades at both ends without solid sphere outlines")
 check(dense.Acceleration.Y>0 and dense.RotSpeed.Min<0 and dense.RotSpeed.Max>0,"smoke drifts upward with varied sprite rotation")
 local emitted=dense.emitted
 damaged:update(injury,1/60)
 check(dense.emitted==emitted,"ordinary render updates cannot repeatedly refill burst")
 injury.smokeBurst=false; damaged:update(injury,1/60)
 check(not dense.Enabled and dense.Rate==0 and dense.clearCalls==1,"dense smoke clears immediately for server recovery interval")
 local stream=damaged.smokeEmitters.wisps
 check(stream.Enabled and stream.Rate==9 and stream.Parent==damaged.smokeVent,"continuous engine stream remains on between big puffs")
 check(not stream.LockedToPart and stream.Lifetime.Min==1.2,"smoke stream trails behind a moving tank instead of moving with the turret")
 check(math.abs(volume.Size.X-(armor.X+1.6)*1.2)<1e-6 and math.abs(dense.Size.Keypoints[2].Value-5.8*1.2)<1e-6,"big puff emission bounds and sprite sizes are both twenty percent larger")
 injury.smokeSeverity=0; damaged:update(injury,1/60)
 check(volume.destroyed and damaged.smokeFolder==nil,"smoke severity reset destroys native emitters and volume")
 injury.smokeSeverity=1; injury.smokeBurst=true; damaged:update(injury,1/60)
 check(damaged.smokeEmitters.dense.Size~=nil and damaged.smokeEmitters.dense.emitted==28,"recreated emitters restore appearance and bounded initial fill")
 injury.health=25; Effects.record(schedule,injury,"Gatling",25,Vector3.new(0,3,0)); Effects.step(schedule,injury,1/60)
 injury.immobilized=true
 local physics=injury.position
 damaged:update(injury,1/60)
 check(#damaged.holes>0 and #damaged.holes<=36,"attributed Gatling hits accumulate bounded bullet scars")
 local _,expected=Sim.shotPose(injury)
 check((damaged.muzzleFrame.LookVector-expected).Magnitude<1e-6 and injury.position==physics and injury.yaw==0,"rattling changes cosmetic panels without changing aiming or authoritative pose")
 local fireballs=0
 for _,p in created do if p.Name=="TankFireball" then fireballs+=1 end end
 injury.health=0; Effects.record(schedule,injury,"Gatling",25,Vector3.zero)
 damaged:update(injury,1/60)
 local maximum=damaged.turret.CFrame.Position.Y
 for _=1,120 do damaged:update(injury,1/60); maximum=math.max(maximum,damaged.turret.CFrame.Position.Y) end
 local afterFireballs,clinks=0,0
 for _,p in created do
  if p.Name=="TankFireball" then afterFireballs+=1 end
  if p.Name=="FinalClink" and p.played then clinks+=1 end
 end
 check(damaged.death.collapse and afterFireballs==fireballs,"Gatling fatal hit selects collapse with no cannon explosion")
 check(maximum<7 and damaged.chassis.CFrame.Position.Y<1.1,"turret falls off instead of launching; chassis drops onto belly")
 check(#damaged.holes==36 and clinks==1,"Swiss-cheese wreck retains perforations and finishes with one metallic clink")
 check(damaged.smokeFolder==nil and damaged.DamageClatter==nil and damaged.EngineSputter==nil,"death immediately removes injury smoke and live status audio")
 local green=Renderer.new("green-smoke","Rattler")
 local greenState=Sim.new(Vector3.new(20,0,0),"Rattler")
 greenState.health=10; greenState.smokeSeverity=3; greenState.smokeStrength=1; greenState.smokeBurst=true
 green:resetPose(greenState); green:update(greenState,1/60)
 local greenArmor=green.turret:GetAttribute("ArmorSize")
 check(green.smokeVolume.Size.X>greenArmor.X and green.smokeVolume.Size.Z>greenArmor.Z,"native smoke also envelopes Rattler's complete turret")
 greenState.position=Vector3.new(30,0,0); greenState.turretYaw=1.2; green:update(greenState,1/60)
 check((green.smokeVolume.CFrame.Position-green.turret.CFrame.Position).Magnitude<0.5 and green.smokeEmitters.dense.LockedToPart,"blanket follows moving/aiming turret instead of trailing at muzzle")
 check(green.smokeEmitters.dense.Rate*green.smokeEmitters.dense.Lifetime.Max+green.smokeEmitters.dense.emitted<100,"dense particle population has a bounded sub-100 budget per tank")
 local oldVolume=green.smokeVolume
 greenState.smokeSeverity=0; greenState.smokeBurst=false; green:update(greenState,1/60)
 check(oldVolume.destroyed and green.smokeEmitters==nil,"reset removes smoke volume and both emitters")
 green:destroy()
 local mark=damaged.holes[#damaged.holes]
 check((mark.hole.CFrame.Position-(mark.host.CFrame*mark.offset).Position).Magnitude<1e-6,"bullet scars follow detached turret/hull pieces")
 local holePart=mark.hole; local deathGroupPart=damaged.death.groups[1].parts[1].part
 damaged:destroy()
 check(holePart.destroyed and deathGroupPart.destroyed,"reset/model cleanup removes scars and collapsed assemblies")
end
-- Boot and exercise the production server entrypoint with two simulated players.
do
 local savedClock=os.clock
 local time=10
 os.clock=function() return time end
 local players={PlayerAdded=signal(),PlayerRemoving=signal()}
 local first={UserId=101}; local second={UserId=102}
 players.GetPlayers=function() return {first,second} end
 local heartbeat=signal()
 local shots,prepared,snapshots,battleStates={}, {}, {}, {}
 local oldFactory=Instance.new
 Instance.new=function(class)
  local p=oldFactory(class)
  p.FindFirstChild=function(self,name)
   for _,child in self.children do if child.Name==name and not child.destroyed then return child end end
  end
  if class=="RemoteEvent" then
   p.OnServerEvent=signal()
   p.FireAllClients=function(self,...)
    local args={...}
    if self.Name=="Shot" then table.insert(shots,{time=time,id=args[1],kind=args[4],origin=args[2],direction=args[3],rock=args[6]}) end
    if self.Name=="PrepareShot" then table.insert(prepared,{time=time,id=args[1]}) end
    if self.Name=="Snapshot" then
     battleStates=args[2] or {}; snapshots={}; for id,state in args[1] do
      snapshots[id]=table.clone(state)
      for _,hitbox in created do
       if hitbox.Name=="TankHitbox" and not hitbox.destroyed and hitbox:GetAttribute("TankId")==id then
        check((hitbox.CFrame.Position-(state.position+Vector3.new(0,2.5,0))).Magnitude<1e-6,"hitbox matches actual simulated recoil position at snapshot")
       end
      end
     end
    end
   end
  end
  return p
 end
 local originalWorkspaceFind=workspace.FindFirstChild
 workspace.FindFirstChild=function(self,name)
  for _,child in self.children do if child.Name==name and not child.destroyed then return child end end
 end
 workspace.GetPartBoundsInRadius=function() return {} end
 workspace.Spherecast=function() return nil end
 game.GetService=function(self,name)
  if name=="Players" then return players end
  if name=="ReplicatedStorage" then return game.ReplicatedStorage end
  if name=="RunService" then return {Heartbeat=heartbeat,IsStudio=function() return true end} end
  if name=="TweenService" then return tweenService end
  if name=="Debris" then return debris end
  return saveService(self,name)
 end
 game.ReplicatedStorage.WaitForChild=function(self,name) return self[name] end
 require("ServerEntrypoint")
 local network
 for _,p in created do if p.Name=="TankNetwork" and not p.destroyed then network=p end end
 local input=network:FindFirstChild("Input")
 local select=network:FindFirstChild("SelectTank")
 local bwRun,bwStop=network:FindFirstChild("BWRun"),network:FindFirstChild("BWStop")
 local reset=network:FindFirstChild("ResetBattle")
 local redraw=network:FindFirstChild("RedrawMap")
 local boomerId,rattlerId="101","101:Rattler"
 local command={throttle=0,steer=0,fire=false,aimMode="Rate",turretX=0,turretY=0}
 local function advance(frames)
  for _=1,frames do time+=1/60; heartbeat:Fire(1/60) end
 end
 local function selected() return battleStates["101"].selected end
 local function tick(fire)
  time+=1/60; command.fire=fire
  input.OnServerEvent:Fire(first,command,selected()); heartbeat:Fire(1/60)
 end
 advance(4)
 check(snapshots[boomerId].tankType=="Boomer" and snapshots[rattlerId].tankType=="Rattler","both tank types exist together")
 check(snapshots[boomerId].health==100 and snapshots[rattlerId].health==100,"both tanks start with 100 HP")
 check((snapshots[boomerId].position-snapshots[rattlerId].position).Magnitude>10,"battle pair has separate spawns")
 check(math.abs(snapshots[boomerId].yaw+snapshots[rattlerId].yaw)<1e-6,"battle pair faces inward")
 local generation=snapshots[boomerId].generation
 local idleRattler=snapshots[rattlerId].position
 tick(false)
 for _=1,100 do tick(true) end
 check(#prepared>=2 and #shots>=2,"production Boomer prepares and releases shells")
 check(shots[1].kind=="Boomer" and shots[1].time-prepared[1].time>=0.2-1e-5,"Boomer production windup stays 0.20 seconds")
 check(math.abs(snapshots[boomerId].aimRecoilYaw or 0)>0,"Boomer shell release kicks its actual turret")
 local originalCount=#shots
 select.OnServerEvent:Fire(first,"Rattler")
 for _=1,5 do tick(false) end
 local start=time
 for _=1,183 do tick(true) end
 check(snapshots[rattlerId].lift>=0 and snapshots[rattlerId].lift<=6,"Rattler hops within six studs while firing")
 check(snapshots[rattlerId].weaponCooldown>1.9,"Rattler enters two-second lockout")
 local rapid=0
 for i=originalCount+1,#shots do
  check(shots[i].kind=="Rattler" and shots[i].time-start<=3+1e-5,"only Rattler rounds during allowed burst")
  rapid+=1
 end
 check(rapid>=28 and rapid<=30,"production server preserves rapid projectile rate")
 check(shots[originalCount+1].rock and math.abs(shots[originalCount+1].rock.roll)>0.1,"release event carries physical roll")
 check((shots[originalCount+1].direction-shots[originalCount+2].direction).Magnitude>0.005,"Rattler rounds use turret recoil direction")
 local lockedShots=#shots
 for _=1,114 do tick(true) end
 check(#shots==lockedShots,"held trigger blocked during lockout")
 for _=1,10 do tick(true) end
 check(#shots>lockedShots,"fire resumes after full lockout")
 select.OnServerEvent:Fire(first,"Boomer"); advance(5)
 check(snapshots[boomerId].generation==generation and snapshots[boomerId].tankType=="Boomer","selection preserves existing Boomer model generation")
 check(snapshots[rattlerId].lift>0,"unselected Rattler remains airborne and simulated")
 advance(240)
 check(snapshots[rattlerId].lift==0 and not snapshots[rattlerId].firing,"unselected tank releases manual trigger and lands")
 select.OnServerEvent:Fire(first,{tankType="Rattler"}); advance(4)
 check(selected()==boomerId,"malformed selection rejected")
 local function fresh()
  advance(40); reset.OnServerEvent:Fire(first); advance(4)
 end
 local request=0
 local function run(id,source)
  request+=1; bwRun.OnServerEvent:Fire(first,source,request,id); return request
 end
 local function stop(id)
  request+=1; bwStop.OnServerEvent:Fire(first,request,id)
 end
 for _,id in {boomerId,rattlerId} do
  fresh()
  local before=#shots
  run(id,require("BWConfig").DefaultSource)
  for _=1,6000 do
   advance(1)
   if snapshots[id].bwStatus and snapshots[id].bwStatus~="running" then break end
  end
  check(snapshots[id].bwStatus=="completed","production BW demo completes on "..id..": "..tostring(snapshots[id].bwMessage))
  check(#shots-before>0,"production BW demo fires normal weapon on "..id)
 end
 fresh()
 local startPose=snapshots[boomerId].position
 local heading=snapshots[boomerId].yaw
 run(boomerId,"forward(100)")
 command.throttle=-1; command.steer=1
 for _=1,10 do tick(true) end
 check((snapshots[boomerId].position-startPose).Magnitude>0 and math.abs(snapshots[boomerId].yaw-heading)<1e-8,"manual inputs cannot override BW")
 select.OnServerEvent:Fire(first,"Rattler"); advance(5)
 check(snapshots[boomerId].bwRunning and selected()==rattlerId,"switch preserves unselected tank program")
 local currentBoomer=snapshots[boomerId].position
 command.throttle=1; command.steer=0
 for _=1,12 do tick(false) end
 check((snapshots[boomerId].position-currentBoomer).Magnitude>0 and (snapshots[rattlerId].position-idleRattler).Magnitude>0,"manual driving and other tank BW coexist")
 run(rattlerId,"fire(2)"); advance(5)
 check(snapshots[boomerId].bwRunning and snapshots[rattlerId].bwRunning,"two BW runtimes run simultaneously")
 stop(rattlerId); advance(5)
 check(not snapshots[rattlerId].bwRunning and snapshots[boomerId].bwRunning,"Stop affects only intended tank")
 stop(boomerId); advance(5)
 check(snapshots[boomerId].speed==0 and not snapshots[boomerId].firing,"Stop releases throttle and trigger")
 fresh()
 local before=snapshots[boomerId].position
 input.OnServerEvent:Fire(first,command,boomerId); advance(8)
 check((snapshots[boomerId].position-before).Magnitude<1e-6,"stale manual input for unselected tank is rejected")
 run(boomerId,"fire()"); advance(1); stop(boomerId)
 local stoppedShots=#shots; advance(30)
 check(#shots==stoppedShots,"Stop cancels prepared Boomer shot")
 request+=2; bwStop.OnServerEvent:Fire(first,request,boomerId)
 bwRun.OnServerEvent:Fire(first,"fire(2)",request-1,boomerId); advance(5)
 check(not snapshots[boomerId].bwRunning and snapshots[boomerId].bwRequestId==request,"late Run cannot overtake Stop")
 bwRun.OnServerEvent:Fire(second,"forward(3)",999,boomerId); advance(5)
 check(snapshots[boomerId].bwRequestId==request,"other player cannot control this tank by explicit id")
 -- The production projectile impact path, with engine sweeps returning chosen hits.
 local hitboxes={}
 for _,p in created do if p.Name=="TankHitbox" and not p.destroyed then hitboxes[p:GetAttribute("TankId")]=p end end
 local targetId,shooterId,remainingHits
 workspace.Spherecast=function(_,origin,radius,delta,params)
  local source=params.FilterDescendantsInstances[1]
  if remainingHits and remainingHits>0 and source==hitboxes[shooterId] then
   remainingHits-=1
   return {Instance=hitboxes[targetId],Position=origin+delta.Unit*0.01,Distance=0.01}
  end
 end
 fresh()
 targetId,shooterId,remainingHits=rattlerId,boomerId,1
 run(boomerId,"fire()"); advance(50)
 check(snapshots[rattlerId].damageByWeapon.Cannon==25 and snapshots[rattlerId].damageSerial==1,"production impact replicates weapon attribution and hit serial")
 check(snapshots["102"].damageSerial==0 and snapshots["102:Rattler"].damageSerial==0,"other owner receives independent injury state")
 check(snapshots[rattlerId].health==75 and snapshots[boomerId].health==100,"Boomer projectile damages only opponent by existing 25 damage")
 advance(20)
 check(snapshots[rattlerId].health==75,"one projectile cannot damage twice")
 fresh()
 targetId,shooterId,remainingHits=boomerId,boomerId,1
 run(boomerId,"fire()"); advance(50)
 check(snapshots[boomerId].health==100,"self-damage blocked even if query returns own hitbox")
 fresh()
 targetId,shooterId,remainingHits=boomerId,rattlerId,1
 run(rattlerId,"fire()"); advance(35)
 check(snapshots[boomerId].damageByWeapon.Gatling==6 and snapshots[boomerId].smokeSeverity==0,"production Gatling damage does not create cannon smoke")
 check(snapshots[boomerId].health==94,"Rattler retains six damage per shot")
 fresh()
 targetId,shooterId,remainingHits=boomerId,rattlerId,9
 run(rattlerId,"fire(0.9)")
 select.OnServerEvent:Fire(first,"Boomer"); advance(4)
 command.throttle=0; command.steer=0; command.turretX=0; tick(false)
 for _=1,150 do advance(1); if snapshots[boomerId].immobilized then break end end
 check(snapshots[boomerId].health==46 and snapshots[boomerId].immobilized,"production server schedules first Gatling immobilization at injured HP")
 local jamStart=time
 local jamPosition=snapshots[boomerId].position
 local jamYaw=snapshots[boomerId].yaw
 command.throttle=1; command.steer=1; command.turretX=0.5
 tick(false)
 for _=1,13 do tick(true) end
 check((snapshots[boomerId].position-jamPosition).Magnitude<1e-6 and snapshots[boomerId].yaw==jamYaw,"production manual throttle/steering suppressed during immobilization")
 check((snapshots[boomerId].weaponActivationSerial or 0)>0 and snapshots[boomerId].turretYaw~=jamYaw,"production victim can aim and activate weapon while immobilized")
 for _=1,30 do if not snapshots[boomerId].immobilized then break end; advance(1) end
 check(time-jamStart>=0.25 and time-jamStart<=0.36,"production scheduler advances once per simulation tick and preserves 0.3-second duration")
 command.steer=0; command.turretX=0
 for _=1,8 do tick(false) end
 check((snapshots[boomerId].position-jamPosition).Magnitude>0.1,"manual mobility resumes automatically after episode")
 command.throttle=0
 fresh()
 targetId,shooterId,remainingHits=rattlerId,boomerId,4
 run(rattlerId,"forward(100)"); run(boomerId,"fire(3)"); advance(190)
 check(snapshots[rattlerId].health==0 and battleStates["101"].winner=="Boomer","four cannon impacts destroy tank and announce winner")
 check(snapshots[rattlerId].fatalWeapon=="Cannon" and not snapshots[rattlerId].immobilized and not snapshots[rattlerId].smokeBurst,"production death records fatal weapon and stops statuses")
 check(not snapshots[rattlerId].bwRunning and not snapshots[rattlerId].firing and not hitboxes[rattlerId].CanQuery,"destruction stops BW, clears inputs and disables damage queries")
 local deathShots=#shots
 run(rattlerId,"fire(2)"); advance(220)
 check(snapshots[rattlerId].health==0 and not snapshots[rattlerId].bwRunning and #shots==deathShots,"wreck cannot fire or automatically respawn")
 fresh()
 check(next(snapshots[rattlerId].damageByWeapon)==nil and snapshots[rattlerId].fatalWeapon==nil and snapshots[rattlerId].smokeSeverity==0 and not snapshots[boomerId].immobilized,"production reset clears attribution and both injury channels")
 check(snapshots[boomerId].health==100 and snapshots[rattlerId].health==100 and not battleStates["101"].winner,"reset restores both HP and clears winner")
 check((snapshots[rattlerId].lift or 0)==0 and snapshots[rattlerId].heat==0 and snapshots[rattlerId].weaponCooldown==0,"reset clears recoil, heat and cooldown")
 check(not snapshots[boomerId].bwRunning and not snapshots[rattlerId].bwRunning and hitboxes[rattlerId].CanQuery,"reset stops both programs and restores hitboxes")
 local expected,yaw=require("LocalBattle").pose(Vector2.new(230,230),1,"Rattler")
 check((snapshots[rattlerId].position-expected).Magnitude<0.01 and snapshots[rattlerId].yaw==yaw,"reset restores original spawn and heading")
 local shellModels=0
 for _,p in created do if p.ClassName=="Model" and p.Name:sub(1,6)=="Shell_" and not p.destroyed then shellModels+=1 end end
 check(shellModels==0,"battle reset removes active projectiles")
 run(boomerId,"forward(100)"); run(rattlerId,"forward(100)"); advance(5)
 redraw.OnServerEvent:Fire(first,Vector2.new(230,230)); advance(5)
 check(not snapshots[boomerId].bwRunning and not snapshots[rattlerId].bwRunning and snapshots[boomerId].bwMessage=="Map redrawn.","redraw resets both programs")
 players.PlayerRemoving:Fire(first); advance(5)
 check(snapshots[boomerId]==nil and snapshots[rattlerId]==nil and snapshots["102"]~=nil and snapshots["102:Rattler"]~=nil,"departure removes only owner's pair")
 local liveHitboxes=0
 for _,p in created do if p.Name=="TankHitbox" and not p.destroyed then liveHitboxes+=1 end end
 check(liveHitboxes==2,"selection keeps two hitboxes per player and departure cleans both")
 print("Production battle integration passed: persistent pair, independent controls/BW, damage/death, switching/reset, ownership and cleanup")

 heartbeat=nil
 Instance.new=oldFactory; os.clock=savedClock; workspace.FindFirstChild=originalWorkspaceFind
 print("Production server integration passed: Boomer windup, Rattler burst/flight/cooldown, switch, ownership and cleanup")
end

Instance.new=saveInstance; game.GetService=saveService
CFrame.new=saveNew; CFrame.Angles=saveAngles; CFrame.lookAt=saveLookAt
print(string.format("Renderer suite passed: %d assertions",count))
