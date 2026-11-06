-- Pure perspective geometry. No camera Instances, input, networking, or gameplay writes.
local Math = {}
local EPSILON = 1e-7
local function dot(a, b) return a.X * b.X + a.Y * b.Y + a.Z * b.Z end
local function dot2(a, b) return a.X * b.X + a.Y * b.Y end
local function distance2(a, b) return (a.X - b.X) ^ 2 + (a.Y - b.Y) ^ 2 end
function Math.basis(elevation, azimuth)
	local e, a = math.rad(elevation), math.rad(azimuth)
	assert(elevation > 0 and elevation < 90, "Camera elevation must be between 0 and 90")
	return {
		forward = Vector3.new(-math.sin(a) * math.cos(e), -math.sin(e), -math.cos(a) * math.cos(e)),
		right = Vector3.new(math.cos(a), 0, -math.sin(a)),
		up = Vector3.new(-math.sin(a) * math.sin(e), math.cos(e), -math.cos(a) * math.sin(e)),
	}
end
function Math.window(viewport, config, padding)
	-- Symmetric safe-area padding keeps the optical center at the physical screen center.
	padding = padding or Vector2.zero
	local width, height = viewport.X - padding.X * 2, viewport.Y - padding.Y * 2
	if width <= 1 or height <= 1 then return nil end
	local w = math.min(width, height * config.AspectRatio)
	local h = w / config.AspectRatio
	local fraction = h / viewport.Y
	local fov = math.deg(2 * math.atan(math.tan(math.rad(config.FieldOfView) / 2) / fraction))
	-- Roblox vertical FOV is limited to 120. Extreme tall windows use a narrower
	-- effective lens; geometry is recalculated, so the footprint cap still holds.
	fov = math.clamp(fov, 1, 120)
	local tanV = math.tan(math.rad(fov) / 2) * fraction
	return { x = (viewport.X - w) / 2, y = (viewport.Y - h) / 2, width = w, height = h,
		fov = fov, tanV = tanV, tanH = tanV * config.AspectRatio }
end
function Math.toLocal(map, point)
	local q, a = point - map.center, math.rad(map.yaw)
	return Vector2.new(math.cos(a) * q.X - math.sin(a) * q.Z, math.sin(a) * q.X + math.cos(a) * q.Z)
end
function Math.toWorld(map, point)
	local a = math.rad(map.yaw)
	return map.center + Vector3.new(math.cos(a) * point.X + math.sin(a) * point.Y, 0,
		-math.sin(a) * point.X + math.cos(a) * point.Y)
end
function Math.corners(map, margin, height)
	local result = {}
	for _, x in { -1, 1 } do
		for _, z in { -1, 1 } do
			table.insert(result, Math.toWorld(map, Vector2.new(x * (map.size.X / 2 + margin), z * (map.size.Y / 2 + margin)))
				+ Vector3.new(0, height, 0))
		end
	end
	return result
end
function Math.fitDistance(map, basis, lens, margin, height)
	local distance = 0
	for _, y in { 0, height } do
		for _, corner in Math.corners(map, margin, y) do
			local q = corner - map.center
			distance = math.max(distance, math.abs(dot(q, basis.right)) / lens.tanH - dot(q, basis.forward),
				math.abs(dot(q, basis.up)) / lens.tanV - dot(q, basis.forward))
		end
	end
	return math.max(distance, 1)
end
function Math.groundCorners(basis, lens, distance, inset)
	local points = {}
	inset = inset or 1
	-- Cyclic order is required by polygon clipping/projection below.
	for _, uv in { Vector2.new(-1, -1), Vector2.new(1, -1), Vector2.new(1, 1), Vector2.new(-1, 1) } do
		local ray = basis.forward + basis.right * (uv.X * lens.tanH * inset) + basis.up * (uv.Y * lens.tanV * inset)
		assert(ray.Y < -EPSILON, "Visible camera window intersects the horizon; lower FOV or increase elevation")
		local origin = basis.forward * -distance
		table.insert(points, origin + ray * (-origin.Y / ray.Y))
	end
	return points
end
local function diameter(points)
	local value = 0
	for _, a in points do for _, b in points do value = math.max(value, (a - b).Magnitude) end end
	return value
