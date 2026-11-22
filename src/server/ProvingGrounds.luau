local Course={}
Course.__index=Course
local requiredHits=3
function Course.new(layout)
 return setmetatable({layout=layout,targets={},nextVolley=0,turretIndex=1},Course)
end
function Course:begin(tank,time)
 tank.course={phase="Ravine Crossing",started=time,targets={},hits=0,nextGate=1}
 self:publish(tank,time)
end
function Course:publish(tank,time)
 local run=tank.course
 local display=tank.state.course or {required=requiredHits}
 display.phase=run.phase;display.elapsed=run.finished or time-run.started;display.hits=run.hits
 display.bridgePassed=run.nextGate-1;display.bridgeTotal=#self.layout.bridgeGates
 display.destination=if run.phase=="Ravine Crossing" then (if run.nextGate<=display.bridgeTotal then "Follow the bridge markers" else "Follow the east bank to the range")
  elseif run.phase=="Moving Target Range" then (if run.hits<requiredHits then "Hit all three moving targets" else "Follow the orange route north to the Cannon Court")
  elseif run.phase=="Bullet Gauntlet" then "Cross to the green finish line" else nil
 tank.state.course=display
end
function Course:advance(tank,time)
 local run=tank.course
 local p=tank.state.position
 local layout=self.layout
 if run.phase=="Ravine Crossing" then
  local gate=layout.bridgeGates[run.nextGate]
  if gate and (p-gate).Magnitude<=5 then run.nextGate+=1 end
  if not gate and (p-layout.range).Magnitude<11 then run.phase="Moving Target Range" end
 elseif run.phase=="Moving Target Range" then
  if run.hits>=requiredHits and p.Z<=layout.gauntlet.Z and p.Z>=layout.gauntlet.Z-10 and math.abs(p.X-layout.gauntlet.X)<=36 then
   run.phase="Bullet Gauntlet"
  end
 elseif run.phase=="Bullet Gauntlet" then
  local court=layout.court
  if p.X<court.x0 or p.X>court.x1 or p.Z>court.z1+3 then
   run.phase="Moving Target Range";run.courtMidpoint=false
  elseif math.abs(p.Z-(court.z0+court.z1)/2)<=8 then
   run.courtMidpoint=true
  elseif run.courtMidpoint and p.Z<=layout.finish.Z then
   run.phase="Complete";run.finished=time-run.started
  end
 end
end
function Course:hit(target,tank,run)
 local id=self.targets[target]
 if id and tank and run and tank.course==run and run.phase=="Moving Target Range" and not run.targets[id] then
  run.targets[id]=true;run.hits+=1
 end
end
function Course:fromFiringLine(position)
 local line=self.layout.range
 return position.X>=line.X-10 and position.X<=line.X+8 and math.abs(position.Z-line.Z)<=20
end
function Course:step(time,fire,gauntlet,range)
 if not gauntlet then self.nextVolley=0;self.turretIndex=1 end
 if gauntlet and time>=self.nextVolley then
  fire(self.layout.turrets[self.turretIndex])
  self.turretIndex=self.turretIndex%#self.layout.turrets+1
  self.nextVolley=time+.68
 end
 if range then self.rangeStarted=self.rangeStarted or time
 elseif not self.rangeStarted then return
 else self.rangeStarted=nil end
 local elapsed=if self.rangeStarted then time-self.rangeStarted else 0
 for part,index in self.targets do
  part.Position=self:targetPosition(index,elapsed)
 end
end
function Course:targetPosition(index,time)
 local target=self.layout.rangeTargets[index]
 local travel=target.travel
 local offset=travel-math.abs((time*target.speed+travel*index*.6)%(4*travel)-2*travel)
 return self.layout.range+Vector3.new(target.distance,3.2,target.lane+offset)
end
return Course
