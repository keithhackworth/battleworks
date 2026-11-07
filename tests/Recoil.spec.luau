local Recoil=require("RattlerRecoil")
local Sim=require("TankSimulation")
local Weapon=require("RattlerWeapon")
local Definitions=require("TankDefinitions")
local Environment=require("Environment")
local count=0
local function check(ok,message) assert(ok,message); count+=1 end
local neutral={throttle=0,steer=0,fire=false,aimMode="Rate",turretX=0,turretY=0}
local function state(seed,ground)
 local s=Sim.new(Vector3.new(0,ground or 0,0),"Rattler",seed)
 s.groundPlaneY=ground or 0; s.groundHeight=ground or 0
 return s
end
-- One shot creates an immediate physical launch, with a 4–5 stud ballistic apex.
for _,seed in {1,101,13579,999999} do
 local s=state(seed,12); s.firing=true
 Recoil.kick(s,0,Vector3.new(0,0,-1))
 check(s.verticalSpeed>37 and s.lift==nil,"initial round applies velocity without teleporting height")
 local peak=0
 for _=1,90 do
  Sim.step(s,neutral,1/120)
  peak=math.max(peak,s.lift)
  check(s.lift<=6 and s.position.Y>=s.groundHeight,"single-hop motion obeys actual ground and ceiling")
 end
 check(peak>=3.99 and peak<=5.01,"initial shot reaches 4–5 studs above local ground")
 check(s.lift==0 and s.verticalSpeed==0 and s.landingImpact>35,"tank falls rapidly and lands hard")
end
-- Horizontal force opposes the barrel heading, not chassis forward.
for _,yaw in {0,math.pi/2,math.pi} do
 for _,dir in {Vector3.new(1,-0.6,0),Vector3.new(0,-0.6,1),Vector3.new(-1,-0.6,0)} do
  local s=state(123); s.yaw=yaw
  Recoil.kick(s,0,dir)
  local dot=s.velocityX*dir.X+s.velocityZ*dir.Z
  check(dot<0,"recoil shove opposes actual shot regardless of chassis yaw")
  if dir.Z==0 then check(math.abs(s.velocityZ)<1e-8,"sideways fire creates a sideways shove") end
  if dir.Z>0 then check(s.velocityZ<0,"backward fire pushes tank forward") end
 end
end
-- Airborne steering/braking/throttle cannot redirect or erase world momentum.
do
 local a=state(12); a.position=Vector3.new(0,4,0); a.lift=4; a.verticalSpeed=0
 a.velocityX=5; a.velocityZ=-7; a.yaw=0.7
 local b=table.clone(a)
 local input={throttle=-1,steer=1,fire=false,aimMode="Rate",turretX=1,turretY=1}
 for _=1,10 do
  Sim.step(a,input,1/60); Sim.step(b,neutral,1/60)
  check(math.abs(a.position.X-b.position.X)<1e-8 and math.abs(a.position.Z-b.position.Z)<1e-8,"airborne input cannot change horizontal path")
  check(a.velocityX==5 and a.velocityZ==-7 and a.yaw==0.7,"airborne world velocity and chassis yaw stay unchanged")
 end
 check(a.turretYaw~=b.turretYaw,"turret aiming remains available in the air")
 for _=1,60 do Sim.step(a,input,1/60) end
 check(a.lift==0 and a.yaw~=0.7,"driving and steering resume after ground contact")
end
local function replay(seed)
 local s=state(seed); local w=Weapon.new()
 local record,launchTimes={},{}
 local lastVelocity=0
 for i=1,300 do
  local fire=i<=180
  local shot=Weapon.step(w,true,fire,1/60)
  s.firing=w.firing; s.heat=w.heat
  local command=table.clone(neutral); command.throttle=if i<80 then 1 else -1; command.steer=math.sin(i)*0.8
  Sim.step(s,command,1/60)
  if shot then Recoil.kick(s,w.heat,Vector3.new(0,0,-1)) end
  if s.verticalSpeed>0 and lastVelocity<=0 then table.insert(launchTimes,i) end
  lastVelocity=s.verticalSpeed
  table.insert(record,{s.position.X,s.position.Y,s.position.Z,s.verticalSpeed,s.flightPitch,s.flightRoll,s.recoilSeed,s.yaw})
  check(s.lift>=0 and s.lift<=6+1e-8,"sustained fire never leaves six-stud local height envelope")
  check(math.abs(s.verticalSpeed)<=Definitions.Rattler.Recoil.MaxFallSpeed,"hop velocity remains bounded")
 end
 return s,record,launchTimes
