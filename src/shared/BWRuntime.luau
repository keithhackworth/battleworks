-- One nonblocking instruction at a time, driven only by authoritative state/ticks.
local Limits=require(script.Parent.BWConfig)
local Adapter=require(script.Parent.BWTankAdapter)
local Command=require(script.Parent.InputCommand)
local Runtime={}
Runtime.__index=Runtime
function Runtime.new(instructions,state)
	return setmetatable({instructions=instructions,index=1,status="running",message="Running",elapsed=0,
		generation=state.generation or 0,tankType=state.tankType or "Boomer"},Runtime)
end
function Runtime:stop(reason,status)
	self.status=status or "stopped"; self.message=reason or "Stopped"
end
function Runtime:fail(message)
	local instruction=if self.current then self.current.instruction else self.instructions[self.index]
	local line=if instruction then instruction.line else 1
	self:stop(string.format("Line %d: %s",line,message),"error")
end
function Runtime:finish()
	self.index+=1; self.current=nil
	if self.index>#self.instructions then
		self:stop(if (self.skipped or 0)>0 then string.format("Program completed (%d skipped).",self.skipped) else "Program completed.","completed")
	end
	return Command.neutral() -- a release tick between every pair of instructions
end
-- Best effort applies only to a failed instruction, never lifecycle/global safety.
function Runtime:instructionFailed(message)
	local instruction=self.current.instruction
	if instruction.bestEffort==false then self:fail(message); return Command.neutral() end
	self.skipped=(self.skipped or 0)+1
	self.warning=string.format("Line %d skipped: %s",instruction.line,message)
	self.releaseSerial=(self.releaseSerial or 0)+1
	local command=self:finish()
	if self.status=="running" then self.message="Skipped an instruction; continuing." end
	return command
end
local function begin(instruction,state)
	local c={instruction=instruction,elapsed=0,held=0,noProgress=0,progress=0,best=0,
		startPosition=state.position,startHeading=state.yaw,lastPosition=state.position,
		startActivation=state.weaponActivationSerial or 0,startShot=state.weaponShotSerial or 0}
	local op=instruction.op
	if op=="forward" or op=="back" then
		c.kind="move"; c.sign=if op=="forward" then 1 else -1
		c.axis=Vector3.new(-math.sin(state.yaw)*c.sign,0,-math.cos(state.yaw)*c.sign)
		c.target=instruction.value; c.timeout=math.min(Limits.MaxInstructionSeconds,math.max(10,c.target/18*4+5))
	elseif op=="fire" then c.kind="fire"; c.timeout=Limits.MaxFireSeconds+5
	else
		c.kind="turn"; c.turret=op:find("turret",1,true)==1
		c.lastAngle=Adapter.angle(state,c.turret); c.startHeading=c.lastAngle
		c.sign,c.target=Adapter.rotation(instruction,c.lastAngle)
		c.timeout=math.min(Limits.MaxInstructionSeconds,math.max(12,c.target/0.6*3+5))
	end
	return c
end
function Runtime:step(state,dt)
	if self.status~="running" then return Command.neutral() end
	if state.health<=0 then self:stop("Tank destroyed."); return Command.neutral() end
	if (state.generation or 0)~=self.generation or (state.tankType or "Boomer")~=self.tankType then
		self:stop("Tank changed or respawned."); return Command.neutral()
	end
	self.elapsed+=dt
	if self.elapsed>Limits.MaxProgramSeconds then self:fail("Program exceeded 180 simulated seconds."); return Command.neutral() end
	if not self.current then
		local instruction=self.instructions[self.index]
		if not instruction then self:stop("Program completed.","completed"); return Command.neutral() end
		self.current=begin(instruction,state)
	end
	local c=self.current
	c.elapsed+=dt
	if c.elapsed>c.timeout then return self:instructionFailed("Instruction timed out.") end
	if c.kind=="fire" then
		local accepted=(state.weaponActivationSerial or 0)-c.startActivation
		local released=(state.weaponShotSerial or 0)-c.startShot
		local command=Command.neutral()
		if c.instruction.value==nil then
			if accepted==0 then command.fire=true; self.message="Waiting for weapon activation"
			elseif released==0 then self.message="Waiting for prepared shot"
			else return self:finish() end
		elseif c.held<c.instruction.value-1e-7 then
			command.fire=true; c.held+=dt
			self.message=string.format("Firing %.2f / %.2f seconds",math.min(c.held,c.instruction.value),c.instruction.value)
		elseif released<accepted then self.message="Waiting for prepared shot"
		else return self:finish() end
		return command
	end
	if c.kind=="move" then
		local delta=state.position-c.startPosition
		c.progress=delta.X*c.axis.X+delta.Z*c.axis.Z
	else
		local angle=Adapter.angle(state,c.turret)
		c.progress+=Adapter.delta(c.lastAngle,angle)*c.sign
		c.lastAngle=angle
	end
	local remaining=c.target-c.progress
	local tolerance=if c.kind=="move" then Limits.DistanceTolerance else Limits.AngleTolerance
	if remaining<=tolerance then return self:finish() end
	local meaningful=if c.kind=="move" then Limits.ProgressDistance else Limits.ProgressAngle
	if c.progress>c.best+meaningful then c.best=c.progress; c.noProgress=0 else c.noProgress+=dt end
	if c.noProgress>Limits.StuckSeconds then
		return self:instructionFailed("No progress for 3 seconds; tank may be blocked or unable to turn.")
	end
	self.message=if c.kind=="move" then string.format("Moved %.2f / %.2f studs",c.progress,c.target)
		else string.format("Turned %.1f / %.1f degrees",math.deg(c.progress),math.deg(c.target))
	if c.kind=="move" then return Adapter.move(state,c.sign,remaining,dt) end
	return Adapter.turn(state,c.sign,remaining,c.turret,dt)
end
return Runtime
