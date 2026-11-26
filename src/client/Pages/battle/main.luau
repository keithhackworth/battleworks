local TrainingGrounds = require(script.Parent.Parent.Parent.UI.TrainingGrounds)

return {
	layout = "standard",
	playground = true,
	mount = function(context)
		local ok, message = TrainingGrounds.enter()
		assert(ok, message)
		context.scope:add(TrainingGrounds.leave)
	end,
	unmount = function(context) end,
}
