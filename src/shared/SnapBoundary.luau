-- Work in normalized asset coordinates so welding is independent of the placed
-- object's translation, rotation, and scale. Profiles round vertices to 1e-6.
local Boundary={}
local tolerance=1e-5
local angleTolerance=.001
local up=Vector3.new(0,1,0)
local function dot(a,b) return a.X*b.X+a.Y*b.Y+a.Z*b.Z end
local function cross(a,b)
 return Vector3.new(a.Y*b.Z-a.Z*b.Y,a.Z*b.X-a.X*b.Z,a.X*b.Y-a.Y*b.X)
end
local function vector(point) return Vector3.new(table.unpack(point)) end

local function surfaces(triangles,authored,bases)
 local result={}
 for index,triangle in triangles do
  local a,b,c=vector(triangle[1]),vector(triangle[2]),vector(triangle[3])
  local normal=cross(b-a,c-a)
  if normal.Magnitude<=tolerance^2 or (not authored and normal.Y<=0) then continue end
  normal=normal.Unit
  local points={a,b,c}
  local inward={}
  for i,p in points do inward[i]=cross(normal,points[i%3+1]-p).Unit end
  local sides={}
  local base=if authored then nil elseif bases then bases[index] else -.5
  if base and math.max(a.Y,b.Y,c.Y)>base+tolerance then
   for i,p in points do sides[i]=cross(up,points[i%3+1]-p).Unit end
  end
  table.insert(result,{points=points,normal=normal,inward=inward,sides=sides,base=base,
   minX=math.min(a.X,b.X,c.X),maxX=math.max(a.X,b.X,c.X),
   minZ=math.min(a.Z,b.Z,c.Z),maxZ=math.max(a.Z,b.Z,c.Z)})
 end
 return result
end

-- Clip the line to the triangle in its own plane. This finds partial
-- overlaps and T-junctions even when neither triangle shares identical vertices.
local function clip(low,high,offset,slope,margin)
 if math.abs(slope)*(high-low)<=tolerance then
  if offset+slope*(low+high)/2<margin-(if margin==0 then tolerance else 0) then return end
 else
  local at=(margin-offset)/slope
  if slope>0 then low=math.max(low,at) else high=math.min(high,at) end
 end
 if high-low>tolerance then return low,high end
end

local function coverage(a,direction,low,high,points,inward,margin)
 for i,normal in inward do
  low,high=clip(low,high,dot(a-points[i],normal),dot(direction,normal),margin)
  if not low then return end
 end
 return low,high
end

local function buriedCoverage(a,direction,length,other)
 if #other.sides==0 then return end
 local low,high=clip(0,length,a.Y-other.base,direction.Y,tolerance)
 if not low then return end
 low,high=clip(low,high,dot(other.points[1]-a,other.normal),-dot(direction,other.normal),tolerance)
 if low then return coverage(a,direction,low,high,other.points,other.sides,-tolerance) end
end