end
function Math.layout(viewport, config, padding)
	local lens = Math.window(viewport, config, padding)
	if not lens then return nil end
	assert(config.MaxGroundFootprint > 0 and config.MapSize.X > 0 and config.MapSize.Y > 0, "Positive camera/map dimensions required")
	assert(config.MinZoom > 0 and config.MaxZoom >= config.MinZoom, "Invalid camera zoom range")
	assert(config.TankViewInset > 0 and config.TankViewInset <= 1, "Invalid camera dead zone")
	local basis = Math.basis(config.Elevation, config.Azimuth)
	local map = { center = config.MapCenter, size = config.MapSize, yaw = config.MapYaw }
	local unit = Math.groundCorners(basis, lens, 1)
	local minimum, maximum = Vector2.new(math.huge, math.huge), Vector2.new(-math.huge, -math.huge)
	for _, offset in unit do
		local p = Math.toLocal(map, map.center + offset)
		minimum = Vector2.new(math.min(minimum.X, p.X), math.min(minimum.Y, p.Y))
		maximum = Vector2.new(math.max(maximum.X, p.X), math.max(maximum.Y, p.Y))
	end
	local fit = Math.fitDistance(map, basis, lens, config.Margin, config.HeightAllowance)
	local footprintCap = config.MaxGroundFootprint / diameter(unit)
	-- A six-stud chord through the chassis along camera-right has constant
	-- depth at every yaw. Bound its pixels at the farthest visible ground point.
	-- Use a FIXED reference pixel budget: smaller viewports must not zoom out.
	local maxDepth = 0
	for _, offset in unit do maxDepth = math.max(maxDepth, 1 + dot(offset, basis.forward)) end
	local readable = config.ReferenceWindowHeight * config.TankReadableWidth
		/ (2 * lens.tanV * config.MinTankPixels * maxDepth)
	local cap = math.min(footprintCap, readable, config.MaxZoom)
	local wholeDistance = math.max(fit, config.MinZoom)
	-- Overview tanks live inside the playable rectangle, not in the empty far
	-- viewport corners. Evaluate the full silhouette at the farthest playable
	-- depth; keep the stricter chassis budget above for action/follow mode.
	local farthest = 0
	for _, corner in Math.corners(map, 0, 0) do
		farthest = math.max(farthest, dot(corner - map.center, basis.forward))
	end
	local wholeReadable = config.ReferenceWindowHeight * config.TankSilhouetteWidth
		/ (2 * lens.tanV * config.WholeMapMinTankPixels) - farthest
	local wholeCap = math.min(footprintCap, config.MaxZoom, wholeReadable)
	local wholeMap = wholeDistance <= wholeCap + EPSILON
	-- In pan mode also reduce distance enough that the footprint CAN fit within
	-- both map axes. A long thin map must not expose enormous empty side regions.
	local contain = math.huge
	if math.max(map.size.X, map.size.Y) > math.min(map.size.X, map.size.Y) * 2 then
		contain = math.min(map.size.X / (maximum.X - minimum.X), map.size.Y / (maximum.Y - minimum.Y))
	end
	-- Geometric/readability safety caps take priority over the preferred minimum
	-- on narrow maps. Prefer the minimum fitting distance; MaxZoom caps both modes.
	local distance = if wholeMap then wholeDistance else math.min(cap, contain,
		math.clamp(math.min(fit, config.DefaultZoom), config.MinZoom, config.MaxZoom))
	return { lens = lens, basis = basis, map = map, distance = distance, wholeMap = wholeMap,
		minimum = minimum * distance, maximum = maximum * distance,
		ground = Math.groundCorners(basis, lens, distance),
		safeGround = Math.groundCorners(basis, lens, distance, config.TankViewInset),
		deadZone = config.TankViewInset, fitDistance = fit, readabilityDistance = readable,
		wholeMapReadabilityDistance = wholeReadable }
end
-- Conservative chassis width in physical window pixels, before rasterization
-- or occlusion. Ground center is conservative for the elevated chassis.
function Math.tankPixels(layout, focus, position, width)
	local depth = layout.distance + dot(position - focus, layout.basis.forward)
	return layout.lens.height * width / (2 * layout.lens.tanV * depth)
