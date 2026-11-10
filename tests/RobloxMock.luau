-- Minimal deterministic stand-ins, not an emulator of Roblox layout or input dispatch.
local os = table.clone(os)
local function signal()
	local listeners = {}
	return {
		Connect = function(_, callback)
			local item = { callback = callback, connected = true }; table.insert(listeners, item)
			return { Disconnect = function() item.connected = false end }
		end,
		Fire = function(_, ...)
			for _, item in table.clone(listeners) do if item.connected then item.callback(...) end end
		end,
	}
end
local function vectorType(kind)
	local mt = {}
	local function new(x, y, z) return setmetatable({ X = x, Y = y, Z = z or 0, kind = kind }, mt) end
	mt.__index = function(v, key)
		if key == "Magnitude" then return math.sqrt(v.X ^ 2 + v.Y ^ 2 + v.Z ^ 2) end
		if key == "Unit" then return v / v.Magnitude end
		if key == "Lerp" then return function(a,b,t) return a+(b-a)*t end end
	end
	mt.__add = function(a, b) return new(a.X + b.X, a.Y + b.Y, a.Z + b.Z) end
	mt.__sub = function(a, b) return new(a.X - b.X, a.Y - b.Y, a.Z - b.Z) end
	mt.__mul = function(a, b) return new(a.X * b, a.Y * b, a.Z * b) end
	mt.__div = function(a, b) return new(a.X / b, a.Y / b, a.Z / b) end
	return { new = new, zero = new(0, 0, 0) }
end
local Vector2, Vector3 = vectorType("Vector2"), vectorType("Vector3")
local originalTypeof = typeof
local function typeof(value) return if type(value) == "table" and value.kind then value.kind else originalTypeof(value) end
local Enum = setmetatable({}, { __index = function(self, key)
	local values = setmetatable({}, { __index = function(_, name) return name end }); rawset(self, key, values); return values
end })
local UDim = { new = function(scale, offset) return { Scale = scale, Offset = offset } end }
local UDim2 = { new = function(xs, xo, ys, yo) return { X = UDim.new(xs, xo), Y = UDim.new(ys, yo) } end }
UDim2.fromScale = function(x, y) return UDim2.new(x, 0, y, 0) end
UDim2.fromOffset = function(x, y) return UDim2.new(0, x, 0, y) end
local NumberRange = {new=function(a,b) return {Min=a,Max=b or a} end}
local NumberSequenceKeypoint={new=function(t,v,e) return {Time=t,Value=v,Envelope=e or 0} end}
local NumberSequence={new=function(points) return {Keypoints=points} end}
local ColorSequence={new=function(a,b) return {Start=a,End=b} end}
local TweenInfo = { new = function(...) return {...} end }
local Color3 = { new = function(r,g,b) return {r or 0,g or 0,b or 0} end, fromRGB = function(r, g, b) return { r, g, b } end }
local Instance = {}
function Instance.new(class)
	local object = { ClassName = class, AbsoluteSize = Vector2.new(640, 320), AbsolutePosition = Vector2.zero,
		InputBegan = signal(), Activated = signal(), ChildAdded = signal(), children = {}, properties = {}, Enabled = true }
	function object:GetAttribute(key) return (self.attributes or {})[key] end
	function object:SetAttribute(key, value) self.attributes = self.attributes or {}; self.attributes[key] = value end
	function object:GetPropertyChangedSignal(key)
		if not self.properties[key] then self.properties[key] = signal() end
		return self.properties[key]
	end
	function object:Emit(count) self.emitted=(self.emitted or 0)+count end
	function object:Clear() self.clearCalls=(self.clearCalls or 0)+1 end
	function object:ReleaseFocus() self.releasedFocus=true end
	function object:IsA(name) return self.ClassName == name end
	function object:GetChildren() return self.children end
	function object:GetFullName() return self.Name or self.ClassName end
	function object:GetDescendants()
		local result={}
		local function visit(parent) for _,child in parent.children do if not child.destroyed then table.insert(result,child); visit(child) end end end
		visit(self); return result
	end
	function object:WaitForChild(name) return self[name] end
	function object:Destroy() self.Parent = nil; self.destroyed = true end
	return object
end
local workspace = Instance.new("Folder")
local UIS = { PreferredInput = "KeyboardAndMouse", TouchEnabled = true, focusedTextBox = nil }
for _, key in { "InputBegan", "InputChanged", "InputEnded", "TouchMoved", "TouchEnded", "WindowFocusReleased", "WindowFocused", "TextBoxFocused", "TextBoxFocusReleased", "GamepadDisconnected" } do UIS[key] = signal() end
UIS.preferredSignal = signal()
function UIS:GetPropertyChangedSignal() return self.preferredSignal end
function UIS:GetFocusedTextBox() return self.focusedTextBox end
local GuiService = { MenuOpened = signal(), MenuClosed = signal() }
GuiService.fullRect = { Min = Vector2.zero, Max = Vector2.new(1920, 1080) }
GuiService.safeRect = GuiService.fullRect
function GuiService:GetInsetArea(kind)
	return if kind == "None" then self.fullRect else self.safeRect
