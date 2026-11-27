local RunService = game:GetService("RunService")
local network = game:GetService("ReplicatedStorage"):WaitForChild("TankNetwork")
local startAtHome = network:GetAttribute("GameMode") == "BattleRoyale" and network:GetAttribute("StartInMenu") == true
if not startAtHome and not RunService:IsStudio() then return end

local player = game:GetService("Players").LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local input = game:GetService("UserInputService")
local cursorStep = "BattleWorksUIDemoCursor"
local focused = true
local cursorActive = false

local function releaseCursor()
	if not cursorActive or not focused then return end
	if input.MouseBehavior ~= Enum.MouseBehavior.Default then
		input.MouseBehavior = Enum.MouseBehavior.Default
	end
	if not input.MouseIconEnabled then
		input.MouseIconEnabled = true
	end
end

input.WindowFocusReleased:Connect(function() focused = false end)
input.WindowFocused:Connect(function()
	focused = true
	releaseCursor()
end)

local function setCursorActive(active)
	if cursorActive == active then return end
	cursorActive = active
	player:SetAttribute("BattleWorksUIDemoOpen", if active then true else nil)
	if active then
		-- The default camera and Studio can update the mouse after input handlers.
		RunService:BindToRenderStep(cursorStep, Enum.RenderPriority.Last.Value, releaseCursor)
		releaseCursor()
	else
		RunService:UnbindFromRenderStep(cursorStep)
	end
end

local launcher = Instance.new("ScreenGui")
launcher.Name = "BattleWorksUIDemoLauncher"
launcher.ResetOnSpawn = false
launcher.DisplayOrder = 100
launcher.Parent = playerGui

local open = Instance.new("TextButton")
open.Name = "Open"
open.Text = if startAtHome then "Open BattleWorks" else "Open UI Demo"
open.Font = Enum.Font.GothamBold
open.TextSize = 14
open.TextColor3 = Color3.fromRGB(239, 233, 219)
open.BackgroundColor3 = Color3.fromRGB(65, 66, 38)
open.BorderSizePixel = 0
open.AnchorPoint = Vector2.new(1, 0)
open.Position = UDim2.new(1, -12, 0, 12)
open.Size = UDim2.fromOffset(130, 36)
open.Parent = launcher
open.Visible = not startAtHome

local app
local starting = false
local function close()
	setCursorActive(false)
	if app then app:destroy() end
	app = nil
	open.Visible = true
end

local function start()
	if app or starting then return end
	starting = true
	open.Visible = false
	setCursorActive(true)
	local ok, result = pcall(function()
		local App = require(script.Parent.UI.App)
		return App.new(playerGui, {
			displayOrder = 101,
			onClose = if startAtHome then nil else close,
			onGameplayView = function(active) setCursorActive(not active) end,
			onEditorMenu = setCursorActive,
		})
	end)
	starting = false
	if ok then
		app = result
		if startAtHome then
			local grounds = require(script.Parent.UI.TrainingGrounds)
			grounds.setHomeHandler(function()
				if not app then return false end
				return app.router:navigate("home")
			end)
		end
	else
		close()
		warn("[BattleWorks UI] Home failed to open:", result)
	end
end

open.Activated:Connect(start)
if startAtHome then task.defer(start) end

launcher.Destroying:Connect(function()
	setCursorActive(false)
	if app then app:destroy() end
end)
