local Math = require("CameraMath")
local defaults = require("BattlefieldCameraConfig")
local count = 0
local function check(value, message) assert(value, message); count += 1 end
local function near(a, b, tolerance) return math.abs(a - b) <= (tolerance or 1e-5) end
local function dot(a, b) return a.X * b.X + a.Y * b.Y + a.Z * b.Z end
local function config(size, yaw)
	local result = table.clone(defaults)
	result.MapSize = size or defaults.MapSize; result.MapYaw = yaw or 0
	return result
end
local function projection(layout, focus, point)
	local q = point - focus
	local depth = layout.distance + dot(q, layout.basis.forward)
	return dot(q, layout.basis.right) / (depth * layout.lens.tanH), dot(q, layout.basis.up) / (depth * layout.lens.tanV), depth
end
local function visible(layout, focus, point, tolerance)
	local x, y, depth = projection(layout, focus, point)
	return depth > 0 and math.abs(x) <= 1 + (tolerance or 1e-5) and math.abs(y) <= 1 + (tolerance or 1e-5)
end
local function assertCap(layout, cap)
	for _, a in layout.ground do
		check(near(a.Y, 0), "footprint corner intersects ground plane")
		for _, b in layout.ground do check((a - b).Magnitude <= cap + 1e-4, "ground diameter cap") end
	end
end
local b = Math.basis(50, 45)
check(near(b.forward.Magnitude, 1) and near(b.up.Magnitude, 1) and near(b.right.Magnitude, 1), "camera basis is normalized")
check(near(dot(b.forward, b.up), 0) and near(dot(b.right, b.up), 0) and near(dot(b.right, b.forward), 0), "basis orthogonal")
check(near(-b.forward.Y, math.sin(math.rad(50))) and b.forward.X < 0 and b.forward.Z < 0, "50 degree elevation, camera +X/+Z looking -X/-Z")
check(near(Math.basis(50, 0).forward.X, 0) and Math.basis(50, 90).forward.X < 0, "azimuth convention")
check(Math.window(Vector2.zero, defaults) == nil, "zero viewport waits for initialization")
local sizes = { Vector2.new(1920, 1080), Vector2.new(2560, 1080), Vector2.new(568, 320), Vector2.new(812, 362), Vector2.new(800, 600), Vector2.new(360, 640), Vector2.new(160, 1000) }
local small = config(Vector2.new(8, 8))
small.Margin = 0; small.HeightAllowance = 2
local reference
for _, viewport in sizes do
	local layout = Math.layout(viewport, small)
	check(layout.wholeMap, "readable tiny arena fits in full-map mode")
	check(near(layout.lens.width / layout.lens.height, defaults.AspectRatio), "competitive window aspect identical")
	check(layout.lens.width <= viewport.X and layout.lens.height <= viewport.Y, "window fits viewport")
	check(layout.lens.fov >= 1 and layout.lens.fov <= 120, "Roblox FOV range")
	local target = Math.target(layout, Vector3.new(100, 0, 100))
	check((target - defaults.MapCenter).Magnitude < 1e-5, "whole map stays centered independent of local tank")
	for _, height in { 0, small.HeightAllowance } do
		for _, corner in Math.corners(layout.map, small.Margin, height) do
			check(visible(layout, target, corner), "all expanded small-map corners fit, including object height")
		end
	end
	assertCap(layout, defaults.MaxGroundFootprint)
	if layout.lens.fov < 119 then
		if reference then check(near(layout.distance, reference.distance), "same world coverage across desktop/mobile aspect ratios") else reference = layout end
	end
	for _, corner in layout.ground do
		local x, y = projection(layout, layout.map.center, layout.map.center + corner)
		check(near(math.abs(x), 1) and near(math.abs(y), 1), "ground corners map to perspective window corners")
	end
end
-- Readability and coverage are separate requirements. Current arena must pan.
local practicalDistance
for _, viewport in sizes do
	local l = Math.layout(viewport, defaults)
	check(not l.wholeMap, "230 square arena sacrifices full framing for readable tanks")
	if l.lens.fov < 119 then
		if practicalDistance then check(near(l.distance, practicalDistance), "resize cannot grant zoom-out coverage") end
		practicalDistance = l.distance
	end
	for _, ground in l.ground do
		local pixels = Math.tankPixels(l, l.map.center, l.map.center + ground, defaults.TankReadableWidth)
		check(pixels >= defaults.MinTankPixels * l.lens.height / defaults.ReferenceWindowHeight - 1e-5,
			"minimum chassis pixels across full ground window, scaled by actual pixel budget")
	end
	assertCap(l, defaults.MaxGroundFootprint)
end
-- Reproduce short Studio window with plausible symmetric Core UI padding.
local studio = Math.layout(Vector2.new(812, 362), defaults, Vector2.new(0, 58))
check(not studio.wholeMap and studio.lens.height == 246, "short Studio viewport uses readable pan policy")
local studioFocus = Math.target(studio, Vector3.new(-45.5, 0, -32.6))
check(visible(studio, studioFocus, Vector3.new(-45.5, 2.1, -32.6)), "runtime tank position remains in frame")
for _, ground in studio.ground do
	check(Math.tankPixels(studio, studio.map.center, ground, 6) >= defaults.MinTankPixels * 246 / 320 - 1e-5,
		"short inset viewport has explicit scaled minimum pixels")
