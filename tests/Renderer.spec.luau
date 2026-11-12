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
 setmetatable(p,{__index=function(self,key)
  if key=="CFrame" and rawget(self,"Position") then return CFrame.new(self.Position) end
 end,__newindex=function(self,key,value)
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
state.health=150; state.maxHealth=200; boomer:update(state,1/60)
check(boomer.healthLabel.Text:find("150/200",1,true) and boomer.healthBar.Size.X.Scale==0.75,"health display uses replicated component durability")
state.health=100; state.maxHealth=100
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
-- Completed observations alone drive harmless sensor decorations and decay.
do
 local Visual=require("ScannerVisual")
 local renderer=Renderer.new("scanner-visual","Boomer")
 local state=Sim.new(Vector3.zero); renderer:resetPose(state); renderer:update(state,1/60)
 check(#renderer.scannerSensors==8 and renderer.scannerSensors[1].Size.X==1.3,"eight enlarged scanner lenses remain visible when idle")
 for _,p in renderer.scannerSensors do check(not p.CanQuery and not p.CanCollide and not p.CanTouch,"sensor cannot affect bullets, rays or movement") end
 local event={serial=1,angle=90,kind="tank",affiliation="enemy",proximity=0.2,remaining=1.2}
 state.scanVisual=event
 renderer:update(state,1/60)
 check(renderer.scannerSensors[3].Material==Enum.Material.Neon and renderer.scannerSensors[3].Size.X==1.6 and renderer.scannerSensors[1].Material~=Enum.Material.Neon,"only requested directional sensor reacts to completed scan")
 local lens=renderer.scannerSensors[3]
 -- Compare the exact same visual phase with far and close observations.
 local base=CFrame.new(0,0,0)
 renderer.sensorClock=0.1; lens.CFrame=base; Visual.update(renderer,state,1/60)
 local far=lens.CFrame.Position.Magnitude
 state.scanVisual={serial=2,angle=90,kind="tank",affiliation="enemy",proximity=1,remaining=1.2}
 renderer.sensorClock=0.1; lens.CFrame=base; Visual.update(renderer,state,1/60)
 check(lens.CFrame.Position.Magnitude>far*20 and lens.Color[2]<30,"close enemy scan turns sensor red with exaggerated trembling")
 state.scanVisual={serial=3,angle=90,kind="tank",affiliation="teammate",proximity=1,remaining=1.2}
 renderer:update(state,1/60)
 check(lens.Color[2]>200 and lens.Color[3]>200,"friendly scan uses distinct cyan indication")
 state.scanVisual={serial=4,angle=90,kind="wall",proximity=1,remaining=1.2}; renderer:update(state,1/60)
 check(lens.Color[1]==165 and lens.Color[2]==169,"wall scan gives subtle neutral indication")
 state.scanVisual={serial=40,angle=90,kind="object",proximity=1,remaining=1.2}; renderer:update(state,1/60)
 check(lens.Color[1]==255 and lens.Color[2]==220 and lens.Color[3]==35 and lens.Material==Enum.Material.Neon,"object detection flashes yellow rather than enemy red")
 state.scanVisual={serial=5,angle=90,kind="none",proximity=0,remaining=1.2}; renderer:update(state,1/60)
 check(lens.Color[3]==220,"empty completed scan gives blue search pulse")
 for _=1,100 do renderer:update(state,1/60) end
 check(lens.Material==Enum.Material.SmoothPlastic and lens.Color[1]==77,"old scan decays even if no new snapshot arrives")
 state.scanVisual=nil; state.scanBW={}
 for index=1,8 do state.scanBW[tostring(index)]={serial=100+index,angle=(index-1)*45,kind="none",proximity=0,remaining=1.2} end
 state.scanVisual=table.clone(state.scanBW["8"])
 renderer:update(state,1/60)
 for _,sensor in renderer.scannerSensors do check(sensor.Material==Enum.Material.Neon,"all eight completed BW observations survive the same snapshot") end
 check(math.abs(renderer.sensorReadings[108].remaining-(1.2-1/60))<1e-8,"legacy latest-event alias cannot double-expire a sensor")
 for _=1,90 do renderer:update(state,1/60) end
 for _,sensor in renderer.scannerSensors do check(sensor.Material==Enum.Material.SmoothPlastic,"each BW sensor expires independently without fresh snapshots") end
 state.scanBW=nil
 state.scanVisual=nil; state.manualScannerActive=true
 state.scanManual={
  ["0"]={serial=10,angle=0,kind="tank",affiliation="enemy",proximity=1,remaining=3},
  ["15"]={serial=11,angle=15,kind="none",proximity=0,remaining=3},
  ["90"]={serial=12,angle=90,kind="wall",proximity=0.55,remaining=3},
 }
 renderer:update(state,1/60)
 check(renderer.scannerSensors[1].Color[2]<30 and renderer.scannerSensors[3].Material==Enum.Material.Neon,"manual sweep retains simultaneous directional warnings without empty neighbor erasing enemy")
 for _=1,190 do renderer:update(state,1/60) end
 check(renderer.scannerSensors[1].Material==Enum.Material.SmoothPlastic,"stale manual snapshots cannot restart expired warning timers")
 state.manualScannerActive=false; renderer:update(state,1/60)
 check(next(renderer.sensorReadings)==nil,"entering BW mode clears manual presentation cache")
 state.scanVisual={serial=6,angle=90,kind="tank",affiliation="enemy",proximity=1,remaining=1.2}; renderer:update(state,1/60)
 state.health=0; renderer:update(state,1/60)
 check(lens.Material==Enum.Material.SmoothPlastic and lens.Color[1]==117,"death clears glow and greys out sensor with wreck")
 renderer:destroy(); check(lens.destroyed,"reset/disconnect removes all scanner decorations")
end

Instance.new=saveInstance; game.GetService=saveService
CFrame.new=saveNew; CFrame.Angles=saveAngles; CFrame.lookAt=saveLookAt
print(string.format("Renderer suite passed: %d assertions",count))