end
local function nearest(polygon, point)
	local result, best, positive, negative = polygon[1], math.huge, false, false
	for i, a in polygon do
		local b = polygon[i % #polygon + 1]
		local edge = b - a
		local cross = edge.X * (point.Y - a.Y) - edge.Y * (point.X - a.X)
		positive = positive or cross > EPSILON; negative = negative or cross < -EPSILON
		local t = math.clamp(dot2(point - a, edge) / math.max(dot2(edge, edge), EPSILON), 0, 1)
		local candidate = a + edge * t
		local squared = distance2(candidate, point)
		if squared < best then result, best = candidate, squared end
	end
	if #polygon >= 3 and not (positive and negative) and best > EPSILON then
		-- Degenerate collinear polygons must not accept arbitrary off-segment points.
		local area = 0
		for i, a in polygon do local b = polygon[i % #polygon + 1]; area += a.X * b.Y - b.X * a.Y end
		if math.abs(area) > EPSILON then return point end
	end
	return result
end
-- Clip the focus region to reasonable map-local optical-target bounds. This
-- deliberately does not require the entire oblique ground footprint to fit.
local function clip(polygon, axis, sign, limit)
	local output = {}
	if #polygon == 0 then return output end
	local a = polygon[#polygon]
	local da = sign * a[axis] - limit
	for _, b in polygon do
		local db = sign * b[axis] - limit
		if (da <= 0) ~= (db <= 0) then table.insert(output,a + (b-a) * (da/(da-db))) end
		if db <= 0 then table.insert(output,b) end
		a,da = b,db
	end
	return output
end
-- Normalized screen coordinates: -1..1 spans the visible battlefield window.
-- An inset of .20 gives pixel bounds [.40W,.60W] and [.40H,.60H].
function Math.project(layout, focus, point)
	local q = point - focus
	local depth = layout.distance + dot(q, layout.basis.forward)
	return dot(q, layout.basis.right) / (depth * layout.lens.tanH),
		dot(q, layout.basis.up) / (depth * layout.lens.tanV), depth
end
function Math.target(layout, tank, desired)
	if layout.wholeMap then return layout.map.center, 0 end
	local map = layout.map
	local current = desired or map.center
	local localFocus = Math.toLocal(map, current)
	local u, v, depth = Math.project(layout, current, tank)
	if depth > 0 and math.abs(u) <= layout.deadZone + EPSILON and math.abs(v) <= layout.deadZone + EPSILON
		and math.abs(localFocus.X) <= map.size.X / 2 and math.abs(localFocus.Y) <= map.size.Y / 2 then
		-- Preserve the exact previous focus inside the screen-space dead zone.
		-- Measure footprint overflow without changing this focus.
		return current, Math.overflow(layout, current)
	end
	local localTank = Math.toLocal(map, tank)
	-- Desired is the PREVIOUS focus, not the tank. Projection returns it exactly
	-- while the tank is inside the dead zone; otherwise it moves only to the
	-- closest feasible focus, preserving the map's position on screen.
	local candidates = {}
	for _, offset in layout.safeGround do
		table.insert(candidates, localTank - Math.toLocal(map, map.center + offset))
	end
	local bounded = clip(candidates,"X",1,map.size.X/2)
	bounded = clip(bounded,"X",-1,map.size.X/2)
	bounded = clip(bounded,"Y",1,map.size.Y/2)
	bounded = clip(bounded,"Y",-1,map.size.Y/2)
	-- Visibility wins if a teleport/out-of-bounds state makes both impossible.
	local focus = nearest(if #bounded > 0 then bounded else candidates,
		Math.toLocal(map, desired or map.center))
	-- Report actual outside-ground extent using every oblique footprint corner.
	-- Overflow affects translation only; distance/FOV/coverage never increase.
	local worldFocus = Math.toWorld(map, focus)
	return worldFocus, Math.overflow(layout, worldFocus)
end
function Math.overflow(layout, worldFocus)
	local map = layout.map
	local focus = Math.toLocal(map, worldFocus)
	local overflow = 0
	for _, offset in layout.ground do
		local point = focus + Math.toLocal(map, map.center + offset)
		overflow = math.max(overflow, math.abs(point.X) - map.size.X / 2, math.abs(point.Y) - map.size.Y / 2)
	end
	return overflow
end
function Math.track(layout, tank, previous)
	-- Immediate minimal correction: no speed cap, easing, or accumulated drift.
	return Math.target(layout, tank, previous or layout.map.center)
end
function Math.shouldSnap(previous, state, threshold)
	return previous == nil or (previous.health <= 0 and state.health > 0)
		or (state.position - previous.position).Magnitude > threshold
end
return Math
