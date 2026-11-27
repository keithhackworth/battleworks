local WorldEditorAccess = require(script.Parent.Parent.Parent.UI.WorldEditorAccess)

return {
	layout = "standard",
	editor = true,
	mount = function(context)
		local ok, message = WorldEditorAccess.open(context.content)
		assert(ok, message)
		context.scope:add(WorldEditorAccess.close)
	end,
	unmount = function() end,
}
