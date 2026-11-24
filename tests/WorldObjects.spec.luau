-- The runner supplies the established numeric CFrame fixture. Real contacts,
-- projectiles, runtime and object state execute; mesh alignment remains Studio-only.
local Objects=require("WorldObjects")
local Contacts=require(Shared.VehicleContacts)
local Sim=require(Shared.TankSimulation)
local Components=require(Shared.VehicleComponents)
local Input=require(Shared.InputCommand)
local Projectiles=require("ProjectileSimulation")
local Parser=require(Shared.BWParser)
local Runtime=require(Shared.BWExecution)
local checks=0
local function check(v,m) checks+=1; assert(v,m) end
local function model()
 local mesh={Transparency=.2}; function mesh:IsA(class) return class=="BasePart" end
 local m={attributes={},mesh=mesh}
 function m:GetBoundingBox() return CFrame.new(0,10,0),Vector3.new(20,20,20) end
 function m:GetDescendants() return {mesh} end
 function m:SetAttribute(k,v) self.attributes[k]=v end
 return m
end
local function setup(options,traction)
 local registry=Objects.new(); local m=model()
 local interaction={solid=true,destructible=true,hp=150,fractions=Vector3.new(.18,.45,.18)}
 for k,v in options or {} do interaction[k]=v end
 local spec={id="tree-large",position=Vector3.zero,rotation=Vector3.zero,interaction=interaction,traction=traction}
 local r=registry:add(m,spec); return registry,r,m
end
local registry,r,m=setup()
do
 local slick=setup(nil,20)
 local _,support=slick:support(0,0,50)
 local material=support.material
 check(material.assetTraction and material.authoredTraction==.2 and material.trackedTraction==.3,"solid support returns authored asset grip and the tracked bonus")
 local ice=setup(nil,0)
 local _,iceSupport=ice:support(0,0,50)
 check(iceSupport.material.staticFriction==0 and iceSupport.material.trackedTraction==.1,"explicit zero grip survives support lookup")
