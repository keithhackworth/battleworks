local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local UIAssets = require(Shared:WaitForChild("UIAssets"))
local Router = require(script.Parent.Router)
local Routes = require(script.Parent.Routes)
local Responsive = require(script.Parent.Responsive)
local Theme = require(script.Parent.Theme)
local Standard = require(script.Parent.Layouts.Standard)

local App = {}
App.__index = App

function App.new(parent, options)
	options = options or {}
	local theme = options.theme or Theme
	local assets = options.assets or UIAssets
	local routes = options.routes or Routes
	local layouts = options.layouts or { standard = Standard }
	local pages = options.pages or script.Parent.Parent.Pages

	local gui = Instance.new("ScreenGui")
	gui.Name = "BattleWorksUI"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = options.displayOrder or 20
	gui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	local root = Instance.new("Frame")
	root.Name = "Shell"
	root.BackgroundColor3 = theme.background
	root.BorderSizePixel = 0
	root.Size = UDim2.fromScale(1, 1)
	root.Parent = gui
	gui.Parent = parent

	local resized = Instance.new("BindableEvent")
	local responsive = { current = Responsive.measure(root.AbsoluteSize, theme), changed = resized.Event }
	local instances = {}
	local visibleLayout
	local router

	local function getLayout(name)
		if instances[name] then return instances[name] end
		local factory = assert(layouts[name], "Unknown layout: " .. tostring(name))
		local layout = factory.new(root, {
			assets = assets,
			theme = theme,
			items = routes.items,
			onClose = options.onClose,
			onGameplayView = options.onGameplayView,
			onSelect = function(item)
				local ok, err = router:navigate(item.route)
				if not ok then warn("[BattleWorks UI]", err) end
				return ok
			end,
		})
		layout:resize(responsive.current)
		instances[name] = layout
		return layout
	end

	local function showLayout(layout, page)
		if visibleLayout and visibleLayout ~= layout then
			if visibleLayout.setPlayground then visibleLayout:setPlayground(false) end
			visibleLayout.root.Visible = false
		end
		visibleLayout = layout
		root.BackgroundTransparency = if page.playground then 1 else 0
		if layout.setPlayground then layout:setPlayground(page.playground == true) end
		layout.root.Visible = true
	end

	router = Router.new(pages, { assets = assets, theme = theme, layout = responsive }, getLayout, showLayout, routes.items)
	local watcher = Responsive.observe(root, theme, function(state)
		responsive.current = state
		for _, layout in pairs(instances) do layout:resize(state) end
		resized:Fire(state)
	end)

	local app = setmetatable({
		gui = gui,
		router = router,
		layouts = instances,
		watcher = watcher,
		resized = resized,
	}, App)

	local ok, err = router:navigate(routes.initialRoute)
	if not ok then
		app:destroy()
		error(err, 2)
	end
	return app
end

function App:destroy()
	if self.destroyed then return end
	self.destroyed = true
	self.watcher()
	self.router:destroy()
	for _, layout in pairs(self.layouts) do layout:destroy() end
	self.resized:Destroy()
	self.gui:Destroy()
end

return App
