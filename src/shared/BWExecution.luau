-- Deterministic cooperative BW virtual CPU. Coroutines are resumable AST evaluation,
-- never Roblox tasks: only this scheduler resumes them in ascending bus order.
local Hardware=require(script.Parent.BWChassis)
local Limits=require(script.Parent.BWConfig)
local Expression=require(script.Parent.BWExpression)
local Commands=require(script.Parent.BWCommands)
local Value=require(script.Parent.BWValue)
local Devices=require(script.Parent.BWDevices)
local Input=require(script.Parent.InputCommand)
local Adapter=require(script.Parent.BWTankAdapter)
local R={}; R.__index=R
-- Only side-effect-free display expressions are waived. An expression that
-- can drive a device or synchronize/query gameplay keeps its normal costs, so
-- print(condition and fire().status == "success") is not a free control path.
local function debugOnly(n)
 if n.kind=="call" then
  if n.name~="print" and n.name~="get_clock" then return false end
  for _,arg in n.args do if not debugOnly(arg.expression) then return false end end
 elseif n.kind=="binary" then return debugOnly(n.left) and debugOnly(n.right)
 elseif n.kind=="unary" then return debugOnly(n.operand)
 elseif n.kind=="group" then return debugOnly(n.expression)
 elseif n.kind=="index" then return debugOnly(n.array) and debugOnly(n.index)
 elseif n.kind=="array" then for _,item in n.items do if not debugOnly(item) then return false end end
 elseif n.kind=="dictionary" then for _,entry in n.entries do if not debugOnly(entry.expression) then return false end end end
 return true
end
function R.new(instructions,state,services,configuration)
 local config=Hardware.copy(configuration or Hardware.forTank(state)); local valid,reason=Hardware.validate(config); assert(valid,reason)
 local self=setmetatable({instructions=instructions,index=1,services=services or {},config=config,variables={},versions={},threads={},results={},cyclesSpent=0,
  status="running",message="Running",elapsed=0,time=0,cycle=-1,generation=state.generation or 0,tankType=state.tankType or "Boomer",outputCount=0,scanCount=0},R)
 self.devices=Devices.new(config,state,self.services)
 local spec=Hardware.Tiers[config.tier]
 for id,stream in instructions.streams or {[1]=instructions} do
  if id>spec.threads then self.status="error"; self.message="Thread "..id.." exceeds "..config.tier.." chassis capacity."; break end
  self.threads[id]={id=id,instructions=stream,index=1,state="running",credit=0,ticks=0,observed={}}
 end
 return self
end
function R:stop(reason,status)
 self.status=status or "stopped"; self.message=reason or "Stopped"
 self.devices:stop(self.time,if self.status=="stopped" then "commandCancelled" else "tankDestroyed")
 for _,t in self.threads do if t.state~="finished" then t.state="finished" end; t.coroutine=nil; t.pending=nil end
 if self.status~="completed" then self.variables={}; self.versions={} end
end
function R:log(t,text,line,kind,observation,angle)
 if kind=="print" then self.printCount=(self.printCount or 0)+1; t.prints=(t.prints or 0)+1 end
 self.outputCount+=1 -- total attempted output; retained UI history is bounded separately
 self.cycleLogCount=self.cycleLogCount or 0
 if self.cycleLogCount>=Limits.MaxLogEventsPerCycle-1 then
  self.suppressedLogs=(self.suppressedLogs or 0)+1
  if self.cycleLogCount<Limits.MaxLogEventsPerCycle then
   self.cycleLogCount+=1
   self.emittedLogCount=(self.emittedLogCount or 0)+1
   if self.services.onEvent then self.services.onEvent({thread=t.id,timestamp=self.time,line=line,kind="diagnostic",
    text="Debug output rate limit reached; further entries this CPU cycle are omitted. Execution continues."}) end
  end
  return
 end
 self.cycleLogCount+=1
 self.emittedLogCount=(self.emittedLogCount or 0)+1
 if self.services.onEvent then self.services.onEvent({thread=t.id,timestamp=self.time,line=line,kind=kind or "result",text=text}) end
 if kind=="scan" and self.services.onValue then self.services.onValue(observation,line,angle,t.id)
 elseif kind=="print" and self.services.onPrint then self.services.onPrint(text,line,t.id) end
end
function R:charge(t,category,cost)
 if (t.debugDepth or 0)>0 and (category=="read" or category=="access" or category=="arithmetic" or category=="comparison" or category=="logical") then return end
 cost=cost or Hardware.Costs[category] or 0
 assert(t.credit+1e-8>=cost,"Instruction cost exceeded reservation")
 t.credit-=cost; t.ticks+=cost; self.cyclesSpent+=cost
