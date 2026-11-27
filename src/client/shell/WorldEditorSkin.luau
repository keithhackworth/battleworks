-- Presentation-only styling for the in-game editor and its registered artwork.
local UIAssets = require(game.ReplicatedStorage.Shared.UIAssets)

local Skin = {}
Skin.ink = Color3.fromRGB(246, 232, 197)
Skin.muted = Color3.fromRGB(177, 173, 145)
Skin.gold = Color3.fromRGB(255, 191, 74)
Skin.recess = Color3.fromRGB(24, 28, 20)
Skin.olive = Color3.fromRGB(67, 72, 43)
Skin.active = Color3.fromRGB(109, 104, 56)
Skin.edge = Color3.fromRGB(116, 111, 83)
Skin.font = Enum.Font.RobotoCondensed
Skin.error = Color3.fromRGB(255, 174, 127)

local white = Color3.fromRGB(255, 255, 255)
local black = Color3.fromRGB(18, 19, 13)
local neutral = Color3.fromRGB(205, 199, 165)
local oliveTint = Color3.fromRGB(174, 187, 143)
local bronze = Color3.fromRGB(220, 186, 143)
local controls = setmetatable({}, {__mode = "k"})
local metal = UIAssets.get("footlockers/olive/panels/01.png")
local atlas = UIAssets.get("editor/icons.png")
local materials = UIAssets.get("editor/terrain-materials.png")

local iconNames = {
	"select", "move", "rotate", "resize", "scale", "assets", "terrain", "audio",
	"motion", "physics", "start", "undo", "redo", "duplicate", "delete", "raise",
	"lower", "smooth", "flatten", "ravine", "tunnel", "folder", "world", "view",
	"down", "play", "right", "item", "hazard",
}
local icons = {}
for i, name in ipairs(iconNames) do
	icons[name] = Vector2.new((i - 1) % 8 * 64, math.floor((i - 1) / 8) * 64)
end

local function make(class, parent, properties)
	local object = Instance.new(class)
	for key, value in pairs(properties) do object[key] = value end
	object.Parent = parent
	return object
end

local function stroke(parent, color, thickness)
	return make("UIStroke", parent, {
		Color = color, Thickness = thickness or 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	})
end

function Skin.icon(parent, name, size, position)
	return make("ImageLabel", parent, {
		Name = "Icon_" .. name, BackgroundTransparency = 1, Image = atlas and atlas.image or "",
		ImageRectOffset = assert(icons[name], name), ImageRectSize = Vector2.new(64, 64),
		ScaleType = Enum.ScaleType.Fit, Size = size, Position = position,
	})
end

function Skin.metal(parent, tint, transparency)
	local clip = make("Frame", parent, {
		Name = "Metal", BackgroundTransparency = 1, ClipsDescendants = true,
		Size = UDim2.fromScale(1, 1),
	})
	return make("ImageLabel", clip, {
		Name = "WeatheredOlive", BackgroundTransparency = 1, Image = metal and metal.image or "",
		ScaleType = Enum.ScaleType.Crop,
		ImageColor3 = tint or oliveTint, ImageTransparency = transparency or 0,
		Size = UDim2.fromScale(1.12, 1.12), Position = UDim2.fromScale(-0.06, -0.06),
	})
end

function Skin.inset(parent, name)
	local inset = make("Frame", parent, {Name = name, BackgroundColor3 = Skin.recess, BorderSizePixel = 0, Visible = true})
	make("UICorner", inset, {CornerRadius = UDim.new(0, 3)})
	stroke(inset, Skin.edge)
	return inset
end

function Skin.rivet(parent, xScale, yScale, xOffset, yOffset)
	local head = make("Frame", parent, {
		Name = "Rivet", BorderSizePixel = 0, BackgroundColor3 = Color3.fromRGB(165, 151, 106),
		AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(5, 5),
		Position = UDim2.new(xScale, xOffset, yScale, yOffset),
	})
	make("UICorner", head, {CornerRadius = UDim.new(1, 0)})
	stroke(head, black)
	make("Frame", head, {
		Name = "Slot", BackgroundColor3 = black, BorderSizePixel = 0, Rotation = -38,
		Position = UDim2.fromOffset(1, 2), Size = UDim2.fromOffset(3, 1),
	})
