-- One description for native character geometry and authoritative tank support.
-- No catch planes: the bridge and banks are the only support above the river.
local Layout=require(script.Parent.PlaygroundProvingLayout)
local Materials=require(script.Parent.TerrainMaterials)
local Surface=require(script.Parent.SurfacePhysics)
local T={Depth=-42,BridgeWidth=24,DefaultSize=Layout.Size}
function T.create(size)
 local x,z=size.X/2,size.Y/2
 local regions={}
 local function add(name,x0,x1,z0,z1,y,slope)
  table.insert(regions,{name=name,x0=x0,x1=x1,z0=z0,z1=z1,y=y or 0,slope=slope or 0})
 end
 -- The west approach rises to a nine-stud plateau overlooking the ravine.
 add("WestBank",-x,-22,-35,z)
 add("WestSlope",-x,-22,-65,-35,9,-.3)
 add("WestPlateau",-x,-22,-z,-65,9)
 add("EastBank",22,x,-z,z)
 add("NorthLand",-22,22,-z,-75)
 add("SouthLand",-22,22,65,z)
 add("Bridge",-22,22,-12,12)
 local entries={}
 for _,z0 in {84,104,44,24}do for _,x0 in {-90,-66,-42,42,66,90}do table.insert(entries,Vector3.new(x0,0,z0))end end
 local data={regions=regions,entries=entries,hazards={
  {name="River",x0=-22,x1=22,z0=-75,z1=65,y0=-1000000,y1=-27},
 },spawns={Vector3.new(-72,0,84),Vector3.new(-48,0,84),Vector3.new(48,0,84),Vector3.new(72,0,84),Vector3.new(-72,0,50),Vector3.new(72,0,50)}}
 if size.X>=Layout.Size.X and size.Y>=Layout.Size.Y then Layout.extend(data)end
 return data
end
-- Attach to the existing Environment. Authored worlds never call this factory.
function T.configure(environment,size)
 local data=T.create(size);environment.playground=data
 environment.rocks={};environment.logs={};environment.zones={};environment.trees=data.trees or{}
 environment.materialTerrain=data.provingGround==true
 if data.provingGround then
  local regions={{id="proving-grass",shape="box",x=0,z=0,rx=size.X/2,rz=size.Y/2,surface=Materials.profile("Grass",0,0,1)}}
  for _,r in data.strips do table.insert(regions,{id=r.id,shape="box",x=r.x,z=r.z,rx=r.rx,rz=r.rz,priority=10,surface=r.profile})end
  for _,r in data.boundaries do table.insert(regions,{id=r.id,shape="box",x=r.x,z=r.z,rx=r.rx,rz=r.rz,priority=5,surface=r.profile})end
  environment.physicsSurfaces=Surface.prepare(regions)
 end
 return data
end
local function inside(r,x,z,margin)
 margin=margin or 0
 return x>=r.x0+margin and x<=r.x1-margin and z>=r.z0+margin and z<=r.z1-margin
end
function T.sample(data,x,z)
 for _,r in data.regions do if inside(r,x,z)then return r.y+(z-r.z0)*r.slope,r end end
 return T.Depth,nil
end
function T.hazard(data,p)
 for _,r in data.hazards do if inside(r,p.X,p.Z)and p.Y>=r.y0 and p.Y<=r.y1 then return r.name end end
 local height,region=T.sample(data,p.X,p.Z)
 if region and region.name~="Bridge" and p.Y<height-12 then return "BelowGround"end
 return nil
end
function T.safe(data,p,radius,allowBridge)
 local y,region=T.sample(data,p.X,p.Z)
 if not region or (region.name=="Bridge" and not allowBridge) or not inside(region,p.X,p.Z,radius or 4)then return false end
 return math.abs(p.Y-y)<2
end
function T.pose(data,position,yaw,shape)
 -- Footprint contacts retain support across tiny joins but not across open
 -- ravine space. A candidate plane needs at least half the chassis contacts.
 local samples={};local s,c=math.sin(yaw),math.cos(yaw)
 for _,a in {-1,0,1}do for _,b in {-1,0,1}do
  local x=position.X+c*a*shape.ContactWidth/2-s*b*shape.ContactLength/2
  local z=position.Z-s*a*shape.ContactWidth/2-c*b*shape.ContactLength/2
  local h,r=T.sample(data,x,z);table.insert(samples,{h=h,r=r,z=z})
 end end
 local best,bestRegion=T.Depth,nil
 for _,v in samples do if v.r then
  local r=v.r;local center=r.y+(position.Z-r.z0)*r.slope
  if center<=position.Y+1.5 and center>best then
   local count=0
   for _,other in samples do if other.r and math.abs(other.h-(r.y+(other.z-r.z0)*r.slope))<=1.5 then count+=1 end end
   if count>=5 then best=center;bestRegion=r end
  end
 end end
 if bestRegion then
  return best,math.atan(-bestRegion.slope*c),math.atan(-bestRegion.slope*s),"Structure",1
 end
 return T.Depth,0,0,"Air",1
end
return T
