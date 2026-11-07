-- Actual turret displacement, not invisible projectile spread. Server applies each
-- kick after launching a round; snapshots render these same recovering offsets.
local Definitions = require(script.Parent.TankDefinitions)
local Aim = {}
function Aim.step(state, dt)
	local Config = Definitions.get(state.tankType).Aim
	local recovery = math.exp(-Config.Recovery*math.max(dt,0))
	state.aimRecoilYaw = math.clamp(state.aimRecoilYaw or 0,-Config.MaxYaw,Config.MaxYaw)*recovery
	state.aimRecoilPitch = math.clamp(state.aimRecoilPitch or 0,-Config.MaxPitch,Config.MaxPitch)*recovery
end
local function random(weapon)
	weapon.aimSeed = ((weapon.aimSeed or 1)*48271)%2147483647
	return weapon.aimSeed/2147483647
end
local function displaced(value, sample, kick, limit)
	local sign = if sample < 0.5 then -1 else 1
	local amount = sign*kick*(0.5+math.abs(sample-0.5))
	-- At an edge, bounce inward instead of repeatedly sticking on the clamp.
	if math.abs(value+amount)>limit then amount = -amount end
	return math.clamp(value+amount,-limit,limit)
end
function Aim.kick(state, weapon)
	if state.health <= 0 then return end
	local Config = Definitions.get(state.tankType).Aim
	local scale = if state.tankType == "Rattler" then 1+math.clamp((weapon.heat or 0)/3,0,1)*0.4 else 1
	state.aimRecoilYaw = displaced(state.aimRecoilYaw or 0,random(weapon),Config.YawKick*scale,Config.MaxYaw)
	state.aimRecoilPitch = displaced(state.aimRecoilPitch or 0,random(weapon),Config.PitchKick*scale,Config.MaxPitch)
end
return Aim