end
-- Project actual chassis corners at multiple yaws, including the far edge.
for _, yaw in { 0, 23, 45, 90, 173 } do
	for _, ground in studio.ground do
		local lo, hi = math.huge, -math.huge
		for _, x in { -3, 3 } do for _, z in { -4, 4 } do
			local a = math.rad(yaw)
			local point = ground + Vector3.new(x * math.cos(a) + z * math.sin(a), 2.1, -x * math.sin(a) + z * math.cos(a))
			local u = projection(studio, studio.map.center, point)
			lo = math.min(lo, u); hi = math.max(hi, u)
		end end
		check((hi - lo) * studio.lens.width / 2 >= defaults.MinTankPixels * 246 / 320,
			"actual six by eight chassis projected width meets budget at every tested yaw")
	end
end
local safeLayout = Math.layout(Vector2.new(800, 360), small, Vector2.new(59, 58))
check(safeLayout.lens.x >= 59 and safeLayout.lens.y >= 58, "notches/topbar excluded symmetrically")
check(near(safeLayout.distance, reference.distance), "safe-area cropping retains competitive ground coverage")
local rotated = config(Vector2.new(18, 9), 37)
rotated.Margin = 0; rotated.HeightAllowance = 2
rotated.MapCenter = Vector3.new(420, 7, -230)
local layout = Math.layout(Vector2.new(568, 320), rotated)
check(layout.wholeMap, "small rotated rectangle fits")
for _, corner in Math.corners(layout.map, rotated.Margin, rotated.HeightAllowance) do
	check(visible(layout, layout.map.center, corner), "translated/rotated rectangular map corners frame correctly")
	local localCorner = Math.toLocal(layout.map, corner)
	local back = Math.toWorld(layout.map, localCorner)
	check(near(back.X, corner.X) and near(back.Z, corner.Z), "map transforms roundtrip")
end
local large = config(Vector2.new(2400, 1800), 0)
local largeReference
for _, viewport in sizes do
	local l = Math.layout(viewport, large)
	check(not l.wholeMap, "large map enters pan mode")
	assertCap(l, large.MaxGroundFootprint)
	if l.lens.fov < 119 then
		if largeReference then check(near(l.distance, largeReference.distance), "large-map desktop and mobile distance parity") else largeReference = l end
	end
	local center, overflow = Math.target(l, l.map.center)
	check(near(overflow, 0), "no outside ground required at large-map center")
	for _, offset in l.ground do
		local p = Math.toLocal(l.map, center + offset)
		check(math.abs(p.X) <= l.map.size.X / 2 + 1e-4 and math.abs(p.Y) <= l.map.size.Y / 2 + 1e-4, "all visible ground fits bounds")
	end
end
for _, yaw in { 0, 23, 45, 90 } do
	local settings = config(Vector2.new(2000, 1400), yaw)
	local l = Math.layout(Vector2.new(568, 320), settings)
	for _, x in { -1, 0, 1 } do for _, z in { -1, 0, 1 } do
		local tank = Math.toWorld(l.map, Vector2.new(x * (settings.MapSize.X / 2 - 5), z * (settings.MapSize.Y / 2 - 5)))
		local focus, overflow = Math.target(l, tank)
		check(visible(l, focus, tank), "tank remains visible at every rotated map edge and corner")
		for _, offset in l.ground do
			local p = Math.toLocal(l.map, focus + offset)
			check(math.abs(p.X) <= l.map.size.X / 2 + overflow + 1e-4 and math.abs(p.Y) <= l.map.size.Y / 2 + overflow + 1e-4, "reported overflow bounds actual footprint")
		end
		if overflow > 0.001 then
			-- Edge following may expose outside ground, without increasing distance.
			check(overflow < settings.MaxGroundFootprint / 2, "corner fallback avoids uncontrolled empty regions")
		end
	end end
end
local l = Math.layout(Vector2.new(1920, 1080), large)
local tracked = Vector3.new(180, 0, 100)
local focus, overflow = Math.target(l, tracked)
check(overflow == 0 and visible(l, focus, tracked), "interior tank clamps with no overflow")
local again = Math.target(l, tracked, focus)
check((again - focus).Magnitude < 1e-4, "clamp is idempotent; no drift at rest")
-- A thin map cannot be fully framed under the cap. Reduce distance so its width
-- can still contain the rotated trapezoid instead of exposing large side voids.
local thin = config(Vector2.new(80, 4000), 31)
local thinLayout = Math.layout(Vector2.new(2560, 1080), thin)
local thinFocus, thinOverflow = Math.target(thinLayout, thinLayout.map.center)
check(not thinLayout.wholeMap and thinOverflow >= 0, "thin map uses limited pan footprint")
for _, offset in thinLayout.ground do
	local p = Math.toLocal(thinLayout.map, thinFocus + offset)
	check(math.abs(p.X) <= 40.0001 + thinOverflow and math.abs(p.Y) <= 2000.0001 + thinOverflow, "thin-map world footprint stays in bounds")
