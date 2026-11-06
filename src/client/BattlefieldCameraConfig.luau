local TankConfig = require(game.ReplicatedStorage.Shared.TankConfig)
return table.freeze({
	Elevation = 50, -- degrees above ground
	Azimuth = 45, -- overhead CCW from camera on +Z toward +X
	FieldOfView = 40, -- vertical FOV of the competitive battlefield window
	AspectRatio = 16 / 9, -- identical visible window on every device; unused screen is masked
	MaxGroundFootprint = 900, -- maximum distance between any two visible ground corners, studs
	ReferenceWindowHeight = 320, -- fixed pixel budget; viewport resizing never grants extra coverage
	MinTankPixels = 12, -- follow-mode conservative chassis span at reference height
	TankReadableWidth = 6, -- smallest horizontal chassis dimension; keep in sync with TankRenderer
	WholeMapMinTankPixels = 12, -- overview budget for the full tank silhouette at reference height
	TankSilhouetteWidth = 8, -- conservative span including tracks (9.3 wide, 8.6 long)
	Margin = 8, -- expand small-map framing by this many studs on every edge
	HeightAllowance = 8, -- also frame objects up to this Y above the ground
	MinZoom = 45, -- preferred minimum camera-to-focus distance, studs
	MaxZoom = 135, -- maximum distance; readability/footprint limits may reduce it
	DefaultZoom = 135, -- follow distance before caps (larger distance shows more ground)
	SnapDistance = 40, -- raw snapshot teleport threshold; also snap on dead -> alive
	TankViewInset = 0.20, -- central 20%: screen coordinates 40% through 60% on each axis
	MapCenter = Vector3.new(0, 0, 0),
	MapSize = Vector2.new(TankConfig.ArenaLimit * 2, TankConfig.ArenaLimit * 2),
	MapYaw = 0, -- degrees, Roblox yaw convention; metadata must match any future arena
})
