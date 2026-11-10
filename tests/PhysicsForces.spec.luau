local M=require(Shared.VehicleMotion)
local Surface=require(Shared.SurfacePhysics)
local checks=0
local function check(v,m) checks+=1; assert(v,m) end
local function near(a,b) return math.abs(a-b)<1e-7 end
local function body() local b={position=Vector3.zero,yaw=0}; M.configure(b,2,4); return b end
local a=body(); M.force(a,Vector3.new(4,0,0)); M.beginStep(a,.5)
check(near(a.linearVelocity.X,1),"force uses acceleration times dt")
M.beginStep(a,.5); check(near(a.linearVelocity.X,1),"force consumed once")
M.impulse(a,Vector3.new(4,0,0)); check(near(a.linearVelocity.X,3),"impulse independent of timestep")
M.impulse(a,Vector3.new(0,0,-4),Vector3.new(2,0,0)); check(near(a.angularVelocity.Y,2),"off-center impulse produces yaw")
local centered=body(); M.impulse(centered,Vector3.new(0,0,-4),Vector3.zero); check(centered.angularVelocity.Y==0,"centered impulse has no spin")
M.integrateHorizontal(a,.1); check(near(a.yaw,.2),"angular velocity integrates yaw")
local regions={
 {id="ice",priority=1,x=0,z=0,rx=10,rz=10,transition=2,surface=Surface.Profiles.Ice},
 {id="normal",priority=2,x=0,z=0,rx=2,rz=2,surface=Surface.Profiles.Normal},
}
local prepared=Surface.prepare(regions)
local friction=Surface.sample(prepared,5,0); check(near(friction,.025),"invisible region overrides surface")
check(Surface.sample(prepared,0,0)==16,"higher priority wins")
check(Surface.sample(prepared,20,0)==16,"outside returns base")
local blended=Surface.sample(prepared,9,0); check(blended>.025 and blended<16,"boundary blends into underlying field")
local reversed=Surface.prepare({regions[2],regions[1]}); check(Surface.sample(prepared,9,0)==Surface.sample(reversed,9,0),"region insertion order irrelevant")
check(not pcall(Surface.prepare,{regions[1],regions[1]}),"duplicate IDs rejected")
print(string.format("Physics forces suite passed: %d assertions",checks))
local Sim=require(Shared.TankSimulation)
local Components=require(Shared.VehicleComponents)
local Input=require(Shared.InputCommand)
local Environment=require(Shared.Environment)
local function tank() return Sim.new(Vector3.zero,"Rattler") end
local normal={zones={},trees={},rocks={},logs={}}
local ice={zones={},trees={},rocks={},logs={},physicsSurfaces=Surface.prepare({{id="invisible-ice",x=0,z=0,rx=1000,rz=1000,surface=Surface.Profiles.Ice}})}
local neutral=Input.neutral()
local forward=Input.neutral(); forward.throttle=1
local function run(s,input,n,env) for _=1,n do Sim.step(s,input,1/60,Vector2.new(2000,2000),env) end end
local stopped=tank(); M.force(stopped,Vector3.new(1,0,0)); run(stopped,neutral,1,ice)
check(stopped.linearVelocity.Magnitude<1e-7,"static friction holds small force on ice")
local sliding=tank()
for _=1,60 do M.force(sliding,Vector3.new(8,0,0)); run(sliding,neutral,1,ice) end
check(sliding.linearVelocity.X>3 and sliding.position.X>1,"force beyond static threshold causes kinetic sliding")
local normalStop,iceStop=tank(),tank()
M.setVelocity(normalStop,Vector3.new(0,0,-20)); M.setVelocity(iceStop,Vector3.new(0,0,-20))
run(normalStop,neutral,60,normal); run(iceStop,neutral,60,ice)
check(math.abs(iceStop.speed)>math.abs(normalStop.speed)+5,"ice braking retains momentum")
local sideNormal,sideIce=tank(),tank()
M.impulse(sideNormal,Vector3.new(8,0,0)); M.impulse(sideIce,Vector3.new(8,0,0))
run(sideNormal,forward,60,normal); run(sideIce,forward,60,ice)
check(sideIce.linearVelocity.X>sideNormal.linearVelocity.X+2,"lateral sliding lasts longer on ice")
local spinNormal,spinIce=tank(),tank()
M.angularImpulse(spinNormal,Vector3.new(0,Components.get(spinNormal).Chassis.YawInertia*3,0))
M.angularImpulse(spinIce,Vector3.new(0,Components.get(spinIce).Chassis.YawInertia*3,0))
run(spinNormal,neutral,30,normal); run(spinIce,neutral,30,ice)
check(math.abs(spinIce.angularVelocity.Y)>math.abs(spinNormal.angularVelocity.Y)+1,"angular momentum persists on low-grip surface")
local airborne=tank(); airborne.position=Vector3.new(0,4,0); airborne.lift=4
M.setVelocity(airborne,Vector3.new(5,0,-3)); M.setYawVelocity(airborne,2)
local airInput=Input.neutral(); airInput.throttle=-1; airInput.steer=-1
run(airborne,airInput,1,normal)
check(near(airborne.linearVelocity.X,5) and near(airborne.linearVelocity.Z,-3) and near(airborne.angularVelocity.Y,2),"airborne controls apply neither contact friction nor drive/steer torque")
check(near(airborne.yaw,2/60),"airborne angular momentum remains physical")
local fast=tank(); M.setVelocity(fast,Vector3.new(0,0,-70)); run(fast,forward,1,normal)
check(fast.speed>60,"propulsion rating is not a world speed clamp")
local recoil=require(Shared.RattlerRecoil)
local assembly=Components.copy(require(Shared.VehicleAssemblies).Rattler); assembly.Weapon="weapon.gatling"
local boost=Sim.new(Vector3.zero,"Rattler",1,assembly); M.setVelocity(boost,Vector3.new(0,0,-70)); recoil.kick(boost,0,Vector3.new(0,0,1))
check(boost.linearVelocity.Z<=-70+1e-7,"recoil cap cannot erase pre-existing overspeed")
local yawA,yawB=tank(),tank()
M.setVelocity(yawA,Vector3.new(3,0,-7)); M.setVelocity(yawB,Vector3.new(3,0,-7))
for _=1,120 do run(yawA,forward,1,ice); run(yawB,forward,1,ice); check(yawA.position.X==yawB.position.X and yawA.linearVelocity.Z==yawB.linearVelocity.Z,"deterministic force integration") end
check(near(yawA.speed,-math.sin(yawA.yaw)*yawA.linearVelocity.X-math.cos(yawA.yaw)*yawA.linearVelocity.Z),"legacy speed is a projection, not authority")
print(string.format("Physics motion/traction coverage passed: %d assertions",checks))
local Contacts=require(Shared.VehicleContacts)
local shape={Radius=1,HitboxHeight=.5,Hitbox={Y=1}}
local function record(id,x,z,vx,vz)
 local s={position=Vector3.new(x,0,z),yaw=0}; M.configure(s,2,2)
 M.setVelocity(s,Vector3.new(vx or 0,0,vz or 0))
 return Contacts.body(id,s,shape)
