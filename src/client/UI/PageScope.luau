local PageScope = {}
PageScope.__index = PageScope

local function cleanup(resource)
	local kind = typeof(resource)
	if kind == "RBXScriptConnection" then
		resource:Disconnect()
	elseif kind == "Instance" then
		if resource:IsA("AnimationTrack") then resource:Stop(0) end
		if resource:IsA("TweenBase") then resource:Cancel() end
		resource:Destroy()
	else
		resource()
	end
end

local function safelyClean(resource)
	local ok, err = pcall(cleanup, resource)
	if not ok then warn("[BattleWorks UI] Page cleanup failed:", err) end
end

function PageScope.new()
	return setmetatable({ resources = {}, closed = false }, PageScope)
end

function PageScope:add(resource)
	local kind = typeof(resource)
	assert(kind == "Instance" or kind == "RBXScriptConnection" or kind == "function", "Unsupported page resource")
	if self.closed then
		safelyClean(resource)
	else
		table.insert(self.resources, resource)
	end
	return resource
end

function PageScope:destroy()
	if self.closed then return end
	self.closed = true
	for index = #self.resources, 1, -1 do
		safelyClean(self.resources[index])
	end
	table.clear(self.resources)
end

return PageScope
