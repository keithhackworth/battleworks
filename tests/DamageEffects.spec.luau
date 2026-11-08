local Effects=require("DamageEffects")
local Config=require("DamageEffectsConfig")
local Sim=require("TankSimulation")
local Parser=require("BWParser")
local Runtime=require("BWRuntime")
local Command=require("InputCommand")
local count=0
local function check(ok,message) assert(ok,message); count+=1 end
local function near(a,b) return math.abs(a-b)<1e-6 end
local function fresh(kind)
 local s=Sim.new(Vector3.zero,kind or "Boomer")
 return s,Effects.new(s)
end
local function hit(e,s,weapon,damage)
 local applied=math.min(s.health,damage); s.health-=applied; Effects.record(e,s,weapon,applied,Vector3.new(1,2,3))
end
local function untilActive(e,s,field)
 for _=1,180 do Effects.step(e,s,1/60); if s[field] then return end end
 error("status failed to start: "..field)
end
for _,sample in {{51,0},{50,1},{26,1},{25,2},{11,2},{10,3},{1,3}} do
 for _,weapon in {"Cannon","Gatling"} do
  local s,e=fresh(); hit(e,s,weapon,100-sample[1]); Effects.step(e,s,1/60)
  check(near(if weapon=="Cannon" then s.smokeSeverity else s.rattleSeverity,sample[2]),"configured HP band scales correct weapon")
  check((if weapon=="Cannon" then s.rattleSeverity else s.smokeSeverity)==0,"low HP never activates other weapon's handicap")
 end
end
local mixed,e=fresh()
hit(e,mixed,"Cannon",30); hit(e,mixed,"Gatling",40)
check(mixed.health==30 and mixed.damageByWeapon.Cannon==30 and mixed.damageByWeapon.Gatling==40,"cumulative actual damage attribution")
check(near(mixed.smokeSeverity,30/70) and near(mixed.rattleSeverity,40/70),"mixed weapons contribute independently by share")
untilActive(e,mixed,"immobilized")
check(mixed.immobilizedRemaining<=0.3*40/70+1e-6,"minority contribution scales handicap duration")
local smoke,se=fresh(); hit(se,smoke,"Cannon",75)
untilActive(se,smoke,"smokeBurst")
check(near(smoke.smokeRemaining,1.5),"second smoke band lasts 1.5 seconds")
local before=smoke.smokeRemaining
hit(se,smoke,"Gatling",1); Effects.step(se,smoke,1/60)
check(smoke.smokeRemaining<before,"new hit cannot refresh/extend active burst")
for _=1,100 do Effects.step(se,smoke,1/60) end
check(not smoke.smokeBurst and se.smoke.recovery>3,"smoke expires into minimum recovery")
local s,st=fresh(); hit(st,s,"Gatling",90)
local maxEpisode,episode,recovery,episodes=0,0,100,0
local was=false
for _=1,1800 do
 hit(st,s,"Gatling",0.0001)
 Effects.step(st,s,1/60)
 if s.immobilized then
  if not was then check(recovery>=Config.Rattle.MinRecovery-1/60,"every immobilization has a minimum recovery window"); episodes+=1; episode=0 end
  episode+=1/60; maxEpisode=math.max(maxEpisode,episode); recovery=0
 else recovery+=1/60 end
 was=s.immobilized
end
check(episodes>=5 and maxEpisode<=1+1/60,"continuous tiny impacts cannot create permanent stun-lock")
local filtered=Effects.input(s,{throttle=1,steer=1,fire=true,turretX=0.7,turretY=-0.2,aimMode="Rate"})
s.immobilized=true
local original={throttle=1,steer=1,fire=true,turretX=0.7,turretY=-0.2,aimMode="Rate"}
filtered=Effects.input(s,original)
check(filtered.throttle==0 and filtered.steer==0 and filtered.fire and filtered.turretX==0.7 and filtered.turretY==-0.2,"manual mobility filtered while aiming/firing preserved")
check(original.throttle==1 and original.steer==1,"input filtering never mutates held manual input")
local movement=Sim.new(Vector3.zero); movement.immobilized=true
Sim.step(movement,original,1/60)
check(movement.position.Magnitude==0 and movement.yaw==0 and movement.turretYaw~=0,"normal authoritative simulation enforces mobility handicap")
local flying=Sim.new(Vector3.zero,"Rattler"); flying.firing=true
require("RattlerRecoil").kick(flying,0.2,Vector3.new(0,0,-1))
flying.immobilized=true
local reference=table.clone(flying)
Sim.step(flying,original,1/60); Sim.step(reference,Command.neutral(),1/60)
check((flying.position-reference.position).Magnitude<1e-6 and near(flying.velocityZ,reference.velocityZ),"immobilization preserves airborne recoil and horizontal momentum")
for _,source in {"forward(10, best_effort=false)","turn_right(90, best_effort=false)"} do
 local state=fresh(); local runtime=Runtime.new(assert(Parser.parse(source)),state)
 state.immobilized=true
 for _=1,20 do runtime:step(state,0.1) end
 local current=runtime.current
 check(runtime.status=="running" and runtime.index==1 and current.progress==0 and current.noProgress==0,"temporary immobilization retains unfinished movement instruction")
 check(near(current.elapsed,0) and near(current.pauseUsed,2),"instruction/stuck deadlines receive bounded pause grace")
 state.immobilized=false
 for _=1,600 do
  local command=runtime:step(state,1/60); Sim.step(state,command,1/60)
  if runtime.status~="running" then break end
 end
 check(runtime.status=="completed" and runtime.skipped==nil,"same instruction resumes and completes through normal physics")
end
local blocked=fresh(); blocked.immobilized=true
local strict=Runtime.new(assert(Parser.parse("forward(100, best_effort=false)")),blocked)
for _=1,150 do strict:step(blocked,0.1) end
check(strict.status=="error" and strict.current.pauseUsed<=Config.MaxBWPausePerInstruction+1e-6,"recurring immobilization cannot extend an instruction indefinitely")
local best=Runtime.new(assert(Parser.parse("forward(100)\nfire()")),blocked)
for _=1,120 do best:step(blocked,0.1); if best.index==2 then break end end
check(best.index==2 and best.skipped==1,"best effort still handles genuine bounded execution failure")
for _,source in {"fire(1)","turret_right(90)"} do
 local state=fresh(); state.immobilized=true
 local runtime=Runtime.new(assert(Parser.parse(source)),state)
 local input=runtime:step(state,0.1)
 check(runtime.current.pauseUsed==0 and runtime.current.elapsed==0.1,"fire/turret commands never pause for mobility handicap")
 check(input.fire or input.turretX~=0,"weapon and turret remain usable during immobilization")
end
local dead,de=fresh(); hit(de,dead,"Cannon",50); untilActive(de,dead,"smokeBurst")
hit(de,dead,"Gatling",200)
check(dead.fatalWeapon=="Gatling" and dead.damageByWeapon.Gatling==50,"fatal weapon stored and overkill excluded from attribution")
check(not dead.smokeBurst and not dead.immobilized and dead.smokeSeverity==0 and dead.rattleSeverity==0,"destruction immediately stops all persistent statuses")
Effects.new(dead)
check(next(dead.damageByWeapon)==nil and dead.damageSerial==0 and dead.fatalWeapon==nil and not dead.immobilized,"reset clears damage history and status state")
print(string.format("Progressive damage/status/BW suite passed: %d assertions",count))
