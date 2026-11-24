-- Straight lined bores through the authored heightfield.
local H=require(script.Parent.WorldHeightfield)
local T={MaxCount=8}
local function valid(n,a,b) return type(n)=="number" and n>=a and n<=b end
function T.validate(settings)
 local list=settings.tunnels
 if list==nil then return end
 assert(settings.terrain and type(list)=="table" and #list<=T.MaxCount,"Tunnels require authored terrain (maximum eight)")
 for i,t in list do
  assert(valid(i,1,#list) and i%1==0 and type(t)=="table","Invalid tunnel")
  for key in t do assert(key=="a" or key=="b" or key=="diameter" or key=="traction","Unknown tunnel field") end
  assert(valid(t.diameter,12,48) and valid(t.traction,0,100),"Tunnel diameter must be 12–48 studs and traction 0–100%")
  for _,point in {t.a,t.b} do
   assert(type(point)=="table" and #point==3,"Invalid tunnel portal")
   for k,n in point do assert(valid(k,1,3) and k%1==0 and valid(n,-2000,2000),"Invalid tunnel portal coordinates") end
   local margin=t.diameter/2+1
   assert(math.abs(point[1])+margin<=settings.width/2 and math.abs(point[3])+margin<=settings.depth/2 and point[2]>=H.MinHeight and point[2]<=H.MaxHeight,"Tunnel portals need clearance inside the world")
  end
  local dx,dz=t.b[1]-t.a[1],t.b[3]-t.a[3]
  local length=math.sqrt(dx*dx+dz*dz)
  assert(length>=12 and math.abs(t.b[2]-t.a[2])<=length*.35,"Tunnel needs portals at least 12 studs apart and a grade of 35% or less")
 end
 local tunnels=T.compile(settings)
 for i,a in tunnels do for j=1,i-1 do
  assert(not T.intersects(a,tunnels[j]),"Tunnel routes cannot cross or overlap")
 end end
end
function T.compile(settings)
 local out={}
 for _,s in settings.tunnels or {} do
  local a,b=Vector3.new(table.unpack(s.a)),Vector3.new(table.unpack(s.b))
  local dx,dz=b.X-a.X,b.Z-a.Z
  local length=math.sqrt(dx*dx+dz*dz)
  local x,z,r=dx/length,dz/length,s.diameter/2
  table.insert(out,{a=a,b=b,x=x,z=z,length=length,r=r,slope=(b.Y-a.Y)/length,
   traction=s.traction,minX=math.min(a.X,b.X)-r,maxX=math.max(a.X,b.X)+r,minZ=math.min(a.Z,b.Z)-r,maxZ=math.max(a.Z,b.Z)+r})
 end
 return out
end
function T.intersects(a,b)
 local delta=(a.a+a.b-b.a-b.b)/2
 local function extent(t,x,z)
  return math.abs(t.x*x+t.z*z)*t.length/2+math.abs(t.z*x-t.x*z)*(t.r+1)
 end
 for _,t in {a,b} do
  for _,axis in {{t.x,t.z},{-t.z,t.x}} do
   local x,z=axis[1],axis[2]
   if math.abs(delta.X*x+delta.Z*z)>=extent(a,x,z)+extent(b,x,z) then return false end
  end
 end
 return true
end
function T.cover(settings,tunnel)
 local middle=(Vector3.new(table.unpack(tunnel.a))+Vector3.new(table.unpack(tunnel.b)))/2
 return H.sample(settings.terrain,settings.width,settings.depth,middle.X,middle.Z)-middle.Y-tunnel.diameter
end
local function coordinates(t,x,z)
 local dx,dz=x-t.a.X,z-t.a.Z
 return dx*t.x+dz*t.z,-dx*t.z+dz*t.x
end
function T.floor(tunnels,x,z,y)
 for _,t in tunnels do
  local along,side=coordinates(t,x,z)
  if along>=-1e-5 and along<=t.length+1e-5 and math.abs(side)<=t.r+.001 then
   local floor=t.a.Y+along*t.slope
   if y>=floor-1.6 and y<floor+2*t.r-math.max(0,math.abs(side)-t.r/2)-.01 then return floor,t end
  end
 end
end
function T.clearance(t,x,z,radius)
 local _,side=coordinates(t,x,z)
 return 2*t.r-math.max(0,math.min(t.r,math.abs(side)+(radius or 0))-t.r/2)
end
function T.roof(tunnels,x,z,reachableHeight)
 local best,shape
 for _,t in tunnels do
  local along,side=coordinates(t,x,z)
  if along>=0 and along<=t.length and math.abs(side)<=t.r then
   local height=t.a.Y+along*t.slope+T.clearance(t,x,z)+1
   if height<=reachableHeight and (not best or height>best) then best,shape=height,t end
  end
 end
 return best,shape
end
function T.overlaps(t,minX,maxX,minZ,maxZ)
 return t.minX<=maxX and t.maxX>=minX and t.minZ<=maxZ and t.maxZ>=minZ
end
local function signed(t,p,plane)
 local u,v=coordinates(t,p.X,p.Z)
 if plane==1 then return u end
 if plane==2 then return t.length-u end
 if plane==3 then return t.r+v end
 if plane==4 then return t.r-v end
 local height=p.Y-t.a.Y-u*t.slope
 if plane==5 then return height+.02 end
 if plane==6 then return 2*t.r-height end
 return 2.5*t.r-height+(if plane==7 then v else -v)
end
-- Partition the triangle into the fragments outside each successive bore
-- plane. The remaining polygon lies entirely inside the tunnel opening.
function T.cut(tunnel,polygon,output)
 for plane=1,8 do
  local inside,outside={},{}
  local prev=polygon[#polygon]
  local prevDistance=signed(tunnel,prev,plane)
  for _,point in polygon do
   local distance=signed(tunnel,point,plane)
   if (distance>=0)~=(prevDistance>=0) then
    local edge=prev+(point-prev)*(prevDistance/(prevDistance-distance))
    table.insert(inside,edge);table.insert(outside,edge)
   end
   table.insert(if distance>=0 then inside else outside,point)
   prev,prevDistance=point,distance
  end
  if #outside>=3 then table.insert(output,outside) end
  if #inside<3 then break end
  polygon=inside
 end
end
function T.sections(t)
 local center=(t.a+t.b)/2
 local right=Vector3.new(t.z,0,-t.x)
 local along=(t.b-t.a).Unit
 local up=along:Cross(right)
 local length=(t.b-t.a).Magnitude
 -- One stud of lining outside the clear opening.
 local frame=CFrame.fromMatrix(center,right,up,along)
 local d=2*t.r/math.sqrt(1+t.slope*t.slope)
 local spring=d-t.r/2
 local sections={
  {kind="Floor",frame=frame*CFrame.new(0,-.5,0),size=Vector3.new(2*t.r+2,1,length)},
  {kind="Roof",frame=frame*CFrame.new(0,d+.5,0),size=Vector3.new(t.r+.04,1,length)},
  {kind="Wall",frame=frame*CFrame.new(-t.r-.5,spring/2,0),size=Vector3.new(1,spring,length)},
  {kind="Wall",frame=frame*CFrame.new(t.r+.5,spring/2,0),size=Vector3.new(1,spring,length)},
 }
 for _,side in {-1,1} do
  local panel=frame*CFrame.new(side*t.r*.75,(spring+d)/2,0)*CFrame.Angles(0,0,-side*math.pi/4)*CFrame.new(0,.5,0)
  table.insert(sections,{kind="Roof",frame=panel,size=Vector3.new(t.r/math.sqrt(2)+.04,1,length)})
 end
 return sections
end
return T
