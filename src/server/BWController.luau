-- Server-only ownership and lifecycle glue around the pure BW runtime.
local Shared=game.ReplicatedStorage.Shared
local Parser=require(Shared.BWParser)
local profileBegin=debug.profilebegin or function()end
local profileEnd=debug.profileend or function()end
local Limits=require(Shared.BWConfig)
local Runtime=require(Shared.BWExecution)
local Hardware=require(Shared.BWChassis)
local Components=require(Shared.VehicleComponents)
local Command=require(Shared.InputCommand)
local Controller={}
function Controller.disarm(tank)
 tank.pendingShot=nil;tank.rattlerShot=false;tank.state.firing=false
 tank.state.weaponPreparationRemaining=nil;tank.requireFireRelease=true
 if tank.rattler then tank.rattler.firing=false end
end
local function cleanup(tank)
	tank.command=Command.neutral(); tank.tickCommand=Command.neutral(); tank.lastInput=0
	Controller.disarm(tank)
end
Controller.clearInputs=cleanup
function Controller.suspendInputs(tank)
	-- Park an accepted cannon preparation with its executor. Resuming can
	-- release that same round, while stopping the program still cancels it.
	local pending,requireRelease=tank.pendingShot,tank.requireFireRelease
	cleanup(tank)
	tank.pendingShot=pending
	tank.state.weaponPreparationRemaining=pending and pending.remaining
	tank.requireFireRelease=requireRelease
end
function Controller.sync(tank)
	local runtime=tank.bw
	tank.state.bwRequestId=tank.lastBWRequest or 0
	tank.state.bwRunRequestId=tank.bwRunRequestId or 0
	if not runtime then return end
	local instruction=runtime.instructions[runtime.index]
	tank.state.bwRunning=runtime.status=="running"
	tank.state.bwWarning=runtime.warning or ""; tank.state.bwSkipped=runtime.skipped or 0
	tank.state.bwStatus=runtime.status; tank.state.bwMessage=runtime.message
	tank.state.bwIndex=runtime.index; tank.state.bwCount=#runtime.instructions
	tank.state.bwLine=runtime.currentLine or (if instruction then instruction.line else 0)
	tank.state.bwInstruction=runtime.currentText or (if instruction then instruction.text else "")
end
function Controller.running(tank) return tank.bw~=nil and tank.bw.status=="running" end
function Controller.stop(tank,reason)
	if not Controller.running(tank) then if tank.bw then tank.bw.variables={}; tank.bw.versions={}; tank.bw.results={}; tank.bw.lastObservation=nil; tank.bw.lastValue=nil end; return false end
	tank.bw:stop(reason or "Stopped by player.")
	cleanup(tank); Controller.sync(tank)
	return true
end
function Controller.reject(tank,message,line)
	tank.bwRunRequestId=tank.lastBWRequest or 0; tank.state.bwRunRequestId=tank.bwRunRequestId
	Controller.stop(tank,"Program rejected."); cleanup(tank)
	tank.bw=nil; tank.state.bwRunning=false; tank.state.bwStatus="error"
	tank.state.bwRequestId=tank.lastBWRequest or 0
	tank.state.bwWarning=""; tank.state.bwSkipped=0
	tank.state.bwLine=line or 0; tank.state.bwMessage=message
	tank.state.bwInstruction=""; tank.state.bwIndex=0; tank.state.bwCount=0
	return false
end
function Controller.start(tank,source)
 tank.state.bwProgramSerial=(tank.state.bwProgramSerial or 0)+1
	if tank.state.manualScannerActive then tank.sensorScanTimes=nil end -- hand off immediately to explicit BW
	tank.state.manualScannerActive=false; tank.state.scanManual=nil; tank.state.scanVisual=nil; tank.state.scanBW=nil
	tank.bwRunRequestId=tank.lastBWRequest or 0; tank.state.bwRunRequestId=tank.bwRunRequestId
	tank.state.bwRequestId=tank.lastBWRequest or 0
	Controller.stop(tank,"Replaced by a new program.")
	cleanup(tank)
	tank.bwSource=if type(source)=="string"and#source<=Limits.MaxSourceBytes then source else nil
	profileBegin("BattleWorks.BWParse")
	local instructions,err=Parser.parse(source)
	profileEnd()
	if not instructions or tank.state.health<=0 then
		return Controller.reject(tank,if err then err.message else "Tank is destroyed; reset the battle.",if err then err.line else 0)
	end
	tank.bwSource=source
	tank.hardware=tank.hardware or Hardware.forTank(tank.state)
 Controller.applyHardware(tank)
 tank.bw=Runtime.new(instructions,tank.state,tank.bwServices,tank.hardware)
	tank.requireFireRelease=false
	Controller.sync(tank)
	return tank.bw.status=="running"
end
function Controller.applyHardware(tank)
 tank.hardware=tank.hardware or Hardware.forTank(tank.state)
 Components.withComputer(tank.state,tank.hardware.tier)
 local devices=tank.hardware.devices
 local profile=Components.get(tank.state)
 for name,field in {drivetrain="drivePerformance",turret="turretPerformance"} do
  tank.state[field]=if devices[name] then Hardware.effective(tank.hardware,name,profile) else 0
 end
 tank.state.weaponPerformance,tank.state.weaponWindupPerformance,tank.state.projectileSpeed=Hardware.weaponStats(tank.hardware,profile)
 tank.scannerPower=nil
 if tank.hardware.allocations then
  for angle in profile.Sensors do
   tank.scannerPower=Hardware.effective(tank.hardware,"sensor"..angle,profile)
   break
  end
 end
end
function Controller.configure(tank,configuration)
 if Controller.running(tank) then return false,"programRunning" end
 if type(configuration)=="table" and (configuration.allocations or configuration.tuning or tank.hardware and tank.hardware.allocations) then return false,"Use the Garage to configure this bus." end
 local valid,reason=Hardware.validate(configuration); if not valid then return false,reason end
 local installed=Hardware.default(configuration.tier,Components.get(tank.state))
 local accepted={tier=configuration.tier,devices={}}
 for name,requested in configuration.devices do
  local device=installed.devices[name]
  if not device then return false,"deviceUnavailable" end
  device.bus=requested.bus;device.allocation=requested.allocation
  accepted.devices[name]=device
 end
 tank.hardware=accepted; Controller.applyHardware(tank); return true
end
function Controller.input(tank,dt)
	if not Controller.running(tank) then return nil end
	profileBegin("BattleWorks.BWRuntime")
	local release=tank.bw.releaseSerial or 0
	local command=tank.bw:step(tank.state,dt)
	if tank.bw.status~="running" then cleanup(tank)
	elseif (tank.bw.releaseSerial or 0)~=release then
		cleanup(tank) -- cancel abandoned preparation/held inputs on the skip tick
		tank.requireFireRelease=false -- BW retains ownership of the next instruction
	end
	Controller.sync(tank)
	profileEnd()
	return command
end
return Controller