end
function R:call(t,call,evaluate)
 -- Debug-only expression work is free, but nested gameplay calls and their
 -- arguments retain normal cost and side effects, even when printed.
 local depth=t.debugDepth or 0
 if call.name~="print" then t.debugDepth=0 end
 local result=self:_call(t,call,evaluate)
 t.debugDepth=depth
 return result
end
function R:debugValue(t,evaluate,expression)
 if not debugOnly(expression) then return evaluate() end
 local depth=t.debugDepth or 0; t.debugDepth=depth+1
 local value=evaluate()
 t.debugDepth=depth
 return value
end
function R:_call(t,call,evaluate)
 local name=call.name; local line=call.line
 if name=="get_facing_direction" then
  self:charge(t,name); return Value.result(nil,{world_direction=Adapter.heading(self.state.yaw)})
 end
 if name=="get_clock" then self:charge(t,name); return Value.result(nil,{time=self.time}) end
 if name=="wait_for" or name=="variable_has_changed" then
  self:charge(t,"sync"); local key=call.args[1].expression.name; local version=self.versions[key] or 0
  if name=="variable_has_changed" then
   local changed=version>(t.observed[key] or 0); t.observed[key]=version
   return Value.result(nil,{changed=changed,version=version})
  end
  local function ready() local v=self.variables[key]; return v~=nil and v~=false and v~=Value.Null end
  if not ready() then coroutine.yield({kind="variable",name=key}) end
  t.observed[key]=self.versions[key] or 0
  return Value.result(nil,{value=self.variables[key],version=t.observed[key]})
 end
 if name=="wait_for_clock" then
  local target=evaluate(call.args[1].expression); self:charge(t,"sync")
  if type(target)~="number" or target~=target or math.abs(target)==math.huge then return Value.result("invalidArgument") end
  if self.time<target then coroutine.yield({kind="clock",target=target}) end
  return Value.result()
 end
 if name=="clear_queue" or name=="abort_command" or name=="command_status" then
  local device=evaluate(call.args[1].expression); self:charge(t,"queue")
  if name=="command_status" then return self.devices:status(device) end
  if type(device)~="string" then return Value.result("invalidArgument") end
  local result=self.devices:manage(device,name=="abort_command",self.time); self:log(t,name.." -> "..Value.format(result),line); return result
 end
 if name=="print" then
  local value=self:debugValue(t,function() return evaluate(call.args[1].expression) end,call.args[1].expression); self:charge(t,"print"); self:log(t,Value.display(value),line,"print"); return Value.result()
 end
 -- Runtime operational arguments fail as values; static literals were validated before Run.
 local evaluated={}
 for index,arg in call.args do evaluated[index]=evaluate(arg.expression) end
 local cursor=0
 local ok,instruction=pcall(Commands.resolve,call,function() cursor+=1; return evaluated[cursor] end)
 if not ok then
  if type(instruction)=="table" and instruction.bwError then
   local fields
   if name=="Scanner" then
    fields={sensor=Value.Null}
    for index,arg in call.args do
     local value=evaluated[index]
     if arg.key=="position" then fields.position=if type(value)=="number" or type(value)=="string" or type(value)=="boolean" then value else Value.Null
     elseif arg.key==nil and type(value)=="number" then fields.sensor=value%360 end
    end
   end
   return Value.result(if name=="Scanner" then "invalidSensor" else "invalidArgument",fields)
  end
  error(instruction,0)
 end
 return self:submit(t,instruction,line)
end
function R:submit(t,instruction,line)
 local name=instruction.op; self:charge(t,name)
 local device=if name=="Scanner" then "sensor"..tostring(instruction.value) elseif name=="fire" then "weapon" elseif name:sub(1,6)=="turret" then "turret" else "drivetrain"
 local result=self.devices:submit(device,instruction,self.time,t.id)
 if result.status=="fail" then
  if name=="Scanner" then result=Value.result(result.reason,{sensor=instruction.value}) end
  self:log(t,Value.format(result),line); return result
 end
 if name~="Scanner" then self:log(t,name.." -> "..Value.format(result),line) end
 if name=="Scanner" then
  self.scanCount+=1
  local c=self.devices.commands[result.commandId]
  coroutine.yield({kind="scan",command=c})
  result=c.result
  if c.observation then
   self.lastObservation=c.observation; self.lastValue=result; table.insert(self.results,c.observation)
   if #self.results>Limits.MaxScannerHistory then table.remove(self.results,1) end
   self:log(t,Value.format(result),line,"scan",c.observation,instruction.value)
  else self:log(t,Value.format(result),line) end
 end
 return result
end
function R:evaluate(t,expression)
 return Expression.evaluate(expression,{variables=self.variables,charge=function(category) self:charge(t,category) end,
  call=function(call,evaluate) return self:call(t,call,evaluate) end})