end
local OverlapParams = { new = function() return {} end }
local RaycastParams = { new = function() return {} end }
local CFrame = {
	new = function(position) return { Position = position } end,
	lookAt = function(position, target) return { Position = position, LookVector = (target - position).Unit } end,
}
local defaultControls = { controlsEnabled = true, disableCount = 0, enableCount = 0 }
function defaultControls:Disable() self.controlsEnabled = false; self.disableCount += 1 end
function defaultControls:Enable() self.controlsEnabled = true; self.enableCount += 1 end
local playerGui = Instance.new("PlayerGui")
local defaultTouchGui = Instance.new("ScreenGui"); defaultTouchGui.Name = "TouchGui"; defaultTouchGui.Parent = playerGui
playerGui.children = { defaultTouchGui }
local playerScripts = Instance.new("PlayerScripts"); playerScripts.PlayerModule = "PlayerModule"
local player = Instance.new("Player"); player.PlayerGui = playerGui; player.PlayerScripts = playerScripts
local Players = { LocalPlayer = player }
local Shared = { BWFunctionAnalysis="BWFunctionAnalysis", ComponentCatalog="ComponentCatalog", VehicleAssemblies="VehicleAssemblies", VehicleComponents="VehicleComponents", BWHandbook="BWHandbook", BWChassis="BWChassis", BWExecution="BWExecution", BWDevices="BWDevices", BWEditorText="BWEditorText", BWCommands="BWCommands", BWLexer="BWLexer", BWExpression="BWExpression", ScannerConfig="ScannerConfig", ScannerGeometry="ScannerGeometry", BWValue="BWValue", DamageEffectsConfig="DamageEffectsConfig", DamageEffects="DamageEffects", BWConfig="BWConfig", BWParser="BWParser", BWTankAdapter="BWTankAdapter", BWRuntime="BWRuntime", MovementTelemetry = "MovementTelemetry", ProjectileTrajectory = "ProjectileTrajectory", TurretRecoil = "TurretRecoil", RattlerDrive = "RattlerDrive", ArenaLayout = "ArenaLayout", WeaponWindup = "WeaponWindup", RattlerRecoil = "RattlerRecoil", TankDefinitions = "TankDefinitions", RattlerWeapon = "RattlerWeapon", TankSelection = "TankSelection", Environment = "Environment", InputCommand = "InputCommand", TankConfig = "TankConfig", TankSimulation = "TankSimulation" }
local Client = { BWEditorController="BWEditorController", BWHandbookView="BWHandbookView", ScannerVisual="ScannerVisual", DirectionalScanner="DirectionalScanner", SmokeVisual="SmokeVisual", DamageVisual="DamageVisual", BWController="BWController", TankCombatVisual="TankCombatVisual", BWIDE="BWIDE", SpeedDebugHud = "SpeedDebugHud", TankRenderer = "TankRenderer", TankRenderers = "TankRenderers", TankSelector = "TankSelector", RattlerVisual = "RattlerVisual", TerrainEffects = "TerrainEffects", Analog = "Analog", TouchInput = "TouchInput", KeyboardMouseInput = "KeyboardMouseInput", GamepadInput = "GamepadInput", BarrelAnimation = "BarrelAnimation", CameraMath = "CameraMath", CameraTestPanel = "CameraTestPanel", BattlefieldCameraConfig = "BattlefieldCameraConfig" }
-- Deterministic text-measurement fixture; native glyph metrics remain Studio-only.
local TextService={GetTextSize=function(_,source,size,font,bounds)
 local columns=math.max(1,math.floor(bounds.X/(size*.6))); local lines=0; local widest=0
 for line in (source.."\n"):gmatch("([^\n]*)\n") do
  local length=utf8.len(line) or #line
  lines+=math.max(1,math.ceil(length/columns)); widest=math.max(widest,math.min(length,columns)*size*.6)
 end
 return Vector2.new(widest,lines*size*1.2)
end}
local game = { ReplicatedStorage = { Shared = Shared } }
function game:GetService(name) return ({ TextService=TextService, UserInputService = UIS, GuiService = GuiService, Players = Players, RunService = { IsStudio = function() return true end } })[name] end
local task = { spawn = function(callback) callback() end, defer = function(callback) callback() end, delay = function(_,callback) callback() end }
local function warn(...) print(...) end
