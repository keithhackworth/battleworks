-- Stateless cosmetic sampling: every value is derived from the base shape.
local Animation = { Duration = 0.264 }
function Animation.sample(age)
	if age == nil or age < 0 or age >= Animation.Duration then
		return { active = false, z = -2.7, bulge = 1.8, opacity = 0, flare = 0, barrelScale = 1 }
	end
	-- Stretch every phase together so bulge, flare and bounce stay synchronized.
	age /= 1.2
	local travel = math.clamp(age / 0.17,0,1)
	local progress = travel * travel * (3 - 2 * travel)
	local swell = math.sin(math.pi * math.clamp(age / 0.205,0,1))
	local finish = math.clamp((age - 0.15) / 0.07,0,1)
	return { active = true, z = -2.7 - 4.05 * progress,
		bulge = 1.8 + 2.8 * swell, opacity = swell,
		flare = math.sin(math.pi * finish) ^ 2,
		barrelScale = 1 + 0.15 * math.sin(finish * math.pi * 4) * math.exp(-finish * 4) }
end
return Animation
