local Course={}
Course.__index=Course
local requiredHits=3
function Course.new(layout)
 return setmetatable({layout=layout,targets={},nextVolley=0},Course)
end
function Course:begin(tank,time)
 tank.course={phase="Ravine Crossing",started=time,targets={},hits=0}
 self:publish(tank,time)
end
function Course:publish(tank,time)
 local run=tank.course
 local display=tank.state.course or {required=requiredHits}
 display.phase=run.phase;display.elapsed=run.finished or time-run.started;display.hits=run.hits
 tank.state.course=display
end
function Course:advance(tank,time)
 local run=tank.course
 local p=tank.state.position
 local layout=self.layout
 if run.phase=="Ravine Crossing" then
  if math.abs(p.X)<8 and p.Z>=17 and p.Z<=30 and p.Y>0 then run.crossed=true end
  if run.crossed and p.X>=layout.range.X-8 and math.abs(p.Z)<14 then run.phase="Moving Target Range" end
 elseif run.phase=="Moving Target Range" then
  if run.hits>=requiredHits and p.X>=layout.gauntlet.X-8 and math.abs(p.Z)<14 then run.phase="Bullet Gauntlet" end
 elseif run.phase=="Bullet Gauntlet" and p.X>=layout.finish and math.abs(p.Z)<14 then
  run.phase="Complete";run.finished=time-run.started
 end
end
function Course:hit(target,tank,run)
 local id=self.targets[target]
 if id and tank and run and tank.course==run and run.phase=="Moving Target Range" and not run.targets[id] then
  run.targets[id]=true;run.hits+=1
 end
end
function Course:step(time,fire,gauntlet,range)
 if not gauntlet then self.nextVolley=0 end
 if gauntlet and time>=self.nextVolley then
  fire()
  self.nextVolley=time+2.5
 end
 if range then self.rangeStarted=self.rangeStarted or time
 elseif not self.rangeStarted then return
 else self.rangeStarted=nil end
 local elapsed=if self.rangeStarted then time-self.rangeStarted else 0
 for part,index in self.targets do
  part.Position=Vector3.new(self.layout.range.X+index*6,3.2,(index-2)*10+math.sin(elapsed*1.15+index)*5)
 end
end
return Course
