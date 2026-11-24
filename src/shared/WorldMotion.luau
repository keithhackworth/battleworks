-- Paths use stud offsets in world axes from the placement's bottom origin.
-- Rotation and scaling affect the model. Moving the placement translates its path.
local Motion={SnapDistance=5,MaxPoints=32}
local function finite(n,low,high)
 return type(n)=="number" and n>=low and n<=high
end
local function vector(p) return Vector3.new(table.unpack(p)) end
function Motion.closed(points)
 return #points>=4 and (vector(points[1])-vector(points[#points])).Magnitude<=Motion.SnapDistance
end
function Motion.validate(m,position,width,depth)
 assert(type(m)=="table","Invalid motion path")
 for key in m do assert(key=="points" or key=="speed" or key=="pause" or key=="face" or key=="enabled","Unknown motion property") end
 assert(type(m.face)=="boolean" and type(m.enabled)=="boolean" and finite(m.speed,1,60) and finite(m.pause,0,10),"Invalid motion settings (speed 1–60, pause 0–10)")
 local points=m.points
 assert(type(points)=="table" and #points>=2 and #points<=Motion.MaxPoints,"Motion requires 2–32 waypoints")
 for i,p in points do
  assert(finite(i,1,#points) and i%1==0 and type(p)=="table" and #p==3,"Invalid waypoint")
  for j,n in p do assert(finite(j,1,3) and j%1==0 and finite(n,-4000,4000),"Invalid waypoint coordinate") end
  assert(math.abs(p[1]+position[1])<=width/2 and math.abs(p[2]+position[2])<=2000 and math.abs(p[3]+position[3])<=depth/2,"Waypoint crosses the world boundary")
 end
 for i=2,#points do assert((vector(points[i])-vector(points[i-1])).Magnitude>=.05,"Consecutive waypoints must be distinct") end
end
function Motion.compile(m)
 local points={}
 for _,p in m.points do table.insert(points,vector(p)) end
 local closed=Motion.closed(m.points)
 if closed then points[#points]=points[1] end
 local segments,period={},0
 local function add(a,b,pause)
  local change=b-a;local length=change.Magnitude
  if length<.05 then return end
  local duration=length/m.speed
  local yaw=if math.abs(change.X)+math.abs(change.Z)>.001 then math.atan2(-change.X,-change.Z) else nil
  table.insert(segments,{a=a,change=change,start=period,duration=duration,finish=period+duration+pause,yaw=yaw})
  period+=duration+pause
 end
 for i=2,#points do add(points[i-1],points[i],if not closed and i==#points then m.pause else 0) end
 if not closed then for i=#points-1,1,-1 do add(points[i+1],points[i],if i==1 then m.pause else 0) end end
 return {segments=segments,period=period,face=m.face}
end
function Motion.sample(path,elapsed)
 local t=elapsed%path.period
 for _,s in path.segments do
  if t<s.finish then return s.a+s.change*math.min(1,(t-s.start)/s.duration),if path.face then s.yaw else nil end
 end
 local last=path.segments[#path.segments]
 return last.a+last.change,if path.face then last.yaw else nil
end
function Motion.validateSpin(spin)
 assert(type(spin)=="table","Invalid asset rotation")
 for key in spin do assert(key=="axis" or key=="speed" or key=="pause" or key=="space" or key=="swing","Unknown rotation property") end
 assert(spin.swing==nil or finite(spin.swing,1,360),"Swing angle must be 1–360 degrees")
 assert(spin.space==nil or spin.space=="local" or spin.space=="world","Rotation axis space must be local or world")
 assert(type(spin.axis)=="table" and #spin.axis==3,"Rotation requires X, Y and Z axes")
 for k,n in spin.axis do assert(finite(k,1,3) and k%1==0 and finite(n,-1,1),"Rotation axes must be within −1 to 1") end
 assert(finite(spin.speed,1,360) and finite(spin.pause,0,3600),"Rotation speed must be 1–360 degrees/sec and pause 0–3600 seconds")
end
function Motion.compileSpin(spin,authoredRotation)
 local axis=vector(spin.axis)
 if axis.Magnitude==0 then return nil end
 local follows=spin.space=="local"
 if follows and authoredRotation then axis=authoredRotation:PointToWorldSpace(axis) end
 local angle=spin.swing or 360
 local duration=angle/spin.speed
 local leg=duration+spin.pause
 return {axis=axis.Unit,follows=follows,duration=duration,leg=leg,period=if spin.swing then 2*leg else leg,
  rate=math.rad(spin.speed),swing=spin.swing~=nil}
end
function Motion.spinAngle(spin,clock)
 local phase=clock%spin.period
 if spin.swing and phase>=spin.leg then
  return math.max(0,spin.duration-(phase-spin.leg))*spin.rate
 end
 return math.min(spin.duration,phase)*spin.rate
end
function Motion.advanceSpin(spin,clock,dt,limit)
 local returning=spin.swing and clock>=spin.leg
 local start=if returning then spin.leg else 0
 local turnEnd=start+spin.duration
 if clock<turnEnd then
  local advance=math.min(dt,turnEnd-clock,limit/spin.rate)
  return (clock+advance)%spin.period,advance*spin.rate*(if returning then -1 else 1)
 end
 -- Do not sweep across a reversal within a single contact step.
 if spin.swing then dt=math.min(dt,start+spin.leg-clock) end
 return (clock+dt)%spin.period,0
end
function Motion.orientation(yaw,spin,angle)
 local turn=CFrame.Angles(0,yaw,0)
 if not spin or angle==0 then return turn end
 local axis=if spin.follows then turn:PointToWorldSpace(spin.axis) else spin.axis
 local c,s=math.cos(angle),math.sin(angle)
 local function rotate(v) return v*c+axis:Cross(v)*s+axis*(axis:Dot(v)*(1-c)) end
 return CFrame.fromMatrix(Vector3.zero,rotate(Vector3.new(1,0,0)),rotate(Vector3.new(0,1,0)),rotate(Vector3.new(0,0,1)))*turn
end
function Motion.frame(origin,offset,yaw,spin,angle,center)
 local yawFrame=CFrame.new(origin+offset)*CFrame.Angles(0,yaw,0)*CFrame.new(origin*-1)
 if not spin then return yawFrame end
 local pivot=yawFrame:PointToWorldSpace(center)
 return CFrame.new(pivot)*Motion.orientation(0,spin,angle)*CFrame.new(pivot*-1)*yawFrame
end
return Motion