local function sortedUnion(intervals)
 table.sort(intervals,function(a,b) return a[1]<b[1] end)
 local merged={}
 for _,interval in intervals do
  local last=merged[#merged]
  if last and interval[1]<=last[2]+tolerance then
   last[2]=math.max(last[2],interval[2])
  else table.insert(merged,interval) end
 end
 return merged
end

-- Require solid coverage on both sides. A lower ledge where the adjacent
-- piece rises above it still has an exposed side and remains snappable.
local function addBuried(covered,inside,outside)
 if #inside==0 or #outside==0 then return end
 inside,outside=sortedUnion(inside),sortedUnion(outside)
 local i,j=1,1
 while i<=#inside and j<=#outside do
  local first,second=inside[i],outside[j]
  local low,high=math.max(first[1],second[1]),math.min(first[2],second[2])
  if high-low>tolerance then table.insert(covered,{low,high}) end
  if first[2]<second[2] then i+=1 else j+=1 end
 end
end

local function addExposed(edges,a,b,face,index,faces,authored)
 local length=(b-a).Magnitude
 if length<=tolerance then return end
 local direction=(b-a)/length
 -- For upward surfaces, the horizontal half-planes identify both sides of
 -- a seam even when the two sheets meet at different slopes.
 local outward=cross(direction,if authored then face.normal else up).Unit
 local covered={}
 local inside,outside={},{}
 local minX,maxX=math.min(a.X,b.X)-tolerance,math.max(a.X,b.X)+tolerance
 local minZ,maxZ=math.min(a.Z,b.Z)-tolerance,math.max(a.Z,b.Z)+tolerance
 for i,other in faces do
  if i==index then continue end
  if other.minX>maxX or other.maxX<minX or other.minZ>maxZ or other.maxZ<minZ then continue end
  if authored and math.abs(dot(face.normal,other.normal))<.99999 then continue end
  local inPlane=math.abs(dot(a-other.points[1],other.normal))<=tolerance and math.abs(dot(b-other.points[1],other.normal))<=tolerance
  local low,high
  if inPlane then low,high=coverage(a,direction,0,length,other.points,other.inward,0)
  elseif not authored then low,high=buriedCoverage(a,direction,length,other) end
  if not low then continue end
  local minSide,maxSide=math.huge,-math.huge
  for _,point in other.points do
   local side=dot(point-a,outward)
   minSide=math.min(minSide,side);maxSide=math.max(maxSide,side)
  end
  -- Opposite-side coverage hides the edge. Same-side coverage belongs to
  -- the first triangle so duplicated or overlapping pieces emit it once.
  if inPlane then
   if maxSide>tolerance or (i<index and minSide< -tolerance) then table.insert(covered,{low,high}) end
  else
   if minSide< -tolerance then table.insert(inside,{low,high}) end
   if maxSide>tolerance then table.insert(outside,{low,high}) end
  end
 end
 addBuried(covered,inside,outside)
 table.sort(covered,function(x,y) return x[1]<y[1] end)
 local start=0
 local function emit(finish)
  if finish-start>tolerance then
   table.insert(edges,{a=a+direction*start,b=a+direction*finish,normal=face.normal})
  end
 end
 for _,span in covered do
  emit(span[1])
  start=math.max(start,span[2])
 end
 emit(length)
end

-- Merge intervals on the same 3-D line. The distance test also accommodates
-- the profile's vertex quantization without straightening a curved perimeter.
local function merge(edges)
 local merged={}
 for _,edge in edges do
  local a,b=edge.a,edge.b
  if (b-a).Magnitude<=tolerance then continue end
  local direction=(b-a).Unit
  local low,high=0,(b-a).Magnitude
  local i=1
  while i<=#merged do
   local other=merged[i]
   local p,q=other.a-a,other.b-a
   local s,t=dot(p,direction),dot(q,direction)
   local first,last=math.min(s,t),math.max(s,t)
   if first<=high+tolerance and last>=low-tolerance and
    (p-direction*s).Magnitude<=tolerance and (q-direction*t).Magnitude<=tolerance and
    cross(direction,(other.b-other.a).Unit).Magnitude<=angleTolerance then
    low=math.min(low,first);high=math.max(high,last)
    table.remove(merged,i)
    -- Extending either end can reach an interval already visited.
    i=1
   else i+=1 end
  end
  table.insert(merged,{a=a+direction*low,b=a+direction*high,normal=edge.normal})
 end
 return merged
end

function Boundary.edges(triangles,authored,bases)
 local faces=surfaces(triangles,authored,bases)
 local edges={}
 for index,face in faces do
  for i,a in face.points do addExposed(edges,a,face.points[i%3+1],face,index,faces,authored~=nil) end
 end
 if authored then
  for _,segment in authored.segments or {} do
   local a,b=vector(segment[1]),vector(segment[2])
   if (b-a).Magnitude<=tolerance then continue end
   local direction=(b-a).Unit
   local normal=up-direction*dot(direction,up)
   if normal.Magnitude<=tolerance then normal=Vector3.new(1,0,0) end
   table.insert(edges,{a=a,b=b,normal=normal.Unit})
  end
 end
 return merge(edges)
end

return Boundary