end
-- A map camera holds its focus inside the dead zone and pans minimally outside.
for _, viewport in { Vector2.new(812,362), Vector2.new(568,320), Vector2.new(2560,1080) } do
	for _, yaw in { 0,37 } do
		local settings = config(Vector2.new(230,230),yaw)
		local arena = Math.layout(viewport,settings)
		local original = arena.map.center
		-- Construct points from the projected dead-zone ground trapezoid.
		for _, corner in arena.safeGround do
			local tank = original + corner * 0.8
			local held = Math.track(arena,tank,original)
			check((held-original).Magnitude < 1e-5,"tank moves across interior without camera movement")
		end
		for _, x in { -110,0,110 } do for _, z in { -110,0,110 } do
			if x ~= 0 or z ~= 0 then
				local destination = Math.toWorld(arena.map,Vector2.new(x,z))
				local focus = original
				for step = 1,180 do
					local tank = original + (destination-original)*(step/180)
					focus = Math.track(arena,tank,focus)
					local u,v = projection(arena,focus,tank)
					check(math.abs(u) <= defaults.TankViewInset+1e-4 and math.abs(v) <= defaults.TankViewInset+1e-4,
						"every rendered route step stays within central 20 percent")
				end
				local ideal = Math.target(arena,destination,focus)
				for _ = 1,240 do focus = Math.track(arena,destination,focus) end
				check((focus-ideal).Magnitude < 1e-4,"stopped tank settles only to dead-zone boundary")
				local u,v = projection(arena,focus,destination)
				check(math.max(math.abs(u),math.abs(v)) > defaults.TankViewInset - 1e-4,"tank is not recentered after stopping")
				local localFocus = Math.toLocal(arena.map,focus)
				check(math.abs(localFocus.X) <=115.0001 and math.abs(localFocus.Y)<=115.0001,
					"optical focus remains within map bounds at all corners")
				local returned = focus + (destination-focus)*0.5
				local held = Math.track(arena,returned,focus)
				check((held-focus).Magnitude < 1e-4,"reversing into dead zone does not recenter camera")
				local outside
				focus,outside = Math.track(arena,destination,focus)
				for _, offset in arena.ground do
					local q = Math.toLocal(arena.map,focus+offset)
					check(math.abs(q.X)<=115+outside+1e-4 and math.abs(q.Y)<=115+outside+1e-4,
						"outside ground measured using oblique footprint")
				end
			end
		end end
		assertCap(arena,defaults.MaxGroundFootprint)
	end
end
local deadLayout = Math.layout(Vector2.new(812,362),defaults)
local outsideTank = deadLayout.safeGround[2]*1.25
local minimumGoal = Math.target(deadLayout,outsideTank,Vector3.zero)
local u,v = projection(deadLayout,minimumGoal,outsideTank)
check(near(math.max(math.abs(u),math.abs(v)),0.20),"minimum pan ends on 20 percent dead-zone boundary")
local corrected = Math.track(deadLayout,outsideTank,Vector3.zero)
check((corrected-minimumGoal).Magnitude < 1e-5,"ordinary pan corrects immediately to boundary")
local heldFocus = minimumGoal
for _ = 1,100 do heldFocus = Math.track(deadLayout,outsideTank,heldFocus) end
check((heldFocus-minimumGoal).Magnitude<1e-5,"stationary camera holds boundary indefinitely")
local tiny = Math.layout(Vector2.new(812,362),small)
local tinyFocus = Math.track(tiny,Vector3.new(3,0,3),Vector3.new(10,0,10))
check((tinyFocus-tiny.map.center).Magnitude<1e-5,"small map stays stationary at center regardless of previous tracking")
-- Displacements representing tiny through long frames are corrected in one step.
local previous, desired = Vector3.zero, Vector3.new(100, 0, 100)
for _, dt in { 0, 1/240, 1/60, 1/15, 0.5 } do
	local tank = desired * (1 + dt * 60)
	local focus = Math.track(deadLayout, tank, previous)
	local u,v = projection(deadLayout,focus,tank)
	check(math.abs(u)<=0.20001 and math.abs(v)<=0.20001,"fast displacement stays within 20 percent at every frame rate")
	local held = Math.track(deadLayout,tank,focus)
	check((held-focus).Magnitude<1e-5,"stopping ends panning immediately without drift")
end
check(Math.shouldSnap(nil, { position = desired, health = 100 }, 40), "first snapshot snaps")
check(Math.shouldSnap({ position = desired, health = 0 }, { position = desired, health = 100 }, 40), "respawn snaps even without position jump")
check(Math.shouldSnap({ position = previous, health = 100 }, { position = desired, health = 100 }, 40), "large teleport snaps")
check(not Math.shouldSnap({ position = previous, health = 100 }, { position = Vector3.new(1, 0, 0), health = 100 }, 40), "ordinary snapshot does not reset rendered pose")
-- Verify the exact pixel rectangle independently of the inverse ground polygon.
local function groundAt(layout, u, v)
	local basis, lens = layout.basis, layout.lens
	local ray = basis.forward + basis.right*(u*lens.tanH) + basis.up*(v*lens.tanV)
	local origin = basis.forward * -layout.distance
	return layout.map.center + origin + ray*(-origin.Y/ray.Y)
