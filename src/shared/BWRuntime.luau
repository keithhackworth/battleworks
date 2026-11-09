-- One nonblocking instruction at a time, driven only by authoritative state/ticks.
local Expression=require(script.Parent.BWExpression)
local Commands=require(script.Parent.BWCommands)
local Value=require(script.Parent.BWValue)
local ScannerConfig=require(script.Parent.ScannerConfig)
local DamageConfig=require(script.Parent.DamageEffectsConfig)
local Limits=require(script.Parent.BWConfig)
local Adapter=require(script.Parent.BWTankAdapter)
local Command=require(script.Parent.InputCommand)
local Runtime={}
Runtime.__index=Runtime
function Runtime.new(instructions,state,services)
	return setmetatable({services=services or {},variables={},cycleCounts={},outputCount=0,results={},cyclesSpent=0,instructions=instructions,index=1,status="running",message="Running",elapsed=0,
		generation=state.generation or 0,tankType=state.tankType or "Boomer"},Runtime)
end
function Runtime:stop(reason,status)
	self.status=status or "stopped"; self.message=reason or "Stopped"
	if self.status~="completed" then self.variables={} end
end
function Runtime:fail(message,lineOverride)
	local instruction=if self.current then self.current.instruction else self.instructions[self.index]
	local line=lineOverride or (if instruction then instruction.line else 1)
	self:stop(string.format("Line %d: %s",line,message),"error")
end
function Runtime:finish(target)
	self.index=target or self.index+1; self.current=nil
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
function Runtime:charge(category,cost)
	cost=cost or Limits.CycleCosts[category] or 0
	self.cycleCounts[category]=(self.cycleCounts[category] or 0)+1
	self.cyclesSpent+=cost
	if self.services.chargeCycles then self.services.chargeCycles(cost,category) end
end
function Runtime:scan(angle,bestEffort,line,inExpression)
	self:charge("call"); self:charge("scanner",ScannerConfig.ScannerCost)
	if #self.results>=Limits.MaxScannerCalls then Commands.error(line,"Program exceeded the maximum scanner observations.") end
	local observation,err
	if self.services.scan then observation,err=self.services.scan(angle) else err="Scanner is unavailable in this environment." end
	if not observation then error({bwError=true,scanFailure=true,expression=inExpression,bestEffort=bestEffort,line=line,message=err or "Scanner failed."},0) end
	self.lastValue=observation.value; self.lastObservation=observation
	table.insert(self.results,observation); self.outputCount+=1
	if self.outputCount>Limits.MaxOutputEvents then Commands.error(line,"Program output limit exceeded.") end
	if self.services.onValue then self.services.onValue(observation,line,angle) end
	return observation.value
end
function Runtime:evaluate(expression)
	return Expression.evaluate(expression,{
		variables=self.variables,
		charge=function(category) self:charge(category) end,
		scan=function(angle,bestEffort,line) return self:scan(angle,bestEffort,line,true) end,
	})
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
	elseif op=="Scanner" then c.kind="scan"; c.timeout=1
	elseif op=="fire" then c.kind="fire"; c.timeout=Limits.MaxFireSeconds+5
	else
		c.kind="turn"; c.turret=op:find("turret",1,true)==1
		c.lastAngle=Adapter.angle(state,c.turret); c.startHeading=c.lastAngle
		c.sign,c.target=Adapter.rotation(instruction,c.lastAngle)
		c.timeout=math.min(Limits.MaxInstructionSeconds,math.max(12,c.target/0.6*3+5))
	end
	return c
