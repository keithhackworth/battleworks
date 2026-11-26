local Preview = {}

local function part(world, color, size, position, shape)
	local object = Instance.new("Part")
	object.Anchored = true
	object.CanCollide = false
	object.Size = size
	object.Color = color
	object.Position = position
	object.Shape = shape or Enum.PartType.Block
	object.Parent = world
	return object
end

local function tank(world, origin, paint, bunny)
	local dark = Color3.fromRGB(37, 39, 32)
	local brass = Color3.fromRGB(183, 145, 66)
	local function block(color, x, y, z, w, h, d)
		return part(world, color, Vector3.new(w, h, d), origin + Vector3.new(x, y, z))
	end
	block(paint, 0, 0.9, 0, 3.3, 0.8, 4.5)
	block(paint, 0, 1.55, 0.15, 2.2, 0.78, 2.2)
	block(paint, 0, 1.6, -1.65, 0.31, 0.34, 2.7)
	for _, side in ipairs({ -1, 1 }) do
		block(dark, side * 1.58, 0.55, 0, 0.65, 0.88, 4.7)
		for index = -2, 2 do
			part(world, brass, Vector3.new(0.15, 0.67, 0.67),
				origin + Vector3.new(side * 1.95, 0.55, index * 0.93), Enum.PartType.Cylinder)
		end
		if bunny then
			local ear = block(Color3.fromRGB(234, 218, 179), side * 0.47, 2.33, 0.25, 0.34, 1.05, 0.25)
			ear.Orientation = Vector3.new(0, 0, -side * 12)
		end
	end
end

function Preview.new(parent, field)
	local view = Instance.new("ViewportFrame")
	view.Size = UDim2.fromScale(1, 1)
	view.BorderSizePixel = 0
	view.BackgroundColor3 = if field then Color3.fromRGB(99, 163, 196) else Color3.fromRGB(72, 78, 58)
	view.Ambient = Color3.fromRGB(172, 167, 143)
	view.LightColor = Color3.fromRGB(255, 231, 192)
	view.LightDirection = Vector3.new(-1, -2, -1)
	view.Parent = parent
	local world = Instance.new("WorldModel")
	world.Parent = view
	local camera = Instance.new("Camera")
	camera.FieldOfView = if field then 50 else 38
	camera.Parent = view
	view.CurrentCamera = camera

	local olive = Color3.fromRGB(113, 121, 57)
	if not field then
		tank(world, Vector3.zero, olive, true)
		camera.CFrame = CFrame.lookAt(Vector3.new(7, 4.7, -8.5), Vector3.new(0, 1.15, 0))
		return
	end

	local earth = Color3.fromRGB(141, 104, 73)
	local grass = Color3.fromRGB(119, 145, 68)
	local wood = Color3.fromRGB(103, 71, 45)
	local green = Color3.fromRGB(55, 91, 65)
	part(world, Color3.fromRGB(51, 146, 181), Vector3.new(11, 0.3, 64), Vector3.new(0, -1.5, 0))
	for _, side in ipairs({ -1, 1 }) do
		part(world, earth, Vector3.new(19, 2, 46), Vector3.new(side * 14.7, -0.9, 0))
		part(world, grass, Vector3.new(19, 0.2, 46), Vector3.new(side * 14.7, 0, 0))
		for index = 1, 7 do
			local x = side * (8 + index % 3 * 3)
			local z = -10 + index * 3.8
			part(world, wood, Vector3.new(0.5, 3, 0.5), Vector3.new(x, 1.5, z))
			part(world, green, Vector3.new(2.7, 4, 2.7), Vector3.new(x, 3.1, z), Enum.PartType.Ball)
		end
	end
	for index = -7, 7 do
		part(world, wood, Vector3.new(0.71, 0.28, 4.4), Vector3.new(index * 0.74, 0.2, 2))
	end
	for _, z in ipairs({ -0.16, 4.16 }) do
		part(world, wood, Vector3.new(11.2, 0.2, 0.2), Vector3.new(0, 1.1, z))
		for index = -2, 2 do
			part(world, wood, Vector3.new(0.2, 1, 0.2), Vector3.new(index * 2.6, 0.68, z))
		end
	end
	tank(world, Vector3.new(-8, 0.15, -3), olive, false)
	tank(world, Vector3.new(8, 0.15, 4), Color3.fromRGB(176, 92, 49), false)
	camera.CFrame = CFrame.lookAt(Vector3.new(-13, 9, -15), Vector3.new(0, 0.75, 3))
end

return Preview
