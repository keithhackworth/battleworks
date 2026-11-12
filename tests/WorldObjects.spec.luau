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
local function setup(options)
 local registry=Objects.new(); local m=model()
 local interaction={solid=true,destructible=true,hp=150,fractions=Vector3.new(.18,.45,.18)}
 for k,v in options or {} do interaction[k]=v end
 local spec={id="tree-large",position=Vector3.zero,rotation=Vector3.zero,interaction=interaction}
 local r=registry:add(m,spec); return registry,r,m
end
local registry,r,m=setup()
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
CFrame.new=saveNew; CFrame.Angles=saveAngles; CFrame.lookAt=saveLookAt
print(string.format("Imported world object suite passed: %d assertions",checks))
