local P=require(Shared.BWParser)
local R=require(Shared.BWExecution)
local H=require(Shared.BWChassis)
local S=require(Shared.TankSimulation)
local D=require(Shared.BWDevices)
local Def=require(Shared.TankDefinitions)
local Controller=require("BWController")
local checks=0
local function check(v,m) checks+=1; assert(v,m) end
local function create(source,tank,config)
 local p,e=P.parse(source); assert(p,e and e.message)
 local s=S.new(Vector3.zero,tank or "Rattler")
 local h=config or H.default("Hexadeca")
 for device,field in {drivetrain="drivePerformance",turret="turretPerformance",weapon="weaponPerformance"} do s[field]=H.performance(h.devices[device].allocation) end
 return R.new(p,s,nil,h),s
end
local function advance(r,s,n,observer)
 for i=1,n do local command=r:step(s,1/60); if observer then observer(command,i) end; S.step(s,command,1/60,Vector2.new(1000,1000)) end
end
for _,source in {'forward()','back()','steer_left(20)','steer_right(35)','steer_center()','stop()','CONST a = 20\nsteer_right(a)'} do check(P.parse(source),source) end
for _,source in {'steer_left()','steer_center(1)','stop(1)','steer_right(-1)','steer_left("x")','steer_right(to=20)','steer_right(181)','forward(null)','back(1,2)'} do local p,e=P.parse(source); check(not p and e.line==1,"invalid "..source) end
local r,s=create('steer_right(20)\nforward()')
advance(r,s,360)
check(r.status=="running" and r.threads[1].state=="finished","persistent drive keeps runtime alive")
check(math.abs(s.steeringAngle+math.rad(20))<1e-6 and s.yaw< -6,"smooth repeated circles")
check(s.speed>29 and r.cyclesSpent==2,"continuous motion no repeated ticks")
check(r.devices.devices.drivetrain.active.continuous and #r.devices.devices.drivetrain.queue==0,"one active owner")
local firstId=r.devices.devices.drivetrain.active.id
local oldSpeed=s.speed
r:stop(); local release=r:step(s,1/60)
check(release.throttle==0 and r.devices.steering==0 and r.devices:status(firstId).state=="cancelled","program cancel releases persistent controls")
S.step(s,release,1/60); check(s.speed>0 and s.speed<oldSpeed,"coasting instead of zeroing velocity")
local changing,cs=create('steer_right(20)\nforward()\nclock = get_clock()\nwait_for_clock(clock.time + 3)\nsteer_left(20)')
local negative,positive=false,false; local minSpeed=100
advance(changing,cs,360,function(c,i) if i>120 then minSpeed=math.min(minSpeed,cs.speed); negative=negative or c.steer<0; positive=positive or c.steer>0 end end)
check(negative and positive and minSpeed>29,"right-to-left transition without restart/braking")
local repeatR,rs=create('a = steer_right(20)\nb = steer_right(20)\nforward()')
advance(repeatR,rs,90); check(math.abs(rs.steeringAngle+math.rad(20))<1e-5,"absolute repeated setpoint")
check(repeatR.variables.a.steeringDegrees==repeatR.variables.b.steeringDegrees and repeatR.devices:status(repeatR.variables.a.commandId).state=="completed","setpoint completion status")
local clamped,cl=create('a = steer_right(35)\nforward()'); advance(clamped,cl,90)
check(math.abs(cl.steeringAngle)<=Def.Rattler.Drive.MaxSteer and math.abs(clamped.variables.a.steeringDegrees+math.deg(Def.Rattler.Drive.MaxSteer))<1e-8,"hardware angle clamp")
local reverse,rv=create('steer_right(20)\nback()'); advance(reverse,rv,120)
check(rv.speed< -17 and rv.yaw>0,"reverse yaw naturally reverses")
local finite,fs=create('steer_right(20)\nforward(100)'); advance(finite,fs,600)
check(finite.status=="completed" and fs.yaw< -4,finite.message.." finite arc completes beyond start-axis limit")
local stop,st=create('forward()\nc = get_clock()\nwait_for_clock(c.time + 2)\nstop()')
advance(stop,st,120); local before=st.speed
advance(stop,st,12); check(stop.status=="completed" and st.speed>0 and st.speed<before,"stop uses physics coast")
advance(stop,st,120); check(math.abs(st.speed)<0.001,"stop settles")
local center,ce=create('steer_right(20)\nforward()\nc = get_clock()\nwait_for_clock(c.time+2)\nsteer_center()')
advance(center,ce,240); check(math.abs(ce.steeringAngle)<1e-6 and ce.speed>29,"center maintains speed")
local boomer,bs=create('a = steer_right(20)\nturn_right(90)',"Boomer"); advance(boomer,bs,180)
check(boomer.variables.a.status=="success" and boomer.status=="completed" and bs.yaw< -1.5,"Boomer now supports track steering and preserves pivot")
local bc,bcs=create('forward()',"Boomer"); advance(bc,bcs,60); check(bcs.position.Z< -10,"Boomer continuous compatible")
local devices=D.new(H.default("Bunny"),S.new(Vector3.zero,"Rattler"))
local function submit(op,value,t) return devices:submit("drivetrain",{op=op,value=value,line=1},t or 0,1) end
local a=submit("forward",100); local b=submit("back",10)
local continuous=submit("forward")
check(devices:status(a.commandId).state=="cancelled" and devices:status(b.commandId).state=="cancelled","continuous replaces active and pending finite work")
local finiteResult=submit("back",5)
check(devices:status(continuous.commandId).state=="cancelled" and devices.devices.drivetrain.active.id==finiteResult.commandId,"finite replaces continuous")
local queued=submit("turn_right",90); local steering=submit("steer_left",10)
check(steering.status=="success" and devices.devices.drivetrain.active.id==finiteResult.commandId and #devices.devices.drivetrain.queue==1,"steering bypasses full FIFO without touching navigation")
local stopped=submit("stop")
check(stopped.status=="success" and not devices:busy() and devices:status(queued.commandId).state=="cancelled","stop clears active and queued")
local concurrent,co=create('with thread(1):\n    a = forward()\n    steer_right(10)\nwith thread(2):\n    b = back()\n    steer_left(15)')
advance(concurrent,co,60)
check(co.speed<0 and concurrent.devices.steering>0 and concurrent.devices:status(concurrent.variables.a.commandId).state=="cancelled","deterministic ascending threads, last submission wins")
local disabled=H.default("Hexadeca"); disabled.devices.drivetrain.allocation=0
local dr,ds=create('a = forward()\nb = steer_left(20)\nc = stop()',nil,disabled); advance(dr,ds,6)
check(dr.variables.a.reason=="deviceDisabled" and dr.variables.b.reason=="deviceDisabled" and dr.variables.c.status=="success" and ds.speed==0,"zero allocation blocks operating, safety stop accepted")
local partial=H.default("Hexadeca"); partial.devices.drivetrain.allocation=50
local pr,ps=create('forward()',nil,partial); advance(pr,ps,120)
check(math.abs(ps.speed-22.5)<1e-6,"existing nonlinear drivetrain performance")
local destroyed,death=create('steer_right(20)\nforward()'); advance(destroyed,death,60); death.health=0
check(destroyed:step(death,1/60).throttle==0 and not destroyed.devices:busy() and destroyed.devices.steering==0,"death cleanup")
local replaced,rep=create('forward()'); advance(replaced,rep,6); rep.generation+=1
check(replaced:step(rep,1/60).throttle==0 and not replaced.devices:busy(),"generation cleanup")
-- Actual server ownership glue: Stop/replacement returns manual ownership.
local tank={state=S.new(Vector3.zero,"Rattler"),hardware=H.forTank("Rattler"),lastBWRequest=1}
check(Controller.start(tank,'steer_right(20)\nforward()'),"controller start")
for _=1,60 do local c=Controller.input(tank,1/60); S.step(tank.state,c,1/60) end
check(Controller.stop(tank) and Controller.input(tank,1/60)==nil and tank.command.throttle==0,"manual control restoration")
check(Controller.start(tank,'forward()') and Controller.start(tank,'stop()'),"program replacement")
Controller.input(tank,1/60); check(not Controller.running(tank) and Controller.input(tank,1/60)==nil,"replacement releases old drive")
local invalidRuntime,ir=create('angle = -1\na = steer_left(angle)\ncontinued = true'); advance(invalidRuntime,ir,12)
check(invalidRuntime.variables.a.reason=="invalidArgument" and invalidRuntime.variables.continued,"computed invalid angle nonfatal")
local br,brs=create('steer_left(20)\nback(50)'); advance(br,brs,420)
check(br.status=="completed" and brs.yaw< -2,"finite reverse follows persistent steering")
local navigating,ns=create('steer_left(10)\nforward()\nc = get_clock()\nwait_for_clock(c.time+1)\nturn_right(45)\nforward(4)')
advance(navigating,ns,900)
check(navigating.status=="completed" and navigating.devices.commands[2].state=="cancelled","high-level turn replaces continuous and finishes through normal physics")
local damage,dm=create('steer_right(20)\nforward()'); advance(damage,dm,60); dm.immobilized=true
local filtered=require(Shared.DamageEffects).input(dm,damage:step(dm,1/60))
check(filtered.throttle==0 and filtered.steer==0 and damage.status=="running","existing server immobilization filters persistent controls")
advance(damage,dm,60); dm.immobilized=false; advance(damage,dm,60)
check(dm.speed>20 and dm.steeringAngle<0,"persistent intent resumes after temporary damage")
local blocked,blockedState=create('forward()'); blocked.config.devices.drivetrain=nil
-- Installed hardware is validated at submission; removing a fixture device fails cleanly.
blocked.devices.devices.drivetrain=nil; advance(blocked,blockedState,6)
check(blocked.status=="completed" and not blocked.devices:busy(),"missing drivetrain operational failure")
local timeout,ts=create('forward()'); timeout.elapsed=180
check(timeout:step(ts,1/60).throttle==0 and timeout.status=="error" and not timeout.devices:busy(),"program timeout releases persistent drive")
local aborted,ab=create('a = forward()\nc = get_clock()\nwait_for_clock(c.time+1)\nabort_command("drivetrain")'); advance(aborted,ab,120)
check(aborted.status=="completed" and aborted.devices:status(aborted.variables.a.commandId).state=="cancelled","queue management can abort continuous work")
local smooth,sm=create('steer_right(20)\nforward()'); local yaw=sm.yaw
local firstCommand=smooth:step(sm,1/60)
check(sm.yaw==yaw and (sm.steeringAngle or 0)==0,"submission does not alter pose or actual wheel angle")
S.step(sm,firstCommand,1/60)
check(math.abs(sm.steeringAngle)>0 and math.abs(sm.steeringAngle)<math.rad(20),"existing steering rate smoothing preserved")
local sensorDrive,sd=create('steer_right(20)\nforward()\nwhile true:\n    scan = Scanner(position=2)\n    if scan.status == "success" and scan.count > 0:\n        target = scan.detections[0]\n        if target.type == "tank" and target.distance < 40:\n            steer_right(10)')
local V=require(Shared.BWValue)
sensorDrive.devices.services.scan=function(angle,performance,time)
 return V.observation(V.result(nil,{count=1,sensor=angle,timestamp=time,range=150,detections=V.array({V.dictionary({type="tank",distance=20},true)})}),time,sd.position,sd.yaw)
end
local uninterrupted=true
advance(sensorDrive,sd,180,function(command) uninterrupted=uninterrupted and command.throttle==1 end)
check(uninterrupted and sensorDrive.scanCount>10 and sd.speed>29 and math.abs(sd.steeringAngle+math.rad(10))<1e-6,"scanner waits and loop steering do not interrupt continuous drive")
print('BW steering/continuous suite passed: '..checks..' assertions')
