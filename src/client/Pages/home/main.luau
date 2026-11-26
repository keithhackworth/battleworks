local Players = game:GetService("Players")
local TextService = game:GetService("TextService")
local Preview = require(script.Parent.Preview)
local ink = Color3.fromRGB(46, 38, 23)
local red = Color3.fromRGB(145, 39, 28)
local olive = Color3.fromRGB(72, 78, 42)
local paper = Color3.fromRGB(235, 198, 139)
local sheetTop = 49
local cream = Color3.fromRGB(255, 236, 193)
local brass = Color3.fromRGB(155, 110, 53)

local function create(class, parent, props)
	local object = Instance.new(class)
	for key, value in pairs(props) do object[key] = value end
	object.Parent = parent
	return object
end

local function box(object, x, y, width, height)
	object.Position = UDim2.fromOffset(x, y)
	object.Size = UDim2.fromOffset(width, height)
end

local function frame(parent, color)
	return create("Frame", parent, {
		BackgroundColor3 = color or paper,
		BackgroundTransparency = if color then 0 else 1,
		BorderSizePixel = 0,
	})
end

local function edge(object, radius, color)
	create("UICorner", object, { CornerRadius = UDim.new(0, radius) })
	create("UIStroke", object, {
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Color = color or brass,
		Thickness = 2,
	})
end

local function gradient(object, top, bottom)
	create("UIGradient", object, { Rotation = 90, Color = ColorSequence.new(top, bottom) })
end

local function text(parent, value, size, options)
	options = options or {}
	return create("TextLabel", parent, {
		Text = value,
		TextSize = size,
		Font = options.font or Enum.Font.GothamBold,
		TextColor3 = options.color or ink,
		BackgroundTransparency = 1,
		TextXAlignment = options.align or Enum.TextXAlignment.Left,
		TextWrapped = options.wrap == true,
		TextTruncate = if options.wrap then Enum.TextTruncate.None else Enum.TextTruncate.AtEnd,
	})
end

local function stamp(parent, value, color, width, x, y, rotation)
	local mark = frame(parent)
	mark.Rotation = rotation
	box(mark, x, y, width, 36)
	edge(mark, 4, color)
	box(text(mark, value, 22, { color = color, align = Enum.TextXAlignment.Center }), 3, 0, width - 6, 36)
	return mark
end

local function button(context, parent, caption, color, action)
	local control = create("TextButton", parent, {
		Text = caption, Font = Enum.Font.GothamBold, TextScaled = true,
		TextColor3 = if color == olive then cream else ink,
		BackgroundColor3 = color, AutoButtonColor = true, BorderSizePixel = 0,
	})
	edge(control, 16, brass)
	create("UITextSizeConstraint", control, { MaxTextSize = 16 })
	context.scope:add(control.Activated:Connect(action))
	return control
end

local function photo(parent, image, context, openReplay)
	local field = openReplay ~= nil
	local card = frame(parent, cream)
	edge(card, 3, brass)
	local aperture = frame(card, Color3.fromRGB(104, 143, 155))
	aperture.Position = UDim2.fromOffset(7, 7)
	aperture.Size = UDim2.new(1, -14, 1, if field then -40 else -14)
	if image then
		create("ImageLabel", aperture, {
			Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1,
			Image = image.image, ScaleType = Enum.ScaleType.Crop,
		})
	else
		Preview.new(aperture, field)
	end
	if field then
		local play = button(context, aperture, "▶", olive, openReplay)
		play.Name = "OpenReplayLab"
		play.AnchorPoint = Vector2.new(0.5, 0.5)
		play.Position = UDim2.fromScale(0.5, 0.5)
		play.Size = UDim2.fromOffset(49, 49)
		local caption = text(card, "River Crossing", 17, { font = Enum.Font.GothamMedium })
		caption.Position = UDim2.new(0, 10, 1, -30)
		caption.Size = UDim2.new(1, -20, 0, 27)
		local clip = frame(card)
		box(clip, 18, -14, 15, 49)
		clip.Rotation = -17
		edge(clip, 7, Color3.fromRGB(115, 113, 101))
	end
	return card
