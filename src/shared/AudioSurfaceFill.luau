-- Flood only through overlapping triangle sides on drivable collision faces.
-- A corner touch or a vertically stacked surface does not join two regions.
local Fill={}
local seam=.12

local function shared(a,b)
 local delta=b.a-a.a
 local along=delta:Dot(a.direction)
 local other=b.b-a.a
 local finish=other:Dot(a.direction)
 if (delta-a.direction*along).Magnitude>seam or (other-a.direction*finish).Magnitude>seam then return false end
 return math.min(a.length,math.max(along,finish))-math.max(0,math.min(along,finish))>seam
end

function Fill.connected(faces,seed)
 local edges,links={},{}
 for i,face in faces do
  links[i]={}
  for j,a in face.vertices do
   local b=face.vertices[j%3+1]
   local direction=b-a
   if direction.Magnitude<=seam then continue end
   table.insert(edges,{face=i,a=a,b=b,direction=direction.Unit,length=direction.Magnitude,
    lo=Vector3.new(math.min(a.X,b.X),math.min(a.Y,b.Y),math.min(a.Z,b.Z)),
    hi=Vector3.new(math.max(a.X,b.X),math.max(a.Y,b.Y),math.max(a.Z,b.Z))})
  end
 end
 table.sort(edges,function(a,b)return a.lo.X<b.lo.X end)
 for i,a in edges do
  for j=i+1,#edges do
   local b=edges[j]
   if b.lo.X>a.hi.X+seam then break end
   if a.face~=b.face and a.lo.Y<=b.hi.Y+seam and b.lo.Y<=a.hi.Y+seam and
    a.lo.Z<=b.hi.Z+seam and b.lo.Z<=a.hi.Z+seam and (shared(a,b) or shared(b,a)) then
    table.insert(links[a.face],b.face);table.insert(links[b.face],a.face)
   end
  end
 end
 local index=table.find(faces,seed)
 if not index then return {} end
 local queue,seen,result={index},{[index]=true},{}
 local head=1
 while head<=#queue do
  local i=queue[head];head+=1
  table.insert(result,faces[i])
  for _,j in links[i] do
   if not seen[j] then seen[j]=true;table.insert(queue,j) end
  end
 end
 return result
end

function Fill.sample(faces,seed,size,limit)
 local step=math.min(size.X,size.Z)*.65
 local vertical=math.max(.01,size.Y*.8)
 local points,used={seed},{}
 local function add(p,x,z)
  local key=string.format("%d:%d:%d",x,math.round(p.Y/vertical),z)
  if used[key] then return true end
  if #points>=limit then return false end
  used[key]=true;table.insert(points,p)
  return true
 end
 for _,face in faces do
  local a,b,c=table.unpack(face.vertices)
  local u,v=b-a,c-a
  local det=u.X*v.Z-u.Z*v.X
  if math.abs(det)<1e-9 then continue end
  local minX,maxX=math.ceil(math.min(a.X,b.X,c.X)/step),math.floor(math.max(a.X,b.X,c.X)/step)
  local minZ,maxZ=math.ceil(math.min(a.Z,b.Z,c.Z)/step),math.floor(math.max(a.Z,b.Z,c.Z)/step)
  -- Very small brushes on a large triangle could otherwise scan millions
  -- of cells before reaching the first point inside the triangle.
  if (maxX-minX+1)*(maxZ-minZ+1)>limit*16 then return nil end
  local sampled=false
  for ix=minX,maxX do for iz=minZ,maxZ do
   local x,z=ix*step,iz*step
   local dx,dz=x-a.X,z-a.Z
   local s,t=(dx*v.Z-dz*v.X)/det,(u.X*dz-u.Z*dx)/det
   if s>=-1e-6 and t>=-1e-6 and s+t<=1+1e-6 then
    if not add(Vector3.new(x,a.Y+s*u.Y+t*v.Y,z),ix,iz) then return nil end
    sampled=true
   end
  end end
  if not sampled then
   local center=(a+b+c)/3
   if not add(center,math.round(center.X/step),math.round(center.Z/step)) then return nil end
  end
 end
 return points
end
return Fill
