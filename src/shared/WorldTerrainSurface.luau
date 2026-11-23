local H=require(script.Parent.WorldHeightfield)
local Traversal=require(script.Parent.TerrainTraversal)
local Materials=require(script.Parent.TerrainMaterials)
local chassis=require(script.Parent.ComponentCatalog)["chassis.standard"].Properties
local Surface={};Surface.__index=Surface
function Surface.new(parent,settings,physical,overlay)
 local folder=Instance.new("Folder")
 folder.Name=if overlay then "TerrainTraversability" else "AuthoredTerrain";folder.Parent=parent
 return setmetatable({folder=folder,settings=settings,physical=physical,chunks={},overlay=overlay},Surface)
end
local colors={Treads=Color3.fromRGB(246,196,48),Impossible=Color3.fromRGB(239,64,70)}
function Surface.waterAppearance(depth)
 local limit=chassis.Hitbox.Y*.5
 local mix=math.clamp((depth-limit+1)/2,0,1)
 mix=mix*mix*(3-2*mix)
 return Color3.fromRGB(93-73*mix,197-136*mix,232-109*mix),.35-.13*mix
end
Surface.TraversalColors=colors
function Surface:chunk(cx,cz)
 local settings=self.settings
 local field=settings.terrain
 local key=cz*field.columns+cx
 local parts=self.chunks[key]
 if not parts then parts={};self.chunks[key]=parts end
 local used=0
 local color=Color3.fromRGB(table.unpack(settings.ground.color))
 local material=Enum.Material[settings.ground.material]
 local cellMaterial,cellColor,waterLevel
 local profile=if self.overlay then Materials.withTraction(Materials.fromMaterial(settings.ground.material),field.traction) else nil
 local function draw(shape,size,frame,tint)
  if self.overlay and not tint then return end
  used+=1
  local p=parts[used]
  if not p then
   p=Instance.new("Part");p.Name="TerrainSurface";p.Anchored=true;p.CanTouch=false
   p:SetAttribute("ScannerTerrainOnly",true);p:SetAttribute("ScannerGroundSupport",true)
   p.TopSurface=Enum.SurfaceType.Smooth;p.BottomSurface=Enum.SurfaceType.Smooth
   parts[used]=p
  end
  p.Shape=shape;p.Size=size;p.CFrame=frame
  if p.Name~="TerrainSurface" then p.Name="TerrainSurface" end
  p.Color=tint or cellColor or color;p.Material=if self.overlay then Enum.Material.Neon else cellMaterial or material
  p.Transparency=if self.overlay then .43 else 0
  p.CanCollide=self.physical;p.CanQuery=not self.overlay
  if p.Parent~=self.folder then p.Parent=self.folder end
 end
 local function triangle(a,b,c)
  local ab,ac,bc=b-a,c-a,c-b
  if ab.Magnitude>ac.Magnitude and ab.Magnitude>bc.Magnitude then a,b,c=c,a,b
  elseif ac.Magnitude>bc.Magnitude then a,b,c=b,a,c end
  local back=(c-b).Unit
  local right=(c-a):Cross(b-a).Unit
  local up=back:Cross(right)
  local size=(a-b):Dot(up)
  local split=b+back*(a-b):Dot(back)
  local tint
  if profile then
   local center=(a+b+c)/3
   local localProfile=profile
   for _,zone in settings.traversalZones or {} do
    if ((center.X-zone.x)/zone.rx)^2+((center.Z-zone.z)/zone.rz)^2<=1 then localProfile=Materials.withTraction(zone.profile,field.traction) end
   end
   local depth=if waterLevel then waterLevel-math.min(a.Y,b.Y,c.Y)+.13 else 0
   tint=if Traversal.waterBlocked(depth,chassis) then colors.Impossible
    else colors[Traversal.classify(math.acos(math.clamp(math.abs(right.Y),0,1)),0,localProfile)]
  end
  draw(Enum.PartType.Wedge,Vector3.new(.025,size,(split-b).Magnitude),CFrame.fromMatrix((a+b)*.5,right,up,back),tint)
  draw(Enum.PartType.Wedge,Vector3.new(.025,size,(c-split).Magnitude),CFrame.fromMatrix((a+c)*.5,right*-1,up,back*-1),tint)
 end
 local x0,z0=cx*H.Chunk,cz*H.Chunk
 local x1,z1=math.min(x0+H.Chunk,field.columns),math.min(z0+H.Chunk,field.rows)
 local dx,dz=settings.width/field.columns,settings.depth/field.rows
 local function point(x,z)
  return Vector3.new(x*dx-settings.width/2,H.height(field,x,z)+(if self.overlay then .13 else 0),z*dz-settings.depth/2)
 end
 local function flat(a,b)
  local tint
  if self.overlay and waterLevel and Traversal.waterBlocked(waterLevel-a.Y+.13,chassis) then tint=colors.Impossible end
  draw(Enum.PartType.Block,Vector3.new(b.X-a.X,.18,b.Z-a.Z),CFrame.new((a+b)*.5-Vector3.new(0,.09,0)),tint)
 end
 local elevation=H.height(field,x0,z0)
 local level=true
 for z=z0,z1 do for x=x0,x1 do if H.height(field,x,z)~=elevation then level=false;break end end;if not level then break end end
 local painted=false
 if level and (field.paint or field.water) then
  for z=z0,z1-1 do
   for x=x0,x1-1 do
    local i=z*field.columns+x+1
    if (field.paint and field.paint[i]~=0) or (field.water and field.water[i]~=0) then painted=true;break end
   end
   if painted then break end
  end
 end
 if level and not painted then flat(point(x0,z0),point(x1,z1))
 else
  for z=z0,z1-1 do for x=x0,x1-1 do
   local a,b,c,d=point(x,z),point(x+1,z),point(x,z+1),point(x+1,z+1)
   local index=z*field.columns+x+1
   local paint=field.paint and H.Paint[field.paint[index]]
   local water=field.water and field.water[index]
   waterLevel=if water and water~=0 then (water-H.WaterOffset)/H.Unit else nil
   local wet=waterLevel and waterLevel>math.min(a.Y,b.Y,c.Y,d.Y)-(if self.overlay then .13 else 0)
   if wet then paint="Mud" end
   cellMaterial=paint and Enum.Material[Materials.Materials[paint]]
   cellColor=paint and Color3.fromRGB(table.unpack(Materials.Colors[paint]))
   profile=if self.overlay then Materials.withTraction(Materials.fromMaterial(paint or settings.ground.material),field.traction) else nil
   if a.Y==b.Y and a.Y==c.Y and a.Y==d.Y then flat(a,d)
   else triangle(a,b,c);triangle(d,c,b) end
   if self.overlay and waterLevel and Traversal.waterBlocked(waterLevel-math.min(a.Y,b.Y,c.Y,d.Y)+.13,chassis) then
    draw(Enum.PartType.Block,Vector3.new(dx,.035,dz),CFrame.new((a.X+d.X)/2,waterLevel+.035,(a.Z+d.Z)/2),colors.Impossible)
   end
   if water and water~=0 and not self.overlay then
    local y=(water-H.WaterOffset)/H.Unit
    if y>math.min(a.Y,b.Y,c.Y,d.Y) then
     -- The cell center is on the shared diagonal of the two ground triangles.
     local waterColor,transparency=Surface.waterAppearance(y-(b.Y+c.Y)/2)
     draw(Enum.PartType.Block,Vector3.new(dx,.04,dz),CFrame.new((a.X+d.X)/2,y-.02,(a.Z+d.Z)/2),waterColor)
     local p=parts[used];p.Name="WaterSurface";p.Material=Enum.Material.Glass;p.Transparency=transparency
     p.CanCollide=false;p.CanQuery=false
    end
   end
  end end
 end
 for i=used+1,#parts do parts[i].Parent=nil end
end
function Surface:all()
 local field=self.settings.terrain
 for z=0,math.ceil(field.rows/H.Chunk)-1 do
  for x=0,math.ceil(field.columns/H.Chunk)-1 do self:chunk(x,z) end
 end
end
function Surface:destroy()
 for _,parts in self.chunks do for _,part in parts do part:Destroy() end end
 self.folder:Destroy()
end
return Surface