end
check(m.attributes.Health==150 and m.attributes.MaxHealth==150 and not m.attributes.Destroyed,"initial HP is replicated on the placed Model")
check(r.proxy.Size.X<4 and r.proxy.Size.Z<4 and r.proxy.Size.Y==9,"trunk dimensions exclude the large canopy")
check(r.proxy.CanQuery and not r.proxy.CanCollide and r.proxy.Transparency==1,"authoritative query proxy; native body physics disabled")
check(#registry:obstacles()==1 and registry:obstacles()[1].fixed,"solid tree enters the existing fixed-body solver")
local function drive(kind,fire,objects)
 local s=Sim.new(Vector3.new(0,0,25),kind)
 local cmd=Input.neutral(); cmd.throttle=1
 for _=1,180 do
  Sim.step(s,cmd,1/60,Vector2.new(230,230),nil,true)
  Contacts.solve({Contacts.body("tank",s,Components.get(s).Chassis)},objects:obstacles(),1/60)
  Sim.reconcileGround(s,nil)
 end
 return s
end
for _,kind in {"Boomer","Rattler"} do
 local s=drive(kind,false,registry)
 check(s.position.Z>=r.proxy.Size.Z/2+Components.get(s).Chassis.CollisionLength/2-.01,"manual tank cannot pass through trunk: "..kind)
 check(math.abs(s.speed)<.01,"blocked input does not leave forward velocity: "..kind)
end
-- High-speed recoil/momentum also uses continuous collision; no tunnelling.
do
 local s=Sim.new(Vector3.new(0,0,30),"Boomer")
 local Motion=require(Shared.VehicleMotion)
 Motion.setVelocity(s,Vector3.new(0,0,-2000)); s.motionStepStart=s.position; s.motionYawStart=s.yaw
 Contacts.solve({Contacts.body("fast",s,Components.get(s).Chassis)},registry:obstacles(),.05)
 check(s.position.Z>r.proxy.Size.Z/2,"high-speed swept body stops at trunk")
end
local token={}
local object,before,after,fatal=registry:impact({Instance=r.proxy},25,token)
check(object==r and before==150 and after==125 and not fatal,"normal cannon damage applied without rebalance")
check(registry:impact({Instance=r.proxy},25,token)==nil and r.health==125,"one projectile cannot damage twice")
for _=1,4 do registry:impact({Instance=r.proxy},25,{}) end
check(r.health==25 and #registry:obstacles()==1,"tree stays solid until its fatal hit")
registry:impact({Instance=r.proxy},25,{})
check(r.destroyed and r.health==0 and not r.proxy.CanQuery and #registry:obstacles()==0,"fatal hit immediately removes both queries and movement obstruction")
check(m.mesh.Transparency==1 and m.attributes.Destroyed and m.attributes.Health==0,"destroyed tree hidden and marked on all replicas")
check(registry:impact({Instance=r.proxy},25,{})==nil,"destroyed tree cannot take further damage")
for _,kind in {"Boomer","Rattler"} do check(drive(kind,false,registry).position.Z<0,"tank can pass after destruction: "..kind) end
local effect={Destroy=function(self) self.destroyed=true end}; registry:trackEffect(effect)
registry:reset()
check(r.health==150 and not r.destroyed and r.proxy.CanQuery and #registry:obstacles()==1,"reset restores health and trunk without duplicate parts")
check(m.mesh.Transparency==.2 and effect.destroyed,"reset restores original visual transparency and clears effects")
check(registry:impact({Instance=r.proxy},25,token)==nil,"reset does not permit replay of a consumed projectile")
for _=1,3 do registry:reset() end
check(#registry:obstacles()==1,"repeated reset cannot accumulate collision proxies")
local immune,ir,im=setup({destructible=false,hp=0})
check(not ir.destroyed and #immune:obstacles()==1 and ir.proxy.CanQuery,"HP zero never implies indestructible or destroyed without explicit flag")
check(immune:impact({Instance=ir.proxy},1000,{})==nil and not ir.destroyed,"indestructible tree remains cover")
local empty,er=setup({hp=0})
check(er.destroyed and #empty:obstacles()==0,"explicit destructible zero-HP tree starts destroyed")
local traversable,tr=setup({solid=false})
check(#traversable:obstacles()==0 and tr.proxy.CanQuery,"traversable destructible item can receive shots without blocking movement")
for _,bad in {0,-1,0/0,math.huge} do check(registry:impact({Instance=r.proxy},bad,{})==nil,"invalid damage rejected") end
check(registry:impact({Instance={}},10,{})==nil,"unknown/cosmetic parts cannot receive object damage")
do
 local objects,record,asset=setup()
 asset.Parent={}
 objects:impact({Instance=record.proxy},150,{})
 objects:stepRegeneration(4.9)
 check(record.destroyed and not record.proxy.CanQuery,"default regeneration waits five seconds")
 objects:stepRegeneration(.1,function()return true end)
 check(record.destroyed,"an occupied collider delays regeneration")
 objects:stepRegeneration(0,function()return false end)
 check(record.health==150 and record.proxy.CanQuery and not record.destroyed,"regeneration restores health and the original collider")
 local disabled,ruin,model=setup({regenerates=false,regenerationDelay=1})
 model.Parent={}
 disabled:impact({Instance=ruin.proxy},150,{})
 disabled:stepRegeneration(60)
 check(ruin.destroyed,"disabled assets stay destroyed")
 local custom,prop,native=setup({regenerationDelay=.5})
 native.Parent={}
 custom:impact({Instance=prop.proxy},150,{})
 custom:stepRegeneration(.5)
 check(not prop.destroyed,"custom regeneration delay is applied")
end
-- BW uses exactly the same blocked authoritative state as manual controls.
do
 local p,err=Parser.parse('forward(20, best_effort=false)'); assert(p,err and err.message)
 local s=Sim.new(Vector3.new(0,0,18),"Boomer")
 local runtime=Runtime.new(p,s,nil,require(Shared.BWChassis).default("Octa"))
 for _=1,600 do
  Sim.step(s,runtime:step(s,1/60),1/60,Vector2.new(230,230),nil,true)
  Contacts.solve({Contacts.body("bw",s,Components.get(s).Chassis)},registry:obstacles(),1/60); Sim.reconcileGround(s,nil)
 end
 check(s.position.Z>r.proxy.Size.Z/2 and runtime.devices.commands[1].state=="failed","BW obstruction uses normal stuck detection rather than bypassing collision")
end
-- Real server projectile sweep results feed the same object's damage path.
do
 local oldIndex=mt.__index
 mt.__index=function(f,key)
  if key=="PointToObjectSpace" then return function(self,p)
   local d=p-self.p; return Vector3.new(self.m[1]*d.X+self.m[4]*d.Y+self.m[7]*d.Z,self.m[2]*d.X+self.m[5]*d.Y+self.m[8]*d.Z,self.m[3]*d.X+self.m[6]*d.Y+self.m[9]*d.Z)
  end end
  return oldIndex(f,key)
 end
 local world={GetPartBoundsInRadius=function() return {r.proxy} end,Spherecast=function() error("initial overlap must already hit the trunk") end}
 local shell=Projectiles.new(r.proxy.CFrame.Position,Vector3.new(0,0,-1),{})
 local hit=Projectiles.step(world,shell,1/60)
 check(hit.Instance==r.proxy and shell.done,"actual projectile overlap recognizes the trunk primitive")
 registry:reset(); registry:impact(hit,6,shell)
 check(r.health==144 and Projectiles.step(world,shell,1/60)==nil,"existing rapid-fire damage applied once and spent projectile cannot hit again")
 mt.__index=oldIndex
end
registry:reset();registry.characterCollision=true;registry:sync(r)
check(r.proxy.CanCollide and m.mesh.CanCollide~=true,"Royale native character support uses authoritative collider parts, without enabling decorative mesh query cover")
registry:impact({Instance=r.proxy},r.health,{})
check(not r.proxy.CanCollide and not r.proxy.CanQuery,"destruction removes native character support and authoritative tank queries together")
registry:reset();check(r.proxy.CanCollide,"reset restores native character support without extra colliders")
do
 local objects=Objects.new()
 local moving=model();moving.Parent={}
 local pivot=CFrame.new()
 function moving:GetPivot() return pivot end
 function moving:PivotTo(nextPivot)
  for _,proxy in objects.records.moving.proxies do
   proxy.CFrame=CFrame.new(nextPivot.Position-pivot.Position)*proxy.CFrame
  end
  pivot=nextPivot
 end
 local spec={id="moving",position=Vector3.zero,rotation=Vector3.zero,
  motion={points={{0,0,0},{20,0,0}},speed=10,pause=0,face=false,enabled=true},
  interaction={solid=true,destructible=true,hp=20,fractions=Vector3.new(.2,.5,.2)}}
 local record=objects:add(moving,spec)
 objects:stepMotion(1)
 local body=objects:obstacles()[1]
 check(pivot.Position.X==10 and body.state.position.X==10 and record.proxy.CFrame.Position.X==10,"motion moves the visual and the existing tank/projectile collision in the same step")
 check(objects:support(0,0,100)==nil and objects:support(10,0,100)==10,"support samples follow the moved asset")
 check(objects:impact({Instance=record.proxy},5,{})==record and record.health==15,"moving collision proxy still routes actual impact damage")
 objects:impact({Instance=record.proxy},20,{})
 objects:stepMotion(.5)
 check(pivot.Position.X==10 and #objects:obstacles()==0,"destroyed motion does not leave live or drifting collision")
 objects:reset()
 check(pivot.Position.X==0 and #objects.moving==1 and objects:obstacles()[1]==body,"reset restores the starting pose and reuses collision state")
 moving.Parent=nil
 objects:stepMotion(1)
 check(pivot.Position.X==0 and #objects.moving==0 and not objects.records.moving,"removed model releases its motion and collision state")
end
do
 local Env=require(Shared.Environment)
 local Motion=require(Shared.VehicleMotion)
 local dt=1/60
 local size=Vector2.new(230,230)
 local function world()
  local objects=Objects.new()
  local env=Env.create(size)
  env.rocks={};env.logs={};env.trees={};env.zones={};env.worldObjects=objects
  return objects,env
 end
 local function asset(objects,id,base,size,points,speed,pause,collider,face,spin)
  local native=model()
  native.Parent={}
  native.mesh.Parent=native
  function native.mesh:SetAttribute() end
  local pivot=CFrame.new(base)
  function native:GetBoundingBox() return CFrame.new(base+Vector3.new(0,size.Y/2,0)),size end
  function native:GetPivot() return pivot end
  function native:PivotTo(value) pivot=value end
  local interaction=collider or {solid=true,destructible=false,hp=100,fractions=Vector3.new(1,1,1)}
  local path=if points then {points=points,speed=speed,pause=pause or 0,enabled=true,face=face==true} else nil
  local record=objects:add(native,{id=id,position=base,rotation=Vector3.zero,interaction=interaction,motion=path,spin=spin})
  objects:stepMotion(0)
  return native,record
 end
 local function simulate(objects,env,states,frames,commands,obstacle)
  local rejected=0
  for _=1,frames do
   local bodies={}
   for i,state in states do
    local platform=Sim.step(state,commands and commands[i] or Input.neutral(),dt,size,env,true)
    local body=Contacts.body("tank"..i,state,Components.get(state).Chassis)
    body.platform=platform
    table.insert(bodies,body)
   end
   local obstacles=objects:obstacles()
   if obstacle then table.insert(obstacles,obstacle) end
   local ok=objects:solveContacts(bodies,obstacles,dt,function(state,body) return Sim.platformTerrainBlocked(state,body,env) end,function(body)
    local state=body.state
    local height,_,_,_,_,_,platform=Env.pose(env,state.position,state.yaw,Components.get(state).Chassis)
    return if math.abs(state.position.Y-height)<.05 then platform else nil
   end)
   if not ok then rejected+=1 end
   for _,body in bodies do Sim.reconcileGround(body.state,env,body.carryVelocity~=nil) end
  end
  return rejected
 end
 local ferry,water=world()
 local deck=asset(ferry,"ferry",Vector3.zero,Vector3.new(30,1,28),{{0,0,0},{20,0,0}},10,.5)
 local boomer=Sim.new(Vector3.new(-6,1,0),"Boomer")
 local rattler=Sim.new(Vector3.new(6,1,0),"Rattler")
 boomer.yaw=-math.pi/2
 check(simulate(ferry,water,{boomer,rattler},60)==0,"ferry advances while two tanks share its deck")
 check(math.abs(boomer.position.X-4)<.025 and math.abs(rattler.position.X-16)<.025,"both wheeled and tracked tanks move with the deck")
 check(math.abs(boomer.motionForwardTravel)<.025,"passive platform motion does not complete BW driving distance")
 boomer.yaw=0
 local driving=Input.neutral();driving.throttle=1
 simulate(ferry,water,{boomer,rattler},30,{driving,Input.neutral()})
 check(boomer.position.Z<-.3 and math.abs(rattler.position.X-21)<.025,"normal acceleration remains available while being carried")
 simulate(ferry,water,{rattler},60)
 check(math.abs(deck:GetPivot().Position.X-20)<.025 and math.abs(rattler.position.X-26)<.025,"endpoint pause preserves deck support")
 simulate(ferry,water,{rattler},30)
 check(rattler.position.X<22 and math.abs(rattler.position.X-deck:GetPivot().Position.X-6)<.025,"reversal carries in the new direction without an extra impulse")

 local river,crossing=world()
 local Heightfield=require(Shared.WorldHeightfield)
 local field=Heightfield.new(size.X,size.Y)
 crossing.terrainSettings={width=size.X,depth=size.Y,ground={material="Grass"},terrain=field}
 for z=0,field.rows do for x=0,field.columns do
  if math.abs((x/field.columns-.5)*size.X)<16 then field.heights[Heightfield.index(field,x,z)]=-12*Heightfield.Unit end
 end end
 Heightfield.fillWater(field,size.X,size.Y,Vector3.new(0,-12,0),8)
 local riverFerry=asset(river,"river_ferry",Vector3.new(-27,-1,0),Vector3.new(22,1,24),{{0,0,0},{54,0,0}},15,1)
 local riverRider=Sim.new(Vector3.new(-27,0,0),"Boomer")
 local bankRejects=simulate(river,crossing,{riverRider},217)
 check(bankRejects==0 and riverRider.position.X>26.9 and riverFerry:GetPivot().Position.X>26.9,"ferry crosses steep submerged banks while its deck stays above terrain")

 local dock,harbor=world()
 local boardingDeck=asset(dock,"boarding",Vector3.zero,Vector3.new(28,1,24),{{0,0,0},{20,0,0}},3,1)
 local boarding=Sim.new(Vector3.new(-20,0,0),"Boomer")
 boarding.yaw=-math.pi/2
 local boarded=false
 for _=1,100 do
  simulate(dock,harbor,{boarding},1,{driving})
  if boarding.grounded and math.abs(boarding.position.Y-1)<.025 then boarded=true;break end
 end
 check(boarded and boardingDeck:GetPivot().Position.X>0,"a tank can drive up onto a deck already following its path")

 local raft,bank=world()
 local edge=asset(raft,"edge",Vector3.zero,Vector3.new(22,8,18),{{0,0,0},{40,0,0}},8)
 local rider=Sim.new(Vector3.new(0,8,-7),"Boomer")
 Motion.setVelocity(rider,Vector3.new(0,0,-20))
 local inherited=false
 local falling=false
 for _=1,24 do
  simulate(raft,bank,{rider},1,{driving})
  if rider.position.Z<-9 and Motion.ensure(rider).X>6 then inherited=true end
  if rider.position.Y<7.95 then falling=true end
 end
 check(inherited and falling,"departing the deck keeps its horizontal momentum and begins gravity")

 local lift,shaft=world()
 local elevator=asset(lift,"lift",Vector3.zero,Vector3.new(20,1,20),{{0,0,0},{0,10,0}},5,.25)
 local passenger=Sim.new(Vector3.new(0,1,0),"Rattler")
 simulate(lift,shaft,{passenger},60)
 check(math.abs(passenger.position.Y-6)<.025 and passenger.grounded,"vertical elevator lifts a grounded passenger")
 simulate(lift,shaft,{passenger},140)
 check(math.abs(passenger.position.Y-elevator:GetPivot().Position.Y-1)<.025 and passenger.grounded,"elevator carries through the endpoint and downward run")

 local blockedLift,blockedShaft=world()
 local stoppedLift=asset(blockedLift,"stopped_lift",Vector3.zero,Vector3.new(20,1,20),{{0,0,0},{0,10,0}},8)
 asset(blockedLift,"ceiling",Vector3.new(0,9,0),Vector3.new(25,1,25))
 local trapped=Sim.new(Vector3.new(0,1,0),"Boomer")
 local ceilingBlocks=simulate(blockedLift,blockedShaft,{trapped},100)
 check(ceilingBlocks>0 and trapped.position.Y<=4.03 and stoppedLift:GetPivot().Position.Y<=3.03,"elevator stops before carrying a tank through a ceiling")

 local turntable,corner=world()
 local rotating=asset(turntable,"turning",Vector3.zero,Vector3.new(30,1,30),{{0,0,0},{0,0,-4},{4,0,-4}},5,0,nil,true)
 local turning=Sim.new(Vector3.new(6,1,0),"Boomer")
 simulate(turntable,corner,{turning},100)
 local center=rotating:GetPivot().Position
 check(math.abs((turning.position-center).Magnitude-math.sqrt(37))<.1 and turning.position.Z>center.Z+1,"facing changes rotate riders around the platform without throwing them off")

 local sweep,ground=world()
 local wall=asset(sweep,"wall",Vector3.new(-8,0,0),Vector3.new(.5,8,30),{{0,0,0},{35,0,0}},60)
 local tank=Sim.new(Vector3.new(0,0,0),"Boomer")
 simulate(sweep,ground,{tank},10)
 check(tank.position.X>6 and tank.position.X>wall:GetPivot().Position.X+4,"thin fast wall sweeps a stationary tank without tunneling")
 local opposing=Input.neutral();opposing.throttle=1;tank.yaw=math.pi/2
 simulate(sweep,ground,{tank},5,{opposing})
 check(tank.position.X>=wall:GetPivot().Position.X+4,"a tank driving into the moving wall cannot pass through")

 local function pushOf(thickness)
  local weighted,field=world()
  asset(weighted,"weighted",Vector3.new(-6-thickness/2,0,0),Vector3.new(thickness,8,12),{{0,0,0},{30,0,0}},30)
  local state=Sim.new(Vector3.zero,"Boomer")
  simulate(weighted,field,{state},8)
  return Motion.ensure(state).X
 end
 local light,heavy=pushOf(.3),pushOf(8)
 check(light>0 and heavy>light+.5 and heavy<90,"heavier collision geometry gives a stronger but bounded push")

 local escape,escapeGround=world()
 asset(escape,"open_rotor",Vector3.new(0,5.1,0),Vector3.new(6,1,18),nil,nil,nil,nil,nil,{axis={1,0,0},speed=180,pause=0})
 local free=Sim.new(Vector3.new(0,0,13.5),"Boomer")
 simulate(escape,escapeGround,{free},70)
 check(free.position.Z>13.6 and Motion.ensure(free).Magnitude<90,"a tank near the rotating asset's edge is pushed clear when it has an escape route")

 local lane,field=world()
 local pusher=asset(lane,"pusher",Vector3.new(-8,0,0),Vector3.new(.5,8,30),{{0,0,0},{40,0,0}},20)
 local first=Sim.new(Vector3.zero,"Boomer")
 local second=Sim.new(Vector3.new(12,0,0),"Rattler")
 local stop=Contacts.box("stationary",Vector3.new(23,0,0),.5,20,0,10)
 local rejected=simulate(lane,field,{first,second},85,nil,stop)
 check(first.position.X>0 and first.position.X<second.position.X and second.position.X>12 and second.position.X<=18.55,string.format("pushing a tank chain transmits contacts and respects stationary cover: %.3f %.3f wall %.3f rejected %d",first.position.X,second.position.X,pusher:GetPivot().Position.X,rejected))
 check(rejected>0 and pusher:GetPivot().Position.X<first.position.X-3.9,"an unresolved squeeze blocks the motion path")

 local jam,jamGround=world()
 local rotor=asset(jam,"rotor",Vector3.new(0,5.1,0),Vector3.new(6,1,18),nil,nil,nil,nil,nil,{axis={1,0,0},speed=180,pause=0})
 local wedged=Sim.new(Vector3.zero,"Boomer")
 local jamWall=Contacts.box("jam_wall",Vector3.new(-6,0,0),.5,20,0,10)
 local peak,rejections=0,0
 for _=1,120 do
  rejections+=simulate(jam,jamGround,{wedged},1,{opposing},jamWall)
  peak=math.max(peak,Motion.ensure(wedged).Magnitude)
 end
 check(rejections>0 and peak<120,"squeezing a tank under a rotating item blocks the rotor without a launch")

 -- Exercise the rollback even when the contact solver reports no overlap.
 local pose=rotor:GetPivot()
 local beforePosition=wedged.position
 local solve=Contacts.solve
 Contacts.solve=function(bodies,statics,step,stats,advance,objects)
  if advance then
   advance(objects,step)
   bodies[1].kinematicAffected=true
   Motion.setVelocity(bodies[1].state,Vector3.new(1900,0,0))
   return true
  end
 end
 local accepted=jam:solveContacts({Contacts.body("wedged",wedged,Components.get(wedged).Chassis)},jam:obstacles(),dt)
 Contacts.solve=solve
 check(accepted and (rotor:GetPivot().LookVector-pose.LookVector).Magnitude>.001
  and (wedged.position-beforePosition).Magnitude<.001 and math.abs(Motion.ensure(wedged).X-90)<.01,
  "a clear 1900 studs/sec release is limited without stopping the rotor")

 local bridge,ravine=world()
 asset(bridge,"bridge",Vector3.zero,Vector3.new(12,8,28))
 asset(bridge,"sweeper",Vector3.new(-11,8,0),Vector3.new(.5,7,20),{{0,0,0},{24,0,0}},12)
 local victim=Sim.new(Vector3.new(0,8,0),"Rattler")
 simulate(bridge,ravine,{victim},80)
 check(victim.position.X>6 and victim.position.Y<7.5,"a side impact pushes a tank beyond the ledge and gravity takes over")

 local imported,arena=world()
 local faces={{{-.5,.5,-.5},{-.5,.5,.5},{.5,.5,-.5}},{{.5,.5,-.5},{-.5,.5,.5},{.5,.5,.5}}}
 local _,record=asset(imported,"explicit_deck",Vector3.zero,Vector3.new(24,2,24),{{0,0,0},{30,0,0}},9,0,
  {fit="faces",faces=faces,sourceSize={24,2,24},solid=true,destructible=false,hp=100,fractions=Vector3.new(1,1,1)})
 local glbRider=Sim.new(Vector3.new(0,2,0),"Boomer")
 simulate(imported,arena,{glbRider},60)
 check(record.bodies[1].polygon and math.abs(glbRider.position.X-9)<.025,"imported collision triangles provide moving support")
 local customWall,customGround=world()
 local _,custom=asset(customWall,"explicit_wall",Vector3.new(-10,0,0),Vector3.new(3,8,24),{{0,0,0},{24,0,0}},20,0,
  {fit="faces",faces=faces,sourceSize={3,8,24},solid=true,destructible=false,hp=100,fractions=Vector3.new(1,1,1)})
 local customVictim=Sim.new(Vector3.zero,"Rattler")
 simulate(customWall,customGround,{customVictim},40)
 check(custom.bodies[1].polygon and customVictim.position.X>5,"custom GLB face prisms push through swept polygon contact")
end
do
 local registry=Objects.new()
 local native=model();native.Parent={}
 local pivot=CFrame.new()
 function native:GetPivot() return pivot end
 function native:PivotTo(value) pivot=value end
 registry:add(native,{id="spinning",position=Vector3.zero,rotation=Vector3.zero,spin={axis={1,0,1},speed=180,pause=2}})
 registry:stepMotion(1)
 check(pivot.UpVector.Y<-.99,"an asset can rotate around a combined axis without a motion path")
 check(math.abs(pivot:PointToWorldSpace(Vector3.new(0,10,0)).Y-10)<.001,"rotation preserves the asset center")
 registry:stepMotion(1)
 check(pivot.UpVector.Y>.99,"the asset returns to its initial orientation after one full turn")
 registry:stepMotion(1)
 check(pivot.UpVector.Y>.99,"the asset holds during the configured pause")
 registry:stepMotion(1)
 registry:stepMotion(.5)
 check(math.abs(pivot.UpVector.Y)<.01,"the asset resumes rotation after the pause")
end
do
 local Motion=require(Shared.WorldMotion)
 local registry=Objects.new()
 local native=model();native.Parent={}
 local pivot=CFrame.new()
 function native:GetPivot() return pivot end
 function native:PivotTo(value) pivot=value end
 local spec={axis={1,0,0},speed=90,pause=1,swing=90}
 local swing=Motion.compileSpin(spec,CFrame.new())
 for time,angle in {[0.5]=45,[1.5]=90,[2.5]=45,[3.5]=0,[4.5]=45} do
  check(math.abs(Motion.spinAngle(swing,time)-math.rad(angle))<1e-6,"swing preview samples outbound, both pauses, return and repeat")
 end
 registry:add(native,{id="swinging",position=Vector3.zero,rotation=Vector3.zero,spin=spec})
 registry:stepMotion(1);registry:stepMotion(1)
 check(math.abs(pivot.UpVector.Y)<1e-6,"swing pauses at the configured angle")
 registry:stepMotion(.5)
 check(math.abs(pivot.UpVector.Y-math.sqrt(.5))<1e-6,"reverse-only swing updates the runtime pose")
 registry:stepMotion(.5);registry:stepMotion(1)
 check(pivot.UpVector.Y>.9999,"swing returns and pauses at the starting orientation")
 registry:stepMotion(1)
 check(math.abs(pivot.UpVector.Y)<1e-6,"swing repeats")
end
do
 local Motion=require(Shared.WorldMotion)
 local axle=Vector3.new(1,0,0)
 local authored=CFrame.Angles(0,math.pi/3,0)
 local localSpin=Motion.compileSpin({axis={1,0,0},speed=30,pause=0,space="local"},authored)
 local worldSpin=Motion.compileSpin({axis={1,0,0},speed=30,pause=0},authored)
 local turned=axle
 turned=authored:PointToWorldSpace(turned)
 local courseYaw=.4
 local expected=CFrame.Angles(0,courseYaw,0):PointToWorldSpace(turned)
 check((Motion.orientation(courseYaw,localSpin,.8):PointToWorldSpace(turned)-expected).Magnitude<1e-5,
  "local spin preserves the axle after authored rotation and path yaw")
 check((Motion.orientation(0,worldSpin,.8):PointToWorldSpace(axle)-axle).Magnitude<1e-5,
  "legacy spins retain world-axis rotation")
end
do
 local Audio=require(Shared.WorldSound)
 check(Audio.playbackAction("Occupied","Repeat",true,2.9,3,false)=="Idle" and
  Audio.playbackAction("Occupied","Repeat",true,3,3,false)=="Repeat" and
  Audio.playbackAction("Occupied","Repeat",false,4,3,false)=="Idle","repeat scheduling honors interval and active state")
 check(Audio.playbackAction("Always","Once",true,1,0,false)=="Once" and
  Audio.playbackAction("Always","Once",true,2,0,true)=="Idle","ambient once plays just once per listener")
 check(Audio.accepts({filter="Moving"},nil,"block","mover",true,true) and
  not Audio.accepts({filter="Moving"},nil,"block","mover",true,false) and
  not Audio.accepts({filter="Both"},"mover","block","mover",true,true),"moving-only excludes static objects and attachments exclude the parent")
 local Attachment=require(Shared.AssetAttachment)
 local Blocks=require("WorldSoundBlocks")
 local oldIndex=mt.__index
 mt.__index=function(frame,key)
  if key=="Lerp" then return function(self,other,t)
   local p=self.Position+(other.Position-self.Position)*t
   return CFrame.fromMatrix(p,self.RightVector,self.UpVector,self.LookVector*-1)
  end end
  if key=="ToObjectSpace" then return function(self,other)
   local function localVector(p)
    return Vector3.new(self.RightVector:Dot(p),self.UpVector:Dot(p),-self.LookVector:Dot(p))
   end
   return CFrame.fromMatrix(localVector(other.Position-self.Position),localVector(other.RightVector),localVector(other.UpVector),localVector(other.LookVector)*-1)
  end end
  return oldIndex(frame,key)
 end
 local function soundConfig(activation,filter)
  local config=table.clone(Audio.Default)
  config.effect="bell";config.activation=activation;config.filter=filter
  config.playback="Once";config.cooldown=.5
  return config
 end
 local function volume(registry,id,config,link,x,z)
  local pivot=CFrame.new(x or 0,0,z or 0)*CFrame.Angles(0,math.rad(20),0)
  local part=Instance.new("Part");part.CFrame=pivot;part.Size=Vector3.new(.15,6,8);part.Destroying=signal()
  function part:AddTag(tag) self.tag=tag end
  local trigger={Parent={}}
  function trigger:GetPivot() return pivot end
  function trigger:PivotTo(frame) pivot=frame;part.CFrame=frame end
  function trigger:FindFirstChildWhichIsA() return part end
  registry:add(trigger,{id=id,position=Vector3.zero,rotation=Vector3.zero,template=Audio.Asset,sound=config,attachment=link})
  return part,trigger
 end
 local function setupSounds()
  local registry=Objects.new()
  registry.sounds=Blocks.new(registry.placements)
  registry.sounds.ids.bell="123"
  return registry
 end
 local function tank(id,from,to)
  return {id=id,halfX=1,halfZ=1,bottom=-1,top=1,state={health=100,position=Vector3.new(to,0,0),motionStepStart=Vector3.new(from,0,0),yaw=.2}}
 end
 local soundWorld=setupSounds()
 local entry=volume(soundWorld,"entry",soundConfig("Entry","Tanks"))
 local leave=volume(soundWorld,"exit",soundConfig("Exit","Tanks"))
 local occupied=volume(soundWorld,"occupied",soundConfig("Occupied","Tanks"))
 check(not entry.CanCollide and not entry.CanQuery and entry.Transparency==1 and #soundWorld:obstacles()==0,
  "runtime Sound Blocks are invisible and excluded from both collision and queries")
 soundWorld.sounds:step({tank("a",-20,20)},.05,{})
 check(entry:GetAttribute("Sfx_Pulse")==1 and leave:GetAttribute("Sfx_Pulse")==1 and occupied:GetAttribute("Sfx_Pulse")==1 and not occupied:GetAttribute("Sfx_Active"),
  "a high-speed crossing pulses every contact mode without claiming end-of-step occupancy")
 soundWorld.sounds:step({tank("a",-20,1),tank("b",-20,0)},.05,{})
 check(entry:GetAttribute("Sfx_Pulse")==1 and occupied:GetAttribute("Sfx_Active")~=true,
  "footprint overlap works outside the block center; entry cooldown is global and occupancy is shared")
 soundWorld.sounds:step({tank("a",1,20),tank("b",0,0)},.6,{})
 check(occupied:GetAttribute("Sfx_Active")~=true and occupied:GetAttribute("Sfx_Pulse")==1,"a cooldown-suppressed occupancy does not restart without a new entry")
 soundWorld.sounds:step({tank("b",0,20)},.1,{})
 check(occupied:GetAttribute("Sfx_Active")~=true,"last departure clears occupancy")
 soundWorld.sounds:step({tank("a",20,0)},.6,{})
 check(entry:GetAttribute("Sfx_Pulse")==2 and occupied:GetAttribute("Sfx_Pulse")==2,"the next activation after cooldown plays normally")
 soundWorld.sounds:step({tank("a",0,0),tank("b",20,0)},.1,{})
 soundWorld.sounds:step({tank("b",0,0)},.1,{})
 check(occupied:GetAttribute("Sfx_Active")==true and occupied:GetAttribute("Sfx_Pulse")==2,"one subject leaving preserves aggregate occupancy")
 entry.Destroying:Fire()
 soundWorld:reset()
 check(occupied:GetAttribute("Sfx_Pulse")==0 and not occupied:GetAttribute("Sfx_Active"),"removal and reset release playback state")
 local movingWorld=setupSounds()
 local ferry=model();local origin=CFrame.new();ferry.Parent={}
 function ferry:GetPivot()return origin end
 function ferry:PivotTo(frame)origin=frame end
 local route={points={{0,0,0},{15,0,0}},speed=15,pause=0,enabled=true}
 movingWorld:add(ferry,{id="ferry",position=Vector3.zero,rotation=Vector3.zero,motion=route,
  spin={axis={0,1,0},speed=45,pause=0,swing=30},interaction={solid=true,destructible=false,hp=10,fractions=Vector3.new(1,1,1)}})
 local link={parent="ferry",position={0,0,0},rotation={0,0,0}}
 local cfg=soundConfig("Entry","Both")
 local attached,sensor=volume(movingWorld,"attached",cfg,link)
 movingWorld:stepMotion(.1);movingWorld.sounds:step({},.1,movingWorld.moving)
 check(math.abs(sensor:GetPivot().Position.X-1.5)<.001 and math.abs(sensor:GetPivot().LookVector.X)>0,
  "an attached trigger inherits the model's accepted translation and swing")
 check(attached:GetAttribute("Sfx_Pulse")==0,"a trigger ignores its own moving parent")
 local accepted=sensor:GetPivot()
 movingWorld:prepareMotion(.1);movingWorld:advanceMotion(.1);movingWorld:finishMotion(false)
 movingWorld.sounds:step({},.1,movingWorld.moving)
 check((sensor:GetPivot().Position-accepted.Position).Magnitude<1e-7,"a blocked parent does not advance its attached trigger")
 ferry.Parent=nil
 movingWorld.sounds:step({},.1,movingWorld.moving)
 check((sensor:GetPivot().Position-accepted.Position).Magnitude<1e-7,"removing a parent preserves its child's last accepted pose")
 local direct=setupSounds()
 local filter=soundConfig("Entry","Specific");filter.targets={"moving"};filter.origin="Trigger"
 local targetOnly=volume(direct,"targetOnly",filter)
 local moving=model();local movePivot=CFrame.new(-30,0,0);moving.Parent={}
 function moving:GetPivot()return movePivot end
 function moving:PivotTo(frame)movePivot=frame end
 function moving:GetBoundingBox() return movePivot,Vector3.new(2,2,2) end
 direct:add(moving,{id="moving",position=Vector3.new(-30,0,0),rotation=Vector3.zero,motion={points={{0,0,0},{60,0,0}},speed=60,pause=0,enabled=true}})
 direct.sounds:step({tank("a",-20,20)},.1,direct.moving)
 check(targetOnly:GetAttribute("Sfx_Pulse")==0,"a persistent asset filter ignores tanks")
 direct:stepMotion(1);direct.sounds:step({},1,direct.moving)
 check(targetOnly:GetAttribute("Sfx_Pulse")==1,"relative sweep detects a selected moving asset crossing the entire trigger")
 for trigger in direct.sounds.entries do
  check(trigger.source.Value==moving.mesh,"trigger-owned playback uses the activating model's moving audio source")
 end
 local parent={id="mount",position={10,0,0},rotation={0,90,0}}
 local child={position={10,0,-2},rotation={0,90,0}}
 child.attachment=Attachment.relative(parent,child)
 parent.position={20,0,0}
 Attachment.apply(parent,child)
 check(math.abs(child.position[1]-20)<1e-6 and math.abs(child.position[3]+2)<1e-6,
  "local authored attachment round trips and follows translated parents")
 local State=require(Shared.WorldEditorState)
 parent.asset="Builtin/BW_crate";child.id="speaker";child.sound=soundConfig("Entry","Specific");child.sound.targets={parent.id}
 local draft=State.new({objects={parent,child},spawns={}})
 draft.selection[parent.id]=true;draft.selection[child.id]=true
 draft:duplicate()
 local newParent,newChild=draft.document.objects[3],draft.document.objects[4]
 check(newChild.attachment.parent==newParent.id and newChild.sound.targets[1]==newParent.id,"duplicate group remaps both link and trigger ID")
 draft.selection={[newParent.id]=true};draft:delete()
 check(newChild.attachment==nil and #newChild.sound.targets==0,"deleting the parent detaches the child and prunes trigger references")
 check(draft:undo() and draft:find(newChild.id).attachment.parent==newParent.id,"undo restores the attachment and trigger target")
 local populated=setupSounds()
 local close=volume(populated,"close",soundConfig("Entry","Tanks"))
 for n=1,260 do volume(populated,"distant_"..n,soundConfig("Entry","Tanks"),nil,(n%13)*48-288,96+math.floor(n/13)*40) end
 local tests=0;local overlap=Audio.overlap
 Audio.overlap=function(...) tests+=1;return overlap(...) end
 populated.sounds:step({tank("a",-20,20)},.05,{})
 Audio.overlap=overlap
 check(tests==1 and close:GetAttribute("Sfx_Pulse")==1,"spatial queries avoid narrow-phase checks on hundreds of distant triggers")
 local ground=setupSounds()
 local thump=volume(ground,"thump",soundConfig("Entry","Terrain"))
 local function height() return 0 end
 ground.sounds:step({tank("a",-20,20)},.1,{},nil)
 check(thump:GetAttribute("Sfx_Pulse")==0,"terrain-only filters ignore passing tanks")
 ground.sounds:step({},.1,{},height)
 ground.sounds:step({},.6,{},height)
 check(thump:GetAttribute("Sfx_Pulse")==1,"continuous ground contact plays only one thump")
 for block in ground.sounds.terrain do
  local resting=block.frame
  block.previous=resting;block.frame=CFrame.new(0,10,0)*resting
  ground.sounds:step({},.3,{},height)
  block.previous=block.frame;block.frame=resting
  ground.sounds:step({},.3,{},height)
 end
 check(thump:GetAttribute("Sfx_Pulse")==2,"lifting off and touching down re-arms the terrain trigger")
 local flat=CFrame.new(0,2,0)
 local half=Vector3.new(.5,.5,.5)
 local inside,passed=Audio.terrainOverlap(CFrame.new(-2,2,0),CFrame.new(2,2,0),half,function(point)
  return if math.abs(point.X)<.25 then 2 else 0
 end,false)
 check(not inside and passed,"sweeping over a narrow crest detects a momentary terrain hit")
 check(not Audio.terrainOverlap(flat,flat,half,height,false),"a trigger above the terrain stays off")
 local corner=CFrame.new(0,math.sqrt(2),0)*CFrame.Angles(0,0,math.pi/4)
 check(Audio.terrainOverlap(corner,corner,Vector3.one,height,false),"a rotated block triggers on corner-to-ground contact")
 mt.__index=oldIndex
end
CFrame.new=saveNew; CFrame.Angles=saveAngles; CFrame.lookAt=saveLookAt
print(string.format("Imported world object suite passed: %d assertions",checks))
