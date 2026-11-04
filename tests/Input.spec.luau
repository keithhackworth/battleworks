local count = 0
local function check(value, message) assert(value, message); count += 1 end
local function near(a, b) return math.abs(a - b) < 1e-6 end
local Command, Analog = require("InputCommand"), require("Analog")
local Simulation, Config = require("TankSimulation"), require("TankConfig")
local valid = Command.neutral()
valid.throttle = 12; valid.steer = -12; valid.turretX = 5; valid.turretY = -5
local clamped = Command.validate(valid)
check(clamped.throttle == 1 and clamped.steer == -1 and clamped.turretX == 1 and clamped.turretY == -1, "server must clamp all axes")
for _, field in { "throttle", "steer", "turretX", "turretY" } do
	for _, invalid in { 0 / 0, math.huge, -math.huge, "1" } do
		local bad = Command.neutral(); bad[field] = invalid
		check(Command.validate(bad) == nil, "reject nonfinite/non-numeric " .. field)
	end
end
local bad = Command.neutral(); bad.fire = 1
check(Command.validate(bad) == nil, "fire requires boolean")
bad = Command.neutral(); bad.aimMode = "Unknown"
check(Command.validate(bad) == nil, "unknown aim mode rejected")
local desktop = { throttle = 1, steer = 0, aim = Vector3.new(0, 3, -100), fire = true }
check(Command.validate(desktop).aimMode == "World", "legacy desktop command remains supported")
desktop.aim = Vector3.new(0 / 0, 0, 0)
check(Command.validate(desktop) == nil, "world aim rejects NaN")
check(Analog.normalize(Vector2.new(0.1, 0), 0.15).Magnitude == 0, "dead zone")
check(near(Analog.normalize(Vector2.new(0.575, 0), 0.15).X, 0.5), "dead zone remaps full range")
check(near(Analog.normalize(Vector2.new(4, 4), 0.15).Magnitude, 1), "diagonal circular clamping")
local state = Simulation.new(Vector3.zero)
local command = Command.neutral(); command.turretX = 1; command.turretY = 1; command.throttle = 1
Simulation.step(state, command, 0.1)
check(near(state.position.Z, -2.4) and near(state.turretYaw, -0.35), "server owns movement and turret rate")
for _ = 1, 100 do Simulation.step(state, command, Config.Step) end
check(state.turretPitch == Config.MaxPitch, "pitch upper bound")
command.turretY = -1
for _ = 1, 100 do Simulation.step(state, command, Config.Step) end
check(state.turretPitch == Config.MinPitch, "pitch lower bound")
local pitch, yaw = state.turretPitch, state.turretYaw
Simulation.step(state, Command.neutral(), 0.1)
check(state.turretPitch == pitch and state.turretYaw == yaw and state.speed == 0, "neutral holds turret and stops driving")
command.fire = true
local origin, direction = Simulation.tryFire(state, command)
check(origin ~= nil and near(direction.Magnitude, 1) and direction.Y < 0, "server shot includes pitch")
check(Simulation.tryFire(state, command) == nil, "server cooldown remains authoritative")
command.aimMode = "World"; command.aim = Vector3.new(0, 0, -100)
Simulation.step(state, command, Config.Step)
check(state.turretPitch == 0, "desktop restores horizontal aim")
state.health = 0
check(Simulation.tryFire(state, command) == nil, "dead tanks cannot fire")
local Touch = require("TouchInput")
local touch = Touch.new(Instance.new("ScreenGui"), { turretDeadZone = 0.2, driveDeadZone = 0.1 })
touch:setActive(true)
local function finger(x, y)
	local input = { UserInputType = "Touch", Position = Vector3.new(x, y, 0), UserInputState = "Begin", changed = signal() }
	function input:GetPropertyChangedSignal() return self.changed end
	return input