end
for _, viewport in sizes do
	local lensLayout = Math.layout(viewport,large)
	for _, u in { -0.20, 0, 0.20 } do for _, v in { -0.20, 0, 0.20 } do
		local tank = groundAt(lensLayout,u,v)
		local focus = Math.track(lensLayout,tank,lensLayout.map.center)
		check(focus == lensLayout.map.center,"inclusive 40 to 60 percent screen rectangle holds exact focus")
		local x,y = Math.project(lensLayout,focus,tank)
		check(near((x+1)/2,(u+1)/2) and near((1-y)/2,(1-v)/2),"projection matches independent screen coordinates")
	end end
	for _, u in { -0.21, 0, 0.21 } do for _, v in { -0.21, 0, 0.21 } do
		if u ~= 0 or v ~= 0 then
			local tank = groundAt(lensLayout,u,v)
			local focus = Math.track(lensLayout,tank,lensLayout.map.center)
			local x,y = projection(lensLayout,focus,tank)
			check(focus.Magnitude>0 and near(math.max(math.abs(x),math.abs(y)),0.20),"crossing each edge/corner corrects exactly to 20 percent boundary")
		end
	end end
end
-- Fast movement cannot outrun correction, including at low FPS and after long frames.
for _, fps in { 15,30,60,144 } do
	for _, speed in { 24,240,2400 } do
		local focus = Vector3.zero
		for frame = 1, fps do
			local tank = Vector3.new(speed*frame/fps,0,-speed*frame/fps)
			focus = Math.track(l, tank, focus)
			local u,v = projection(l,focus,tank)
			check(math.abs(u)<=0.20001 and math.abs(v)<=0.20001,"speed and frame rate never permit dead-zone escape")
		end
	end
end
-- Explicit zoom controls and safety precedence; larger distance means zoom out.
local oldConfig = config(); oldConfig.MinTankPixels = 24
local oldLayout = Math.layout(Vector2.new(568,320),oldConfig)
local currentLayout = Math.layout(Vector2.new(568,320),defaults)
check(currentLayout.distance > oldLayout.distance*1.25,"default shows at least 25 percent more ground span than previous policy")
check(near(currentLayout.distance,defaults.DefaultZoom),"current arena uses configured default zoom")
for _, viewport in {Vector2.new(812,362), Vector2.new(568,320), Vector2.new(2560,1080)} do
	for _, depth in {200,230,300,400} do
		local view = Math.layout(viewport,config(Vector2.new(230,depth)))
		check(not view.wholeMap and near(view.distance,135), "follow camera reaches 135 studs on regular maps across slider depths and viewports")
		assertCap(view,defaults.MaxGroundFootprint)
	end
end
local zoom = config(Vector2.new(2400,1800)); zoom.DefaultZoom = 1
check(near(Math.layout(Vector2.new(568,320),zoom).distance,zoom.MinZoom),"default zoom clamps to minimum")
zoom.DefaultZoom=10000; zoom.MaxZoom=80
check(near(Math.layout(Vector2.new(568,320),zoom).distance,80),"default zoom clamps to maximum")
local tinyZoom = Math.layout(Vector2.new(568,320),small)
check(tinyZoom.wholeMap and near(tinyZoom.distance,small.MinZoom),"tiny maps respect minimum zoom while staying fully framed")
local fitZoom = config(Vector2.new(35,35)); fitZoom.DefaultZoom=45
local fitted = Math.layout(Vector2.new(568,320),fitZoom)
check(fitted.wholeMap and fitted.distance>45,"whole-map fitting can zoom beyond follow default within readable maximum")
for _, height in { 0,fitZoom.HeightAllowance } do
	for _, corner in Math.corners(fitted.map,fitZoom.Margin,height) do
		check(visible(fitted,fitted.map.center,corner),"whole-map framing includes configured margin and height")
	end
