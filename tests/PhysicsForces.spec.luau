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
