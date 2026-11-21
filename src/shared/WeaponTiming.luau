-- Hardware durations consumed by simulation and reported to players.
local Timing={}
local MinimumTimerPower=.0001
function Timing.interval(weapon,power)
 if power<=0 then return nil end
 return weapon.Cooldown/(if weapon.Operation=="Heat" then math.max(power,MinimumTimerPower) else power)
end
function Timing.preparation(weapon,power)
 if power<=0 or not weapon.FireWindup then return nil end
 return weapon.FireWindup/math.max(power,MinimumTimerPower)
end
return Timing