end
print(string.format("Camera coverage: previous distance %.2f, current %.2f, linear gain %.1f%%",oldLayout.distance,currentLayout.distance,(currentLayout.distance/oldLayout.distance-1)*100))
-- Thin controller integration: stand-ins verify writes/order/discontinuities,
-- not Roblox rendering or actual ScreenPointToRay projection/event behavior.
local Battlefield = require("BattlefieldCamera")
local viewport = Vector2.new(1920, 1080)
GuiService.fullRect = { Min = Vector2.zero, Max = viewport }
GuiService.safeRect = GuiService.fullRect
local camera = { ViewportSize = viewport }
local battlefield = Battlefield.new(Instance.new("PlayerGui"), large)
local initial = { position = Vector3.zero, health = 100 }
battlefield:observe(initial); battlefield:update(camera, 1 / 60, initial)
check(camera.CameraType == "Scriptable" and camera.FieldOfViewMode == "Vertical" and camera.ProjectionType == "Perspective", "controller owns Scriptable perspective camera")
check((camera.CFrame.LookVector - b.forward).Magnitude < 1e-5 and camera.Focus.Position == battlefield.focus, "controller writes fixed CFrame and Focus")
local inside = { position = Vector3.new(5,0,-3), health = 100 }
battlefield:observe(inside); battlefield:update(camera,1/60,inside)
check(battlefield.focus.Magnitude < 1e-5,"controller keeps camera stationary for movement inside dead zone")
local moved = { position = Vector3.new(40, 0, 0), health = 100, yaw = 2, turretYaw = -1 }
check(not battlefield:observe(moved), "normal movement does not request camera teleport")
battlefield:update(camera, 1 / 60, moved)
check(battlefield.focus.X > 0 and battlefield.focus.X < 40, "raw snapshot produces minimal immediate camera correction")
check((camera.CFrame.LookVector - b.forward).Magnitude < 1e-5, "tank/turret rotation cannot rotate camera")
camera.FieldOfView = 90; camera.CameraType = "Custom"
battlefield:update(camera, 1 / 60, moved)
check(camera.CameraType == "Scriptable" and near(camera.FieldOfView, battlefield.layout.lens.fov), "external/default zoom and rotation values overwritten")
local beforeMissing = battlefield.focus
battlefield:observe(nil); battlefield:update(camera,1/60,nil)
check(battlefield.focus == beforeMissing,"missing tank reference holds last valid focus")
check(battlefield:observe(moved),"tank reappearance resets rendered pose safely")
local dead = { position = moved.position, health = 0 }
battlefield:observe(dead)
local respawn = { position = Vector3.new(-300, 0, 100), health = 100 }
check(battlefield:observe(respawn), "controller notices respawn")
local respawnGoal = Math.track(battlefield.layout, respawn.position, battlefield.focus)
battlefield:update(camera, 1 / 60, respawn)
check((battlefield.focus - respawnGoal).Magnitude < 1e-5, "respawn focus snaps without long sweep")
local phone = { ViewportSize = Vector2.new(528, 320) } -- smaller than fullscreen on a notched device
GuiService.fullRect = { Min = Vector2.new(-20, -24), Max = Vector2.new(548, 296) }
GuiService.safeRect = { Min = Vector2.zero, Max = Vector2.new(528, 296) }
battlefield:update(phone, 1 / 60, respawn)
check(phone.CameraType == "Scriptable" and battlefield.camera == phone, "replacement camera and mobile viewport reinitialize")
check(battlefield.layout.lens.x >= 20 and battlefield.layout.lens.y >= 24, "controller uses runtime safe insets")
local expectedPhone = Math.layout(Vector2.new(568, 320), large, Vector2.new(20, 24))
check(near(battlefield.layout.lens.fov, expectedPhone.lens.fov) and near(battlefield.layout.lens.width, expectedPhone.lens.width), "notched device FOV/masks use fullscreen size, not device-safe ViewportSize")
check(battlefield.bars[1].Size.Y.Offset == battlefield.layout.lens.y, "opaque masks match calculated battlefield window")
check(near(battlefield.layout.distance, largeReference.distance), "mobile replacement retains competitive scale")
local zero = { ViewportSize = Vector2.zero }
battlefield:update(zero, 0, respawn)
check(battlefield.camera == phone, "transient zero viewport does not destroy valid camera layout")
local heldCFrame, heldFocus, heldFov = phone.CFrame, phone.Focus, phone.FieldOfView
battlefield.gui:SetAttribute("PauseCamera", true)
battlefield.gui:SetAttribute("HideMasks", true)
phone.CFrame = CFrame.new(Vector3.new(1, 20, 3))
local manual = phone.CFrame
battlefield:update(phone, 1 / 60, initial)
check(phone.CFrame == manual and phone.Focus == heldFocus and phone.FieldOfView == heldFov,
	"Studio pause preserves manual pose, Focus and FOV")
check(not battlefield.gui.Enabled, "Studio mask switch reveals underlying world")
battlefield.gui:SetAttribute("PauseCamera", false)
battlefield.gui:SetAttribute("HideMasks", false)
battlefield:update(phone, 1 / 60, initial)
check(phone.CFrame ~= manual and battlefield.gui.Enabled, "resume restores camera ownership and masks")
-- Core UI may reserve a top bar; the world window only reserves device cutouts.
local savedGetInset = GuiService.GetInsetArea
function GuiService:GetInsetArea(kind)
	if kind == "CoreUISafeInsets" then return { Min = Vector2.new(0,58), Max = Vector2.new(812,362) } end
	return { Min = Vector2.zero, Max = Vector2.new(812,362) }