end
local a,first,times=replay(13579)
local b,second,otherTimes=replay(13579)
local c,different=replay(24680)
local changed=false
for i,row in first do
 for k,value in row do check(value==second[i][k],"same fixed-step input and seed reproduce motion exactly") end
 changed=changed or math.abs(row[2]-different[i][2])>0.1
end
check(changed,"different seeds produce different physical recoil")
check(#times>=5 and #otherTimes==#times,"sustained fire produces repeated hops rather than hovering")
local irregular=false
for i=3,#times do irregular=irregular or times[i]-times[i-1]~=times[i-1]-times[i-2] end
check(irregular,"seeded recoil timing is not a periodic bouncing loop")
local low,mid,air=0,0,0
for i=25,180 do
 local height=first[i][2]
 if height<1 then low+=1 end
 if height>=3 and height<=5.1 then mid+=1 end
 if height>0.1 then air+=1 end
end
check(mid>air*0.45,"continuous firing spends most elevated time in the 3–5 stud band")
check(low>0 and a.landingSerial>=2,"occasional full thuds occur during sustained firing")
check(a.lift==0 and a.verticalSpeed==0 and math.abs(a.bounce)<0.01,"stop firing lands and settles instead of hovering")
-- Ground sampling is the real support profile plus arena elevation, not Y=0.
do
 local hill={zones={},trees={},logs={},rocks={{x=0,z=0,rx=20,rz=20,height=2.8}}}
 local s=state(101,7); Sim.step(s,neutral,1/60,Vector2.new(230,230),hill)
 check(math.abs(s.position.Y-9.8)<1e-6,"grounded tank follows actual raised rock surface")
 s.firing=true; Recoil.kick(s,0,Vector3.new(0,0,-1))
 for _=1,120 do
  Sim.step(s,neutral,1/120,Vector2.new(230,230),hill)
  local height=Environment.pose(hill,s.position,s.yaw)+7
  check(math.abs(s.groundHeight-height)<1e-8 and s.position.Y-height<=6+1e-8,"hops stay bounded above sampled nonzero ground")
 end
 check(s.lift==0 and s.position.Y>9,"landing uses terrain beneath the actual horizontal position")
end
-- Extreme shot frequency cannot accumulate upward energy or override map collision.
do
 local s=state(53); s.firing=true
 for _=1,1000 do
  Recoil.kick(s,3,Vector3.new(1,0,0)); Sim.step(s,neutral,1/120)
  check(s.lift<=6+1e-8,"rapid recoil cannot accumulate altitude beyond limit")
 end
 s.position=Vector3.new(109.9,3,0); s.lift=3; s.verticalSpeed=0; s.velocityX=20; s.velocityZ=0
 Sim.step(s,neutral,1/60,Vector2.new(230,230))
 check(s.position.X==110 and s.velocityX==0,"world boundary stops airborne recoil momentum")
 local obstacles={zones={},rocks={},logs={},trees={{x=0,z=0,radius=1}}}
 s.position=Vector3.new(0,3,6.1); s.lift=3; s.velocityX=0; s.velocityZ=-20
 Sim.step(s,neutral,1/60,Vector2.new(230,230),obstacles)
 check(s.position.Z==6.1 and s.velocityZ==0,"tree collision stops airborne recoil movement")
end
-- Motion uses a distinct RNG stream and never consumes the accuracy ledger.
do
 local recoil=state(1); local weapon={aimSeed=999,heat=2}
 for _=1,30 do Recoil.kick(recoil,weapon.heat,Vector3.new(0,0,-1)) end
 check(weapon.aimSeed==999,"random physical motion does not draw weapon-accuracy randomness")
end
-- Strong seeded L/R throws accompany every round, without long one-side runs.
do
 local s=state(731); s.firing=true
 local left,right=0,0
 for _=1,90 do
  Recoil.kick(s,0,Vector3.new(0,0,-1))
  check(math.abs(s.flightRoll)>=math.rad(7) and math.abs(s.flightRoll)<=math.rad(10),"each round gives a pronounced 7–10 degree roll")
  check(s.rollStreak<=2,"irregular rocking cannot stick on the same side")
  check(math.abs(s.bodyRoll-s.flightRoll)<1e-6,"visible physical hull roll updates on the shot tick")
  if s.flightRoll<0 then left+=1 else right+=1 end
  Sim.step(s,neutral,0.1)
 end
 check(left>20 and right>20,"firing rocks strongly in both directions")
 s.firing=false
 for _=1,240 do Sim.step(s,neutral,1/60) end
 check(math.abs(s.flightRoll)<1e-8 and math.abs(s.bodyRoll)<1e-6,"cartoon lurches settle after firing stops")
end
print(string.format("Jackhammer recoil suite passed: %d assertions; %d hops, %d near-ground samples, %d mid-band samples",count,#times,low,mid))
