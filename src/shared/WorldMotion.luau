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
return Motion
