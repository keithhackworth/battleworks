local TrainingGrounds = {}
local admission, departure, showHome

function TrainingGrounds.register(enter, leave)
	admission, departure = enter, leave
end

function TrainingGrounds.enter()
	if not admission then return false, "The Playground is available in Battle Royale mode." end
	return admission()
end

function TrainingGrounds.leave()
	if departure then departure() end
end

function TrainingGrounds.setHomeHandler(handler)
	showHome = handler
end

function TrainingGrounds.openHome()
	return showHome and showHome() == true
end

return TrainingGrounds
