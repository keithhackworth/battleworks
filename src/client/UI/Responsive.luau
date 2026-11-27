local GuiService = game:GetService("GuiService")

local Responsive = {}

function Responsive.measure(viewport, theme, topbar, coreTop)
	local metrics = theme.metrics
	local scale = math.clamp(viewport.Y / metrics.referenceHeight, 0.65, 1.3)
	local headerLeft, headerRight, headerTop = 0, viewport.X, 0
	local headerHeight = math.round(metrics.headerHeight * scale)
	local topbarBottom = math.max(coreTop or 0, if topbar then topbar.Max.Y else 0)
	if topbar and topbar.Max.Y > topbar.Min.Y then
		headerHeight = topbar.Max.Y - topbar.Min.Y
		local left = math.clamp(topbar.Min.X, 0, viewport.X)
		local right = math.clamp(topbar.Max.X, left, viewport.X)
		if left > 0 and right - left >= math.min(280 * scale, viewport.X) then
			headerLeft, headerRight, headerTop = left, right, math.max(0, topbar.Min.Y)
		else
			headerTop = topbarBottom
		end
	else
		headerTop = topbarBottom
	end
	return table.freeze({
		viewport = viewport,
		scale = scale,
		headerLeft = headerLeft,
		headerRight = headerRight,
		headerTop = headerTop,
		topbarBottom = topbarBottom,
		headerHeight = math.clamp(headerHeight, 0, math.max(0, viewport.Y - headerTop)),
		navWidth = math.floor(math.min(viewport.X * metrics.navFraction, metrics.navMax * scale)),
	})
end

function Responsive.menu(width, height, tags, state, theme)
	local metrics = theme.metrics
	local preferredGap = math.round(metrics.rowGap * state.scale)
	local maxScale = math.max(theme.dogTag.hoverScale, theme.dogTag.selectedScale)
	local rowFactors = {}
	local totalHeightFactor = 0
	local widthLimit = metrics.maxTagHeight * state.scale
	for index, tag in ipairs(tags) do
		local angle = math.rad(tag.rotation)
		local sine, cosine = math.abs(math.sin(angle)), math.abs(math.cos(angle))
		local widthFactor = (tag.aspect * cosine + sine) * maxScale
		local heightFactor = (tag.aspect * sine + cosine) * maxScale
		rowFactors[index] = heightFactor
		totalHeightFactor += heightFactor
		widthLimit = math.min(widthLimit, (width - metrics.scrollbar) / widthFactor)
	end
	local count = #tags
	if count == 0 then return 0, rowFactors, 0 end

	-- Leave room for per-row pixel rounding and a small clearance at the bottom.
	local budget = math.max(0, math.floor(height) - count - 2)
	local idealHeight = math.min(widthLimit, metrics.minTagHeight * state.scale)
	local gapCount = count - 1
	local gap = if gapCount > 0 then math.clamp(
		math.floor((budget - idealHeight * totalHeightFactor) / gapCount), 0, preferredGap
	) else 0
	local fit = (budget - gap * gapCount) / totalHeightFactor
	return math.max(0, math.min(widthLimit, fit)), rowFactors, gap
end

function Responsive.observe(root, theme, onResize)
	local function resize()
		local device = GuiService:GetInsetArea(Enum.ScreenInsets.DeviceSafeInsets)
		local topbar = GuiService:GetInsetArea(Enum.ScreenInsets.TopbarSafeInsets)
		local core = GuiService:GetInsetArea(Enum.ScreenInsets.CoreUISafeInsets)
		local full = GuiService:GetInsetArea(Enum.ScreenInsets.None)
		local published = GuiService.TopbarInset
		local topLeft, bottomRight = topbar.Min - device.Min, topbar.Max - device.Min
		if published.Max.X > published.Min.X then
			-- TopbarInset is screen-relative; GetInsetArea uses the Core UI origin.
			local deviceLeft = device.Min.X - full.Min.X
			topLeft = Vector2.new(math.max(topLeft.X, published.Min.X - deviceLeft), topLeft.Y)
			bottomRight = Vector2.new(math.min(bottomRight.X, published.Max.X - deviceLeft), bottomRight.Y)
		end
		local relative = Rect.new(topLeft, Vector2.new(math.max(topLeft.X, bottomRight.X), bottomRight.Y))
		onResize(Responsive.measure(root.AbsoluteSize, theme, relative, core.Min.Y - device.Min.Y))
	end
	local size = root:GetPropertyChangedSignal("AbsoluteSize"):Connect(resize)
	local inset = GuiService:GetPropertyChangedSignal("TopbarInset"):Connect(resize)
	resize()
	return function()
		size:Disconnect()
		inset:Disconnect()
	end
end

return Responsive
