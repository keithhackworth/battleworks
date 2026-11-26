local Components = script.Parent.Parent.Components
local DogTagMenu = require(Components.DogTagMenu)
local Footlocker = require(Components.Footlocker)
local Header = require(Components.Header)

local Standard = {}

function Standard.new(parent, options, spacing)
	spacing = spacing or {}
	local margin = spacing.margin or 0
	local headerGap = math.clamp(spacing.headerGap or 2, 0, 4)
	local columnGap = spacing.columnGap or 4
	local root = Instance.new("Frame")
	root.Name = "Standard"
	root.BackgroundTransparency = 1
	root.Size = UDim2.fromScale(1, 1)
	root.Visible = false
	root.Parent = parent

	local header = Header.new(root, options.theme, options.assets, options.onClose)
	local menu = DogTagMenu.new(root, options.items, options.theme, options.assets, options.onSelect)
	local panel, content, setSurfaceVisible = Footlocker.new(root, options.theme, options.assets)
	local layout = { root = root, content = content, toolbar = header.toolbar }

	local toggle = Instance.new("TextButton")
	toggle.Name = "ToggleDogTags"
	toggle.Font = options.theme.font
	toggle.TextSize = 14
	toggle.TextColor3 = options.theme.text
	toggle.BackgroundColor3 = options.theme.panel
	toggle.BorderSizePixel = 0
	toggle.ZIndex = 5
	toggle.Parent = root
	local boxAsset = options.assets.get("branding/menu_box2.png")
	if boxAsset then
		toggle.BackgroundTransparency = 1
		toggle.AutoButtonColor = false
		local artwork = Instance.new("ImageLabel")
		artwork.Name = "MenuBox"
		artwork.Image = boxAsset.image
		artwork.BackgroundTransparency = 1
		artwork.Size = UDim2.fromScale(1, 1)
		artwork.ScaleType = Enum.ScaleType.Fit
		artwork.Parent = toggle
	end

	local playground, expanded = false, true
	local lastState
	local function update()
		header.root.Visible = not playground or expanded
		toggle.Text = if boxAsset then "" elseif expanded then "Hide Menu" else "Menu"
		setSurfaceVisible(not playground)
		menu:setRetracted(not expanded)
		if lastState then layout:resize(lastState) end
		if options.onGameplayView then options.onGameplayView(playground and not expanded) end
	end
	local toggled = toggle.Activated:Connect(function()
		expanded = not expanded
		update()
	end)
	update()
	function layout:setPlayground(value)
		if playground == value then return end
		playground = value
		expanded = not value
		update()
	end

	function layout:resize(state)
		lastState = state
		local width = math.max(0, state.viewport.X - 2 * margin)
		local navWidth = math.min(state.navWidth, width)
		local toggleWidth = navWidth
		local toggleHeight = if boxAsset then toggleWidth * boxAsset.height / boxAsset.width else 29
		local visibleToggleTop = state.topbarBottom + 1
		-- The visible lid starts below the transparent band in menu_box2.png.
		local topPadding = if boxAsset then toggleHeight * (91 / 896) else 0
		local toggleTop = visibleToggleTop - topPadding
		toggle.Position = UDim2.fromOffset(margin, toggleTop)
		toggle.Size = UDim2.fromOffset(toggleWidth, toggleHeight)

		local headerLeft = state.headerLeft
		if state.headerTop + state.headerHeight > visibleToggleTop then
			headerLeft = math.max(headerLeft, margin + toggleWidth + columnGap)
		end
		local headerWidth = math.max(0, state.headerRight - headerLeft)
		header.root.Position = UDim2.fromOffset(headerLeft, state.headerTop)
		header.root.Size = UDim2.fromOffset(headerWidth, state.headerHeight)

		local top = state.headerTop + state.headerHeight + headerGap
		local menuTop = math.max(top, toggleTop + toggleHeight)
		local parking = Vector2.new(margin + toggleWidth / 2, toggleTop + toggleHeight * 0.49)
		local boxHook = if boxAsset then Vector2.new(margin + toggleWidth * 0.105, toggleTop + toggleHeight * 0.88) else nil
		menu.onTagHeightChanged = function(tagHeight)
			local headerHeight = header:resize(headerWidth, state.headerHeight, state.scale, tagHeight)
			local panelTop = state.headerTop + headerHeight + headerGap
			local panelLeft = margin + navWidth + columnGap
			panel.Position = UDim2.fromOffset(panelLeft, panelTop)
			panel.Size = UDim2.fromOffset(math.max(0, width - navWidth - columnGap),
				math.max(0, state.viewport.Y - panelTop - margin))
		end
		local menuHeight = math.max(0, state.viewport.Y - menuTop - margin)
		menu:resize(Vector2.new(margin, menuTop), Vector2.new(navWidth, menuHeight), state, parking, boxHook)
	end

	function layout:setSelected(id)
		header:setTagArtwork(menu:setSelected(id))
		if lastState then layout:resize(lastState) end
	end
	function layout:setHeader(content)
		header:setContent(content)
		if lastState then layout:resize(lastState) end
	end
	function layout:destroy()
		toggled:Disconnect()
		menu:destroy()
		header:destroy()
		root:Destroy()
	end
	return layout
end

return Standard
