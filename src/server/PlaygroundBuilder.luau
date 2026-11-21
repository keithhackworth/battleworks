local Terrain=require(game.ReplicatedStorage.Shared.PlaygroundTerrain)
local Materials=require(game.ReplicatedStorage.Shared.TerrainMaterials)
local Builder={}
function Builder.build(arena,data,floor)
 local scale=data.geometryScale or 1
 floor.CanCollide=false;floor.CanQuery=false;floor.Transparency=1
 local folder=Instance.new("Folder");folder.Name="PlaygroundTerrain";folder.Parent=arena
 local function part(name,size,frame,color,material,solid)
  local p=Instance.new("Part");p.Name=name;p.Anchored=true;p.Size=size;p.CFrame=frame;p.Color=color;p.Material=material
  p.CanCollide=solid;p.CanQuery=solid;p.CanTouch=false;p.Parent=folder;return p
 end
 for _,r in data.regions do
  local angle=-math.atan(r.slope);local mid=(r.z0+r.z1)/2
  local bridge=r.name=="Bridge"
  local thickness=if bridge then 2 else 42
  local height=r.y+(mid-r.z0)*r.slope
  local ground=part(r.name,Vector3.new(r.x1-r.x0,thickness,(r.z1-r.z0)*math.sqrt(1+r.slope*r.slope)),
   CFrame.new((r.x0+r.x1)/2,height-thickness*math.cos(angle)/2,mid-thickness*math.sin(angle)/2)*CFrame.Angles(angle,0,0),
   if bridge then Color3.fromRGB(146,112,69)else Color3.fromRGB(100,112,86),if bridge then Enum.Material.WoodPlanks else Enum.Material.Grass,true)
  if data.provingGround then ground:SetAttribute("ScannerTerrainOnly",true);if not bridge then Materials.annotate(ground,Materials.profile("Grass",0,0,1))end end
 end
 if data.provingGround then
  for _,zone in data.configurationZones or {} do
   local pad=part("ConfigurationZone",Vector3.new(zone.halfX*2,.06,zone.halfZ*2),CFrame.new(zone.x,zone.y+.04,zone.z),Color3.fromRGB(24,57,97),Enum.Material.SmoothPlastic,false)
   pad:SetAttribute("ConfigurationZoneId",zone.id)
   local hx,hz=zone.halfX-1.5,zone.halfZ-1.5
   for i=-6,6 do
    local offset=i*6*scale
    local low,high=math.max(-hx,-hz-offset),math.min(hx,hz-offset)
    if high>low then
     local middle=(low+high)/2
     part("ConfigurationStripe",Vector3.new((high-low)*math.sqrt(2),.03,1.8),
      CFrame.new(zone.x+middle,zone.y+.09,zone.z+middle+offset)*CFrame.Angles(0,-math.pi/4,0),
      Color3.fromRGB(57,149,239),Enum.Material.SmoothPlastic,false)
    end
   end
   local sign=part("ConfigurationZoneLabel",Vector3.new(zone.halfX*1.72,.04,zone.halfZ*.5),
    CFrame.new(zone.x,zone.y+.13,zone.z),Color3.fromRGB(20,48,86),Enum.Material.SmoothPlastic,false)
   local gui=Instance.new("SurfaceGui");gui.Face=Enum.NormalId.Top;gui.Parent=sign
   local label=Instance.new("TextLabel");label.Size=UDim2.fromScale(.94,.85);label.Position=UDim2.fromScale(.03,.075)
   label.BackgroundColor3=Color3.fromRGB(20,48,86);label.TextColor3=Color3.fromRGB(239,250,255)
   label.Font=Enum.Font.GothamBold;label.TextScaled=true;label.Text="CONFIGURATION ZONE";label.Parent=gui
  end
  for _,r in data.staticBoxes do
   local wall=part("BarracksWall",Vector3.new(r.sx,r.sy,r.sz),CFrame.new(r.x,r.y,r.z),Color3.fromRGB(104,119,92),Enum.Material.Concrete,true)
   wall:SetAttribute("ScannerType","object");wall:SetAttribute("WorldObjectId","proving:barracks");wall:SetAttribute("ScannerObjectName","Barracks")
  end
  local function sign(name,text,x,y,z)
   local board=part(name,Vector3.new(18*scale,3,.3),CFrame.new(x,y,z),Color3.fromRGB(49,65,52),Enum.Material.Metal,false)
   for _,face in {Enum.NormalId.Front,Enum.NormalId.Back}do
   local gui=Instance.new("SurfaceGui");gui.Face=face;gui.Parent=board
   local label=Instance.new("TextLabel");label.Size=UDim2.fromScale(1,1);label.BackgroundTransparency=1;label.TextColor3=Color3.fromRGB(235,235,216);label.TextScaled=true;label.Text=text;label.Parent=gui
   end
  end
  sign("BarracksSign","BARRACKS",170*scale,13,195*scale)
  for _,strip in data.strips do
   local y=Terrain.sample(data,strip.x,strip.z)
   local profile=strip.profile
   local color=Materials.Colors[profile.surfaceType]
   local layer=part(strip.id,Vector3.new(strip.rx*2,.05,strip.rz*2),CFrame.new(strip.x,y-.024,strip.z),Color3.fromRGB(table.unpack(color)),Enum.Material[Materials.Materials[profile.surfaceType]],false)
   layer.CanQuery=true;layer:SetAttribute("ScannerTerrainOnly",true);layer:SetAttribute("ScannerGroundSupport",true);Materials.annotate(layer,profile)
   layer.Reflectance=profile.wetness*.2
   sign("StripLabel",string.format("%s | wet %.0f%% | depth %.2f studs | firmness %.2f",profile.surfaceType,profile.wetness*100,profile.depth,profile.consistency),strip.x,y+3,strip.z+strip.rz+4)
  end
  -- Boundary-only pavement and dirt: the combat rectangle itself stays open.
  for _,r in data.boundaries do
   local profile=r.profile
   local patch=part(r.id,Vector3.new(r.rx*2,.05,r.rz*2),CFrame.new(r.x,-.024,r.z),Color3.fromRGB(table.unpack(Materials.Colors[profile.surfaceType])),Enum.Material[Materials.Materials[profile.surfaceType]],false)
   patch.CanQuery=true;patch:SetAttribute("ScannerTerrainOnly",true);patch:SetAttribute("ScannerGroundSupport",true);Materials.annotate(patch,profile)
  end
 end
 -- Visible vertical banks, not collision barriers above the lip.
 for _,x in {-23,23}do
  part("RavineWall",Vector3.new(2*scale,40,140*scale),CFrame.new(x*scale,-22,-5*scale),Color3.fromRGB(102,88,72),Enum.Material.Slate,true)
 end
 local river=part("River",Vector3.new(44*scale,.3,140*scale),CFrame.new(0,-30,-5*scale),Color3.fromRGB(42,125,161),Enum.Material.Glass,false)
 river.Transparency=.2;river:SetAttribute("FlowDirection","South")
 for z=-68,60,16 do
  part("Current",Vector3.new(1,.05,7*scale),CFrame.new(0,-29.8,z*scale),Color3.fromRGB(143,210,222),Enum.Material.SmoothPlastic,false)
 end
 part("RavineBed",Vector3.new(44*scale,2,140*scale),CFrame.new(0,Terrain.Depth-1,-5*scale),Color3.fromRGB(79,70,62),Enum.Material.Slate,true)
 return folder
end
return Builder
