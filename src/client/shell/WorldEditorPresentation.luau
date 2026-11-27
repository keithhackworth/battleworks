-- Layout and presentation for the existing World Editor controls.
local Skin = require(script.Parent.WorldEditorSkin)
local WorldSettings = require(game.ReplicatedStorage.Shared.WorldSettings)
local Presentation = {}
local dark, olive, cream, gold = Skin.recess, Skin.olive, Skin.ink, Skin.gold

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
	local quick = panel(view.left, "ControlStaging")
	local inspector = panel(frame, "Inspector")
	view.inspector = inspector
	local toolsBack = Skin.inset(inspector, "ToolSettingsRecess")
	local selectionBack = Skin.inset(inspector, "SelectionPropertiesRecess")
	local toolsHeader, toolsTitle = Skin.header(inspector, "TOOL SETTINGS")
	local selectionHeader, selectionTitle = Skin.header(inspector, "SELECTION PROPERTIES")
	local inspectorWidth, inspectorHeight = 0, 0
	local headerHeight = 22
	local chrome = Skin.inset(frame, "ViewportFrameMetal")
	chrome.BackgroundColor3 = olive
	Skin.metal(chrome, nil, 0.12)
	chrome.ZIndex = 1
	view.viewport.ZIndex = 2
	for _, x in ipairs({0, 1}) do
		for _, y in ipairs({0, 1}) do
			Skin.rivet(chrome, x, y, if x == 0 then 3 else -3, if y == 0 then 3 else -3)
		end
	end
	local footer = Skin.inset(frame, "EditorFooter")
	footer.BackgroundColor3 = olive
	Skin.metal(footer, Color3.fromRGB(222, 190, 153), 0.08)
	for _, x in ipairs({0, 1}) do
		Skin.rivet(footer, x, 0.5, if x == 0 then 7 else -7, 0)
	end
	local footerHazard = Skin.icon(footer, "hazard", UDim2.fromOffset(36, 32), UDim2.new(0, 10, 0.5, -16))
	footerHazard.ImageTransparency = 0.08
	local statusWell = Skin.inset(footer, "StatusWell")
	local hintWell = Skin.inset(footer, "ContextWell")
	local statusFlow = scrolling(statusWell, "StatusMessages", UDim2.fromScale(1, 1), UDim2.fromOffset(0, 0))
	statusFlow.BackgroundTransparency = 1
	statusFlow.ScrollBarThickness = 2
	view.status.Parent = statusFlow
	view.status.AutomaticSize = Enum.AutomaticSize.Y
	view.status.TextYAlignment = Enum.TextYAlignment.Top
	local hintFlow = scrolling(hintWell, "StatusContext", UDim2.fromScale(1, 1), UDim2.fromOffset(0, 0))
	hintFlow.BackgroundTransparency = 1
	hintFlow.ScrollBarThickness = 2
	view.hint.Parent = hintFlow
	view.hint.AutomaticSize = Enum.AutomaticSize.Y
	view.hint.TextYAlignment = Enum.TextYAlignment.Top
	view.status.BackgroundTransparency = 1
	view.status.Font = Skin.font
	view.hint.Font = Skin.font
	Skin.metal(toolbar, nil, 0.35)
	Skin.metal(view.left, nil, 0.75)
	view.selected.Parent = inspector
	view.selected.AutomaticSize = Enum.AutomaticSize.None
	view.selected.TextSize = 12
	local groups = {}
	local quickGroups = {}
	local subToolGroups = {}
	local categories = {"Placement", "Rotation", "Physics", "Motion", "Sound"}
	local toolMode = "Select"
	local selection
	local inspecting, inspectorOverride = true, nil
	for _, name in ipairs(categories) do
		groups[name] = list(inspector)
		groups[name].Name = name .. "Properties"
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
	quickGroups.Placement = {view.fitButtons.Move, view.fitButtons.Stretch,
		view.fitButtons.Scale, view.pinA, view.pinB, view.releasePin, view.copyScale, view.pasteScale}
	subToolGroups.Rotation = {view.rotationAxes.Pitch, view.rotationAxes.Yaw, view.rotationAxes.Roll}
	quickGroups.Physics = {view.solid, view.destructible}
	subToolGroups.Motion = {view.spinToggle, view.motionDraw}
	quickGroups.Motion = {view.spinSpace, view.spinMode, view.motionPreview,
		view.motionRemove, view.motionPoint, view.motionFace, view.motionEnable}
	local sound = view.soundButtons
	view.addSoundBlock = button(quick, "AddSoundBlock", "Add Sound Block")
	view.addPaintAudio = button(quick, "AddPaintAudio", "Paint Audio")
	view.soundRelationships = list(inspector)
	view.soundRelationships.Name = "AudioRelationships"
	local relationshipLabel = text(view.soundRelationships, "RelationshipSummary", "", 100)
	local relationshipButton = button(view.soundRelationships, "SelectRelatedSound", "Select related audio")
	relationshipButton.LayoutOrder = 1
	view.selectRelatedSound = relationshipButton
	function view:setAudioRelationships(label, relatedId)
		relationshipLabel.Text = label
		relationshipButton.Visible = relatedId ~= nil
		self.relatedSoundId = relatedId
	end
	view.nextRelatedSound = button(view.soundRelationships, "NextRelatedSound", "Next relationship")
	view.nextRelatedSound.LayoutOrder = 2
	subToolGroups.Sound = {view.addSoundBlock, view.addPaintAudio}
	quickGroups.Sound = {sound.effect, sound.preview, sound.targets,
		sound.attach, sound.follow, sound.paint, view.finishPaint, view.paintBucket}
	put(groups.Sound, {sound.activation, sound.playback, sound.rollOff, sound.filter, sound.origin})
	local materialBar = panel(frame, "TerrainMaterials")
	materialBar.ZIndex = 4
	view.terrainMaterialBar = materialBar
	Skin.metal(materialBar, nil, 0.22)
	local materialChoices = {}
	for _, name in ipairs({"None", "Clear", "Grass", "Mud", "Ice", "Snow", "Pavement", "Water"}) do
		local control = view.surfaceTools[name] or button(materialBar, name, name)
		view.surfaceTools[name] = control
		control.Parent = materialBar
		table.insert(materialChoices, control)
	end
	local materialHeight = 50
	view.startPlacement = button(quick, "PlaceStart", "Place start zone")
	quickGroups.Start = {view.startPlacement}

	local contextPanels, actionGrids, subPanels, subGrids = {}, {}, {}, {}
	local sectionHeaders = {}
	local terrainIcons = {"raise", "lower", "smooth", "flatten", "ravine", "tunnel"}
	local terrainOperations = {view.terrainTools.Raise, view.terrainTools.Lower, view.terrainTools.Smooth,
		view.terrainTools.Flatten, view.surfaceTools["Carve Ravine"], view.surfaceTools.Tunnel}
	local extraTerrain = {view.tunnelNew, view.tunnelNext, view.tunnelDelete}
	quickGroups.Terrain = terrainOperations
	for i, control in ipairs(materialChoices) do
		Skin.button(view, control, if i > 2 then {swatch = i - 2, size = 11} else {size = 12})
	end
	for i, control in ipairs(terrainOperations) do
		if i == 5 then control.Text = "Ravine" end
		Skin.button(view, control, {icon = terrainIcons[i], size = 10})
	end
	local function section(name, suffix, controls)
		local container, grid = flow(view.left)
		container.Name = name .. suffix
		put(container, controls)
		local title = if suffix == "SubTools" then "TOOL OPTIONS" else "OPERATIONS"
		if name == "Terrain" then title = if suffix == "SubTools" then "TERRAIN MATERIALS" else "TERRAIN OPERATIONS" end
		sectionHeaders[container] = Skin.header(view.left, title)
		return container, grid
	end
	for name, controls in pairs(quickGroups) do
		contextPanels[name], actionGrids[name] = section(name, "Actions", controls)
	end
	for name, controls in pairs(subToolGroups) do
		subPanels[name], subGrids[name] = section(name, "SubTools", controls)
	end
	local tunnelPanel = flow(view.left)
	tunnelPanel.Name = "TunnelActions"
	put(tunnelPanel, extraTerrain)
	local tunnelHeader = Skin.header(view.left, "TUNNEL")
	function view:setTunnelControlsVisible(visible)
		tunnelPanel.Visible, tunnelHeader.Visible = visible, visible
	end
	quick:Destroy()

	local menuShield = shield("EditorMenuBackdrop", 5)
	menuShield.BackgroundTransparency = 1
	local dropdowns, dropdownCounts = {}, {}
	local menuNames = {"File", "World", "View", "Test"}
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
		dropdownCounts[name] = #controls
		return window
	end
	view.importMenu = button(toolbar, "ImportMenu", "Import JSON")
	view.terrainVisibility = button(toolbar, "TerrainVisibility", "Hide Terrain")
	view.scaleVisibility = button(toolbar, "ScaleVisibility", "Hide Tank Scale")
	local fileControls = {view.newWorld, view.openWorld}
	if context.royale then table.insert(fileControls, view.openPlayground) end
	view.back.Text = if context.integratedEditor then "Leave Editor" else "Main Menu"
	append(fileControls, view.saveWorld, view.saveAs, view.importMenu, view.export, view.back)
	dropdown("File", fileControls)
	local sensitivityLabel = text(toolbar, "SensitivityHeading", "Camera sensitivity", 24)
	view.focusSelected = button(toolbar, "FocusSelected", "Focus Selected  •  F")
	dropdown("View", {view.terrainVisibility, view.soundVisibility, sensitivityLabel, view.cameraSensitivity,
		view.frameWorld, view.focusSelected, view.scaleVisibility, view.traversability, view.inspect})
	for _, name in ipairs(menuNames) do
		local control = if name == "Test" then view.worlds else button(toolbar, name:gsub(" ", ""), name)
		menuButtons[name] = control
		control.Parent = toolbar
		if name == "Test" then
			control.Text = "Test"
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
		local menuIcons = {File = "folder", World = "world", View = "view", Test = "play"}
		Skin.button(view, control, {icon = menuIcons[name], side = true, dropdown = dropdowns[name] ~= nil, gold = name == "Test", size = 13})
	end

	view.fileMenu = menuButtons.File

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
	Skin.button(view, view.groundMaterial, {dropdown = true})
	local materialPicker = Skin.inset(settingsList, "GroundMaterialChoices")
	materialPicker.LayoutOrder = 8
	materialPicker.Size = UDim2.new(1, -10, 0, 120)
	materialPicker.Visible = false
	make("UIPadding", materialPicker, {
		PaddingLeft = UDim.new(0, 4), PaddingRight = UDim.new(0, 4), PaddingTop = UDim.new(0, 4),
	})
	make("UIGridLayout", materialPicker, {
		CellSize = UDim2.new(0.5, -2, 0, 25), CellPadding = UDim2.fromOffset(4, 4),
		FillDirectionMaxCells = 2, SortOrder = Enum.SortOrder.LayoutOrder,
	})
	view.groundMaterialChoices = {}
	for index, material in ipairs(WorldSettings.GroundMaterials) do
		local caption = if material == "WoodPlanks" then "Wood Planks" else material
		local choice = button(materialPicker, material, caption)
		choice.LayoutOrder = index
		Skin.button(view, choice)
		view.groundMaterialChoices[material] = choice
		view:on(choice.Activated, function() materialPicker.Visible = false end)
	end
	view:on(view.groundMaterial.Activated, function() materialPicker.Visible = not materialPicker.Visible end)
	function view:setGroundMaterial(material)
		local caption = if material == "WoodPlanks" then "Wood Planks" else material
		self.groundMaterial.Text = "Default terrain: " .. caption
		for name, choice in pairs(self.groundMaterialChoices) do Skin.select(choice, name == material) end
	end
	local colorLabel = text(settingsList, "GroundColorLabel", "Ground color (R, G, B)", 22)
	colorLabel.LayoutOrder = 9
	view.groundColor = make("TextBox", settingsList, {Name = "GroundColor", LayoutOrder = 10,
		Size = UDim2.new(1,-8,0,28), Text = "", ClearTextOnFocus = false,
		TextColor3 = cream, BackgroundColor3 = olive, Font = Enum.Font.Code, TextSize = 14})
	view.worldTraction = {}
	for index, material in ipairs({"Grass", "Mud", "Snow", "Ice"}) do
		local label = text(settingsList, material .. "TractionLabel", material .. " traction default (% of pavement)", 22)
		label.LayoutOrder = 9 + 2 * index
		view.worldTraction[material] = make("TextBox", settingsList, {Name = material .. "Traction",
			LayoutOrder = 10 + 2 * index, Size = UDim2.new(1,-8,0,28), Text = "", ClearTextOnFocus = false,
			TextColor3 = cream, BackgroundColor3 = olive, Font = Enum.Font.Code, TextSize = 14})
	end
	local settingsClose = button(settings, "Done", "Done", UDim2.new(1,-16,0,30), UDim2.new(0,8,1,-35))
	settingsList.Size = UDim2.new(1,0,1,-42)
	settings.Size = UDim2.fromScale(0.84,0.85)
	view:on(settingsClose.Activated, function() materialPicker.Visible = false; settingsShield.Visible = false end)
	view:on(menuButtons.World.Activated, function() closeDropdown(); settingsShield.Visible = true end)

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

	view.palette.Parent = view.left
	local catalogHeader = Skin.header(view.left, "ASSET CATALOG")
	Skin.field(view, view.search)
	view.recentAssets.Parent = view.left
	view.assetSelect = button(view.left, "PlaceAsset", "Place Asset")
	view.repeatPlacement.Parent = inspector
	local assetPreview = list(inspector)
	assetPreview.Name = "CatalogPreview"
	view.catalogPreview = assetPreview
	local previewBox = Skin.inset(assetPreview, "Preview")
	Skin.metal(previewBox, nil, 0.36)
	previewBox.Size = UDim2.new(1,-14,0,86)
	local assetDetails = text(assetPreview, "AssetDetails", "", 110)
	assetDetails.AutomaticSize = Enum.AutomaticSize.Y
	assetDetails.TextColor3 = cream
	local function clearPreview()
		for _, child in previewBox:GetChildren() do child:Destroy() end
		table.clear(view.thumbnails)
	end
	function view:showCatalogAsset(item, assets)
		if self.previewedAsset ~= item then
			self.previewedAsset = item
			clearPreview()
			if item then self:thumbnail(previewBox, item, assets) end
		end
		local size = item and item.size
		local dimensions = if size then string.format("\n%.4g × %.4g × %.4g studs", size[1], size[2], size[3]) else ""
		local details = item and (item.loadError or item.collisionWarning)
		assetDetails.Text = if item then item.name.."\n"..item.model..dimensions..(if details then "\n"..details else "") else "Select an asset to preview it."
		self.assetSelect.Interactable = item ~= nil and item.available == true
		self.assetSelect.TextTransparency = if self.assetSelect.Interactable then 0 else 0.5
	end

	local objectMenu = panel(menuShield, "ObjectContextMenu")
	objectMenu.Visible = false
	objectMenu.ZIndex = 3
	view.delete.Parent = objectMenu
	view.delete.Size = UDim2.new(1, 0, 1, 0)
	view.delete.Position = UDim2.fromOffset(0, 0)
	view:on(view.delete.Activated, function() objectMenu.Visible = false; closeDropdown() end)
	view.objectActions = button(inspector, "ObjectActions", "Object actions")
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
		return leaveShield.Visible or settingsShield.Visible or menuShield.Visible or installedModal(self)
	end
	function view:dismissPresentation()
		if leaveShield.Visible then exitAction = nil; leaveShield.Visible = false; return true end
		if materialPicker.Visible then materialPicker.Visible = false; return true end
		if settingsShield.Visible then settingsShield.Visible = false; return true end
		if menuShield.Visible then objectMenu.Visible = false; closeDropdown(); return true end
		return false
	end
	function view:resetPresentation()
		self.previewedAsset = nil
		clearPreview()
		exitAction = nil
		leaveShield.Visible = false
		materialPicker.Visible = false
		settingsShield.Visible = false
		objectMenu.Visible = false
		closeDropdown()
	end

	view.tools.Assets = view.assets
	view.tools.Terrain = view.terrain
	view.tools.StartZones = view.placeStart
	view.tools.Audio = button(view.left, "Audio", "Audio")
	view.tools.Motion = button(view.left, "Motion", "Motion")
	view.tools.Physics = button(view.left, "Physics", "Physics")
	local rail = {
		{view.tools.Select, "select", "Select", "Select / Navigate"}, {view.tools.Assets, "assets", "Assets"},
		{view.tools.Move, "move", "Move"},
		{view.tools.Rotate, "rotate", "Rotate"}, {view.tools.Resize, "resize", "Resize"},
		{view.tools.Scale, "scale", "Scale"},
		{view.tools.Terrain, "terrain", "Terrain"}, {view.tools.Audio, "audio", "Audio"},
		{view.tools.Motion, "motion", "Motion"}, {view.tools.Physics, "physics", "Physics"},
		{view.tools.StartZones, "start", "Starts", "Start Zones"},
	}
	local railHeading = Skin.header(view.left, "EDITOR TOOLS")
	local tooltip = text(view.left, "ToolTooltip", "", 20)
	tooltip.BackgroundTransparency = 0
	tooltip.BackgroundColor3 = dark
	tooltip.TextXAlignment = Enum.TextXAlignment.Center
	tooltip.ZIndex = 3
	tooltip.Visible = false
	local tooltipOwner
	local function bindTooltip(control, caption)
		view:on(control.MouseEnter, function()
			tooltipOwner = control
			tooltip.Text = caption
			tooltip.Visible = true
		end)
		view:on(control.MouseLeave, function()
			if tooltipOwner == control then tooltip.Visible = false end
		end)
	end
	for _, record in ipairs(rail) do
		local control = record[1]
		control.Parent = view.left
		control.Text = record[3]
		Skin.button(view, control, {icon = record[2], rivets = true})
		bindTooltip(control, record[4] or record[3])
	end
	for i, control in ipairs(terrainOperations) do
		bindTooltip(control, ({"Raise", "Lower", "Smooth", "Flatten", "Carve Ravine", "Tunnel"})[i])
	end
	local commands = panel(view.left, "CommonCommands")
	local deleteCommand = button(commands, "Delete", "Delete")
	Skin.metal(commands, nil, 0.45)
	local commandButtons = {view.undo, view.redo, view.duplicate, deleteCommand}
	for index, control in ipairs(commandButtons) do
		local captions = {"Undo", "Redo", "Duplicate", "Delete"}
		bindTooltip(control, captions[index])
		control.Parent = commands
		control.Text = captions[index]
		Skin.button(view, control, {icon = captions[index]:lower(), iconOnly = true})
	end
	view.deleteCommand = deleteCommand

	view.startPlacement.Text = "Place Next Start Zone"
	view.startDetails = text(inspector, "StartZoneDetails", "", 38)

	local shared = list(inspector)
	local gridHeading = text(shared, "GridIncrement", "Grid increment (studs)", 20)
	put(shared, {view.snap, gridHeading, view.grid, view.edgeSnap})
	local brushSettings = list(inspector)
	for index, key in ipairs({"radius", "strength", "falloff"}) do
		local row = panel(brushSettings, key .. "Row")
		row.LayoutOrder = index
		row.Size = UDim2.new(1, -13, 0, 31)
		row.BackgroundTransparency = 1
		local label, field = view.brushLabels[key], view.brushFields[key]
		label.Parent, field.Parent = row, row
		label.Size = UDim2.new(0.63, -5, 1, 0)
		label.TextSize = 12
		field.AnchorPoint = Vector2.new(1, 0)
		field.Position = UDim2.fromScale(1, 0)
		field.Size = UDim2.new(0.37, 0, 0, 26)
	end
	view.grid.PlaceholderText = "Grid increment"
	view.grid.Size = UDim2.new(1,-8,0,28)
	view.frameWorld.Text = "Frame World  •  Home"
	view.pinA.Visible = true
	view.pinB.Visible = true

	view.snapReadout = text(groups.Placement, "SnapReadout", "", 42)
	view.snapReadout.LayoutOrder = 999

	for _, control in ipairs({view.snap, view.edgeSnap, view.repeatPlacement, view.assetSelect, view.recentAssets,
		view.fitButtons.Move, view.fitButtons.Stretch, view.fitButtons.Scale, view.traversability}) do
		Skin.button(view, control)
	end
	for _, axis in ipairs({"Pitch", "Yaw", "Roll"}) do
		Skin.button(view, view.rotationAxes[axis], {icon = "rotate", side = true})
	end
	for _, record in ipairs({{view.addSoundBlock, "audio"}, {view.addPaintAudio, "terrain"},
		{view.spinToggle, "rotate"}, {view.motionDraw, "motion"}, {view.startPlacement, "start"}}) do
		Skin.button(view, record[1], {icon = record[2], side = true})
	end
	for _, group in ipairs({quickGroups, subToolGroups}) do
		for _, buttons in pairs(group) do
			for _, control in ipairs(buttons) do Skin.button(view, control) end
		end
	end
	for _, control in ipairs(extraTerrain) do Skin.button(view, control) end
	for _, control in ipairs({sound.activation, sound.playback, sound.rollOff, sound.filter,
		sound.origin, view.regenerates, view.useWorldTraction, view.paintEntireWorld}) do
		Skin.button(view, control)
	end
	Skin.button(view, view.objectActions, {dropdown = true})
	for _, control in pairs(view.fields) do Skin.field(view, control) end
	for _, control in pairs(view.brushFields) do Skin.field(view, control) end
	for _, control in pairs(view.tunnelFields) do Skin.field(view, control) end
	for _, rows in ipairs({view.soundFields, view.spinFields, view.motionFields, view.waypointFields}) do
		for _, row in pairs(rows) do Skin.field(view, row.field) end
	end
	for _, control in ipairs({view.grid, view.brushTraction, view.assetTraction, view.regenerationDelay, view.cameraSensitivity}) do
		Skin.field(view, control)
	end
	for _, part in ipairs({shared, brushSettings, assetPreview, view.soundRelationships, view.brushPanel}) do
		part.BackgroundTransparency = 1
	end
	for _, group in pairs(groups) do group.BackgroundTransparency = 1 end
	local function layoutInspector(current, showShared, browsing, start)
		local w, h = inspectorWidth, inspectorHeight
		local terrain = current == "Terrain"
		if terrain then h = math.max(0, h - materialHeight) end
		local useTools = terrain or showShared or browsing
		toolsBack.Visible, toolsHeader.Visible = useTools, useTools
		local toolHeight = if not useTools then 0 elseif browsing then 60
			else math.min(if terrain then 138 else 154, math.floor(h * 0.56))
		local insetX, insetWidth = 3, math.max(0, w - 6)
		area(toolsBack, insetX, 2, insetWidth, toolHeight)
		area(toolsHeader, insetX, 2, insetWidth, headerHeight)
		area(shared, 4, 2 + headerHeight, w - 8, toolHeight - headerHeight)
		area(brushSettings, 4, 2 + headerHeight, w - 8, toolHeight - headerHeight)
		area(view.repeatPlacement, 8, 29, w - 16, 26)
		local y = if useTools then toolHeight + 7 else 2
		area(selectionBack, insetX, y, insetWidth, h - y - 3)
		area(selectionHeader, insetX, y, insetWidth, headerHeight)
		local content = y + headerHeight + 4
		area(view.selected, 9, content, w - 18, 34)
		area(view.objectActions, 9, content + 37, w - 18, 25)
		area(view.startDetails, 9, content + 64, w - 18, 39)
		local fieldsTop = content + (if start then 105 else 65)
		for _, group in pairs(groups) do area(group, 4, fieldsTop, w - 8, h - fieldsTop - 4) end
		area(view.soundRelationships, 4, fieldsTop, w - 8, h - fieldsTop - 4)
		area(view.brushPanel, 4, content, w - 8, h - content - 4)
		area(assetPreview, 4, content, w - 8, h - content - 4)
		local toolNames = {StartZones = "START ZONES"}
		local toolName = toolNames[toolMode] or toolMode:upper()
		toolsTitle.Text = if w < 170 then toolName .. " SETTINGS" else "TOOL SETTINGS - " .. toolName
		local contexts = {Placement = "OBJECT", Rotation = "ROTATION", Start = "START ZONES", Sound = "AUDIO", Terrain = "TERRAIN"}
		local propertyContext = contexts[current] or current:upper()
		selectionTitle.Text = if browsing then "ASSET PREVIEW" elseif w < 225 then propertyContext .. " PROPERTIES"
			else "SELECTION PROPERTIES - " .. propertyContext
	end

	function view:setControlSelected(control, selected)
		Skin.select(control, selected)
	end

	function view:setEditorMode(mode)
		toolMode = mode
		tooltip.Visible = false
		for name, button in pairs(self.tools) do Skin.select(button, name == mode) end
		self:applyContext()
	end
	function view:applyContext()
		local current = if toolMode == "Terrain" then "Terrain"
			elseif toolMode == "StartZones" or ((toolMode == "Move" or toolMode == "Select") and selection and selection.slot) then "Start"
			elseif toolMode == "Rotate" then "Rotation"
			elseif toolMode == "Audio" then "Sound"
			elseif toolMode == "Physics" or toolMode == "Motion" then toolMode else "Placement"
		materialBar.Visible = current == "Terrain"
		local browsing = toolMode == "Assets"
		self.palette.Visible = browsing
		self.recentAssets.Visible = browsing
		self.assetSelect.Visible = browsing
		self.repeatPlacement.Visible = browsing
		assetPreview.Visible = browsing
		if not browsing and self.previewedAsset then
			self.previewedAsset = nil
			clearPreview()
		end
		catalogHeader.Visible = browsing
		local selected = selection ~= nil
		local start = current == "Start"
		local fitMode = ({Move="Move",Resize="Stretch",Scale="Scale"})[toolMode]
		local clipboard = toolMode == "Resize" or toolMode == "Scale"
		for name, control in pairs(view.fitButtons) do control.Visible = name == fitMode end
		view.edgeSnap.Visible = fitMode ~= nil
		view.pinA.Visible, view.pinB.Visible, view.releasePin.Visible = fitMode ~= nil, fitMode ~= nil, fitMode ~= nil
		view.copyScale.Visible, view.pasteScale.Visible = clipboard, clipboard
		shared.Visible = not start and (fitMode ~= nil or toolMode == "Rotate")
		brushSettings.Visible = current == "Terrain"
		self.soundRelationships.Visible = current == "Sound" and not (selection and selection.sound)
		view.snapReadout.Visible = not start and fitMode ~= nil
		for name, group in pairs(groups) do
			local objectProperties = selected and name == current and (name ~= "Sound" or selection.sound ~= nil)
			local startProperties = start and name == "Placement" and selected and selection.slot ~= nil
			group.Visible = not browsing and (objectProperties or startProperties)
		end
		for name, controls in pairs(contextPanels) do
			controls.Visible = name == current and not browsing and (selected or name ~= "Physics" and name ~= "Motion")
			if name == "Placement" and fitMode == nil then controls.Visible = false end
			sectionHeaders[controls].Visible = controls.Visible
		end
		for name, controls in pairs(subPanels) do
			controls.Visible = name == current and (selected or name ~= "Motion")
			sectionHeaders[controls].Visible = controls.Visible
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
		self.selected.Visible = not browsing and current ~= "Terrain" and (selected or not start)
		self.objectActions.Visible = not browsing and selected and current ~= "Terrain"
		for _, control in ipairs({self.duplicate, self.deleteCommand}) do
			control.Interactable = selected
			Skin.refresh(control)
		end
		layoutInspector(current, shared.Visible, browsing, start)
		for _, record in ipairs({view.edgeSnap,view.fitButtons.Move,view.fitButtons.Stretch,view.fitButtons.Scale,
			view.pinA,view.pinB,view.releasePin,view.copyScale,view.pasteScale}) do
			record.Interactable = selected
			Skin.refresh(record)
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
			Skin.refresh(control)
		end
	end
	function view:setStartCount(count)
		local caption = string.format("Start Zones (%d/5)", count)
		self.placeStart.Text = string.format("Starts %d/5", count)
		self.startDetails.Text = caption .. "\nPlace on clear ground, 40 studs apart."
	end
	view:on(view.inspect.Activated, function() inspectorOverride = not inspecting; view:layout() end)

	function view:layout()
		local size = frame.AbsoluteSize
		local w, h = size.X, size.Y
		local compact = w < 720
		inspecting = if inspectorOverride == nil then w >= 360 else inspectorOverride
		self.inspect.Text = if inspecting then "Hide Inspector" else "Show Inspector"
		local left = if compact then math.clamp(w * 0.29, 96, 138) else 164
		local right = if inspecting then math.min(if compact then 155 else 248, w * (if compact then 0.34 else 0.26)) else 0
		local top, status = 38, 39

		local center = math.max(0, w - left - right)
		area(toolbar, 0, 0, w, top)
		local offset = 5
		local menuWidth = if compact then math.clamp(math.floor(w * 0.19), 56, 81) else 96
		for _, name in ipairs(menuNames) do
			local control = menuButtons[name]
			local x = if name == "Test" then w - menuWidth - 5 else offset
			area(control, x, 4, menuWidth, 29)
			if dropdowns[name] then
				local count = dropdownCounts[name]
				local dropWidth = math.min(223, w)
				area(dropdowns[name], math.clamp(x, 0, math.max(0, w - dropWidth)), top, dropWidth, math.min(count * 33, h - top))
			end
			offset += menuWidth + 6
		end
		area(self.left, 0, top, left, h - top - status)
		local available = math.max(0, h - top - status)
		local railTop = 18
		area(railHeading, 3, 2, left - 6, 15)
		local row = math.min(48, math.floor(available * 0.43 / 4))
		local column = left / 3
		for index, record in ipairs(rail) do
			local position = index - 1
			area(record[1], 3 + position % 3 * column, railTop + math.floor(position / 3) * row + 2, column - 6, row - 4)
		end
		local stripTop = railTop + row * 4
		area(commands, 0, stripTop, left, 28)
		area(tooltip, 2, stripTop + 28, left - 4, 21)
		for index, control in ipairs(commandButtons) do
			local width = left / #commandButtons
			area(control, (index - 1) * width + 2, 2, width - 4, 23)
		end
		local contextualTop = stripTop + 31
		local contextualHeight = math.max(0, available - contextualTop)
		local subWidth = math.max(0, left - 15)
		local terrainHeight = math.min(92, math.max(34, contextualHeight - materialHeight - 18))
		local function terrainSection(grid)
			grid.CellSize = UDim2.fromOffset(math.floor((subWidth - 8) / 3), math.max(14, math.floor((terrainHeight - 9) / 2)))
		end
		for name, controls in pairs(subPanels) do
			local hasOperations = contextPanels[name] ~= nil
			local availableHeight = if hasOperations then math.floor(contextualHeight * 0.38)
				else math.max(0, contextualHeight - 18)
			local contentHeight = #subToolGroups[name] * 31
			local subHeight = math.min(contentHeight, availableHeight)
			subGrids[name].CellSize = UDim2.fromOffset(subWidth, 27)
			controls.ScrollingDirection = Enum.ScrollingDirection.Y
			controls.ScrollingEnabled = contentHeight > subHeight
			area(sectionHeaders[controls], 3, contextualTop, left - 6, 18)
			area(controls, 0, contextualTop + 18, left, subHeight)
		end
		for name, controls in pairs(contextPanels) do
			local reserved = if subPanels[name] then subPanels[name].Size.Y.Offset + 19 else 0
			local sectionTop = contextualTop + reserved
			area(sectionHeaders[controls], 3, sectionTop, left - 6, 18)
			if name == "Terrain" then
				terrainSection(actionGrids[name])
				area(controls, 0, sectionTop + 18, left, terrainHeight)
				local tailTop = sectionTop + 19 + terrainHeight
				area(tunnelHeader, 3, tailTop, left - 6, 18)
				area(tunnelPanel, 0, tailTop + 18, left, available - tailTop - 18 - materialHeight)
			else
				actionGrids[name].CellSize = UDim2.fromOffset(subWidth, 27)
				area(controls, 0, sectionTop + 18, left, available - sectionTop - 18)
			end
		end
		area(chrome, left, top, center, available)
		area(self.viewport, left + 3, top + 3, center - 6, available - 6)
		inspector.Visible = inspecting
		area(inspector, w - right, top, right, available)
		inspectorWidth, inspectorHeight = right, available
		self.brushPanel.Parent = inspector
		area(materialBar, 0, h - status - materialHeight, w, materialHeight)
		local materialWidth = math.min(102, math.floor((w - 12) / #materialChoices))
		local materialStart = math.floor((w - materialWidth * #materialChoices) / 2)
		for index, control in ipairs(materialChoices) do
			area(control, materialStart + (index - 1) * materialWidth + 2, 4, materialWidth - 4, materialHeight - 8)
		end
		area(footer, 0, h - status, w, status)
		local footerInset = if compact then 30 else 51
		footerHazard.Size = UDim2.fromOffset(footerInset - 11, 32)
		local footerWidth = w - footerInset - 13
		local separateWells = w >= 1000
		local messageWidth = if separateWells then math.floor(footerWidth * 0.54) else footerWidth
		local messageHeight = if separateWells then status - 8 else 19
		local contextX = if separateWells then footerInset + messageWidth + 5 else footerInset
		local contextY = if separateWells then 4 else 23
		local contextWidth = if separateWells then footerWidth - messageWidth - 5 else footerWidth
		local contextHeight = if separateWells then status - 8 else 13
		area(statusWell, footerInset, 4, messageWidth, messageHeight)
		area(hintWell, contextX, contextY, contextWidth, contextHeight)
		self.status.TextSize = 12
		area(statusFlow, 0, 1, messageWidth, messageHeight - 2)
		area(self.status, 6, if separateWells then 6 else 0, messageWidth - 16, 16)
		area(self.hint, 6, if separateWells then 6 else 0, contextWidth - 16, 13)
		self.hint.TextSize = if separateWells then 11 else 10
		area(catalogHeader, 3, contextualTop, left - 6, 18)
		area(self.recentAssets, 3, contextualTop + 21, left - 6, 24)
		area(self.palette, 0, contextualTop + 47, left, available - contextualTop - 76)
		area(self.assetSelect, 3, available - 28, left - 6, 25)
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