end
function R:write(name,value,line)
 if self.variables[name]==nil then local count=0; for _ in self.variables do count+=1 end; if count>=Limits.MaxVariables then Commands.error(line,"Too many variables.") end end
 self.variables[name]=value; self.versions[name]=(self.versions[name] or 0)+1
end
function R:instruction(t,n)
 local nextIndex=t.index+1; local op=n.op
 if op=="$assign" then
  local value=self:evaluate(t,n.expression); self:charge(t,"write"); self:write(n.name,value,n.line)
 elseif op=="$set" then
  local target=n.targetExpression; local dictionary=self:evaluate(t,target.array); local key=self:evaluate(t,target.index); local value=self:evaluate(t,n.expression)
  self:charge(t,"write")
  if not Value.isDictionary(dictionary) or table.isfrozen(dictionary) or type(key)~="string" then Commands.error(n.line,"Cannot mutate this value; expected a mutable dictionary and string key.") end
  local count=0; for _ in dictionary do count+=1 end; if dictionary[key]==nil and count>=Limits.MaxArrayItems then Commands.error(n.line,"Dictionary is too large.") end
  dictionary[key]=value
  local root=target.array; while root.kind=="index" do root=root.array end
  if root.kind=="variable" then self.versions[root.name]=(self.versions[root.name] or 0)+1 end
 elseif op=="$while" then t.loopTests=(t.loopTests or 0)+1; self:charge(t,"loop"); if not Expression.truthy(self:evaluate(t,n.condition)) then nextIndex=n.target end
 elseif op=="$branch" then self:charge(t,"branch"); if not Expression.boolean(self:evaluate(t,n.condition),n.line) then nextIndex=n.target end
 elseif op=="$switch" then
  self:charge(t,"switch"); local value=self:evaluate(t,n.expression); nextIndex=n.target
  for _,choice in n.choices do if Value.equal(value,choice.value) then nextIndex=choice.target; break end end
 elseif op=="$jump" then nextIndex=n.target
 elseif op=="$print" then local value=self:debugValue(t,function() return self:evaluate(t,n.expression) end,n.expression); self:charge(t,"print"); self:log(t,Value.display(value),n.line,"print")
 elseif op=="$call" then self:evaluate(t,n.expression)
 elseif n.call then self:call(t,n.call,function(expr) return self:evaluate(t,expr) end)
 else self:submit(t,n,n.line) end
 t.index=nextIndex
end
function R:ready(p)
 if p.kind=="cost" then return true end
 if p.kind=="clock" then return self.time+1e-8>=p.target end
 if p.kind=="variable" then local v=self.variables[p.name]; return v~=nil and v~=false and v~=Value.Null end
 if p.kind=="scan" then return p.command.result~=nil end
 return false
end
-- Reserve a bounded worst-case cost before beginning a source instruction. Ordinary
-- assignments/decisions therefore cannot be split by CPU exhaustion or interleaved writes.
local function expressionCost(n,debug)
 if not n then return 0 end
 local k=n.kind; local costs=Hardware.Costs
 local function cost(category) return if debug then 0 else costs[category] end
 if k=="variable" then return cost("read") end
 if k=="index" then return expressionCost(n.array,debug)+expressionCost(n.index,debug)+cost("access") end
 if k=="group" then return expressionCost(n.expression,debug) end
 if k=="unary" then return expressionCost(n.operand,debug)+(if n.op=="not" then cost("logical") else cost("arithmetic")) end
 if k=="binary" then
  if n.op=="and" or n.op=="or" then
   local known,value=Expression.constant(n.left)
   if known and ((n.op=="and" and value==false) or (n.op=="or" and value==true)) then return expressionCost(n.left,debug)+cost("logical") end
  end
  local category=if n.op=="and" or n.op=="or" then "logical" elseif n.op=="==" or n.op=="!=" or n.op=="<" or n.op=="<=" or n.op==">" or n.op==">=" then "comparison" else "arithmetic"
  return expressionCost(n.left,debug)+expressionCost(n.right,debug)+cost(category)
 end
 local total=0
 if k=="call" then
  total=if n.name=="wait_for" or n.name=="variable_has_changed" or n.name=="wait_for_clock" then costs.sync elseif n.name=="clear_queue" or n.name=="abort_command" or n.name=="command_status" then costs.queue else costs[n.name] or 0
  for _,arg in n.args do total+=expressionCost(arg.expression,n.name=="print" and debugOnly(arg.expression)) end
 elseif k=="array" then for _,item in n.items do total+=expressionCost(item,debug) end
 elseif k=="dictionary" then for _,entry in n.entries do total+=expressionCost(entry.expression,debug) end end
 return total