end
function Runtime:_step(state,dt)
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
		self.current={instruction=instruction} -- errors retain the reached source line
		local op=instruction.op
		if op=="$jump" then return self:finish(instruction.target) end
		if op=="$while" then
            self:charge("branch")
            return self:finish(if Expression.truthy(self:evaluate(instruction.condition)) then self.index+1 else instruction.target)
        elseif op=="$branch" then
			self:charge("branch")
			local condition=Expression.boolean(self:evaluate(instruction.condition),instruction.line)
			return self:finish(if condition then self.index+1 else instruction.target)
		elseif op=="$switch" then
			self:charge("branch")
			local value=self:evaluate(instruction.expression)
			local target=instruction.target
			for _,choice in instruction.choices do self:charge("comparison"); if Value.equal(value,choice.value) then target=choice.target; break end end
			return self:finish(target)
		elseif op=="$assign" then
			local value=self:evaluate(instruction.expression)
			if self.variables[instruction.name]==nil then
				local count=0; for _ in self.variables do count+=1 end
				if count>=Limits.MaxVariables then Commands.error(instruction.line,"Too many program variables.") end
			end
			self:charge("write"); self.variables[instruction.name]=value
			self.message="Assigned "..instruction.name
			return self:finish()
		elseif op=="$print" then
			self:charge("call")
			local value=self:evaluate(instruction.expression)
			self.outputCount+=1; if self.outputCount>Limits.MaxOutputEvents then Commands.error(instruction.line,"Program output limit exceeded.") end
			if self.services.onPrint then self.services.onPrint(Value.display(value),instruction.line) end
			self.message="Printed value."
			return self:finish()
		end
		if instruction.call then
			instruction=Commands.resolve(instruction.call,function(expr) return self:evaluate(expr) end)
			self.current.instruction=instruction
		end
		if instruction.op~="Scanner" then self:charge("call") end
		self.current=begin(instruction,state)
	end
	local c=self.current
	local immobilized=state.immobilized and (c.kind=="move" or (c.kind=="turn" and not c.turret))
	local paused=if immobilized then math.min(dt,math.max(0,DamageConfig.MaxBWPausePerInstruction-(c.pauseUsed or 0))) else 0
	c.pauseUsed=(c.pauseUsed or 0)+paused
	c.elapsed+=dt-paused
	if c.elapsed>c.timeout then return self:instructionFailed("Instruction timed out.") end
	if c.kind=="scan" then
		self:scan(c.instruction.value,c.instruction.bestEffort,c.instruction.line)
		return self:finish()
	end
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
        if self.services.followSteering then
            -- Actual signed travel along the changing chassis-forward tangent.
            -- Excludes lateral drift; unlike a start-axis projection this can
            -- complete a long arc or full circle without losing progress.
            local delta=state.position-c.lastPosition
            local heading=c.startHeading+Adapter.delta(c.startHeading,state.yaw)*0.5
            c.progress+=(delta.X*(-math.sin(heading))+delta.Z*(-math.cos(heading)))*c.sign
            c.lastPosition=state.position; c.startHeading=state.yaw
        else
            local delta=state.position-c.startPosition
            c.progress=delta.X*c.axis.X+delta.Z*c.axis.Z
        end
	else
		local angle=Adapter.angle(state,c.turret)
		c.progress+=Adapter.delta(c.lastAngle,angle)*c.sign
		c.lastAngle=angle
	end
	local remaining=c.target-c.progress
	local tolerance=if c.kind=="move" then Limits.DistanceTolerance else Limits.AngleTolerance
	if remaining<=tolerance then return self:finish() end
	local meaningful=if c.kind=="move" then Limits.ProgressDistance else Limits.ProgressAngle
	if c.progress>c.best+meaningful then c.best=c.progress; c.noProgress=0 else c.noProgress+=dt-paused end
	if c.noProgress>Limits.StuckSeconds then
		return self:instructionFailed("No progress for 3 seconds; tank may be blocked or unable to turn.")
	end
	self.message=if c.kind=="move" then string.format("Moved %.2f / %.2f studs",c.progress,c.target)
		else string.format("Turned %.1f / %.1f degrees",math.deg(c.progress),math.deg(c.target))
	if immobilized then self.message="Temporarily immobilized; retaining movement target."; return Command.neutral() end
	if c.kind=="move" then return Adapter.move(state,c.sign,remaining,dt) end
	return Adapter.turn(state,c.sign,remaining,c.turret,dt)
end
function Runtime:step(state,dt)
	local ok,command=pcall(self._step,self,state,dt)
	if ok then return command end
	local err=command
	if type(err)=="table" and err.bwError then
		if err.scanFailure and not err.expression and err.bestEffort and self.current and self.current.instruction.bestEffort~=false then return self:instructionFailed(err.message) end
		self:fail(err.message,err.line)
	else self:fail("Internal device error: "..tostring(err)) end
	return Command.neutral()
end
return Runtime
