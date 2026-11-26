local Footlocker = {}

function Footlocker.new(parent, theme, assets)
	local root = Instance.new("Frame")
	root.Name = "Footlocker"
	root.BorderSizePixel = 0
	root.ClipsDescendants = true
	root.BackgroundColor3 = theme.panel
	root.Parent = parent

	local image = assets.listImages(theme.footlocker.artwork)[1]
	local artwork
	if image then
		artwork = Instance.new("ImageLabel")
		artwork.Name = "MetalPanel"
		artwork.BackgroundTransparency = 1
		artwork.Size = UDim2.fromScale(1, 1)
		artwork.Image = image.image
		artwork.ScaleType = Enum.ScaleType.Stretch
		artwork.Parent = root
		root.BackgroundTransparency = 1
	end

	local content = Instance.new("Frame")
	content.Name = "Content"
	content.BackgroundTransparency = 1
	content.Size = UDim2.fromScale(1, 1)
	content.Parent = root
	return root, content, function(visible)
		if artwork then artwork.Visible = visible end
		root.BackgroundTransparency = if visible and not artwork then 0 else 1
	end
end

return Footlocker
