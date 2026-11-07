-- Server-only ownership and lifecycle glue around the pure BW runtime.
local Shared=game.ReplicatedStorage.Shared
local Parser=require(Shared.BWParser)
local Runtime=require(Shared.BWRuntime)
local Command=require(Shared.InputCommand)
local Controller={}
local function cleanup(tank)
	tank.command=Command.neutral(); tank.tickCommand=Command.neutral(); tank.lastInput=0
	tank.pendingShot=nil; tank.rattlerShot=false; tank.state.firing=false
	if tank.rattler then tank.rattler.firing=false end
	tank.requireFireRelease=true
end
function Controller.sync(tank)
	local runtime=tank.bw
	tank.state.bwRequestId=tank.lastBWRequest or 0
	if not runtime then return end
	local instruction=runtime.instructions[runtime.index]
	tank.state.bwRunning=runtime.status=="running"
	tank.state.bwWarning=runtime.warning or ""; tank.state.bwSkipped=runtime.skipped or 0
	tank.state.bwStatus=runtime.status; tank.state.bwMessage=runtime.message
	tank.state.bwIndex=runtime.index; tank.state.bwCount=#runtime.instructions
	tank.state.bwLine=if instruction then instruction.line else 0
	tank.state.bwInstruction=if instruction then instruction.text else ""
end
function Controller.running(tank) return tank.bw~=nil and tank.bw.status=="running" end
function Controller.stop(tank,reason)
	if not Controller.running(tank) then return false end
	tank.bw:stop(reason or "Stopped by player.")
	cleanup(tank); Controller.sync(tank)
	return true
end
function Controller.reject(tank,message,line)
	Controller.stop(tank,"Program rejected."); cleanup(tank)
	tank.bw=nil; tank.state.bwRunning=false; tank.state.bwStatus="error"
	tank.state.bwRequestId=tank.lastBWRequest or 0
	tank.state.bwWarning=""; tank.state.bwSkipped=0
	tank.state.bwLine=line or 0; tank.state.bwMessage=message
	tank.state.bwInstruction=""; tank.state.bwIndex=0; tank.state.bwCount=0
	return false
end
function Controller.start(tank,source)
	tank.state.bwRequestId=tank.lastBWRequest or 0
	Controller.stop(tank,"Replaced by a new program.")
	cleanup(tank)
	local instructions,err=Parser.parse(source)
	if not instructions or tank.state.health<=0 then
		return Controller.reject(tank,if err then err.message else "Tank is destroyed; wait for respawn.",if err then err.line else 0)
	end
	tank.bw=Runtime.new(instructions,tank.state)
	tank.requireFireRelease=false
	Controller.sync(tank)
	return true
end
function Controller.input(tank,dt)
	if not Controller.running(tank) then return nil end
	local release=tank.bw.releaseSerial or 0
	local command=tank.bw:step(tank.state,dt)
	if tank.bw.status~="running" then cleanup(tank)
	elseif (tank.bw.releaseSerial or 0)~=release then
		cleanup(tank) -- cancel abandoned preparation/held inputs on the skip tick
		tank.requireFireRelease=false -- BW retains ownership of the next instruction
	end
	Controller.sync(tank)
	return command
end
return Controller
