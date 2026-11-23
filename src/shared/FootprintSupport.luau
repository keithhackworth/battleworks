-- Structural support is the intersection of real top faces with the chassis,
-- never an expanded platform or a bridge inserted into the world.
local Geometry=require(script.Parent.WorldObjectGeometry)
local Traversal=require(script.Parent.TerrainTraversal)
local F={}
local epsilon=1e-6
local maxGradient=math.tan(math.rad(Traversal.MaxSupportAngle))
local function cross(a,b,c)return (b.x-a.x)*(c.z-a.z)-(b.z-a.z)*(c.x-a.x)end
local function clip(poly,axis,limit,sign)
 local out={}
 for i,a in poly do
  local b=poly[i%#poly+1];local da,db=limit-sign*a[axis],limit-sign*b[axis]
  if da>=0 then table.insert(out,a) end
  if (da>=0)~=(db>=0) then
   local t=da/(da-db);table.insert(out,{x=a.x+(b.x-a.x)*t,z=a.z+(b.z-a.z)*t})
  end
 end
 return out
end
local function surroundsCenter(points)
 table.sort(points,function(a,b)return a.x<b.x or (a.x==b.x and a.z<b.z)end)
 local hull={}
 for _,p in points do
  while #hull>=2 and cross(hull[#hull-1],hull[#hull],p)<=epsilon do table.remove(hull) end
  table.insert(hull,p)
 end
 local lower=#hull
 for i=#points-1,1,-1 do local p=points[i]
  while #hull>lower and cross(hull[#hull-1],hull[#hull],p)<=epsilon do table.remove(hull)end
  table.insert(hull,p)
 end
 if #hull<4 then return false end
 table.remove(hull)
 for i,a in hull do if cross(a,hull[i%#hull+1],{x=0,z=0})< -epsilon then return false end end
 return true
end
function F.solve(boxes,position,yaw,shape)
 local s,c=math.sin(yaw),math.cos(yaw)
 local candidates={};local highest=-math.huge
 for _,box in boxes do
  local h=Geometry.planeHeight(box,position.X,position.Z)
  if h and h<=position.Y+Geometry.MaxStep+.001 then
   local e=box.extents
   local radius=(shape.ContactWidth+shape.ContactLength)/2
   if not e or (math.abs(position.X-box.position.X)<=e.X+radius and math.abs(position.Z-box.position.Z)<=e.Z+radius) then
    local poly={}
    for _,vertex in Geometry.topVertices(box)do
     local p=vertex-position
     table.insert(poly,{x=c*p.X-s*p.Z,z=-s*p.X-c*p.Z})
    end
    for _,edge in {{"x",shape.ContactWidth/2,1},{"x",shape.ContactWidth/2,-1},{"z",shape.ContactLength/2,1},{"z",shape.ContactLength/2,-1}}do poly=clip(poly,table.unpack(edge))end
    if #poly>=3 then
     local area=0;for i,a in poly do local b=poly[i%#poly+1];area+=a.x*b.z-a.z*b.x end
     if math.abs(area)>epsilon then
      local low,high=math.huge,-math.huge
      for _,p in poly do
       local y=Geometry.planeHeight(box,position.X+c*p.x-s*p.z,position.Z-s*p.x-c*p.z)
       low=math.min(low,y);high=math.max(high,y)
      end
      local level=math.clamp(h,low,high)
      table.insert(candidates,{box=box,height=level,poly=poly,area=math.abs(area)/2});highest=math.max(highest,level)
     end
    end
   end
  end
 end
 local contacts={};local weight,sx,sz,sy,sxx,szz,sxz,sxy,szy=0,0,0,0,0,0,0,0,0
 local material,bestArea=nil,0
 local platforms,staticArea=nil,0
 for _,candidate in candidates do
  -- Distant lower decks cannot prop up a chassis above a cliff or upper level.
  if candidate.height>=highest-Geometry.MaxStep-.001 then
   if candidate.height>=highest-.05 then
    local support=candidate.box.platform
    if support then
     platforms=platforms or {}
     platforms[support]=(platforms[support] or 0)+candidate.area
    else
     staticArea+=candidate.area
    end
   end
   local profile=candidate.box.material
   if profile and (candidate.area>bestArea or (candidate.area==bestArea and material and profile.surfaceType<material.surfaceType)) then
    material=profile;bestArea=candidate.area
   end
   local w=candidate.area/#candidate.poly
   for _,p in candidate.poly do
    local x,z=position.X+c*p.x-s*p.z,position.Z-s*p.x-c*p.z
    local y=Geometry.planeHeight(candidate.box,x,z)
    table.insert(contacts,{x=p.x,z=p.z,y=y})
    weight+=w;sx+=w*p.x;sz+=w*p.z;sy+=w*y
    sxx+=w*p.x*p.x;szz+=w*p.z*p.z;sxz+=w*p.x*p.z;sxy+=w*p.x*y;szy+=w*p.z*y
   end
  end
 end
 if not surroundsCenter(contacts) then return nil end
 -- Area-weighted suspension plane; exact for a single incline, continuous
 -- across adjacent faces. Raise it to avoid penetrating any real contact.
 local xx,zz,xz=sxx-sx*sx/weight,szz-sz*sz/weight,sxz-sx*sz/weight
 local xy,zy=sxy-sx*sy/weight,szy-sz*sy/weight
 local determinant=xx*zz-xz*xz
 local roll,pitch=0,0
 if determinant>epsilon then roll=(xy*zz-zy*xz)/determinant;pitch=(zy*xx-xy*xz)/determinant end
 roll=math.clamp(roll,-maxGradient,maxGradient);pitch=math.clamp(pitch,-maxGradient,maxGradient)
 local height=-math.huge
 for _,p in contacts do height=math.max(height,p.y-roll*p.x-pitch*p.z)end
 local platform,area=nil,staticArea
 if platforms then
  for support,coverage in platforms do
   if coverage>area or (coverage==area and platform and support.id<platform.id) then
    platform,area=support,coverage
   end
  end
 end
 return height,math.atan(pitch),math.atan(roll),material,platform
end
return F