end
local shortCamera = { ViewportSize = Vector2.new(812,362) }
battlefield:update(shortCamera, 1 / 60, initial)
check(near(battlefield.layout.lens.height, 362), "top-bar reservation does not shrink battlefield to central patch")
check(near(shortCamera.FieldOfView, defaults.FieldOfView), "short landscape uses configured window FOV without top-bar inflation")
GuiService.GetInsetArea = savedGetInset
battlefield:destroy()
check(battlefield.gui.destroyed, "camera overlay cleanup")
local classic = setmetatable({ ViewportSize = Vector2.new(528, 320) }, {
	__newindex = function(self, key, value)
		if key == "ProjectionType" then error("ProjectionType unavailable on classic engine") end
		rawset(self, key, value)
	end,
})
local compatible = Battlefield.new(Instance.new("PlayerGui"), large)
compatible:observe(initial); compatible:update(classic, 1 / 60, initial)
check(classic.CameraType == "Scriptable" and classic.CFrame ~= nil, "classic perspective clients do not require new projection beta property")
local keyboard = require("KeyboardMouseInput").new(); keyboard:setActive(true)
local aimX, aimY
keyboard:sample({ ScreenPointToRay = function(_, x, y)
	aimX, aimY = x, y
	return { Origin = Vector3.new(0, 10, 0), Direction = Vector3.new(0, -1, -1) }
end })
check(aimX == 80 and aimY == 76, "raw desktop cursor converts to core-safe ray coordinates with notches/topbar")
-- Production overview policy: real slider transitions, not relaxed test tuning.
local overviewConfig = config(Vector2.new(40,40))
local overview = Math.layout(Vector2.new(568,320),overviewConfig)
check(overview.wholeMap,"40 square enters whole-map mode with actual production settings")
check(near(overview.distance,108.795,0.02),"100 square fit distance matches perspective derivation")
check(defaults.MaxZoom>=overview.distance,"production maximum permits readable 40 square fit")
local tightest = math.huge
for _, viewport in sizes do
	local view = Math.layout(viewport,overviewConfig)
	if view.lens.fov<119 then
		check(view.wholeMap,"40 square frames on normal desktop, phone, portrait and ultrawide windows")
	end
	if view.wholeMap then
		for _, height in {0,overviewConfig.HeightAllowance} do
			for _, corner in Math.corners(view.map,overviewConfig.Margin,height) do
				check(visible(view,view.map.center,corner),"production overview includes expanded corners and height")
			end
		end
		for _, tank in Math.corners(view.map,0,0) do
			local pixels = Math.tankPixels(view,view.map.center,tank,defaults.TankSilhouetteWidth)
			local normalized = pixels*defaults.ReferenceWindowHeight/view.lens.height
			tightest=math.min(tightest,normalized)
			check(normalized>=defaults.WholeMapMinTankPixels-1e-5,"full silhouette meets overview budget throughout actual playable rectangle")
			-- Project existing track boxes, including their height, to independently
			-- check the conservative full-tank span across chassis orientations.
			for yaw=0,175,5 do
				local low,high=math.huge,-math.huge
				local a=math.rad(yaw)
				for _, side in {-1,1} do for _, x in {-0.85,0.85} do
					for _, z in {-4.5,4.5} do for _, y in {0.2,2.6} do
						local xx=side*3.8+x
						local point=tank+Vector3.new(xx*math.cos(a)+z*math.sin(a),y,-xx*math.sin(a)+z*math.cos(a))
						local u=projection(view,view.map.center,point)
						low=math.min(low,u); high=math.max(high,u)
					end end
				end end
				check((high-low)*view.lens.width/2>=pixels-1e-5,"actual track silhouette exceeds configured eight-stud budget at all tested yaws")
			end
		end
	end
end
local maxWhole=0
for side=10,130 do
	local settings=config(Vector2.new(side,side))
	local view=Math.layout(Vector2.new(568,320),settings)
	if view.wholeMap then maxWhole=side end
end
check(maxWhole==53,"135-stud maximum places square transition between 53 and 54 studs")
for _, side in {110,150,230,1000,2000} do
	check(not Math.layout(Vector2.new(568,320),config(Vector2.new(side,side))).wholeMap,"larger unreadable arenas use follow mode")
end
local atLimit=Math.layout(Vector2.new(568,320),config(Vector2.new(53,53)))
check(atLimit.wholeMap,"largest integer square in overview remains readable")
for _, corner in Math.corners(atLimit.map,0,0) do
	check(Math.tankPixels(atLimit,atLimit.map.center,corner,defaults.TankSilhouetteWidth)>=defaults.WholeMapMinTankPixels*atLimit.lens.height/defaults.ReferenceWindowHeight-1e-5,"transition respects tank budget rather than arbitrary size cutoff")