end

local function mount(context)
	local player = Players.LocalPlayer
	local scroll = create("ScrollingFrame", context.content, {
		Name = "HomeDossier", Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(45, 48, 29), BorderSizePixel = 0,
		ScrollingDirection = Enum.ScrollingDirection.Y, ScrollBarThickness = 4,
		ScrollBarImageColor3 = brass, CanvasSize = UDim2.fromOffset(0, 0),
	})
	gradient(scroll, Color3.fromRGB(255, 255, 255), Color3.fromRGB(173, 157, 108))
	local canvas = frame(scroll)
	local zoom = create("UIScale", canvas, { Scale = 1 })
	local folderArt = {
		Personnel = context.assets.get("folders/folder1.png"),
		Debrief = context.assets.get("folders/folder2.png"),
	}
	local hasFolderArt = folderArt.Personnel and folderArt.Debrief
	local folders = {}
	local folderBack, folderMiddle
	local sheet = frame(canvas, if hasFolderArt then nil else paper)
	sheet.ZIndex = 3
	if hasFolderArt then
		for name, image in pairs(folderArt) do
			folders[name] = create("ImageLabel", canvas, {
				Name = name .. "Folder", Image = image.image, BackgroundTransparency = 1,
				ScaleType = Enum.ScaleType.Stretch,
			})
		end
	else
		folderBack = frame(canvas, Color3.fromRGB(174, 114, 54))
		edge(folderBack, 16)
		folderBack.Rotation = -1.7
		folderMiddle = frame(canvas, Color3.fromRGB(203, 155, 89))
		edge(folderMiddle, 13)
		folderMiddle.Rotation = 1.4
		edge(sheet, 11)
		gradient(sheet, Color3.new(1, 1, 1), Color3.fromRGB(228, 209, 176))
		local grain = context.assets.get("home/paper.png")
		if grain then
			create("ImageLabel", sheet, {
				Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1,
				Image = grain.image, ScaleType = Enum.ScaleType.Crop, ImageTransparency = 0.48,
			})
		end
	end

	local pages = {}
	local tabs = {}
	local seam = frame(canvas, paper)
	seam.ZIndex = sheet.ZIndex + 1
	seam.Visible = not hasFolderArt
	local function show(name)
		for key, page in pairs(pages) do
			local selected = key == name
			local tab = tabs[key]
			page.Visible = selected
			if hasFolderArt then
				local folder = folders[key]
				-- Each image already depicts both tabs and the complete folder stack.
				folder.Visible = selected
				tab.TextColor3 = if selected then ink else Color3.fromRGB(87, 68, 42)
			else
				tab.BackgroundColor3 = if selected then paper else Color3.fromRGB(182, 151, 108)
				local top = if selected then 12 else 20
				box(tab, tab.Position.X.Offset, top, 155, sheetTop - top + 12)
				if selected then box(seam, tab.Position.X.Offset + 1, sheetTop - 4, 153, 9) end
			end
		end
	end
	for index, name in ipairs({ "Personnel", "Debrief" }) do
		local tab = create("TextButton", canvas, {
			Name = name .. "Tab", Text = string.upper(name), BackgroundColor3 = paper, BorderSizePixel = 0,
			AutoButtonColor = false, Font = Enum.Font.GothamBold, TextSize = 16, TextColor3 = ink,
			BackgroundTransparency = if hasFolderArt then 1 else 0,
			ZIndex = if hasFolderArt then 4 else 2,
		})
		if not hasFolderArt then
			edge(tab, 9, brass)
			tab.Position = UDim2.fromOffset(37 + (index - 1) * 159, 12)
		end
		context.scope:add(tab.Activated:Connect(function() show(name) end))
		tabs[name] = tab
		pages[name] = frame(sheet)
		pages[name].Size = UDim2.fromScale(1, 1)
	end

	local function route(name)
		local ok, err = context.router:navigate(name)
		if not ok then warn("[BattleWorks UI]", err) end
	end

	local function heading(page, title, subtitle, chipped)
		local x = 43
		if chipped then
			local glyph = TextService:GetTextSize("B", 16, Enum.Font.GothamBold, Vector2.new(370, 24))
			local letter = text(page, "B", 16)
			box(letter, x, 15 + (24 - glyph.Y) / 2, glyph.X, glyph.Y)
			create("UIGradient", letter, {
				Rotation = 45,
				Transparency = NumberSequence.new({
					NumberSequenceKeypoint.new(0, 1),
					NumberSequenceKeypoint.new(0.40, 1),
					NumberSequenceKeypoint.new(0.41, 0),
					NumberSequenceKeypoint.new(1, 0),
				}),
			})
			box(text(page, "ATTLEWORKS ARMORED DIVISION", 16), x + glyph.X, 15, 348 - glyph.X, 24)
		else
			box(text(page, "BATTLEWORKS ARMORED DIVISION", 16), x, 15, 348, 24)
		end
		stamp(page, title, red, 239, 24, 48, -2)
		box(text(page, subtitle, 13, { font = Enum.Font.Code }), 26, 89, 360, 21)
	end

	local personnel = pages.Personnel
	heading(personnel, "PERSONNEL FILE", "RECRUIT INTAKE / FORM BW-001")
	local portrait = frame(personnel, cream)
	edge(portrait, 3)
	portrait.Rotation = -4
	box(portrait, 24, 125, 113, 124)
	local headshot = create("ImageLabel", portrait, {
		Position = UDim2.fromOffset(5, 5), Size = UDim2.new(1, -10, 1, -10),
		BackgroundColor3 = Color3.fromRGB(84, 126, 147), BorderSizePixel = 0,
		ScaleType = Enum.ScaleType.Crop,
	})
	local thumbnail = task.defer(function()
		local ok, image = pcall(Players.GetUserThumbnailAsync, Players, player.UserId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size150x150)
		if ok and headshot.Parent then headshot.Image = image end
	end)
	context.scope:add(function()
		if coroutine.status(thumbnail) ~= "dead" then task.cancel(thumbnail) end
	end)

	for index, entry in ipairs({
		{ "NAME", player.DisplayName }, { "RANK", "Private First Class" }, { "SERVICE NO.", tostring(player.UserId) },
	}) do
		local y = 132 + (index - 1) * 31
		local isRank = entry[1] == "RANK"
		local valueLeft = 249
		box(text(personnel, entry[1], 13, { font = Enum.Font.Code }), 153, y, valueLeft - 155, 23)
		local value = text(personnel, entry[2], 16)
		box(value, valueLeft, y, 380 - valueLeft, 23)
		if isRank then
			value.TextTruncate = Enum.TextTruncate.None
			value.TextScaled = true
			create("UITextSizeConstraint", value, { MaxTextSize = 16 })
		end
		box(frame(personnel, brass), 153, y + 25, 227, 1)
	end

	local assigned = frame(personnel, cream)
	box(assigned, 23, 269, 361, 152)
	edge(assigned, 8)
	local assetTitle = text(assigned, "ASSIGNED ASSETS  /  PREVIEW", 15, { color = cream })
	assetTitle.BackgroundTransparency = 0
	assetTitle.BackgroundColor3 = olive
	box(assetTitle, 7, 7, 347, 25)
	local tank = photo(assigned, context.assets.get("home/bunny-tank.png"))
	box(tank, 10, 40, 149, 103)
	local assignedName = text(assigned, "Bunny Tank", 20)
	box(assignedName, 170, 51, 175, 32)
	box(text(assigned, "Motor Pool preview", 14, { font = Enum.Font.Code }), 170, 88, 175, 25)
	local orders = frame(personnel)
	orders.Name = "Orders"
	box(orders, 23, 269, 361, 152)
	orders.Rotation = -1.8

	local shadow = frame(orders, Color3.fromRGB(81, 57, 31))
	shadow.BackgroundTransparency = 0.56
	box(shadow, 3, 5, 361, 148)
	local note = frame(orders, Color3.fromRGB(249, 238, 208))
	box(note, 0, 0, 361, 148)
	gradient(note, Color3.new(1, 1, 1), Color3.fromRGB(233, 218, 183))
	local marginRule = frame(note, Color3.fromRGB(165, 98, 80))
	marginRule.BackgroundTransparency = 0.55
	box(marginRule, 15, 12, 1, 122)
	box(text(note, "ORDERS:", 17), 24, 14, 324, 23)
	for index, line in ipairs({
		"Report to the Training Grounds for",
		"initial vehicle assignment and basic",
		"armored operations training.",
	}) do
		local y = 42 + (index - 1) * 26
		local rule = frame(note, Color3.fromRGB(116, 136, 145))
		rule.BackgroundTransparency = 0.48
		box(rule, 5, y + 22, 351, 1)
		box(text(note, line, 14, { font = Enum.Font.Code }), 24, y, 327, 24)
	end

	local function tape(x, y, rotation)
		local shadowStrip = frame(orders, Color3.fromRGB(91, 64, 32))
		shadowStrip.BackgroundTransparency = 0.78
		shadowStrip.Rotation = rotation
		box(shadowStrip, x + 1, y + 2, 63, 20)
		local strip = frame(orders, Color3.fromRGB(216, 181, 112))
		strip.BackgroundTransparency = 0.25
		strip.Rotation = rotation
		box(strip, x, y, 63, 20)
		gradient(strip, Color3.fromRGB(255, 245, 216), Color3.fromRGB(205, 172, 121))
	end
	tape(278, -9, 11)
	tape(2, 132, -13)

	local function updateAssignment()
		local name = player:GetAttribute("BattleWorksAssignedTank")
		local hasTank = type(name) == "string" and string.find(name, "%S") ~= nil
		assigned.Visible = hasTank
		orders.Visible = not hasTank
		if hasTank then
			assignedName.Text = name
			tank.Visible = name == "Bunny Tank"
		end
	end
	context.scope:add(player:GetAttributeChangedSignal("BattleWorksAssignedTank"):Connect(updateAssignment))
	updateAssignment()

	local function openReplay() route("replay_lab") end
	local crossing = context.assets.get("home/river-crossing.png")
	local field = photo(personnel, crossing, context, openReplay)
	field.Rotation = -3

	local debrief = pages.Debrief
	heading(debrief, "DEBRIEF", "BATTLE REPORT / SAMPLE REPLAY", true)
	local wear = {}
	if hasFolderArt then
		-- Reprint small pieces of the exact folder underneath the ink to expose the crease.
		for index = 1, 36 do
			wear[index] = create("ImageLabel", debrief, {
				Name = "ExposedPaper", Image = folderArt.Debrief.image,
				BackgroundTransparency = 1, ScaleType = Enum.ScaleType.Stretch, ZIndex = 6,
			})
		end
	end

	local function placeDebriefWear(designWidth, designHeight, bodyTop)
		local image = folderArt.Debrief
		local function expose(patch, x, y, width, height)
			box(patch, x - 5, y, width, height)
			local sourceX = x * image.width / designWidth
			local sourceY = (bodyTop + y - 3) * image.height / (designHeight - 3)
			patch.ImageRectOffset = Vector2.new(sourceX, sourceY)
			patch.ImageRectSize = Vector2.new(width * image.width / designWidth, height * image.height / (designHeight - 3))
		end
		for index = 1, 32 do
			local y = 17 + (index - 1) * 2
			local fraction = (bodyTop + y - 3) / (designHeight - 3)
			local crease = (0.395 - fraction * 1.04) * designWidth
			local width = 3 + (index * 7 % 5)
			expose(wear[index], math.max(5, crease - width / 2), y, width, 2.4)
		end
		-- Ink also flakes off in small isolated spots on the stamp and text.
		expose(wear[33], 41, 53, 5, 2)
		expose(wear[34], 197, 46, 7, 2)
		expose(wear[35], 250, 80, 6, 3)
		expose(wear[36], 173, 28, 4, 2)
	end

	for index, entry in ipairs({
		{ "MAP", "River Crossing" }, { "MODE", "Domination" }, { "RESULT", "Victory" },
		{ "KILLS", "7" }, { "DEATHS", "2" }, { "DAMAGE", "2,830" }, { "TIME", "3:24" },
	}) do
		local y = 122 + (index - 1) * 33
		box(text(debrief, entry[1], 15, { font = Enum.Font.Code }), 26, y, 120, 26)
		box(text(debrief, entry[2], 19, { color = if index == 3 then olive else ink }), 152, y, 226, 26)
		box(frame(debrief, brass), 26, y + 29, 350, 1)
	end
	stamp(debrief, "CLASSIFIED", red, 159, 205, 365, -6)
	local replay = photo(debrief, crossing, context, openReplay)
	replay.Rotation = -4
	local personnelActions = {
		button(context, personnel, "MOTOR POOL", olive, function() route("motor_pool") end),
		button(context, personnel, "REPLAY LAB", cream, function() route("replay_lab") end),
		button(context, personnel, "TRAINING GROUNDS", Color3.fromRGB(244, 173, 64), function() route("battle") end),
	}
	local debriefActions = {
		button(context, debrief, "OPEN REPLAY LAB", olive, function() route("replay_lab") end),
		button(context, debrief, "NEXT MISSION", Color3.fromRGB(244, 173, 64), function() route("battle") end),
	}
	show("Personnel")

	local function resize()
		local size = scroll.AbsoluteSize
		local compact = size.X < 720
		local designWidth = if compact then 406 else 916
		local designHeight = if compact then 865 else 575
		local scale = math.min(1.2, math.max(0.1, (size.X - 14) / designWidth))
		zoom.Scale = scale
		local y = math.max(5, (size.Y - designHeight * scale) / 2)
		box(canvas, math.max(4, (size.X - designWidth * scale) / 2), y, designWidth, designHeight)
		scroll.CanvasSize = UDim2.fromOffset(0, math.ceil(y + designHeight * scale + 8))
		if hasFolderArt then
			for _, folder in pairs(folders) do box(folder, 0, 3, designWidth, designHeight - 3) end
			local tabHeight = designHeight * 0.065
			box(tabs.Personnel, designWidth * 0.081, designHeight * 0.020, designWidth * 0.275, tabHeight)
			box(tabs.Debrief, designWidth * 0.374, designHeight * 0.020, designWidth * 0.261, tabHeight)
			local bodyTop = math.round(designHeight * 0.13)
			box(sheet, 5, bodyTop, designWidth - 12, designHeight - bodyTop - 18)
			placeDebriefWear(designWidth, designHeight, bodyTop)
		else
			box(folderBack, 9, 44, designWidth - 22, designHeight - 52)
			box(folderMiddle, 11, 43, designWidth - 25, designHeight - 53)
			box(sheet, 5, sheetTop, designWidth - 12, designHeight - 64)
		end
		for _, card in ipairs({ field, replay }) do
			if compact then box(card, 32, 438, 325, 228) else box(card, 421, 52, 451, 342) end
		end
		local actionY = if compact then 687 else 431
		for _, actions in ipairs({ personnelActions, debriefActions }) do
			local actionWidth = if compact then 112 else 207
			for index, action in ipairs(actions) do
				box(action, 21 + (index - 1) * (actionWidth + 9), actionY, actionWidth, 39)
			end
		end
	end
	context.scope:add(scroll:GetPropertyChangedSignal("AbsoluteSize"):Connect(resize))
	resize()
end

return { layout = "standard", mount = mount, unmount = function() end }
