local PageScope = require(script.Parent.PageScope)
local Router = {}
Router.__index = Router

local function findEntry(pages, route)
	local entry = pages:FindFirstChild(route)
	if entry and entry:IsA("Folder") then entry = entry:FindFirstChild("main") end
	if entry and entry:IsA("ModuleScript") then return entry end
	return nil
end

local function dispose(record)
	if not record or record.disposed then return end
	record.disposed = true
	if record.mountStarted then
		local ok, err = pcall(record.page.unmount, record.context)
		if not ok then warn("[BattleWorks UI] Page unmount failed:", err) end
	end
	record.context.scope:destroy()
end

function Router.new(pages, context, getLayout, showLayout, items)
	local menuByRoute = {}
	for _, item in ipairs(items) do
		assert(type(item.route) == "string" and item.route ~= "", "Menu items must specify a route")
		assert(not menuByRoute[item.route], "Only one menu item can represent each route")
		menuByRoute[item.route] = item
	end
	return setmetatable({
		pages = pages,
		context = context,
		getLayout = getLayout,
		showLayout = showLayout,
		menuByRoute = menuByRoute,
	}, Router)
end

function Router:current()
	return self.active and self.active.context.route
end

function Router:navigate(route, params)
	if self.closed then return false, "Router is closed" end
	if self.navigating then return false, "A page transition is already in progress" end
	if type(route) ~= "string" or route == "" then return false, "Expected a route name" end
	if self:current() == route and params == nil then return true end
	local entry = findEntry(self.pages, route)
	if not entry then return false, "Unknown route: " .. route end

	self.navigating = true
	local candidate
	local ok, result = pcall(function()
		local page = require(entry)
		assert(type(page) == "table" and type(page.mount) == "function" and type(page.unmount) == "function",
			"Page must export mount and unmount")
		assert(not self.closed, "Router is closed")
		local layout = self.getLayout(page.layout or "standard")
		local content = Instance.new("Frame")
		content.Name = route
		content.BackgroundTransparency = 1
		content.Size = UDim2.fromScale(1, 1)
		content.Visible = false

		local context = table.clone(self.context)
		context.router = self
		context.route = route
		context.params = params
		context.content = content
		context.scope = PageScope.new()
		context.scope:add(content)
		candidate = { page = page, context = context, mountStarted = true }
		self.pending = candidate
		content.Parent = layout.content
		page.mount(context)
		assert(not self.closed, "Router is closed")

		local menu = self.menuByRoute[route]
		local heading = page.title or (menu and menu.text)
		layout:setHeader({ title = self.context.theme.header.title, pageTitle = heading })
		layout:setSelected(menu and menu.id)
		dispose(self.active)
		assert(not self.closed, "Router is closed")
		self.active = candidate
		content.Visible = true
		self.showLayout(layout, page)
	end)
	self.pending = nil
	if not ok then dispose(candidate) end
	self.navigating = false
	if not ok then return false, tostring(result) end
	return true
end

function Router:destroy()
	if self.closed then return end
	self.closed = true
	dispose(self.pending)
	dispose(self.active)
	self.active = nil
end

return Router
