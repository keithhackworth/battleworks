-- A driver-only sweep. This never feeds BW values, output logs or CPU accounting.
local Config=require(game.ReplicatedStorage.Shared.ScannerConfig)
local Components=require(game.ReplicatedStorage.Shared.VehicleComponents)
local Geometry=require(game.ReplicatedStorage.Shared.ScannerGeometry)
local Manual={}
local function priority(event)
	return if event.kind=="tank" then (if event.affiliation=="enemy" then 4 else 3) elseif (event.kind=="wall" or event.kind=="object") then 2 else 1
end
function Manual.record(tank,angle,event)
	local state=tank.state
	state.scanManual=state.scanManual or {}
	local key=tostring(Geometry.sensorIndex(angle))
	local old=state.scanManual[key]
	-- At most one recent warning per physical lens. A neighboring empty cone
	-- must not immediately erase a real enemy; rechecking its own angle can.
	if not old or old.angle==angle or priority(event)>priority(old)
		or (priority(event)==priority(old) and event.proximity>=old.proximity) then state.scanManual[key]=event end
end
function Manual.step(tank,enabled,time,dt,scan,publish)
	local state=tank.state
	state.manualScannerActive=enabled and state.health>0
	if not state.manualScannerActive then
		state.scanManual=nil; tank.manualSensors=nil
		return false
	end
	for key,event in state.scanManual or {} do
		event.remaining=math.max(0,event.remaining-dt)
		if event.remaining==0 then state.scanManual[key]=nil end
	end
	tank.manualSensors=tank.manualSensors or {}
	local completed=false
	local hardware=Components.get(state).Sensors
	for index=1,Config.SensorCount do
        local installed=hardware[(index-1)*45]; if not installed then continue end
		local sensor=tank.manualSensors[index]
		if not sensor then sensor={nextTime=time,phase=0}; tank.manualSensors[index]=sensor end
		if time<sensor.nextTime-1e-8 then continue end
		sensor.nextTime=math.max(sensor.nextTime+Config.ManualSensorInterval,time+installed.Cooldown)
		local offset=if sensor.phase==0 then 0 elseif sensor.phase==1 then Config.ManualStep else -Config.ManualStep
		local angle=((index-1)*360/Config.SensorCount+offset)%360
		local observation=scan(angle)
		sensor.phase=(sensor.phase+1)%3
		if observation then publish(angle,observation); completed=true end
	end
	return completed
end
return Manual
