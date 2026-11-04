-- Radial dead zone, full-scale remapping, circular clamping. Shared by adapters.
local Analog = {}
function Analog.normalize(vector, deadZone)
	deadZone = math.clamp(deadZone, 0, 0.95)
	local magnitude = vector.Magnitude
	if magnitude <= deadZone then return Vector2.zero end
	return vector.Unit * ((math.min(magnitude, 1) - deadZone) / (1 - deadZone))
end
return Analog
