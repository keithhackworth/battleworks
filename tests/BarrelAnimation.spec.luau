local Animation = require("BarrelAnimation")
local count = 0
local function check(ok,message) assert(ok,message); count += 1 end
check(math.abs(Animation.Duration - 0.22 * 1.2) < 1e-6,"effect takes twenty percent longer")
local rest = Animation.sample(nil)
check(not rest.active and rest.barrelScale == 1 and rest.opacity == 0 and rest.flare == 0,"idle barrel has exact base shape")
local lastZ, peak, peakFlare, bounce = 0,0,0,false
for frame = 0,66 do
	local age = frame * Animation.Duration / 66
	local state = Animation.sample(age)
	if state.active then
		check(state.z <= lastZ+1e-6 and state.z >= -6.75001,"rounded bulge travels only toward muzzle")
		lastZ = state.z
		check(state.barrelScale > 0 and state.bulge >= 1.8 and state.opacity >= 0 and state.opacity <= 1,
			"deformation remains bounded")
		peak = math.max(peak,state.bulge); peakFlare = math.max(peakFlare,state.flare)
		bounce = bounce or state.barrelScale < 1
		if age < 0.15 * 1.2 then check(state.flare == 0,"muzzle flares only as bulge arrives") end
	end
end
check(peak > 4.5 and peakFlare > 0.99 and bounce,"exaggerated swell, muzzle flare and elastic undershoot")
for _, age in {Animation.Duration,1,100} do
	local state = Animation.sample(age)
	check(not state.active and state.barrelScale == 1 and state.opacity == 0 and state.flare == 0,"completion/long frame restores original shape")
end
for _ = 1,20 do
	local start = Animation.sample(0)
	local mid = Animation.sample(0.1)
	check(start.barrelScale == 1 and mid.bulge == Animation.sample(0.1).bulge,"repeated firing restarts from base without cumulative scale")
end
print(string.format("Barrel animation suite passed: %d assertions",count))