end
local turret, drive = touch.sticks.Turret, touch.sticks.Drive
for _, stick in { turret, drive } do stick.frame.AbsoluteSize = Vector2.new(120, 120); stick.frame.AbsolutePosition = Vector2.zero end
local left, right, fire = finger(90, 30), finger(40, 15), finger(0, 0)
turret.frame.InputBegan:Fire(left); drive.frame.InputBegan:Fire(right); touch.fire.InputBegan:Fire(fire)
local sampled = touch:sample()
check(sampled.turretX > 0 and sampled.turretY > 0 and sampled.throttle > 0 and sampled.steer > 0 and sampled.fire, "three simultaneous touches")
local turretBefore = sampled.turretX
right.Position = Vector3.new(200, 200, 0); UIS.TouchMoved:Fire(right)
sampled = touch:sample()
check(sampled.turretX == turretBefore and sampled.throttle < 0 and sampled.fire, "finger movement stays with its owning stick")
check(touch.sticks.Drive.value.Magnitude <= 1.000001, "drag beyond stick clamps")
local extra = finger(60, 60); turret.frame.InputBegan:Fire(extra)
check(turret.touch == left and touch.captures[extra] == nil, "second touch cannot steal occupied joystick")
fire.UserInputState = "Cancel"; fire.changed:Fire()
check(not touch:sample().fire and turret.touch == left and drive.touch == right, "fire cancellation leaves both joysticks held")
UIS.TouchEnded:Fire(left)
check(turret.value.Magnitude == 0 and turret.knob.Position.X.Scale == 0.5 and drive.touch == right, "release recenters only its joystick")
local fire2 = finger(0, 0); touch.fire.InputBegan:Fire(fire2)
UIS.TouchEnded:Fire(fire2)
check(not touch:sample().fire, "fire ends immediately")
touch:setActive(false)
check(next(touch.captures) == nil and drive.value.Magnitude == 0 and not touch.root.Visible, "mode deactivation releases all touches")
touch:setActive(true); turret.knob.InputBegan:Fire(finger(60, 60))
touch:layout()
check(next(touch.captures) == nil, "resize releases captured fingers")
-- Controller uses real providers against deterministic service stand-ins.
local Controller = require("InputController")
local releases = 0
local controller = Controller.new(Instance.new("ScreenGui"), function(c)
	check(not c.fire and c.throttle == 0, "switch sends neutral intent"); releases += 1
end)
check(controller.mode == "KeyboardMouse" and not controller.providers.Touch.root.Visible, "Auto starts with PreferredInput, not touch capability")
UIS.PreferredInput = "Touch"; UIS.preferredSignal:Fire()
check(controller.mode == "Touch" and not defaultControls.controlsEnabled and not defaultTouchGui.Enabled, "Auto touch suppresses only default movement UI/controller")
controller:setPreference("KeyboardMouse")
check(defaultControls.controlsEnabled and defaultTouchGui.Enabled and controller.providers.KeyboardMouse.active, "leaving Touch restores default controls")
UIS.PreferredInput = "Gamepad"; UIS.preferredSignal:Fire()
check(controller.mode == "KeyboardMouse", "explicit mode ignores PreferredInput changes")
controller:setPreference("Gamepad")
local pad = { UserInputType = "Gamepad1", KeyCode = "Thumbstick1", Position = Vector3.new(1, 1, 0) }
UIS.InputChanged:Fire(pad)
check(controller:sample().throttle > 0, "gamepad adapter emits movement")
UIS.GamepadDisconnected:Fire("Gamepad1")
check(controller:sample().throttle == 0, "gamepad disconnect clears axes")
controller:setPreference("Touch")
local controllerTouch = controller.providers.Touch
controllerTouch.fire.InputBegan:Fire(finger(0, 0))
check(controller:sample().fire, "touch fire active")
GuiService.MenuOpened:Fire()
check(not controller:sample().fire and not controllerTouch.active, "Roblox menu releases and suspends touch")
GuiService.MenuClosed:Fire()
check(controllerTouch.active and not controller:sample().fire, "closing menu requires new touch")
UIS.WindowFocusReleased:Fire()
check(not controllerTouch.active, "focus loss disables capture")
UIS.WindowFocused:Fire()
controller:setPreference("Auto")
check(controller.mode == "Gamepad", "Auto resolves current PreferredInput at runtime")
controller:setPreference("KeyboardMouse")
local camera = { ScreenPointToRay = function() return { Origin = Vector3.new(0, 10, 0), Direction = Vector3.new(0, -1, -1) } end }
function UIS:GetMouseLocation() return Vector2.new(100, 100) end
local key = { KeyCode = "W", UserInputType = "Keyboard" }
UIS.InputBegan:Fire(key, false)
check(controller:sample(camera).throttle == 1 and controller:sample(camera).aimMode == "World", "desktop W and world aim retained")
UIS.InputEnded:Fire(key)
check(controller:sample(camera).throttle == 0, "desktop release retained")
check(releases > 0, "mode transitions released commands")
-- Small safe-area geometry: no stick/FIRE/debug overlap and no debug/HUD overlap.
for _, dimensions in { Vector2.new(480, 200), Vector2.new(568, 240), Vector2.new(640, 280), Vector2.new(960, 480) } do
	touch.root.AbsoluteSize = dimensions; touch:layout()
	local diameter = touch.sticks.Turret.frame.Size.X.Offset
	local fireWidth = touch.fire.Size.X.Offset
	local centerGap = dimensions.X - 2 * diameter - 32
	check(fireWidth < centerGap and touch.debug.Size.X.Offset < centerGap, "center controls fit between sticks")
	local debugBottom = dimensions.Y + touch.debug.Position.Y.Offset
	local debugTop = debugBottom - touch.debug.Size.Y.Offset
	local fireTop = dimensions.Y + touch.fire.Position.Y.Offset - fireWidth
	check(debugTop >= 44 and debugBottom < fireTop, "debug avoids top HUD and FIRE on small landscape safe area")
end
controller:setPreference("Touch")
controllerTouch.fire.InputBegan:Fire(finger(0, 0))
UIS.focusedTextBox = {}; UIS.TextBoxFocused:Fire()
check(not controller:sample().fire and controller.suspended, "text focus releases touch")
UIS.focusedTextBox = nil; UIS.TextBoxFocusReleased:Fire()
check(not controller.suspended and not controller:sample().fire, "text blur resumes without stale fire")
controller:setPreference("KeyboardMouse")
defaultControls.controlsEnabled = false; defaultTouchGui.Enabled = false
controller:setPreference("Touch"); controller:setPreference("KeyboardMouse")
check(not defaultControls.controlsEnabled and not defaultTouchGui.Enabled, "leaving Touch preserves previously disabled default controls")
touch:setActive(true)
local canceled = finger(90, 30)
turret.frame.InputBegan:Fire(canceled)
canceled.UserInputState = "Cancel"; canceled.changed:Fire()
check(touch:sample().turretX == 0 and turret.touch == nil, "joystick cancel recenters")
local relay = Command.neutral(); relay.throttle = 0.82; relay.steer = -0.14; relay.turretX = 0.35; relay.turretY = -0.20; relay.fire = true
touch:showDebug(relay, "Touch")
check(touch.debug.Text == "INPUT: Touch\nTHROTTLE:  +0.82\nSTEERING:  -0.14\nTURRET X:  +0.35\nTURRET Y:  -0.20\nFIRE:      TRUE", "relay display matches requested format")
print(string.format("Full input suite passed: %d assertions", count))