end
print(string.format("Production overview: 40x40 fit %.2f studs, minimum silhouette %.2f pixels at reference height; square transition %d -> %d",overview.distance,tightest,maxWhole,maxWhole+1))
-- Live simulated dimensions share the production layout, including shifted/rotated maps.
local testViewport = Vector2.new(812,362)
GuiService.fullRect = { Min = Vector2.zero, Max = testViewport }
GuiService.safeRect = GuiService.fullRect
local devConfig = config(Vector2.new(230,230),37)
devConfig.MapCenter = Vector3.new(40,7,-20)
-- All camera tuning is production tuning; only actual map metadata differs.
local dev = Battlefield.new(Instance.new("PlayerGui"),devConfig)
local devCamera = { ViewportSize = testViewport }
local devState = { position = devConfig.MapCenter, health = 100 }
dev:update(devCamera,1/60,devState)
check(dev.testPanel ~= nil and not dev.testPanel.frame.Visible,"Studio panel exists and starts collapsed")
dev.testPanel.toggle.Activated:Fire()
check(dev.testPanel.frame.Visible,"developer toggle expands controls")
for _, size in { Vector2.new(35,35), Vector2.new(100,100),Vector2.new(2000,2000),Vector2.new(100,2000),Vector2.new(2000,100) } do
	check(dev:setMapSizeOverride(size),"valid dimensions accepted")
	dev:update(devCamera,1/60,devState)
	local expected = table.clone(devConfig); expected.MapSize = size
	local expectedLayout = Math.layout(testViewport,expected)
	check(dev.layout.wholeMap == expectedLayout.wholeMap and near(dev.layout.distance,expectedLayout.distance),"override uses exact production mode and zoom")
	check(dev.layout.map.size == size and dev.layout.map.center == devConfig.MapCenter and dev.layout.map.yaw == 37,"only simulated dimensions change; center and yaw preserved")
	check(devConfig.MapSize.X == 230 and devConfig.MapSize.Y == 230,"override does not mutate actual tuning")
	if size.X == 35 and size.Y == 35 then
		check(dev.layout.wholeMap and dev.focus == devConfig.MapCenter,"readable small simulated map locks to actual center")
		check(string.find(dev.testPanel.status.Text,"Whole Map",1,true) ~= nil,"panel reports whole map mode")
	else
		check(not dev.layout.wholeMap,"larger simulated map returns to follow mode")
		for _, x in { -1,1 } do for _, z in { -1,1 } do
			devState.position = Math.toWorld(dev.layout.map,Vector2.new(x*(size.X/2-5),z*(size.Y/2-5)))
			dev:update(devCamera,1/60,devState)
			local focus = Math.toLocal(dev.layout.map,dev.focus)
			local u,v = Math.project(dev.layout,dev.focus,devState.position)
			check(math.abs(focus.X)<=size.X/2+1e-5 and math.abs(focus.Y)<=size.Y/2+1e-5,"override clamps focus to simulated rectangle")
			check(math.abs(u)<=0.20001 and math.abs(v)<=0.20001,"simulated boundary tracking preserves central 20 percent")
		end end
		check(string.find(dev.testPanel.status.Text,"Follow",1,true) ~= nil,"panel reports follow mode")
	end
	devState.position = devConfig.MapCenter
end
-- Slider endpoints, independent axes, drag ownership and reset button.
local requestedSize
 dev.redrawMap = function(size) requestedSize = size end
 dev.testPanel.redraw.Activated:Fire()
 check(requestedSize == dev.mapSizeOverride, "redraw button sends selected dimensions")
 local oldConfig = dev.config
 check(dev:setActualMapSize(Vector2.new(160,90)), "server arena dimensions update actual map")
 check(dev.mapSizeOverride == nil and dev.config.MapSize.X == 160 and oldConfig.MapSize.X == 230, "redraw clears preview without mutating frozen source tuning")
 check(dev.layoutKey == nil and dev.focus == nil, "redraw invalidates projection and focus")
 dev:setActualMapSize(Vector2.new(230,230)); dev:setMapSizeOverride(Vector2.new(100,100))
 dev:update(devCamera,1/60,devState)
