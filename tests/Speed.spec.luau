local Telemetry=require("MovementTelemetry")
local Hud=require("SpeedDebugHud")
local Sim=require("TankSimulation")
local Weapon=require("RattlerWeapon")
local Recoil=require("RattlerRecoil")
local count=0
local function check(ok,message) assert(ok,message); count+=1 end
local s=Sim.new(Vector3.new(3,12,4),"Rattler")
Telemetry.update(s,Vector3.zero,0.5)
check(s.movementSpeedXZ==10 and s.movementSpeedY==24 and s.movementSpeed3D==26,"XZ, vertical and total speeds are measured independently")
s.position=Vector3.new(3,17,4)
Telemetry.update(s,Vector3.new(3,12,4),0.5)
check(s.movementSpeedXZ==0 and s.movementSpeedY==10 and s.movementPeakXZ==10,"vertical hopping does not masquerade as horizontal boost")
Telemetry.update(s,s.position,1/60)
check(s.movementSpeedXZ==0,"blocked tank reports zero movement despite intended throttle")
s.generation=1
Telemetry.update(s,s.position,1/60)
check(s.movementPeakXZ==0,"respawn or redraw generation resets peak")
s.tankType="Boomer"
Telemetry.update(s,s.position,1/60)
check(s.telemetryType=="Boomer" and s.movementPeakXZ==0,"switching types does not inherit previous peak")
local cmd={throttle=1,steer=0,aimMode="Rate",turretX=0,turretY=0}
local function run(direction)
 local state=Sim.new(Vector3.new(0,0,40),"Rattler",13579)
 state.speed=30; state.velocityX=0; state.velocityZ=-30; state.turretYaw=math.pi
 local w=Weapon.new()
 for _=1,180 do
  local shot=Weapon.step(w,true,true,1/60)
  state.firing=w.firing; state.heat=w.heat
  local previous=state.position
  Sim.step(state,cmd,1/60)
  Telemetry.update(state,previous,1/60)
  if shot then Recoil.kick(state,w.heat,direction) end
 end
 return state.movementPeakXZ
end
local boosted=run(Vector3.new(0,0,1))
local unboosted=run(Vector3.new(0,0,-1))
check(boosted>30.5 and boosted<=36.00001,"backward gun recoil can exceed full driving speed without breaking recoil cap")
check(unboosted<=30.00001,"forward firing does not create a forward speed bonus")
local hud=Hud.new(Instance.new("ScreenGui"))
hud:update({tankType="Rattler",movementSpeedXZ=36,movementPeakXZ=36,movementSpeedY=20,movementSpeed3D=41.2})
check(string.find(hud.label.Text,"36.0 studs/s",1,true)~=nil and string.find(hud.label.Text,"BOOST +6.0 (+20%)",1,true)~=nil,"HUD displays measured horizontal boost versus normal drive speed")
hud:update(nil)
check(string.find(hud.label.Text,"waiting",1,true)~=nil,"HUD handles missing tank")
hud:destroy(); check(hud.label.destroyed,"speed HUD cleans up its label")
local saved=game.GetService
game.GetService=function(self,name)
 if name=="RunService" then return {IsStudio=function() return false end} end
 return saved(self,name)
end
check(Hud.new(Instance.new("ScreenGui"))==nil,"speed debug HUD stays Studio-only")
game.GetService=saved
print(string.format("Speed telemetry suite passed: %d assertions; backward-firing peak %.2f studs/sec (normal 30)",count,boosted))