end

function Skin.header(parent, caption)
	local back = Skin.inset(parent, "MetalHeader")
	back.BackgroundColor3 = Skin.olive
	Skin.metal(back, bronze, 0.12)
	Skin.rivet(back, 0, 0.5, 6, 0)
	local hazard = Skin.icon(back, "hazard", UDim2.fromOffset(25, 18), UDim2.new(1, -27, 0.5, -9))
	hazard.ImageTransparency = 0.28
	local label = make("TextLabel", back, {
		Name = "Title", Text = caption, BackgroundTransparency = 1, Font = Enum.Font.GothamBold,
		TextSize = 10, TextColor3 = Skin.ink, TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd, TextStrokeTransparency = 0.5,
		Size = UDim2.new(1, -37, 1, 0), Position = UDim2.fromOffset(11, 0),
	})
	return back, label
end

function Skin.field(view, field)
	field.BackgroundColor3 = Skin.recess
	field.PlaceholderColor3 = Skin.muted
	field.TextSize = 13
	local outline = stroke(field, Skin.edge)
	local function apply()
		field.TextColor3 = if field.TextEditable == false then Skin.muted else Skin.ink
		outline.Transparency = if field.TextEditable == false then 0.45 else 0
	end
	view:on(field:GetPropertyChangedSignal("TextEditable"), apply)
	view:on(field.Focused, function()
		if field.TextEditable ~= false then outline.Color = Skin.gold end
	end)
	view:on(field.FocusLost, function() outline.Color = Skin.edge end)
	apply()
end

local function swatch(parent, index)
	local x, y = (index - 1) % 3, math.floor((index - 1) / 3)
	local clip = make("Frame", parent, {
		Name = "MaterialSwatch", BorderSizePixel = 0, BackgroundTransparency = 1, ClipsDescendants = true,
		Position = UDim2.fromOffset(4, 3), Size = UDim2.new(1, -8, 1, -18),
	})
	return make("ImageLabel", clip, {
		Name = "TerrainTexture", BackgroundTransparency = 1, Image = materials and materials.image or "",
		Size = UDim2.fromScale(3, 2), Position = UDim2.fromScale(-x, -y),
	})
end

