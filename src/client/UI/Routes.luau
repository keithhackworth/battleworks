local function reportSelection(item)
	print(item.id)
end

local items = {
	{ id = "home", text = "Home", route = "home" },
	{ id = "battle", text = "Training Grounds", route = "battle" },
	{ id = "campaign", text = "Campaign", route = "campaign" },
	{ id = "competitions", text = "Competitions", route = "competitions" },
	{ id = "motor_pool", text = "Motor Pool", route = "motor_pool" },
	{ id = "replay_lab", text = "Replay Lab", route = "replay_lab" },
	{ id = "gear", text = "Gear", route = "gear" },
	{ id = "world_editor", text = "World Editor", route = "world_editor" },
}

for _, item in ipairs(items) do
	item.onSelect = reportSelection
	table.freeze(item)
end

return table.freeze({ initialRoute = "home", items = table.freeze(items) })
