local TextService = game:GetService("TextService")
local TweenService = game:GetService("TweenService")
local slide = TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local DogTag = {}

function DogTag.listArtwork(theme, assets)
	local style = theme.dogTag
	local images = {}
	for _, image in ipairs(assets.listImages(style.artwork)) do
		if image.source ~= style.chain and image.source ~= style.connector and not image.name:match("^chain") then
			table.insert(images, image)
		end
	end
	return images
end

function DogTag.new(parent, item, theme, assets, activated, image)
	local style = theme.dogTag
	local enabled = item.enabled ~= false
	local widthScale = if activated or item.menuProportions then style.menuWidthScale or 1 else 1

	local row = Instance.new("Frame")
	row.Name = item.id
	row.BackgroundTransparency = 1
	row.Parent = parent

	local button = Instance.new("TextButton")
	button.Name = "Tag"
	button.Text = ""
	button.AnchorPoint = Vector2.new(0.5, 0.5)
	button.Position = UDim2.fromScale(0.5, 0.5)
	button.Rotation = item.rotation or 0
	button.AutoButtonColor = false
	button.Interactable = enabled and activated ~= nil
	button.Selectable = button.Interactable
	button.BackgroundColor3 = theme.steel
	button.BorderSizePixel = 0
	button.Parent = row

	local round = Instance.new("UICorner")
	round.CornerRadius = UDim.new(0.4, 0)
	round.Parent = button

	local artwork = Instance.new("ImageLabel")
	artwork.Name = "Artwork"
	artwork.Size = UDim2.fromScale(1, 1)
	artwork.BackgroundTransparency = 1
	artwork.ScaleType = if widthScale == 1 then Enum.ScaleType.Fit else Enum.ScaleType.Stretch
	artwork.ImageTransparency = if enabled then 0 else 0.45
	artwork.Parent = button

	local icon = item.icon and assets.get(item.icon)
	local textInset = if activated or item.menuProportions then 0.155 else 0.18
	local textStart = if icon then 0.29 else textInset
	local textWidth = 1 - textInset - textStart
	local lettering = Instance.new("Frame")
	lettering.Name = "Lettering"
	lettering.AnchorPoint = Vector2.new(0.5, 0.5)
	lettering.Rotation = button.Rotation
	lettering.Active = false
	lettering.BackgroundTransparency = 1
	lettering.ZIndex = 2
	lettering.Parent = row
	local letteringScale = Instance.new("UIScale")
	letteringScale.Parent = lettering
	local function makeText(name, color, transparency, offset, zIndex)
		local label = Instance.new("TextLabel")
		label.Name = name
		label.Text = item.text
		label.Font = theme.font
		label.TextColor3 = color
		label.TextTransparency = transparency
		label.TextWrapped = false
		label.BackgroundTransparency = 1
		label.Position = UDim2.fromOffset(0, offset - 2)
		label.Size = UDim2.fromScale(1, 1)
		label.ZIndex = zIndex
		label.Parent = lettering
		return label
	end

	-- The highlight below the dark lettering is the light-catching edge of the cut.
	local edge = makeText("EngravingEdge", style.engravingEdge, if enabled then 0.4 else 0.75, 1, 2)
	local label = makeText("Label", style.engraving, if enabled then 0.06 else 0.5, 0, 3)

	local textFitBounds = Vector2.new(4096, 4096)
	local fittedWidth, fittedHeight, fittedText
	local function fitText(width, height)
		if width == fittedWidth and height == fittedHeight and label.Text == fittedText then return end
		fittedWidth, fittedHeight, fittedText = width, height, label.Text
		local size = math.clamp(math.floor(height * 0.54), 1, 25)
		while size > 1 do
			local bounds = TextService:GetTextSize(fittedText, size, label.Font, textFitBounds)
			if bounds.X <= width * textWidth - 1 and bounds.Y <= height * 0.54 then break end
			size -= 1
		end
		label.TextSize, edge.TextSize = size, size
	end

	if icon then
		local glyph = Instance.new("ImageLabel")
		glyph.Name = "Icon"
		glyph.Size = UDim2.fromScale(0.1, 0.38)
		glyph.Position = UDim2.fromScale(0.18, 0.31)
		glyph.BackgroundTransparency = 1
		glyph.Image = icon.image
		glyph.ScaleType = Enum.ScaleType.Fit
		glyph.Parent = button
	end

	local scale = Instance.new("UIScale")
	scale.Parent = button

	local hovered, selected = false, false
	local targetScale = 1
	local scaleTween, letteringTween
	local function stopTweens()
		if scaleTween then scaleTween:Destroy() end
		if letteringTween then letteringTween:Destroy() end
	end
	local function move()
		local size = if selected then style.selectedScale elseif hovered then style.hoverScale else 1
		if size == targetScale then return end
		targetScale = size
		stopTweens()
		-- Both layers use the same scale without refitting the label mid-tween.
		scaleTween = TweenService:Create(scale, slide, { Scale = size })
		letteringTween = TweenService:Create(letteringScale, slide, { Scale = size })
		scaleTween:Play()
		letteringTween:Play()
	end

	-- The row stays still so the moving tag cannot repeatedly exit its own hover area.
	local connections = if activated then {
		button.Activated:Connect(function()
			if enabled then activated() end
		end),
		row.MouseEnter:Connect(function()
			hovered = enabled
			move()
		end),
		row.MouseLeave:Connect(function()
			hovered = false
			move()
		end),
	} else {}

	local tag = { row = row, rotation = button.Rotation }
	function tag:observeEyelet(point, onMove)
		local function update()
			local size = button.AbsoluteSize
			local center = button.AbsolutePosition + size / 2
			local offset = size * (point - Vector2.new(0.5, 0.5))
			local angle = math.rad(button.Rotation)
			local sine, cosine = math.sin(angle), math.cos(angle)
			local rotated = Vector2.new(offset.X * cosine - offset.Y * sine, offset.X * sine + offset.Y * cosine)
			onMove(center + rotated, size.Y)
		end
		table.insert(connections, button:GetPropertyChangedSignal("AbsoluteSize"):Connect(update))
		table.insert(connections, button:GetPropertyChangedSignal("AbsolutePosition"):Connect(update))
		return update
	end
	function tag:setArtwork(asset)
		self.artwork = asset
		self.aspect = (if asset then asset.width / asset.height else style.fallbackAspect) * widthScale
		artwork.Image = if asset then asset.image else ""
		button.BackgroundTransparency = if asset then 1 elseif enabled then 0 else 0.4
	end
	tag:setArtwork(image)
	function tag:setText(text)
		label.Text = text
		edge.Text = text
		if fittedHeight then fitText(fittedWidth, fittedHeight) end
	end
	function tag:setSelected(isSelected)
		selected = isSelected
		move()
	end
	function tag:resize(height, rowHeight)
		local width = height * self.aspect
		button.Size = UDim2.fromOffset(width, height)
		local textCenter = width * (textStart + textWidth / 2 - 0.5)
		local angle = math.rad(button.Rotation)
		lettering.Position = UDim2.new(0.5, textCenter * math.cos(angle), 0.5, textCenter * math.sin(angle))
		lettering.Size = UDim2.fromOffset(width * textWidth, height * 0.54)
		fitText(width, height)
		row.Size = UDim2.new(1, 0, 0, rowHeight)
	end
	function tag:destroy()
		for _, connection in ipairs(connections) do connection:Disconnect() end
		stopTweens()
		row:Destroy()
	end
	return tag
end

return DogTag
