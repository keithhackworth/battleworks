local TweenService = game:GetService("TweenService")
local DogTag = require(script.Parent.DogTag)
local Responsive = require(script.Parent.Parent.Responsive)

local DogTagMenu = {}
local random = Random.new()

function DogTagMenu.new(parent, items, theme, assets, onSelect)
	local seen = {}
	for _, item in ipairs(items) do
		assert(type(item.id) == "string" and item.id ~= "" and not seen[item.id], "Dog tag IDs must be unique")
		seen[item.id] = true
	end

	local root = Instance.new("CanvasGroup")
	root.Name = "DogTagMenu"
	root.BackgroundTransparency = 1
	root.BorderSizePixel = 0
	root.ClipsDescendants = true
	root.Parent = parent

	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "Tags"
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ClipsDescendants = true
	scroll.ScrollingDirection = Enum.ScrollingDirection.Y
	scroll.VerticalScrollBarInset = Enum.ScrollBarInset.Always
	scroll.ScrollBarThickness = theme.metrics.scrollbar
	scroll.ScrollBarImageColor3 = theme.accent
	scroll.CanvasSize = UDim2.fromOffset(0, 0)
	scroll.Parent = root

	local chainAsset = theme.dogTag.chain and assets.get(theme.dogTag.chain)
	local chain, boxLink
	if chainAsset then
		chain = Instance.new("ImageLabel")
		chain.Name = "Chain"
		chain.Image = chainAsset.image
		chain.ScaleType = Enum.ScaleType.Tile
		chain.BackgroundTransparency = 1
		chain.Active = false
		chain.ZIndex = 2
		chain.Parent = root

		boxLink = chain:Clone()
		boxLink.Name = "ParkingBoxChain"
		boxLink.AnchorPoint = Vector2.new(0.5, 0.5)
		boxLink.ZIndex = 1
		boxLink.Visible = false
		boxLink.Parent = parent
	end

	local connectorAsset = chain and theme.dogTag.connector and assets.get(theme.dogTag.connector)
	local updateLinks = {}
	local function addLink(tag)
		local right = Instance.new("ImageLabel")
		right.Name = "TagConnector"
		right.Image = connectorAsset.image
		right.BackgroundTransparency = 1
		right.AnchorPoint = Vector2.new(0.5, 0.55)
		right.ZIndex = 3
		right.Active = false
		right.Parent = root
		local left = right:Clone()
		left.Name = "MirroredTagConnector"
		left.ImageRectOffset = Vector2.new(connectorAsset.width, 0)
		left.ImageRectSize = Vector2.new(-connectorAsset.width, connectorAsset.height)
		left.Parent = root

		local update = tag:observeEyelet(theme.header.tagEyelet, function(eyelet, size)
			local finish = eyelet - root.AbsolutePosition
			local start = chain.AbsoluteSize.X * 0.63
			local length = finish.X - start
			local visible = chain.Visible and size >= 8 and length > 0
				and finish.Y >= 0 and finish.Y <= root.AbsoluteSize.Y
			left.Visible, right.Visible = visible, visible
			if not visible then return end
			local half = length / 2
			local linkHeight = math.min(half * connectorAsset.height / connectorAsset.width, size * 0.32)
			local halfWidth = half + math.min(1, half * 0.25)
			left.Size = UDim2.fromOffset(halfWidth, linkHeight)
			right.Size = left.Size
			left.Position = UDim2.fromOffset(start + halfWidth / 2, finish.Y)
			right.Position = UDim2.fromOffset(finish.X - halfWidth / 2, finish.Y)
		end)
		table.insert(updateLinks, update)
	end


	local images = DogTag.listArtwork(theme, assets)
	local remaining = {}
	local function pickArtwork()
		if #images == 0 then return nil end
		if #remaining == 0 then remaining = table.clone(images) end
		local last = #remaining
		local index = random:NextInteger(1, last)
		local image = remaining[index]
		remaining[index] = remaining[last]
		remaining[last] = nil
		return image
	end
	local retracted = false
	local tags = {}
	local menu = { root = root }
	function menu:setSelected(id)
		local selectedArtwork
		for index, item in ipairs(items) do
			local tag = tags[index]
			local selected = item.id == id
			tag:setSelected(selected)
			if selected then selectedArtwork = tag.artwork end
		end
		return selectedArtwork
	end
	for index, item in ipairs(items) do
		tags[index] = DogTag.new(scroll, item, theme, assets, function()
			if retracted then return end
			if not onSelect or onSelect(item) ~= false then
				menu:setSelected(item.id)
				if item.onSelect then item.onSelect(item) end
			end
		end, pickArtwork())
		if connectorAsset and tags[index].artwork then addLink(tags[index]) end
	end

	local responsiveState, origin, parking, menuSize, boxHook
	local chainWidth = 0
	local rowTops, rowHeights = {}, {}
	local progress = Instance.new("NumberValue")
	progress.Parent = root
	local tween

	local function updatePosition()
		if not origin then return end
		local amount = progress.Value
		local parked = parking - Vector2.new(menuSize.X / 2, (rowHeights[1] or 0) / 2)
		local position = origin:Lerp(parked, amount)
		root.Visible = amount < 1
		root.Position = UDim2.fromOffset(position.X, position.Y)
		root.GroupTransparency = math.clamp((amount - 0.74) / 0.26, 0, 1)
		if boxLink then
			boxLink.Visible = boxHook ~= nil and chainWidth > 0 and amount < 1
			if boxLink.Visible then
				local head = position + Vector2.new(chainWidth / 2, chainWidth * 0.25)
				local delta = head - boxHook
				local midpoint = (head + boxHook) / 2
				boxLink.Position = UDim2.fromOffset(midpoint.X, midpoint.Y)
				boxLink.Size = UDim2.fromOffset(chainWidth, delta.Magnitude)
				boxLink.Rotation = math.deg(math.atan2(-delta.X, delta.Y))
				boxLink.ImageTransparency = root.GroupTransparency
			end
		end
		local lastCenter, lastRestCenter = 0, 0
		for index, tag in ipairs(tags) do
			local top = rowTops[index] or 0
			local rowHeight = rowHeights[index] or 0
			local stacked = math.max(0, ((rowHeights[1] or 0) - rowHeight) / 2) + (index - 1)
			local currentTop = top + (stacked - top) * amount
			tag.row.Position = UDim2.fromOffset(0, currentTop)
			lastCenter = math.max(lastCenter, currentTop + rowHeight / 2)
			lastRestCenter = math.max(lastRestCenter, top + rowHeight / 2)
		end
		if chain then
			local tail = math.max(0, menuSize.Y - lastRestCenter) * (1 - amount)
			local chainHeight = math.min(menuSize.Y, lastCenter + tail)
			chain.Size = UDim2.fromOffset(chainWidth, chainHeight)
		end
	end

	local animated = progress:GetPropertyChangedSignal("Value"):Connect(updatePosition)
	function menu:setRetracted(value, instant)
		if value == retracted and not instant then return end
		retracted = value
		if value then scroll.CanvasPosition = Vector2.zero end
		if tween then tween:Destroy(); tween = nil end
		if instant then
			progress.Value = if value then 1 else 0
			return
		end
		tween = TweenService:Create(progress, TweenInfo.new(0.36, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut), {
			Value = if value then 1 else 0,
		})
		tween:Play()
	end

	local function fitRows()
		if not responsiveState then return end
		local height = scroll.AbsoluteWindowSize.Y
		local tagHeight, factors, gap = Responsive.menu(scroll.AbsoluteSize.X, height, tags, responsiveState, theme)
		local canvasHeight = 0
		for index, tag in ipairs(tags) do
			local rowHeight = math.ceil(tagHeight * factors[index])
			rowTops[index], rowHeights[index] = canvasHeight, rowHeight
			tag:resize(tagHeight, rowHeight)
			canvasHeight += rowHeight
			if index < #tags then canvasHeight += gap end
		end
		updatePosition()
		scroll.CanvasSize = UDim2.fromOffset(0, canvasHeight)
		scroll.ScrollingEnabled = canvasHeight > height
		if not scroll.ScrollingEnabled then scroll.CanvasPosition = Vector2.zero end
		if menu.onTagHeightChanged then menu.onTagHeightChanged(tagHeight) end
	end

	local resized = scroll:GetPropertyChangedSignal("AbsoluteWindowSize"):Connect(fitRows)
	function menu:resize(position, size, state, parkingPoint, hookPoint)
		responsiveState = state
		origin, menuSize = position, size
		parking = parkingPoint or position + Vector2.new(size.X / 2, 0)
		boxHook = hookPoint
		root.Size = UDim2.fromOffset(size.X, size.Y)
		local gutter = 0
		if chain then
			local width = math.min(math.round(chainAsset.width * state.scale), math.floor(size.X * 0.14))
			local tileHeight = math.max(1, math.round(width * chainAsset.height / chainAsset.width))
			chainWidth = width
			chain.Visible = width > 0
			chain.TileSize = UDim2.fromOffset(math.max(1, width), tileHeight)
			boxLink.TileSize = chain.TileSize
			gutter = if connectorAsset then width + math.round(width * 0.2) else math.round(width * 0.75)
		end
		scroll.Position = UDim2.fromOffset(gutter, 0)
		scroll.Size = UDim2.fromOffset(size.X - gutter, size.Y)
		fitRows()
		for _, update in ipairs(updateLinks) do update() end
	end

	function menu:destroy()
		resized:Disconnect()
		animated:Disconnect()
		if tween then tween:Destroy() end
		for _, tag in ipairs(tags) do tag:destroy() end
		if boxLink then boxLink:Destroy() end
		root:Destroy()
	end
	return menu
end

return DogTagMenu
