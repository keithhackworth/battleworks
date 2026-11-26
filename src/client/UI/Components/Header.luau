local DogTag = require(script.Parent.DogTag)
local Header = {}

function Header.new(parent, theme, assets, onClose)
	local root = Instance.new("Frame")
	root.Name = "Header"
	root.BackgroundTransparency = 1
	root.Parent = parent

	local chainAsset = theme.dogTag.chain and assets.get(theme.dogTag.chain)
	local chain
	if chainAsset then
		chain = Instance.new("ImageLabel")
		chain.Name = "LogoChain"
		chain.Image = chainAsset.image
		chain.ScaleType = Enum.ScaleType.Tile
		chain.BackgroundTransparency = 1
		chain.AnchorPoint = Vector2.new(0.5, 0.5)
		chain.Rotation = 90
		chain.Active = false
		chain.Visible = false
		chain.Parent = root
	end

	local connectorAsset = theme.dogTag.connector and assets.get(theme.dogTag.connector)
	local connector, mirroredConnector
	if connectorAsset then
		connector = Instance.new("ImageLabel")
		connector.Name = "ChainConnector"
		connector.Image = connectorAsset.image
		connector.ScaleType = Enum.ScaleType.Stretch
		connector.BackgroundTransparency = 1
		connector.AnchorPoint = Vector2.new(0.5, 0.5)
		connector.Active = false
		connector.Visible = false
		connector.ZIndex = 2
		connector.Parent = root

		mirroredConnector = connector:Clone()
		mirroredConnector.Name = "MirroredChainConnector"
		mirroredConnector.ImageRectOffset = Vector2.new(connectorAsset.width, 0)
		mirroredConnector.ImageRectSize = Vector2.new(-connectorAsset.width, connectorAsset.height)
		mirroredConnector.Parent = root
	end

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.BackgroundTransparency = 1
	title.Font = theme.font
	title.TextColor3 = theme.text
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextScaled = true
	title.TextTruncate = Enum.TextTruncate.AtEnd
	title.Parent = root
	local limit = Instance.new("UITextSizeConstraint")
	limit.MaxTextSize = 30
	limit.Parent = title

	local logoAsset = theme.header.logo and assets.get(theme.header.logo)
	local logo
	if logoAsset then
		logo = Instance.new("ImageLabel")
		logo.Name = "Logo"
		logo.Image = logoAsset.image
		logo.ScaleType = Enum.ScaleType.Fit
		logo.BackgroundTransparency = 1
		logo.Parent = root
	end

	local artwork = DogTag.listArtwork(theme, assets)
	local pageTag = DogTag.new(root, { id = "PageTag", text = "", menuProportions = true }, theme, assets, nil, artwork[1])
	pageTag.row.Visible = false
	title.Visible = not logo

	local close
	local connection
	if onClose then
		close = Instance.new("TextButton")
		close.Name = "Close"
		close.Text = "Close"
		close.Font = theme.font
		close.TextColor3 = theme.text
		close.TextSize = 14
		close.BackgroundColor3 = theme.panel
		close.BorderSizePixel = 0
		close.Parent = root
		connection = close.Activated:Connect(onClose)
	end

	local toolbar = Instance.new("Frame")
	toolbar.Name = "Toolbar"
	toolbar.BackgroundTransparency = 1
	toolbar.ClipsDescendants = true
	toolbar.Parent = root

	local header = { root = root, toolbar = toolbar }
	local lastWidth, lastHeight, lastScale, lastTagHeight
	function header:setContent(content)
		local pageTitle = content.pageTitle or ""
		title.Text = content.title
		pageTag:setText(pageTitle)
		pageTag.row.Visible = pageTitle ~= ""
		if lastWidth then header:resize(lastWidth, lastHeight, lastScale, lastTagHeight) end
	end
	function header:setTagArtwork(image)
		pageTag:setArtwork(image or artwork[1])
		if lastWidth then header:resize(lastWidth, lastHeight, lastScale, lastTagHeight) end
	end
	function header:resize(width, height, scale, menuTagHeight)
		lastWidth, lastHeight, lastScale, lastTagHeight = width, height, scale, menuTagHeight
		local closeWidth = if close then math.min(math.round(74 * scale), math.floor(width / 3)) else 0
		local available = math.max(0, width - closeWidth)
		local toolbarWidth = math.clamp(toolbar:GetAttribute("PreferredWidth") or 0, 0, math.floor(available / 2))
		toolbar.Position = UDim2.fromOffset(available - toolbarWidth, 0)
		toolbar.Size = UDim2.fromOffset(toolbarWidth, height)
		available -= toolbarWidth

		local tagVisible = pageTag.row.Visible
		local hasConnector = (connector ~= nil or chain ~= nil) and logo ~= nil and tagVisible
		local gap = if hasConnector then math.min(math.round(height * 0.34), available * 0.1) else 4
		local desiredTagHeight = menuTagHeight or height
		local tagSpace = if tagVisible then math.min(desiredTagHeight * pageTag.aspect + gap, available * 0.72) else 0
		local brandSpace = available - tagSpace
		local brandWidth, logoHeight
		if logo then
			local aspect = logoAsset.width / logoAsset.height
			logoHeight = math.min(height, brandSpace / aspect)
			brandWidth = logoHeight * aspect
			logo.AnchorPoint = Vector2.new(0, 0.5)
			logo.Position = UDim2.fromScale(0, 0.5)
			logo.Size = UDim2.fromOffset(brandWidth, logoHeight)
		else
			brandWidth = math.min(math.round(155 * scale), brandSpace)
			title.Size = UDim2.fromOffset(brandWidth, height)
		end
		local tagLeft = math.min(available, brandWidth + gap)
		local tagHeight = math.min(desiredTagHeight, (available - tagLeft) / pageTag.aspect)
		local tagRowHeight = math.max(height, tagHeight)
		pageTag.row.Position = UDim2.fromOffset(tagLeft, 0)
		pageTag:resize(tagHeight, tagRowHeight)
		pageTag.row.Size = UDim2.fromOffset(tagHeight * pageTag.aspect, tagRowHeight)
		local showLink = hasConnector and tagHeight >= 8
		if connector then
			connector.Visible = showLink
			mirroredConnector.Visible = showLink
		end
		if chain then chain.Visible = showLink and not connector end
		if showLink then
			local logoEyelet, tagEyelet = theme.header.logoEyelet, theme.header.tagEyelet
			local start = Vector2.new(brandWidth * logoEyelet.X, height / 2 + logoHeight * (logoEyelet.Y - 0.5))
			local finish = Vector2.new(tagLeft + tagHeight * pageTag.aspect * tagEyelet.X, tagRowHeight / 2 + tagHeight * (tagEyelet.Y - 0.5))
			local delta = finish - start
			local midpoint = (start + finish) / 2
			local angle = math.deg(math.atan2(delta.Y, delta.X))
			if connector then
				local halfWidth = delta.Magnitude / 2
				local halfHeight = halfWidth * connectorAsset.height / connectorAsset.width
				local rightCenter = midpoint + delta / 4
				local leftCenter = midpoint - delta / 4
				local halfSize = UDim2.fromOffset(halfWidth, halfHeight)
				connector.Position = UDim2.fromOffset(rightCenter.X, rightCenter.Y)
				connector.Rotation = angle
				connector.Size = halfSize
				mirroredConnector.Position = UDim2.fromOffset(leftCenter.X, leftCenter.Y)
				mirroredConnector.Rotation = angle
				mirroredConnector.Size = halfSize
			elseif chain then
				local thickness = math.max(1, math.round(tagHeight * 0.22))
				chain.Position = UDim2.fromOffset(midpoint.X, midpoint.Y)
				chain.Rotation = angle + 90
				chain.Size = UDim2.fromOffset(thickness, delta.Magnitude)
				chain.TileSize = UDim2.fromOffset(thickness, math.round(thickness * chainAsset.height / chainAsset.width))
			end
		end
		if close then
			close.AnchorPoint = Vector2.new(1, 0.5)
			close.Position = UDim2.fromScale(1, 0.5)
			close.Size = UDim2.fromOffset(closeWidth, math.min(34, height))
		end
		return if tagVisible then tagRowHeight else height
	end
	local toolbarChanged = toolbar:GetAttributeChangedSignal("PreferredWidth"):Connect(function()
		if lastWidth then header:resize(lastWidth, lastHeight, lastScale, lastTagHeight) end
	end)
	function header:destroy()
		toolbarChanged:Disconnect()
		pageTag:destroy()
		if connection then connection:Disconnect() end
		root:Destroy()
	end
	return header
end

return Header