local panel = dev.testPanel
local widthSlider,depthSlider = panel.sliders[1],panel.sliders[2]
widthSlider.track.AbsolutePosition = Vector2.new(20,40); widthSlider.track.AbsoluteSize = Vector2.new(200,22)
depthSlider.track.AbsolutePosition = Vector2.new(20,100); depthSlider.track.AbsoluteSize = Vector2.new(200,22)
panel:setFromPosition(widthSlider,-100)
check(dev.mapSizeOverride.X==25 and dev.mapSizeOverride.Y==100,"width slider clamps to 25 and preserves depth")
panel:setFromPosition(depthSlider,999)
check(dev.mapSizeOverride.X==25 and dev.mapSizeOverride.Y==2000,"depth slider clamps to 2000 and preserves width")
panel:setFromPosition(widthSlider,120)
check(dev.mapSizeOverride.X==1013,"slider midpoint maps to 1013 studs")
check(panel.sliders[1].label.Text=="Map Width: 1013 studs","slider displays numeric value")
local touch = { KeyCode = Enum.KeyCode.Unknown, UserInputType = Enum.UserInputType.Touch, Position = Vector3.new(20,40,0) }
widthSlider.track.InputBegan:Fire(touch)
local otherTouch = { UserInputType = Enum.UserInputType.Touch, Position = Vector3.new(220,40,0) }
UIS.InputChanged:Fire(otherTouch)
check(dev.mapSizeOverride.X==25,"other fingers cannot steal slider")
touch.Position = Vector3.new(220,40,0); UIS.InputChanged:Fire(touch)
check(dev.mapSizeOverride.X==2000,"captured touch updates slider")
UIS.InputEnded:Fire(touch)
check(panel.drag==nil,"touch release clears drag")
widthSlider.track.InputBegan:Fire(touch); UIS.WindowFocusReleased:Fire()
check(panel.drag==nil,"focus loss cancels slider drag")
local mouse = { KeyCode=Enum.KeyCode.Unknown, UserInputType=Enum.UserInputType.MouseButton1, Position=Vector3.new(20,40,0) }
widthSlider.track.InputBegan:Fire(mouse)
UIS.InputChanged:Fire({UserInputType=Enum.UserInputType.MouseMovement,Position=Vector3.new(220,40,0)})
check(dev.mapSizeOverride.X==2000,"mouse drag follows movement outside original click object")
GuiService.MenuOpened:Fire()
check(panel.drag==nil,"menu cancels slider drag")
widthSlider.track.InputBegan:Fire(mouse)
panel.gui:GetPropertyChangedSignal("AbsoluteSize"):Fire()
check(panel.drag==nil,"resizing cancels active drag without clearing override")
-- Override survives layout changes, missing state and respawn.
dev:update(devCamera,1/60,devState)
local override = dev.mapSizeOverride
GuiService.fullRect = { Min = Vector2.zero, Max = Vector2.new(568,320) }; GuiService.safeRect=GuiService.fullRect
devCamera.ViewportSize = Vector2.new(568,320)
dev:update(devCamera,1/30,nil)
check(dev.layout.map.size==override and dev.layout.lens.height==319.5,"viewport change recomputes layout with active override")
dev:observe({position=devState.position,health=0}); dev:observe(devState); dev:update(devCamera,1/60,devState)
check(dev.mapSizeOverride==override and dev.layout.map.size==override,"respawn retains override")
check(string.find(panel.status.Text,string.format("%.2f",dev.layout.distance),1,true)~=nil,"panel shows effective camera distance")
for _, invalid in { Vector2.new(0,100),Vector2.new(-1,100),Vector2.new(0/0,100),Vector2.new(math.huge,100),"100" } do
	check(not dev:setMapSizeOverride(invalid) and dev.mapSizeOverride==override,"invalid size does not replace valid override")
end
panel.reset.Activated:Fire(); dev:update(devCamera,1/60,devState)
local actual = Math.layout(devCamera.ViewportSize,devConfig)
check(dev.mapSizeOverride==nil and dev.layout.map.size.X==devConfig.MapSize.X and dev.layout.map.size.Y==devConfig.MapSize.Y,"reset restores actual dimensions")
check(dev.layout.wholeMap==actual.wholeMap and near(dev.layout.distance,actual.distance),"reset restores actual production mode and distance")
check(panel.sliders[1].label.Text=="Map Width: 230 studs" and string.find(panel.status.Text,"Actual",1,true)~=nil,"reset synchronizes values and debug status")
dev:destroy()
check(panel.gui.destroyed,"controller destroys panel and connections")
dev:setMapSizeOverride(Vector2.new(150,150))
local afterDestroy = dev.mapSizeOverride
panel.reset.Activated:Fire()
check(dev.mapSizeOverride==afterDestroy,"destroyed panel listeners disconnect")
-- Published clients cannot create the panel or enable dimension overrides.
local savedGetService = game.GetService
function game:GetService(name)
	if name=="RunService" then return { IsStudio=function() return false end } end
	return savedGetService(self,name)
end
local live = Battlefield.new(Instance.new("PlayerGui"))
check(live.testPanel==nil,"normal clients get no developer UI")
local liveRedraw = false; live.redrawMap = function() liveRedraw = true end
check(not live:requestMapRedraw() and not liveRedraw, "published client cannot request development redraw")
check(not live:setActualMapSize(Vector2.new(50,50)), "published client cannot apply development arena dimensions")
check(not live:setMapSizeOverride(Vector2.new(100,100)) and live.mapSizeOverride==nil,"normal clients reject dimension overrides")
live:update(devCamera,1/60,devState)
check(live.layout.map.size==defaults.MapSize,"normal clients retain actual map configuration")
live:destroy(); game.GetService=savedGetService
-- Minimum-fit selection stays monotonic and never exceeds the hard distance cap.
do
 local lastDistance = 0
 for side = 25, 400 do
  local view = Math.layout(Vector2.new(568,320),config(Vector2.new(side,side)))
  check(view.distance<=135+1e-5, "hard distance limit applies in both camera modes")
  check(view.distance>=lastDistance-1e-5, "increasing square size does not zoom closer")
  if view.wholeMap then
   check(near(view.distance,math.max(view.fitDistance,defaults.MinZoom)), "small map uses minimum fitting distance")
  end
  lastDistance=view.distance
 end
end
print(string.format("Camera suite passed: %d assertions", count))

