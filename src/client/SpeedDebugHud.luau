-- Studio readout: horizontal recoil boost is separate from vertical hopping speed.
local Components=require(game.ReplicatedStorage.Shared.VehicleComponents)
local Hud={}
Hud.__index=Hud
function Hud.new(gui)
	if not game:GetService("RunService"):IsStudio() then return nil end
	local self=setmetatable({},Hud)
	local label=Instance.new("TextLabel")
	label.Name="MovementSpeedDebug"; label.AnchorPoint=Vector2.new(1,0)
	label.Position=UDim2.new(1,-8,0,88); label.Size=UDim2.fromOffset(228,110)
	label.BackgroundColor3=Color3.fromRGB(24,31,35); label.BackgroundTransparency=0.12
	label.TextColor3=Color3.fromRGB(237,235,218); label.Font=Enum.Font.Code; label.TextSize=12
	label.TextXAlignment=Enum.TextXAlignment.Left; label.TextWrapped=false
	label.Text="SPEED: waiting for tank…"; label.Parent=gui
	self.label=label
	return self
end
function Hud:update(state)
	if not state then self.label.Text="SPEED: waiting for tank…"; return end
	local rated=Components.get(state).Drivetrain.Speed
 local normal=rated*(state.drivePerformance or 1)
	local horizontal=state.movementSpeedXZ or 0
	local extra=math.max(0,horizontal-normal)
	self.label.Text=string.format("XZ SPEED %5.1f studs/s\nPEAK %4.1f | LIMIT %4.1f\nRATED %4.1f | YAW %+5.1f deg/s\nVERT %+5.1f | 3D %5.1f\n%s",
		horizontal,state.movementPeakXZ or 0,normal,rated,math.deg(if state.angularVelocity then state.angularVelocity.Y else 0),state.movementSpeedY or 0,state.movementSpeed3D or 0,
		if extra>0.05 then (if normal>0 then string.format("BOOST +%.1f (+%.0f%%)",extra,extra/normal*100) else "MOVING WITH DRIVE DISABLED") else "AT/BELOW DRIVE SPEED").."\n"..(if state.motionSlipping then "SLIDING / TRACTION LIMITED" else "CONTACT: "..(if state.grounded then "GROUNDED" else "AIRBORNE"))
	self.label.TextColor3=if extra>0.05 then Color3.fromRGB(203,255,78) else Color3.fromRGB(237,235,218)
end
function Hud:destroy() self.label:Destroy() end
return Hud
