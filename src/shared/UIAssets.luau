local data = require(script.Parent.UIAssetData)

local byPath = {}
local images = {}
local directories = {}
local empty = table.freeze({})

for _, record in ipairs(data) do
	local image = table.clone(record)
	image.image = "rbxassetid://" .. image.assetId
	table.freeze(image)
	byPath[image.source] = image

	local parent = ""
	local directory = string.match(image.source, "^(.+)/[^/]+$") or ""
	for segment in string.gmatch(directory, "[^/]+") do
		local child = if parent == "" then segment else parent .. "/" .. segment
		if not directories[parent] then
			directories[parent] = {}
		end
		directories[parent][child] = true
		parent = child
	end

	if not images[parent] then
		images[parent] = {}
	end
	table.insert(images[parent], image)
end

for _, entries in pairs(images) do
	table.freeze(entries)
end

for directory, children in pairs(directories) do
	local paths = {}
	for child in pairs(children) do
		table.insert(paths, child)
	end
	table.sort(paths)
	directories[directory] = table.freeze(paths)
end

local UIAssets = {}

function UIAssets.get(source)
	return byPath[source]
end

function UIAssets.listImages(directory)
	return images[directory or ""] or empty
end

function UIAssets.listDirectories(directory)
	return directories[directory or ""] or empty
end

return table.freeze(UIAssets)
