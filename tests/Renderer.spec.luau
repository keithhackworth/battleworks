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
boomer:destroy(); rattler:destroy()
check(boomer.model.destroyed and rattler.model.destroyed and bore.destroyed,"model destruction removes all attached barrel geometry")
-- Boot and exercise the production server entrypoint with two simulated players.
do
 local savedClock=os.clock
 local time=10
 os.clock=function() return time end
 local players={PlayerAdded=signal(),PlayerRemoving=signal()}
 local first={UserId=101}; local second={UserId=102}
 players.GetPlayers=function() return {first,second} end
 local heartbeat=signal()
 local shots,prepared,snapshots={}, {}, {}
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
     snapshots={}; for id,state in args[1] do
      snapshots[id]=table.clone(state)
      for _,hitbox in created do
       if hitbox.Name=="TankHitbox" and not hitbox.destroyed and tostring(hitbox:GetAttribute("OwnerId"))==id then
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
 local command={throttle=0,steer=0,fire=true,aimMode="Rate",turretX=0,turretY=0}
 local function tick(fire)
  time+=1/60
  command.fire=fire
  input.OnServerEvent:Fire(first,command)
  heartbeat:Fire(1/60)
 end
 for _=1,100 do tick(true) end
 check(#prepared>=2 and #shots>=2,"production Boomer prepares and releases shells")
 check(shots[1].kind=="Boomer" and shots[1].time-prepared[1].time>=0.2-1e-5,"Boomer production windup stays 0.20 seconds")
 check(math.abs(snapshots["101"].aimRecoilYaw or 0)>0,"production Boomer shell release kicks its actual turret")
 check(snapshots["102"].tankType=="Boomer" and snapshots["102"].health==100,"second player's tank is independent")
 local originalCount=#shots
 select.OnServerEvent:Fire(first,"Rattler")
 for _=1,5 do tick(false) end
 local start=time
 for _=1,180 do tick(true) end
 check(snapshots["101"].tankType=="Rattler" and snapshots["101"].lift>=0 and snapshots["101"].lift<=6,"production Rattler hops within six studs while firing")
 check(snapshots["101"].weaponCooldown>1.9,"production Rattler enters two-second lockout")
 local rapid=0
 for i=originalCount+1,#shots do
  check(shots[i].kind=="Rattler" and shots[i].time-start<=3+1e-5,"only Rattler rounds during its allowed burst")
  rapid+=1
 end
 check(rapid>=28 and rapid<=30,"production server launches rapid projectiles")
check(shots[originalCount+1].rock and shots[originalCount+1].rock.serial>0 and math.abs(shots[originalCount+1].rock.roll)>0.1,"release event carries the full physical roll before snapshot decay")
local firstRapid,secondRapid=shots[originalCount+1],shots[originalCount+2]
check((firstRapid.direction-secondRapid.direction).Magnitude>0.005,"production Rattler bullets vary with turret recoil")
check(math.abs(snapshots["101"].aimRecoilYaw or 0)>0,"server replicates recoil offsets for visible turret motion")
 local lockedShots=#shots
 for _=1,119 do tick(true) end
 check(#shots==lockedShots,"production server blocks held trigger during lockout")
 for _=1,4 do tick(true) end
 check(#shots>lockedShots,"production server resumes after full lockout")
 select.OnServerEvent:Fire(first,"Boomer")
 for _=1,5 do tick(false) end
 check(snapshots["101"].tankType=="Boomer" and snapshots["101"].lift>0,"switch preserves airborne pose")
 for _=1,240 do tick(false) end
 check(snapshots["101"].lift==0,"switched airborne tank still falls and lands")
 select.OnServerEvent:Fire(first,{tankType="Rattler"})
 for _=1,5 do tick(false) end
 check(snapshots["101"].tankType=="Boomer","production selection rejects malformed requests")
 -- BW owns the same production tank command/weapon loop; real lifecycle paths.
 local bwRun,bwStop=network:FindFirstChild("BWRun"),network:FindFirstChild("BWStop")
 local redraw=network:FindFirstChild("RedrawMap")
 local function advance(count)
  for _=1,count do time+=1/60; heartbeat:Fire(1/60) end
 end
 local function demo(kind,id)
  select.OnServerEvent:Fire(first,kind); advance(40)
  redraw.OnServerEvent:Fire(first,Vector2.new(230,230)); advance(4)
  local before=#shots
  bwRun.OnServerEvent:Fire(first,require("BWConfig").DefaultSource,id)
  for _=1,6000 do
   advance(1)
   local state=snapshots["101"]
   if state and (state.bwRequestId or 0)>=id and state.bwStatus and state.bwStatus~="running" then break end
  end
  check(snapshots["101"].bwStatus=="completed","production BW demo completes with "..kind..": "..tostring(snapshots["101"].bwMessage))
  check(#shots-before==(if kind=="Boomer" then 5 else 21),"production BW single/timed fire uses normal "..kind.." weapon")
 end
 demo("Boomer",1); demo("Rattler",2)
 select.OnServerEvent:Fire(first,"Boomer"); advance(40)
 redraw.OnServerEvent:Fire(first,Vector2.new(230,230)); advance(4)
 local start=snapshots["101"].position
 bwRun.OnServerEvent:Fire(first,"forward(4)",3)
 command.throttle=-1; command.steer=1
 for _=1,10 do tick(true) end
 check(snapshots["101"].position.Z<start.Z and math.abs(snapshots["101"].yaw)<1e-8,"manual reverse/steer/fire cannot override running BW")
 bwStop.OnServerEvent:Fire(first,4)
 local stoppedShots=#shots
 advance(20)
 check(snapshots["101"].bwStatus=="stopped" and snapshots["101"].speed==0 and #shots==stoppedShots,"Stop releases owned throttle and trigger")
 advance(40)
 bwRun.OnServerEvent:Fire(first,"fire()",5); advance(1)
 bwStop.OnServerEvent:Fire(first,6); stoppedShots=#shots; advance(30)
 check(#shots==stoppedShots and not snapshots["101"].bwRunning,"Stop cancels a prepared Boomer shell before release")
 bwStop.OnServerEvent:Fire(first,8)
 bwRun.OnServerEvent:Fire(first,"fire(2)",7); advance(5)
 check(not snapshots["101"].bwRunning and snapshots["101"].bwRequestId==8,"late Run request cannot overtake a newer Stop")
 local firstPosition=snapshots["101"].position
 bwRun.OnServerEvent:Fire(second,"forward(3)",1); advance(12)
 check((snapshots["101"].position-firstPosition).Magnitude<1e-6,"another player's BW program cannot control this player's tank")
 bwStop.OnServerEvent:Fire(second,2); advance(40)
 bwRun.OnServerEvent:Fire(first,"forward(100)",9); advance(3)
 select.OnServerEvent:Fire(first,"Rattler"); advance(5)
 check(snapshots["101"].bwStatus=="stopped" and snapshots["101"].tankType=="Rattler","selection cancels a running program cleanly")
 advance(40)
 bwRun.OnServerEvent:Fire(first,"forward(100)",10); advance(3)
 redraw.OnServerEvent:Fire(first,Vector2.new(230,230)); advance(5)
 check(snapshots["101"].bwStatus=="stopped" and snapshots["101"].bwMessage=="Map redrawn.","redraw cancels BW before replacing tank state")
 advance(40)
 bwRun.OnServerEvent:Fire(first,"forward(100)",11); advance(3)
 command.throttle=0; command.steer=0
 print("BW production integration passed: both default programs, weapon counts, input isolation, Stop, stale requests, selection and redraw")

 players.PlayerRemoving:Fire(first)
 for _=1,5 do time+=1/60; heartbeat:Fire(1/60) end
 check(snapshots["101"]==nil and snapshots["102"]~=nil,"departure removes only the departing player's simulation")
 local hitboxes=0
 for _,p in created do if p.Name=="TankHitbox" and not p.destroyed then hitboxes+=1 end end
 check(hitboxes==1,"switching retains a single hitbox per player and departure cleans it")
 heartbeat=nil
 Instance.new=oldFactory; os.clock=savedClock; workspace.FindFirstChild=originalWorkspaceFind
 print("Production server integration passed: Boomer windup, Rattler burst/flight/cooldown, switch, ownership and cleanup")
end

Instance.new=saveInstance; game.GetService=saveService
CFrame.new=saveNew; CFrame.Angles=saveAngles; CFrame.lookAt=saveLookAt
print(string.format("Renderer suite passed: %d assertions",count))
