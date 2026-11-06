-- Temporary, Studio-only diagnostics. Attributes live on PlayerGui.BattlefieldCameraBars.
local Debug = {}
local function v(p) return string.format("(%.2f,%.2f,%.2f)", p.X, p.Y, p.Z) end
function Debug.report(camera, state, layout, gui, world, id)
	local lines = { "[BattleWorks camera debug]",
		"position=" .. v(camera.CFrame.Position) .. " look=" .. v(camera.CFrame.LookVector)
			.. " focus=" .. v(camera.Focus.Position),
		"FOV=" .. camera.FieldOfView .. " mode=" .. tostring(camera.FieldOfViewMode)
			.. " viewport=" .. tostring(camera.ViewportSize) .. " GUI size=" .. tostring(gui.AbsoluteSize),
		"paused=" .. tostring(gui:GetAttribute("PauseCamera")) .. " masksHidden=" .. tostring(gui:GetAttribute("HideMasks")),
		"playable X/Z=[-115,115]; walls X/Z=[-120,120]; ground Y=0",
	}
	if layout then
		table.insert(lines, string.format("window=(%.1f,%.1f,%.1f,%.1f) distance=%.2f wholeMap=%s",
			layout.lens.x, layout.lens.y, layout.lens.width, layout.lens.height, layout.distance, tostring(layout.wholeMap)))
	end
	local arena = world:FindFirstChild("Arena")
	if arena then
		for _, part in arena:GetChildren() do
			if part:IsA("BasePart") and part.Name == "Boundary" then
				table.insert(lines, "actual boundary center=" .. v(part.Position) .. " size=" .. v(part.Size))
			end
		end
	end
	local base = world:FindFirstChild("Baseplate")
	if base then table.insert(lines, "baseplate position=" .. v(base.Position) .. " size=" .. v(base.Size)) end
	if state then
		local p, on = camera:WorldToViewportPoint(state.position)
		table.insert(lines, "tank state=" .. v(state.position) .. " screen=" .. v(p) .. " onScreen=" .. tostring(on))
	end
	local model = world:FindFirstChild("Tank_" .. id)
	if model then
		local lowX, lowY, highX, highY = math.huge, math.huge, -math.huge, -math.huge
		for _, part in model:GetChildren() do
			if part:IsA("BasePart") then
				local a, b, c, d = math.huge, math.huge, -math.huge, -math.huge
				local behind = false
				for _, x in { -1, 1 } do for _, y in { -1, 1 } do for _, z in { -1, 1 } do
					local point = part.CFrame:PointToWorldSpace(Vector3.new(x * part.Size.X / 2, y * part.Size.Y / 2, z * part.Size.Z / 2))
					local q = camera:WorldToViewportPoint(point)
					behind = behind or q.Z <= 0
					a = math.min(a, q.X); b = math.min(b, q.Y); c = math.max(c, q.X); d = math.max(d, q.Y)
				end end end
				lowX = math.min(lowX, a); lowY = math.min(lowY, b); highX = math.max(highX, c); highY = math.max(highY, d)
				if part.Name == "Chassis" then
					table.insert(lines, string.format("rendered chassis center=%s pixels=%.1fx%.1f rect=(%.1f,%.1f)-(%.1f,%.1f) behind=%s transparency=%.1f localTransparency=%.1f",
						v(part.Position), c-a, d-b, a,b,c,d,tostring(behind),part.Transparency,part.LocalTransparencyModifier))
				end
			end
		end
		table.insert(lines, string.format("full model projected bounds=(%.1f,%.1f)-(%.1f,%.1f)",lowX,lowY,highX,highY))
	end
	for _, uv in { Vector2.new(0,0), Vector2.new(0.5,0.5), Vector2.new(1,0), Vector2.new(1,1), Vector2.new(0,1) } do
		local ray = camera:ViewportPointToRay(camera.ViewportSize.X * uv.X, camera.ViewportSize.Y * uv.Y)
		local t = if math.abs(ray.Direction.Y) > 1e-6 then -ray.Origin.Y / ray.Direction.Y else -1
		table.insert(lines, "viewport ray " .. tostring(uv) .. " ground=" .. (if t >= 0 then v(ray.Origin + ray.Direction * t) else "no forward intersection"))
	end
	for _, bar in gui:GetChildren() do
		if bar:IsA("Frame") then table.insert(lines, bar.Name .. " absolute=" .. tostring(bar.AbsolutePosition) .. " size=" .. tostring(bar.AbsoluteSize)) end
	end
	print(table.concat(lines, "\n"))
end
return Debug