end
local function instructionCost(n)
 local costs=Hardware.Costs
 if n.op=="$assign" then return expressionCost(n.expression)+costs.write end
 if n.op=="$set" then return expressionCost(n.targetExpression.array)+expressionCost(n.targetExpression.index)+expressionCost(n.expression)+costs.write end
 if n.op=="$while" then return costs.loop+expressionCost(n.condition) end
 if n.op=="$branch" then return costs.branch+expressionCost(n.condition) end
 if n.op=="$switch" then return costs.switch+expressionCost(n.expression) end
 if n.op=="$print" then return costs.print+expressionCost(n.expression,debugOnly(n.expression)) end
 if n.op=="$call" then return expressionCost(n.expression) end
 if n.call then return expressionCost(n.call) end
 return costs[n.op] or 0
end
function R:runThread(t)
 local spec=Hardware.Tiers[self.config.tier]
 local nextInstruction=t.instructions[t.index]
 local required=if nextInstruction then instructionCost(nextInstruction) else 0
 if required>Hardware.MaxInstructionCredit then Commands.error(nextInstruction.line,"Instruction exceeds maximum CPU reservation.") end
 t.credit=math.min(math.max(spec.ticks*Hardware.CreditCycles,required),t.credit+spec.ticks)
 local operations=0
 while operations<Hardware.MaxOperationsPerCycle do
  operations+=1
  if t.pending then
   if not self:ready(t.pending) then t.state="waiting"; return end
   t.pending=nil
  end
  if not t.coroutine then
   local n=t.instructions[t.index]
   if not n then t.state="finished"; return end
   t.line=n.line
   if t.credit+1e-8<instructionCost(n) then t.state="waiting"; t.waitReason="cpuBudget"; return end
   t.waitReason=nil; t.coroutine=coroutine.create(function() self:instruction(t,n) end)
  end
  local ok,yielded=coroutine.resume(t.coroutine)
  if not ok then
   t.state="failed"; t.error=if type(yielded)=="table" and yielded.bwError then yielded.message else "Internal BW error: "..tostring(yielded)
   self:stop(string.format("Thread %d, line %d: %s",t.id,t.line,t.error),"error"); t.state="failed"; return
  end
  if coroutine.status(t.coroutine)=="dead" then t.coroutine=nil else t.pending=yielded end
  t.state="running"
 end
end
function R:_step(state,dt)
 if self.status~="running" then return Input.neutral() end
 if state.health<=0 or (state.generation or 0)~=self.generation or state.tankType~=self.tankType then self:stop("Tank destroyed or replaced."); return Input.neutral() end
 self.state=state
 self.elapsed+=dt; self.time=if self.services.getClock then self.services.getClock() else self.elapsed
 if self.elapsed>Limits.MaxProgramSeconds then self:stop("Program exceeded 180 simulated seconds.","error"); return Input.neutral() end
 local cycle=math.floor((self.elapsed-dt+1e-8)*Hardware.CyclesPerSecond)
 if cycle>self.cycle then
  self.cycle=cycle; self.cycleLogCount=0
  for id=1,Hardware.Tiers[self.config.tier].threads do local t=self.threads[id]; if t and t.state~="finished" then self:runThread(t); if self.status~="running" then return Input.neutral() end end end
 end
 local command=self.devices:step(state,dt,self.time)
 local allFinished=true; for _,t in self.threads do if t.state~="finished" then allFinished=false end end
 if allFinished and not self.devices:busy() then self.status="completed"; self.message="Program completed." end
 local first=self.threads[1]; self.index=if first then first.index else 1
 return command
end
function R:step(state,dt)
 local ok,result=pcall(self._step,self,state,dt)
 if ok then return result end
 if type(result)=="table" and result.bwError then self:stop(string.format("Line %d: %s",result.line or 1,result.message),"error")
 else self:stop("Internal BW engine error: "..tostring(result),"error") end
 return Input.neutral()
end
function R:diagnostics()
 local threads={}
 for id,t in self.threads do threads[id]={id=id,prints=t.prints or 0,loopTests=t.loopTests or 0,line=t.line or 0,state=t.state,ticks=t.ticks,credit=t.credit,waiting=if t.pending then t.pending.kind else t.waitReason or ""} end
 local recent={}
 for id=math.max(1,self.devices.nextId-15),self.devices.nextId do local c=self.devices.commands[id]; if c then table.insert(recent,{id=id,device=c.device,state=c.state,reason=c.reason,thread=c.thread}) end end
 return {printCount=self.printCount or 0,emittedLogCount=self.emittedLogCount or 0,scanCount=self.scanCount,outputCount=self.outputCount,suppressedLogs=self.suppressedLogs or 0,retainedScans=#self.results,retainedCommands=self.devices.retainedCount,recent=recent,clock=self.time,tier=self.config.tier,ticksPerCycle=Hardware.Tiers[self.config.tier].ticks,threads=threads,devices=self.devices:diagnostics(),status=self.status}
end
return R
