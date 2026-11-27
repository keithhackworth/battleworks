-- Layout and presentation for the existing World Editor controls.
local Presentation = {}
local dark = Color3.fromRGB(33, 39, 25)
local olive = Color3.fromRGB(61, 71, 45)
local cream = Color3.fromRGB(241, 222, 174)
local gold = Color3.fromRGB(233, 181, 80)
local active = Color3.fromRGB(105, 112, 56)
local disabled = Color3.fromRGB(44, 50, 36)

local function area(object, x, y, width, height)
	object.Position = UDim2.fromOffset(x, y)
	object.Size = UDim2.fromOffset(math.max(0, width), math.max(0, height))
end

local function append(list, ...)
	for _, object in ipairs({...}) do table.insert(list, object) end
end

function Presentation.install(view, context, ui)
	local make, button, text, scrolling = ui.make, ui.button, ui.text, ui.scrolling
	local frame = view.frame
	local toolbar = view.toolbar
	local function panel(parent, name)
		return make("Frame", parent, {Name = name, BackgroundColor3 = dark, BorderSizePixel = 0, Active = true})
	end
	local function flow(parent)
		local container = scrolling(parent, "Controls", UDim2.fromScale(1, 1), UDim2.fromOffset(0, 0))
		container.BackgroundTransparency = 1
		make("UIPadding", container, {PaddingTop = UDim.new(0, 4), PaddingLeft = UDim.new(0, 5), PaddingRight = UDim.new(0, 5)})
		local grid = make("UIGridLayout", container, {CellSize = UDim2.fromOffset(122, 27), CellPadding = UDim2.fromOffset(4, 4), SortOrder = Enum.SortOrder.LayoutOrder})
		return container, grid
	end
	local function list(parent)
		local container = scrolling(parent, "Fields", UDim2.fromScale(1, 1), UDim2.fromOffset(0, 0))
		make("UIPadding", container, {PaddingTop = UDim.new(0, 6), PaddingLeft = UDim.new(0, 8)})
		make("UIListLayout", container, {Padding = UDim.new(0, 3), SortOrder = Enum.SortOrder.LayoutOrder})
		return container
	end
	local function put(parent, controls)
		for index, control in ipairs(controls) do
			control.Parent = parent
			control.LayoutOrder = index
			if parent.Name:match("Actions$") and control:IsA("TextButton") then
				control.TextWrapped = true
				control.TextSize = 12
			end
		end
	end
	local function shield(name, z)
		local node = panel(frame, name)
		node.BackgroundColor3 = Color3.new(0, 0, 0)
		node.BackgroundTransparency = 0.45
		node.Size = UDim2.fromScale(1, 1)
		node.ZIndex = z
		node.Visible = false
		return node
	end

	view.left = panel(frame, "ToolRail")
	view.bottom = panel(frame, "ContextControls")
	local tabs = panel(view.bottom, "Categories")
	local quick = flow(view.bottom)
	local inspector = panel(frame, "Inspector")
	view.inspector = inspector
	local inspectorTitle = text(inspector, "InspectorTitle", "PROPERTIES", 23)
	inspectorTitle.TextColor3 = gold
	view.selected.Parent = inspector
	view.selected.AutomaticSize = Enum.AutomaticSize.None
	view.selected.TextSize = 12
	local descriptions = {
		Placement = "Choose a source and target contact to snap.",
		Rotation = "Choose a local axis, then drag the viewport ring.",
		Physics = "Collision, durability and surface traction.",
		Motion = "Configure automatic rotation or a motion path.",
		Sound = "Select a Sound Block or use Add Asset to place one.",
	}
	view.contextHint = text(view.bottom, "ContextHint", "", 20)
	local groups = {}
	local quickGroups = {}
	local categories = {"Placement", "Rotation", "Physics", "Motion", "Sound"}
	local selectedCategory = "Placement"
	local toolMode = "Select"
	local selection
	local inspecting, inspectorOverride = true, nil
	local startMode = false
	local tabButtons = {}
	for _, name in ipairs(categories) do
		groups[name] = list(inspector)
		groups[name].Name = name .. "Properties"
		tabButtons[name] = button(tabs, name, name)
		view:on(tabButtons[name].Activated, function()
			selectedCategory = name
			view:applyContext()
		end)
		quickGroups[name] = {}
	end
	local function field(group, name)
		view.fieldLabels[name].Parent = groups[group]
		view.fields[name].Parent = groups[group]
	end
	for _, name in ipairs({"x", "y", "z", "scale", "sizeX", "sizeY", "sizeZ"}) do field("Placement", name) end
	for _, name in ipairs({"pitch", "yaw", "roll"}) do field("Rotation", name) end
	field("Physics", "hp")
	put(groups.Physics, {view.fieldLabels.hp, view.fields.hp, view.regenerates, view.regenerationLabel,
		view.regenerationDelay, view.assetTractionLabel, view.assetTraction, view.influences})
	for _, row in pairs(view.soundFields) do row.label.Parent, row.field.Parent = groups.Sound, groups.Sound end
	for _, row in pairs(view.spinFields) do row.label.Parent, row.field.Parent = groups.Motion, groups.Motion end
	for _, row in pairs(view.waypointFields) do row.label.Parent, row.field.Parent = groups.Motion, groups.Motion end
	for _, row in pairs(view.motionFields) do row.label.Parent, row.field.Parent = groups.Motion, groups.Motion end

	view.fitButtons = {}
	for _, mode in ipairs({"Move", "Stretch", "Scale"}) do
		view.fitButtons[mode] = button(quick, mode .. "ToSnap", mode .. " to Snap")
	end
	quickGroups.Placement = {view.snap, view.edgeSnap, view.fitButtons.Move, view.fitButtons.Stretch,
		view.fitButtons.Scale, view.pinA, view.pinB, view.releasePin, view.copyScale, view.pasteScale}
	quickGroups.Rotation = {view.tools.Rotate, view.rotationAxes.Pitch, view.rotationAxes.Yaw, view.rotationAxes.Roll}
	quickGroups.Physics = {view.solid, view.destructible}
	quickGroups.Motion = {view.spinToggle, view.spinSpace, view.spinMode, view.motionDraw, view.motionPreview,
		view.motionRemove, view.motionPoint, view.motionFace, view.motionEnable}
	local sound = view.soundButtons
	quickGroups.Sound = {sound.effect, sound.preview, sound.activation, sound.playback, sound.rollOff, sound.filter,
		sound.origin, sound.targets, sound.attach, sound.follow, sound.paint}
	local terrainControls = {}
	for _, name in ipairs({"Raise", "Lower", "Smooth", "Flatten"}) do append(terrainControls, view.terrainTools[name]) end
	for _, name in ipairs({"Grass", "Mud", "Ice", "Snow", "Pavement", "Water", "Carve Ravine", "Tunnel"}) do
		append(terrainControls, view.surfaceTools[name])
	end
	append(terrainControls, view.traversability, view.tunnelNew, view.tunnelNext, view.tunnelDelete)
	view.startPlacement = button(quick, "PlaceStart", "Place start zone")
	quickGroups.Start = {view.startPlacement}

	local contextPanels, actionGrids = {}, {}
	for _, name in ipairs({"Placement", "Rotation", "Physics", "Motion", "Sound", "Terrain", "Start"}) do
		local controls, grid = flow(view.bottom)
		actionGrids[name] = grid
		controls.Name = name .. "Actions"
		contextPanels[name] = controls
		put(controls, if name == "Terrain" then terrainControls else quickGroups[name])
	end
	quick:Destroy()

	local menuShield = shield("EditorMenuBackdrop", 5)
	menuShield.BackgroundTransparency = 1
	local dropdowns = {}
	local menuNames = {"File", "World Settings", "View", "Advanced", "Test"}
	local menuButtons = {}
	local function closeDropdown()
		menuShield.Visible = false
		for _, dropdown in pairs(dropdowns) do dropdown.Visible = false end
	end
	local closeMenu = make("TextButton", menuShield, {Text = "", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1)})
	view:on(closeMenu.Activated, closeDropdown)
	local function dropdown(name, controls)
		local window = scrolling(menuShield, name .. "Dropdown", UDim2.fromScale(1,1), UDim2.fromOffset(0,0))
		window.Visible = false
		window.ZIndex = 2
		make("UIListLayout", window, {Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder})
		put(window, controls)
		for _, control in ipairs(controls) do
			control.Size = UDim2.new(1, 0, 0, 31)
			if control:IsA("TextButton") then view:on(control.Activated, closeDropdown) end
		end
		dropdowns[name] = window
		return window
	end
	view.importMenu = button(toolbar, "ImportMenu", "Import JSON")
	view.terrainVisibility = button(toolbar, "TerrainVisibility", "Hide Terrain")
	view.scaleVisibility = button(toolbar, "ScaleVisibility", "Hide Tank Scale")
	dropdown("File", {view.newWorld, view.openWorld, view.openPlayground, view.saveWorld, view.saveAs})
	local sensitivityLabel = text(toolbar, "SensitivityHeading", "Camera sensitivity", 24)
	dropdown("View", {view.terrainVisibility, view.soundVisibility, sensitivityLabel,
		view.cameraSensitivity, view.frameWorld, view.scaleVisibility, view.inspect})
	dropdown("Advanced", {view.importMenu, view.export})
	for _, name in ipairs(menuNames) do
		local control = if name == "Test" then view.worlds else button(toolbar, name:gsub(" ", ""), name .. (if name == "World Settings" then "" else "  ▾"))
		menuButtons[name] = control
		control.Parent = toolbar
		if name == "Test" then
			control.Text = "▶ Test"
			control.TextColor3 = dark
			control.BackgroundColor3 = gold
			view:on(control.Activated, closeDropdown)
		elseif dropdowns[name] then
			view:on(control.Activated, function()
				local wasOpen = dropdowns[name].Visible
				closeDropdown()
				if not wasOpen then menuShield.Visible = true; dropdowns[name].Visible = true end
			end)
		end
	end

	local settingsShield = shield("WorldSettingsModal", 18)
	local settings = panel(settingsShield, "WorldSettings")
	settings.AnchorPoint = Vector2.new(0.5, 0.5)
	settings.Position = UDim2.fromScale(0.5, 0.5)
	settings.Size = UDim2.new(0.84, 0, 0, 254)
	make("UISizeConstraint", settings, {MaxSize = Vector2.new(440, 370)})
	local settingsList = list(settings)
	put(settingsList, view.dimensionRows)
	local boundary = text(settingsList, "Boundary", "World boundary is always enabled.", 27)
	boundary.LayoutOrder = 6
	view.groundMaterial = button(settingsList, "GroundMaterial", "Ground material")
	view.groundMaterial.LayoutOrder = 7
	local colorLabel = text(settingsList, "GroundColorLabel", "Ground color (R, G, B)", 22)
	colorLabel.LayoutOrder = 8
	view.groundColor = make("TextBox", settingsList, {Name = "GroundColor", LayoutOrder = 9,
		Size = UDim2.new(1,-8,0,28), Text = "", ClearTextOnFocus = false,
		TextColor3 = cream, BackgroundColor3 = olive, Font = Enum.Font.Code, TextSize = 14})
	local settingsClose = button(settings, "Done", "Done", UDim2.new(1,-16,0,30), UDim2.new(0,8,1,-35))
	settingsList.Size = UDim2.new(1,0,1,-42)
	settings.Size = UDim2.fromScale(0.84,0.85)
	view:on(settingsClose.Activated, function() settingsShield.Visible = false end)
	view:on(menuButtons["World Settings"].Activated, function() closeDropdown(); settingsShield.Visible = true end)

	local leaveShield = shield("LeaveEditorModal", 27)
	local leavePanel = panel(leaveShield, "LeaveEditor")
	leavePanel.AnchorPoint = Vector2.new(0.5, 0.5)
	leavePanel.Position = UDim2.fromScale(0.5, 0.5)
	leavePanel.Size = UDim2.new(0.85, 0, 0, 128)
	make("UISizeConstraint", leavePanel, {MaxSize = Vector2.new(420, 128)})
	local leaveText = text(leavePanel, "Message", "Unsaved changes. Save from File before leaving, or keep this draft for this session.", 66)
	leaveText.Position = UDim2.fromOffset(10, 8)
	local stay = button(leavePanel, "Stay", "Keep Editing", UDim2.new(0.48,-12,0,32), UDim2.fromOffset(8, 81))
	local leave = button(leavePanel, "Leave", "Leave Editor", UDim2.new(0.48,-12,0,32), UDim2.new(0.52,0,0,81))
	local exitAction
	view:on(stay.Activated, function() exitAction = nil; leaveShield.Visible = false end)
	view:on(leave.Activated, function()
		local action = exitAction
		exitAction = nil
		leaveShield.Visible = false
		if action then action() end
	end)
	function view:confirmExit(action)
		exitAction = action
		leaveShield.Visible = true
	end

	local libraryShield = shield("AssetLibraryModal", 18)
	view.palette.Parent = libraryShield
	view.palette.AnchorPoint = Vector2.new(0.5, 0.5)
	view.palette.Position = UDim2.fromScale(0.5, 0.5)
	view.palette.Size = UDim2.fromScale(0.84, 0.81)
	make("UISizeConstraint", view.palette, {MaxSize = Vector2.new(900, 650)})
	view.palette.Visible = true
	view.paletteStatus = text(view.palette, "SelectedAsset", "Choose an asset to place", 23)
	view.paletteStatus.TextSize = 12
	view.assetSelect = button(view.palette, "SelectAsset", "Select Asset")
	view.assetCancel = button(view.palette, "Cancel", "Cancel")
	view.assetScroll.Size = UDim2.new(1, -20, 1, -145)
	view.assetScroll.Position = UDim2.fromOffset(10, 78)
	view.assetPrevious = button(view.palette, "PreviousAssets", "‹")
	view.nextPage.Text = "›"
	view.page.TextSize = 11

	function view:stageAsset(item, tile, choose)
		if self.assetTile then self.assetTile.BackgroundColor3 = self.assetTileColor end
		self.pendingAsset, self.assetTile, self.chooseAsset = item, tile, choose
		if tile then self.assetTileColor = tile.BackgroundColor3; tile.BackgroundColor3 = active end
		self.paletteStatus.Text = if item then (if item.available then item.model else item.loadError or "Asset unavailable") else "Choose an asset to place"
		self.assetSelect.Interactable = item ~= nil and item.available == true
		self.assetSelect.TextTransparency = if self.assetSelect.Interactable then 0 else 0.5
	end
	function view:closeAssetLibrary()
		libraryShield.Visible = false
		self:stageAsset(nil)
	end
	view:stageAsset(nil)
	view:on(view.assets.Activated, function()
		closeDropdown()
		libraryShield.Visible = true
	end)
	view:on(view.assetCancel.Activated, function() view:closeAssetLibrary() end)
	view:on(view.assetSelect.Activated, function()
		local item, choose = view.pendingAsset, view.chooseAsset
		if item and item.available and choose then
			view:closeAssetLibrary()
			choose(item)
		end
	end)

	local objectMenu = panel(menuShield, "ObjectContextMenu")
	objectMenu.Visible = false
	objectMenu.ZIndex = 3
	view.delete.Parent = objectMenu
	view.delete.Size = UDim2.new(1, 0, 1, 0)
	view.delete.Position = UDim2.fromOffset(0, 0)
	view:on(view.delete.Activated, function() objectMenu.Visible = false; closeDropdown() end)
	view.objectActions = button(inspector, "ObjectActions", "Object actions  ▾")
	view:on(view.objectActions.Activated, function()
		closeDropdown()
		local at = view.objectActions.AbsolutePosition - frame.AbsolutePosition
		area(objectMenu, at.X, at.Y + 26, view.objectActions.AbsoluteSize.X, 31)
		objectMenu.Visible = true
		menuShield.Visible = true
	end)
	view:on(closeMenu.Activated, function() objectMenu.Visible = false end)
	local installedModal = view.isModal
	function view:isModal()
		return leaveShield.Visible or libraryShield.Visible or settingsShield.Visible or menuShield.Visible or installedModal(self)
	end
	function view:dismissPresentation()
		if leaveShield.Visible then exitAction = nil; leaveShield.Visible = false; return true end
		if libraryShield.Visible then self:closeAssetLibrary(); return true end
		if settingsShield.Visible then settingsShield.Visible = false; return true end
		if menuShield.Visible then objectMenu.Visible = false; closeDropdown(); return true end
		return false
	end
	function view:resetPresentation()
		exitAction = nil
		leaveShield.Visible = false
		self:closeAssetLibrary()
		settingsShield.Visible = false
		objectMenu.Visible = false
		closeDropdown()
	end

	local rail = {
		{view.tools.Select, "↖", "Select / Navigate"}, {view.assets, "⎔", "Add Asset"}, {view.tools.Move, "✥", "Move"}, {view.tools.Resize, "↔", "Resize"},
		{view.tools.Scale, "⤢", "Scale"}, {view.duplicate, "▣", "Duplicate"}, {view.terrain, "▲", "Terrain"},
		{view.undo, "↶", "Undo"}, {view.redo, "↷", "Redo"}, {view.placeStart, "⚑", "Start Zones"},
	}
	for _, record in ipairs(rail) do
		local control = record[1]
		control.Parent = view.left
		control.Text = record[2] .. "\n" .. record[3]
		control.Font = Enum.Font.GothamBold
		control.TextScaled = true
		make("UITextSizeConstraint", control, {MaxTextSize = 14})
	end
	view.startPlacement.Text = "Place Next Start Zone"
	view.startDetails = text(inspector, "StartZoneDetails", "", 38)
	view.noSound = text(groups.Sound, "SoundHelp", "Select a Sound Block or add one from the Asset Library.", 54)
	view.noSound.LayoutOrder = 999
	view.grid.PlaceholderText = "Grid increment"
	local gridLabel = text(groups.Placement, "GridIncrement", "Grid increment (studs)", 24)
	gridLabel.LayoutOrder = 997
	view.grid.Parent = groups.Placement
	view.grid.Size = UDim2.new(1,-8,0,28)
	view.grid.LayoutOrder = 998
	view.frameWorld.Text = "Frame World  •  Home"
	view.pinA.Visible = true
	view.pinB.Visible = true

	view.snapReadout = text(groups.Placement, "SnapReadout", "", 42)
	view.snapReadout.LayoutOrder = 999

	function view:setEditorMode(mode)
		toolMode = mode
		startMode = false
		if mode == "Rotate" then selectedCategory = "Rotation"
		elseif mode == "Move" or mode == "Scale" or mode == "Resize" or mode == "Select" then selectedCategory = "Placement" end
		self:applyContext()
	end
	function view:setStartMode()
		startMode = true
		self:applyContext()
	end
	function view:applyContext()
		local current = if self.terrainActive then "Terrain" elseif startMode or (selection and selection.slot) then "Start" else selectedCategory
		local selected = selection ~= nil
		local start = current == "Start"
		local fitMode = ({Move="Move",Resize="Stretch",Scale="Scale"})[toolMode]
		local clipboard = toolMode == "Resize" or toolMode == "Scale"
		for name, control in pairs(view.fitButtons) do control.Visible = name == fitMode end
		view.edgeSnap.Visible = fitMode ~= nil
		view.pinA.Visible, view.pinB.Visible, view.releasePin.Visible = fitMode ~= nil, fitMode ~= nil, fitMode ~= nil
		view.copyScale.Visible, view.pasteScale.Visible = clipboard, clipboard
		gridLabel.Visible, view.grid.Visible = not start, not start
		view.snapReadout.Visible = not start and fitMode ~= nil
		tabs.Visible = current ~= "Terrain" and not start
		for name, control in pairs(tabButtons) do control.BackgroundColor3 = if name == selectedCategory then active else olive end
		for name, group in pairs(groups) do
			group.Visible = (selected and name == current) or (start and name == "Placement" and selection and selection.slot ~= nil) or (name == "Sound" and current == "Sound")
		end
		view.noSound.Visible = current == "Sound" and not (selection and selection.sound)
		for name, controls in pairs(contextPanels) do
			controls.Visible = name == current and (selected or name == "Terrain" or name == "Start" or name == "Placement")
		end
		for _, name in ipairs({"x", "y", "z", "sizeX", "sizeY", "sizeZ", "scale", "yaw"}) do
			local isSize = name:match("^size") ~= nil
			local visible = if start then name == "x" or name == "z" or name == "yaw"
				elseif isSize then toolMode == "Resize" elseif name == "scale" then toolMode == "Scale"
				elseif name == "yaw" then false else toolMode ~= "Resize" and toolMode ~= "Scale"
			if name == "yaw" then
				local parent = if start then groups.Placement else groups.Rotation
				view.fieldLabels.yaw.Parent, view.fields.yaw.Parent = parent, parent
				visible = true
			end
			view.fields[name].Visible, view.fieldLabels[name].Visible = visible, visible
		end
		self.brushPanel.Visible = current == "Terrain"
		self.startDetails.Visible = start
		self.selected.Visible = current ~= "Terrain" and (selected or not start)
		self.objectActions.Visible = selected and current ~= "Terrain"
		self.contextHint.Text = if current == "Terrain" then "Terrain brush • choose a tool or material." elseif start then "Five numbered zones are required to play." else descriptions[current]
		if current == "Placement" and fitMode then self.contextHint.Text = self.pinStatus.Text end
		self.duplicate.Interactable = selected
		self.duplicate.TextTransparency = if selected then 0 else 0.5
		self.placeStart.BackgroundColor3 = if start then active else olive
		for _, record in ipairs({view.edgeSnap,view.fitButtons.Move,view.fitButtons.Stretch,view.fitButtons.Scale,
			view.pinA,view.pinB,view.releasePin,view.copyScale,view.pasteScale}) do
			record.Interactable = selected
			record.TextTransparency = if selected then 0 else 0.5
		end
	end
	function view:presentSelection(entry)
		selection = entry
		self:applyContext()
	end
	function view:setHistory(undo, redo)
		for index, control in ipairs({self.undo, self.redo}) do
			local allowed = if index == 1 then undo > 0 else redo > 0
			control.Interactable = allowed
			control.TextTransparency = if allowed then 0 else 0.45
			control.BackgroundColor3 = if allowed then olive else disabled
		end
	end
	function view:setStartCount(count)
		local caption = string.format("Start Zones (%d/5)", count)
		self.placeStart.Text = "⚑\n" .. caption
		self.startDetails.Text = caption .. "\nPlace on clear ground, 40 studs apart."
	end
	view:on(view.inspect.Activated, function() inspectorOverride = not inspecting; view:layout() end)

	function view:layout()
		local size = frame.AbsoluteSize
		local w, h = size.X, size.Y
		local compact = w < 720
		inspecting = if inspectorOverride == nil then w >= 560 else inspectorOverride
		self.inspect.Text = if inspecting then "Hide Inspector" else "Show Inspector"
		local left = if compact then math.clamp(w * 0.29, 86, 126) else 146
		local right = if inspecting then math.min(if compact then 155 else 248, w * (if compact then 0.34 else 0.26)) else 0
		local top, status = 43, 36
		local dock = math.min(131, math.max(72, math.floor(h * 0.26)))
		local center = math.max(0, w - left - right)
		area(toolbar, 0, 0, w, top)
		local backWidth = if context.integratedEditor then 0 else math.min(76, w * 0.16)
		self.back.Visible = backWidth > 0
		area(self.back, 3, 4, backWidth, 33)
		local toolbarWidth = w - backWidth - 5
		local offset = backWidth + 4
		for index, name in ipairs(menuNames) do
			local width = toolbarWidth * ({0.16, 0.29, 0.16, 0.23, 0.16})[index]
			local control = menuButtons[name]
			area(control, offset, 4, width - 3, 33)
			control.TextSize = if compact then 11 else 14
			if dropdowns[name] then
				local count = if name == "File" then (if context.royale then 5 else 4) elseif name == "View" then 7 else 2
				local dropWidth = math.min(223, w)
				area(dropdowns[name], math.clamp(offset, 0, math.max(0, w - dropWidth)), top, dropWidth, math.min(count * 33, h - top))
			end
			offset += width
		end
		area(self.left, 0, top, left, h - top - status)
		local row = math.min(60, math.max(0, (h - top - status) / math.ceil(#rail / 2)))
		local column = left / 2
		for index, record in ipairs(rail) do
			local position = index - 1
			area(record[1], 3 + position % 2 * column, math.floor(position / 2) * row + 2, column - 6, row - 4)
		end
		area(self.viewport, left, top, center, h - top - status - dock)
		area(self.bottom, left, h - status - dock, center, dock)
		area(tabs, 0, 0, center, 27)
		for index, name in ipairs(categories) do
			local control = tabButtons[name]
			area(control, (index - 1) * center / #categories, 1, center / #categories - 2, 25)
			control.TextSize = if compact then 10 else 13
		end
		local columns = math.max(1, math.floor(center / 112))
		for name, controls in pairs(contextPanels) do
			actionGrids[name].CellSize = UDim2.fromOffset(math.max(0,(center - 15) / columns - 4), 27)
			local hasTabs = name ~= "Terrain" and name ~= "Start"
			local controlsTop = if hasTabs then 28 else 0
			area(controls, 0, controlsTop, center, dock - controlsTop - 19)
		end
		area(self.contextHint, 5, dock - 19, center - 10, 19)
		self.contextHint.TextSize = 10
		inspector.Visible = inspecting
		area(inspector, w - right, top, right, h - top - status)
		area(inspectorTitle, 8, 3, right - 16, 23)
		area(self.selected, 8, 27, right - 16, 37)
		area(self.startDetails, 8, 65, right - 16, 39)
		area(self.objectActions, 8, 105, right - 16, 26)
		for _, group in pairs(groups) do area(group, 0, 135, right, h - top - status - 135) end
		self.brushPanel.Parent = inspector
		area(self.brushPanel, 0, 27, right, h - top - status - 27)
		self.status.TextSize = 12
		area(self.status, 6, h - status, w - 155, 19)
		area(self.hint, 6, h - 17, w - 12, 17)
		self.hint.TextSize = 10
		area(self.finishPaint, w - 140, h - status, 134, 21)
		area(self.paintBucket, w - 140, h - status, 134, 21)
		self.paletteStatus.Position = UDim2.new(0, 10, 1, -63)
		self.paletteStatus.Size = UDim2.new(1, -20, 0, 22)
		self.assetSelect.Position = UDim2.new(0.53, 0, 1, -34); self.assetSelect.Size = UDim2.new(0.28,-5,0,28)
		self.assetCancel.Position = UDim2.new(0.81, 0, 1, -34); self.assetCancel.Size = UDim2.new(0.19,-7,0,28)
		self.assetPrevious.Position = UDim2.new(0, 10, 1, -34); self.assetPrevious.Size = UDim2.fromOffset(24, 28)
		self.nextPage.Position = UDim2.new(0, 38, 1, -34); self.nextPage.Size = UDim2.fromOffset(24, 28)
		self.page.Position = UDim2.new(0, 68, 1, -34); self.page.Size = UDim2.new(0.48, -62, 0, 28)
		self.import.Position = UDim2.new(0.50, 3, 0, 86)
		self.import.Size = UDim2.new(0.5, -19, 0, 30)
		self.generate.Size = UDim2.new(0.5, -19, 0, 30)
		self.import.TextSize, self.generate.TextSize = if compact then 11 else 13, if compact then 11 else 13
		self:applyContext()
	end
	view:on(frame:GetPropertyChangedSignal("AbsoluteSize"), function() view:layout() end)
	view:layout()
end

return Presentation