end
local function energy(r) local s=r.state; return .5*s.motionMass*s.linearVelocity.Magnitude^2+.5*s.yawInertia*s.angularVelocity.Y^2 end
local wall=Contacts.box("wall",Vector3.zero,.1,20,-1,3)
local straight=record("a",-4,0,30,0)
Contacts.solve({straight},{wall},.2)
check(straight.state.position.X<=-1.1+.001 and math.abs(straight.state.linearVelocity.X)<.001,"continuous contact blocks fast translation")
check(math.abs(straight.state.angularVelocity.Y)<.001,"centered face contact does not create artificial spin")
local glancing=record("a",-4,0,30,12); local beforeEnergy=energy(glancing)
Contacts.solve({glancing},{wall},.2)
check(glancing.state.linearVelocity.Z>1 and glancing.state.position.Z>0,"glancing wall contact retains tangential motion")
check(energy(glancing)<=beforeEnergy+1e-6,"contact does not add kinetic energy")
local missile=record("fast",-100,0,30000,0)
Contacts.solve({missile},{wall},1/60)
check(missile.state.position.X<=-1.1+.001,"swept contact prevents high-speed thin-wall tunneling")
local hitA,hitB=record("a",-4,1.5,30,0),record("b",0,0)
local initial=energy(hitA)+energy(hitB)
Contacts.solve({hitA,hitB},{},.2)
check(math.abs(hitA.state.angularVelocity.Y)+math.abs(hitB.state.angularVelocity.Y)>.1,"off-center body collision produces physical yaw")
check(near(hitA.state.linearVelocity.X+hitB.state.linearVelocity.X,30),"pair impulse conserves linear momentum")
check(energy(hitA)+energy(hitB)<=initial+1e-5,"off-center collision does not manufacture energy")
local function collisionReplay(reverse)
 local a,b,c=record("a",-2,0,10,0),record("b",0,0),record("c",2,0,-10,0)
 local bodies=if reverse then {c,b,a} else {a,b,c}
 Contacts.solve(bodies,{},.1)
 return a,b,c