function Skin.button(view, control, options)
	if controls[control] then return end
	options = options or {}
	control.AutoButtonColor = false
	control.TextTransparency = 1
	control.BackgroundColor3 = Skin.olive
	local metalImage = Skin.metal(control, neutral)
	local outline = stroke(control, Skin.edge)
	local icon
	if options.swatch then
		icon = swatch(control, options.swatch)
	elseif options.icon then
		local size, position
		if options.side then
			size, position = UDim2.fromOffset(22, 22), UDim2.new(0, 4, 0.5, -11)
		elseif options.iconOnly then
			size, position = UDim2.new(1, -4, 1, -2), UDim2.fromOffset(2, 1)
		else
			size, position = UDim2.new(1, -10, 1, -12), UDim2.fromOffset(5, 0)
		end
		icon = Skin.icon(control, options.icon, size, position)
	end
	if options.dropdown then
		Skin.icon(control, "down", UDim2.fromOffset(14, 20), UDim2.new(1, -16, 0.5, -10))
	end
	if options.rivets then
		Skin.rivet(control, 0, 0, 4, 4)
		Skin.rivet(control, 1, 1, -4, -4)
	end
	local stacked = options.swatch or (options.icon and not options.side and not options.iconOnly)
	local caption = make("TextLabel", control, {
		Name = "Caption", Text = control.Text, BackgroundTransparency = 1, TextStrokeTransparency = 0.55,
		Font = Skin.font, TextSize = options.size or 11, TextColor3 = Skin.ink,
		TextXAlignment = if options.side then Enum.TextXAlignment.Left else Enum.TextXAlignment.Center,
		TextWrapped = not stacked and not options.side,
		TextTruncate = if stacked or options.side then Enum.TextTruncate.AtEnd else Enum.TextTruncate.None,
		Visible = not options.iconOnly or atlas == nil,
		Size = if stacked then UDim2.new(1, -4, 0, 13)
			elseif options.side then UDim2.new(1, if options.dropdown then -43 else -30, 1, 0)
			else UDim2.new(1, if options.dropdown then -20 else -4, 1, 0),
		Position = if stacked then UDim2.new(0, 2, 1, -14) else UDim2.fromOffset(if options.side then 27 else 2, 0),
	})
	local state = {selected = false, hover = false, pressed = false}
	local function render()
		local disabled = control.Interactable == false
		local selected = state.selected and not disabled
		local hover = state.hover and not disabled
		local pressed = state.pressed and not disabled
		outline.Color = if disabled then Color3.fromRGB(66, 65, 54)
			elseif selected then Skin.gold elseif state.remembered then bronze elseif hover then neutral else Skin.edge
		outline.Thickness = if selected then 2 else 1
		metalImage.ImageColor3 = if disabled then Color3.fromRGB(103, 102, 93)
			elseif pressed then oliveTint elseif selected or options.gold then bronze elseif hover then white else neutral
		metalImage.ImageTransparency = if options.gold and not disabled then 0.57 else 0.05
		control.BackgroundColor3 = if options.gold and not disabled then Color3.fromRGB(205, 142, 39) else Skin.olive
		caption.TextColor3 = if disabled then Skin.muted elseif options.gold then black elseif selected then Skin.gold elseif state.remembered then bronze else Skin.ink
		caption.TextStrokeTransparency = if options.gold then 1 else 0.55
		if icon then
			icon.ImageTransparency = if disabled then 0.52 else 0
			icon.ImageColor3 = if options.gold and not disabled then black else white
		end
	end
	state.render = render
	controls[control] = state
	view.skinnedControls = view.skinnedControls or {}
	table.insert(view.skinnedControls, control)
	view:on(control:GetPropertyChangedSignal("Text"), function() caption.Text = control.Text end)
	view:on(control:GetPropertyChangedSignal("Interactable"), render)
	view:on(control.MouseEnter, function() state.hover = true; render() end)
	view:on(control.MouseLeave, function() state.hover = false; state.pressed = false; render() end)
	view:on(control.InputBegan, function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			state.pressed = true
			render()
		end
	end)
	view:on(control.InputEnded, function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			state.pressed = false
			render()
		end
	end)
	render()
end

function Skin.release(view)
	for _, control in ipairs(view.skinnedControls or {}) do controls[control] = nil end
	view.skinnedControls = nil
end

function Skin.select(control, selected)
	local state = controls[control]
	if state and state.selected ~= selected then
		state.selected = selected
		state.render()
	end
end

function Skin.remember(control, remembered)
	local state = controls[control]
	if state and state.remembered ~= remembered then
		state.remembered = remembered
		state.render()
	end
end

function Skin.catalogRow(control, depth, expanded, isAsset, available)
	local indent = math.min(depth, 6) * 7
	control.TextTransparency = 1
	control.BackgroundColor3 = if isAsset then Skin.recess else Skin.olive
	make("TextLabel", control, {
		Name = "TreeCaption", Text = control.Text, BackgroundTransparency = 1,
		TextColor3 = if isAsset and not available then Skin.muted else Skin.ink,
		Font = Skin.font, TextSize = 12, TextTruncate = Enum.TextTruncate.AtEnd,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(indent + 31, 0), Size = UDim2.new(1, -indent - 33, 1, 0),
	})
	make("Frame", control, {
		Name = "SelectedMark", Visible = false, BackgroundColor3 = Skin.gold, BorderSizePixel = 0,
		Position = UDim2.fromOffset(1, 1), Size = UDim2.new(0, 2, 1, -2),
	})
	if not isAsset then
		Skin.icon(control, if expanded then "down" else "right", UDim2.fromOffset(12, 16), UDim2.new(0, indent + 3, 0.5, -8))
	end
	Skin.icon(control, if isAsset then "item" else "folder", UDim2.fromOffset(18, 19), UDim2.new(0, indent + 13, 0.5, -10))
end

function Skin.highlightRow(control, selected)
	control.BackgroundColor3 = if selected then Skin.active else Skin.recess
	local mark = control:FindFirstChild("SelectedMark")
	if mark then mark.Visible = selected end
end

function Skin.refresh(control)
	local state = controls[control]
	if state then state.render() end
end

return Skin
