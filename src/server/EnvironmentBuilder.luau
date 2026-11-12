-- Cosmetic terrain and queryable cover from the same deterministic terrain data.
local Builder = {}
local function part(parent,name,size,frame,color,material,shape,query)
	local p=Instance.new("Part")
	p.Name=name; p.Size=size; p.CFrame=frame; p.Color=color; p.Material=material
	p.Anchored=true; p.CanCollide=false; p.CanTouch=false; p.CanQuery=query or false
	p.TopSurface=Enum.SurfaceType.Smooth; p.BottomSurface=Enum.SurfaceType.Smooth
	if shape then p.Shape=shape end
	if query then p:SetAttribute("ScannerType","object") end
	p.Parent=parent
	return p
end
function Builder.build(arena,data,floor)
 local icy=data.weather=="IceWind"
 if floor then
  floor.Material=if icy then Enum.Material.Ice else Enum.Material.Grass
  floor.Color=if icy then Color3.fromRGB(184,218,235) else Color3.fromRGB(100,112,86)
  floor.Reflectance=if icy then 0.16 else 0
 end
	local old=arena:FindFirstChild("Environment")
	if old then old:Destroy() end
	local folder=Instance.new("Folder"); folder.Name="Environment"; folder.Parent=arena
	for _,zone in data.zones do
		local color=if zone.kind=="Water" then Color3.fromRGB(67,156,183) elseif zone.kind=="Mud" then Color3.fromRGB(103,70,43) else Color3.fromRGB(73,105,57)
		local patch=part(folder,zone.kind,Vector3.new(zone.rx*2,0.16,zone.rz*2),CFrame.new(zone.x,0.08,zone.z),color,
			if zone.kind=="Water" then Enum.Material.Glass elseif zone.kind=="Mud" then Enum.Material.Mud else Enum.Material.Grass,Enum.PartType.Ball)
		if zone.kind=="Water" then
			patch.Transparency=0.18; patch.Reflectance=0.15
			for i=1,7 do
				part(folder,"WaterGlint",Vector3.new(zone.rx*0.18,0.025,0.14),CFrame.new(zone.x+math.sin(i*2.4)*zone.rx*0.7,0.17,zone.z+math.cos(i*1.8)*zone.rz*0.7),Color3.fromRGB(151,218,230),Enum.Material.SmoothPlastic)
			end
		elseif zone.kind=="Mud" then
			for i=1,8 do
				part(folder,"MudRuts",Vector3.new(0.45,0.04,zone.rz*0.25),CFrame.new(zone.x+math.sin(i*2.4)*zone.rx*0.7,0.17,zone.z+math.cos(i)*zone.rz*0.6),Color3.fromRGB(73,47,31),Enum.Material.Mud,Enum.PartType.Ball)
			end
		end
	end
 if icy then
  for _,p in folder:GetChildren() do
   if p:IsA("BasePart") then
    p.Material=Enum.Material.Ice; p.Color=Color3.fromRGB(165,206,225); p.Reflectance=0.12
   end
  end
  -- Cosmetic frost streaks never enter collision/scanner queries.
  for i=1,12 do
   local x=math.sin(i*2.4)*data.size.X*.42; local z=math.cos(i*1.7)*data.size.Y*.42
   local length=math.min(12,data.size.X*.12)
   local streak=part(folder,"IceStreak",Vector3.new(length,.025,.12),CFrame.new(x,.015,z)*CFrame.Angles(0,-.3,0),Color3.fromRGB(228,246,251),Enum.Material.SmoothPlastic)
   streak.Transparency=.4
  end
  local direction=data.wind.direction
  local frame=CFrame.new(0,.18,data.size.Y*.32)*CFrame.Angles(0,math.atan2(-direction.X,-direction.Z),0)
  part(folder,"WindArrow",Vector3.new(.2,.04,5),frame,Color3.fromRGB(93,154,184),Enum.Material.SmoothPlastic)
  for _,side in {-1,1} do
   part(folder,"WindArrowHead",Vector3.new(.2,.04,2),frame*CFrame.new(side*.65,0,-1.8)*CFrame.Angles(0,side*math.pi/4,0),Color3.fromRGB(93,154,184),Enum.Material.SmoothPlastic)
  end
 end
	for i,rock in data.rocks do
		part(folder,"Rock",Vector3.new(rock.rx*2,rock.height*2,rock.rz*2),CFrame.new(rock.x,0,rock.z),
			if i%2==0 then Color3.fromRGB(115,123,126) else Color3.fromRGB(137,143,139),Enum.Material.Slate,Enum.PartType.Ball,true)
	end
	for _,log in data.logs do
		part(folder,"FallenLog",Vector3.new(log.half*2,log.radius*2,log.radius*2),CFrame.new(log.x,0,log.z),Color3.fromRGB(92,61,37),Enum.Material.Wood,Enum.PartType.Cylinder,true)
		for _,side in {-1,1} do
			part(folder,"LogCutEnd",Vector3.new(0.05,log.radius*1.65,log.radius*1.65),CFrame.new(log.x+side*log.half,0,log.z),Color3.fromRGB(196,154,94),Enum.Material.Wood,Enum.PartType.Cylinder)
		end
	end
	for i,tree in data.trees do
		part(folder,"TreeTrunk",Vector3.new(tree.height,tree.radius*2,tree.radius*2),CFrame.new(tree.x,tree.height/2,tree.z)*CFrame.Angles(0,0,math.pi/2),Color3.fromRGB(100,72,44),Enum.Material.Wood,Enum.PartType.Cylinder,true)
		for layer=1,2 do
			local crown=part(folder,"TreeCrown",Vector3.new(6.5-layer,5,6.5-layer),CFrame.new(tree.x,tree.height-1+layer*1.7,tree.z),
				if icy then Color3.fromRGB(218,235,237) elseif i%2==0 then Color3.fromRGB(66,126,61) else Color3.fromRGB(91,147,63),Enum.Material.Grass,Enum.PartType.Ball)
			crown.Transparency=0.15
		end
	end
	return folder
end
return Builder