end
local a1,b1,c1=collisionReplay(false); local a2,b2,c2=collisionReplay(true)
check(a1.state.position.X==a2.state.position.X and b1.state.linearVelocity.X==b2.state.linearVelocity.X and c1.state.angularVelocity.Y==c2.state.angularVelocity.Y,"multi-contact result independent of body insertion order")
local tight=record("tight",0,0)
local left=Contacts.box("left",Vector3.new(-1.9,0,0),1,10,-1,3)
local right=Contacts.box("right",Vector3.new(1.9,0,0),1,10,-1,3)
for _=1,120 do Contacts.solve({tight},{right,left},1/60) end
check(energy(tight)<1e-8 and math.abs(tight.state.position.X)<.2,"overconstrained tight contacts remain bounded without separation energy")
check(tight.state.motionCorrection~=nil,"penetration correction has separate progress ledger")
local contactAir=record("air",-3,0,30,0); contactAir.state.position=Vector3.new(-3,10,0)
Contacts.solve({contactAir},{wall},.2)
check(contactAir.state.position.X>0,"non-overlapping vertical intervals do not collide")
print(string.format("Physics contact coverage passed: %d assertions",checks))
local blendA={id="a",x=0,z=0,rx=10,rz=10,priority=4,surface=Surface.Profiles.Normal}
local blendB={id="b",x=0,z=0,rx=10,rz=10,priority=4,surface=Surface.Profiles.Ice}
local mix=Surface.sample(Surface.prepare({blendB,blendA}),0,0)
check(near(mix,(16+.025)/2),"equal-priority full regions blend instead of multiplying grip")
check(mix==Surface.sample(Surface.prepare({blendA,blendB}),0,0),"equal-priority blend is insertion-order independent")
local mutableProfile={staticFriction=.2,kineticFriction=.1,resistance=.4}
local mutableRegion={id="owned",x=0,z=0,rx=10,rz=10,surface=mutableProfile}
local isolated=Surface.prepare({mutableRegion}); mutableProfile.staticFriction=10; mutableRegion.x=100
check(near(Surface.sample(isolated,0,0),.2),"prepared surfaces do not leak source mutations")
check(not pcall(Surface.prepare,{{id="bad",x=0,z=0,rx=10,rz=10,surface={staticFriction=.1,kineticFriction=.2,resistance=1}}}),"invalid friction ordering rejected")
check(not pcall(M.configure,{},0,1),"zero mass rejected")
check(not pcall(M.impulse,body(),Vector3.new(0/0,0,0)),"non-finite impulse rejected")
local patch=Surface.prepare({{id="small",shape="box",x=0,z=0,rx=2,rz=10,surface=Surface.Profiles.Ice}})
check(Surface.contact(patch,Vector3.zero,0,Components.get("Rattler").Chassis)==16,"contact patch sampling differs correctly from center-only sampling")
local invisible=tank(); run(invisible,forward,1,ice)
check(invisible.surface=="Grass" and invisible.motionSlipping,"visual terrain kind is independent from physical grip")
local outside=record("outside",10000,10000)
Contacts.solve({outside},Contacts.obstacles(nil,Vector2.new(25,40)),1/60)
check(math.abs(outside.state.position.X)<=11.5001 and math.abs(outside.state.position.Z)<=19.0001,"infinite arena planes recover invalid initial positions")
check(energy(outside)==0,"deep boundary correction does not add energy")
print(string.format("Physics surface/validation coverage passed: %d assertions",checks))
-- Flight must land against the resolved position, not ground sampled behind
-- an obstacle in the unconstrained prediction.
local landing=tank(); landing.position=Vector3.new(0,1.5,0); landing.lift=1.5
M.setVelocity(landing,Vector3.new(480,-20,0))
local ledge={zones={},trees={},logs={},rocks={{x=8,z=0,rx=2,rz=4,height=3}}}
Sim.step(landing,neutral,1/60,Vector2.new(2000,2000),ledge,true)
Contacts.solve({Contacts.body("landing",landing,Components.get(landing).Chassis)},{Contacts.box("cover",Vector3.new(6,0,0),.5,10,0,10)},1/60)
Sim.reconcileGround(landing,ledge)
check(landing.position.X<.501 and landing.position.Y>1 and landing.position.Y<1.5,"resolved contact position controls vertical flight support")
check((landing.landingSerial or 0)==0 and landing.linearVelocity.Y< -20 and landing.motionDeferredDt==nil,"no phantom landing or duplicate gravity from deferred contacts")
local localFlight,serverFlight=tank(),tank()
for _,s in {localFlight,serverFlight} do s.position=Vector3.new(0,3,0); s.lift=3; M.setVelocity(s,Vector3.new(3,12,-5)); M.setYawVelocity(s,.3) end
for _=1,120 do
 Sim.step(localFlight,neutral,1/60,Vector2.new(2000,2000),normal)
 Sim.step(serverFlight,neutral,1/60,Vector2.new(2000,2000),normal,true)
 Contacts.solve({Contacts.body("server",serverFlight,Components.get(serverFlight).Chassis)},Contacts.obstacles(normal,Vector2.new(2000,2000)),1/60)
 Sim.reconcileGround(serverFlight,normal)
 check((localFlight.position-serverFlight.position).Magnitude<1e-8 and localFlight.linearVelocity.Y==serverFlight.linearVelocity.Y,"standalone and two-phase server flight are equivalent")
