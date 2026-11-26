local Theme = {
	font = Enum.Font.GothamBold,
	background = Color3.fromRGB(25, 27, 23),
	panel = Color3.fromRGB(65, 66, 38),
	steel = Color3.fromRGB(163, 151, 132),
	ink = Color3.fromRGB(28, 25, 20),
	text = Color3.fromRGB(239, 233, 219),
	accent = Color3.fromRGB(247, 183, 79),
	dogTag = table.freeze({
		artwork = "dogtags",
		chain = "dogtags/chain2.png",
		connector = "dogtags/chain_connector2.png",
		hoverScale = 1.04,
		selectedScale = 1.09,
		engraving = Color3.fromRGB(32, 27, 21),
		engravingEdge = Color3.fromRGB(218, 201, 171),
		fallbackAspect = 8 / 3,
		menuWidthScale = 1.334,
	}),
	footlocker = table.freeze({ artwork = "footlockers/olive/panels" }),
	header = table.freeze({
		title = "BattleWorks",
		logo = "branding/logo3.png",
		logoEyelet = Vector2.new(0.951, 0.448),
		tagEyelet = Vector2.new(0.114, 0.50),
	}),
	metrics = table.freeze({
		referenceHeight = 800,
		navFraction = 0.28,
		navMax = 345,
		minTagHeight = 24,
		maxTagHeight = 104,
		rowGap = 1,
		headerHeight = 44,
		scrollbar = 4,
	}),
}

return table.freeze(Theme)
