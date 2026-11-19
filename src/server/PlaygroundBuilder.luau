local Terrain=require(game.ReplicatedStorage.Shared.PlaygroundTerrain)
local Builder={}
function Builder.build(arena,data,floor)
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
  part(r.name,Vector3.new(r.x1-r.x0,thickness,(r.z1-r.z0)*math.sqrt(1+r.slope*r.slope)),
   CFrame.new((r.x0+r.x1)/2,height-thickness*math.cos(angle)/2,mid-thickness*math.sin(angle)/2)*CFrame.Angles(angle,0,0),
   if bridge then Color3.fromRGB(146,112,69)else Color3.fromRGB(100,112,86),if bridge then Enum.Material.WoodPlanks else Enum.Material.Grass,true)
 end
 -- Visible vertical banks, not collision barriers above the lip.
 for _,x in {-23,23}do
  part("RavineWall",Vector3.new(2,40,140),CFrame.new(x,-22,-5),Color3.fromRGB(102,88,72),Enum.Material.Slate,true)
 end
 local river=part("River",Vector3.new(44,.3,140),CFrame.new(0,-30,-5),Color3.fromRGB(42,125,161),Enum.Material.Glass,false)
 river.Transparency=.2;river:SetAttribute("FlowDirection","South")
 for z=-68,60,16 do
  part("Current",Vector3.new(1,.05,7),CFrame.new(0,-29.8,z),Color3.fromRGB(143,210,222),Enum.Material.SmoothPlastic,false)
 end
 part("RavineBed",Vector3.new(44,2,140),CFrame.new(0,Terrain.Depth-1,-5),Color3.fromRGB(79,70,62),Enum.Material.Slate,true)
 return folder
end
return Builder