end
print(string.format("Physics resolved-flight coverage passed: %d assertions",checks))

local supported=tank(); M.force(supported,Vector3.new(0,Components.get(supported).Recoil.Gravity*.5,0)); run(supported,forward,1,normal)
check(supported.grounded and supported.position.Y==0 and supported.speed>0,"sub-weight upward force reduces normal load without fake takeoff or lost traction")
check((supported.landingSerial or 0)==0,"normal reaction does not create a phantom landing")
local lifted=tank(); M.force(lifted,Vector3.new(0,Components.get(lifted).Recoil.Gravity*2,0)); run(lifted,forward,1,normal)
check(not lifted.grounded and lifted.position.Y>0 and lifted.speed==0,"force exceeding weight lifts body and disables ground propulsion")
print(string.format("Physics support reaction coverage passed: %d assertions",checks))

local catalog=Components.copy(require(Shared.ComponentCatalog)); catalog["chassis.standard"].Properties.Mass=2
local heavyProfile=Components.resolve(assembly,catalog)
local lightGun=Sim.new(Vector3.zero,"Rattler",17,assembly)
local heavyGun=Sim.new(Vector3.zero,"Rattler",17,heavyProfile)
recoil.kick(lightGun,0,Vector3.new(1,0,0)); recoil.kick(heavyGun,0,Vector3.new(1,0,0))
check(near(heavyGun.linearVelocity.X*2,lightGun.linearVelocity.X),"horizontal weapon impulse respects physical chassis mass")
print(string.format("Physics recoil mass coverage passed: %d assertions",checks))
