-- Local, short-lived water/mud accents driven by replicated surface and motion.
local TweenService=game:GetService("TweenService")
local Debris=game:GetService("Debris")
local Effects={}
local function part(name,size,color)
	local p=Instance.new("Part"); p.Name=name; p.Size=size; p.Color=color
	p.Anchored=true; p.CanCollide=false; p.CanTouch=false; p.CanQuery=false; p.CastShadow=false
	p.Material=Enum.Material.SmoothPlastic; p.Parent=workspace
	return p
end
local function ripple(center)
	-- Eight connected segments keep a real hollow ring without an image asset.
	for i=1,8 do
		local a=(i-1)*math.pi/4
		local radial=Vector3.new(math.cos(a),0,math.sin(a))
		local p=part("WaterRipple",Vector3.new(0.9,0.045,0.09),Color3.fromRGB(185,234,241))
		p.Transparency=0.2; p.CFrame=CFrame.new(center+radial*1.1)*CFrame.Angles(0,-a-math.pi/2,0)
		TweenService:Create(p,TweenInfo.new(0.7,Enum.EasingStyle.Quad,Enum.EasingDirection.Out),{
			CFrame=CFrame.new(center+radial*3.5)*CFrame.Angles(0,-a-math.pi/2,0),Size=Vector3.new(2.9,0.025,0.06),Transparency=1,
		}):Play(); Debris:AddItem(p,0.75)
	end
end
function Effects.update(renderer,state,dt)
	local wet=state.surface=="Water"
	local muddy=state.surface=="Mud"
	local moving=state.health>0 and math.abs(state.speed)>1
	renderer.terrainEffectAge=(renderer.terrainEffectAge or 0)+math.max(dt,0)
	local entered=wet and renderer.lastSurface~="Water"
	renderer.lastSurface=state.surface
	if not moving or not (wet or muddy) then return end
	if not entered and renderer.terrainEffectAge<(if wet then 0.3 else 0.45) then return end
	renderer.terrainEffectAge=0
	local position=renderer.position or state.position
	local frame=CFrame.new(position)*CFrame.Angles(0,renderer.yaw or state.yaw,0)
	local side=if (renderer.terrainSide or 1)>0 then 1 else -1
	renderer.terrainSide=-side
	local contact=frame:PointToWorldSpace(Vector3.new(side*3.8,0,if state.speed>0 then 2 else -2))
	local center=Vector3.new(contact.X,0.2,contact.Z)
	if wet then ripple(center) end
	for i=1,(if entered then 8 else 4) do
		local p=part(if wet then "WaterSplash" else "MudFleck",Vector3.new(0.28,0.5,0.28),
			if wet then Color3.fromRGB(141,214,234) else Color3.fromRGB(90,58,33))
		p.Shape=Enum.PartType.Ball; p.Position=center
		local offset=Vector3.new(math.sin(i*2.4)*1.6,1+(i%3)*0.5,math.cos(i*2.4)*1.6)
		local rise=TweenService:Create(p,TweenInfo.new(0.18,Enum.EasingStyle.Quad,Enum.EasingDirection.Out),{Position=center+offset})
		local fall=TweenService:Create(p,TweenInfo.new(0.2,Enum.EasingStyle.Quad,Enum.EasingDirection.In),{
			Position=center+Vector3.new(offset.X*1.4,0,offset.Z*1.4),Transparency=1,Size=Vector3.new(0.1,0.1,0.1),
		})
		local connection
		connection=rise.Completed:Connect(function() connection:Disconnect(); fall:Play() end)
		rise:Play(); Debris:AddItem(p,0.42)
	end
end
return Effects
