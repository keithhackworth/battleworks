-- Device queues own physical operation; CPU threads only submit commands.
local Limits=require(script.Parent.BWConfig)
local Hardware=require(script.Parent.BWChassis)
local Value=require(script.Parent.BWValue)
local Components=require(script.Parent.VehicleComponents)
local Physical=require(script.Parent.BWRuntime)
local Input=require(script.Parent.InputCommand)
local ScannerConfig=require(script.Parent.ScannerConfig)
local D={}; D.__index=D
function D.new(config,state,services)
 local self=setmetatable({config=config,services=services or {},devices={},commands={},completed={},retainedCount=0,nextId=0,generation=state.generation,tankType=state.tankType,components=Components.get(state),steering=0},D)
 for name,spec in config.devices do self.devices[name]={name=name,spec=spec,performance=Hardware.performance(spec.allocation,self.components.Bus),queue={}} end
 return self
end
function D:submit(name,instruction,time,thread)
 local d=self.devices[name]
 if not d then return Value.result("deviceUnavailable") end
 if name:sub(1,6)=="sensor" and not self.components.Sensors[tonumber(name:sub(7))] then return Value.result("deviceUnavailable") end
 if d.performance<=0 and instruction.op~="stop" then return Value.result("deviceDisabled") end
 local op=instruction.op
 local steering=op=="steer_left" or op=="steer_right" or op=="steer_center"
 local continuous=(op=="forward" or op=="back") and instruction.value==nil
 if (steering or op=="turn_left" or op=="turn_right") and not self.components.Capabilities.Steer then return Value.result("unsupportedDrivetrain") end
 -- Steering is an immediate setpoint, not queued behind physical navigation.
 -- Continuous movement/stop explicitly replace the entire drivetrain pipeline.
 if name=="drivetrain" then
  if op=="stop" or continuous then
   self:manage(name,false,time)
   if d.active then self:terminal(d,d.active,"cancelled","commandCancelled",time) end
  elseif not steering and d.active and d.active.continuous then
   self:terminal(d,d.active,"cancelled","commandCancelled",time)
  end
 end
 if steering or op=="stop" then
  self.nextId+=1
  local c={id=self.nextId,instruction=instruction,thread=thread,submitted=time,started=time,completed=time,state="completed",device=name}
  self.commands[c.id]=c; self.retainedCount+=1; self:archive(c)
  if steering then
   self.steeringThread=thread
   local max=self.components.Mobility.MaxSteer
   self.steering=if op=="steer_center" then 0 else math.min(math.rad(instruction.value),max)*(if op=="steer_left" then 1 else -1)
   return Value.result(nil,{commandId=c.id,steeringDegrees=math.deg(self.steering)})
  end
  return Value.result(nil,{commandId=c.id})
 end
 if (d.active or #d.queue>0) and #d.queue>=Hardware.Tiers[self.config.tier].queue then return Value.result("deviceQueueFull") end
 self.nextId+=1
 local c={id=self.nextId,instruction=instruction,thread=thread,submitted=time,state=if d.active or #d.queue>0 then "queued" else "accepted",device=name,continuous=continuous}
 self.commands[c.id]=c; self.retainedCount+=1
 if not d.active and #d.queue==0 then d.active=c else table.insert(d.queue,c) end
 return Value.result(nil,{commandId=c.id})
end
function D:archive(c)
 if c.archived then return end
 c.archived=true; table.insert(self.completed,c.id)
 if #self.completed>Limits.MaxCommandHistory then
  self.commands[table.remove(self.completed,1)]=nil; self.retainedCount-=1
 end
end
function D:terminal(d,c,state,reason,time)
 c.state=state; c.reason=reason; c.completed=time
 if d.name:sub(1,6)=="sensor" and not c.result then c.result=Value.result(reason or "commandCancelled",{sensor=c.instruction.value}) end
 if d.name=="weapon" and state~="completed" and self.services.cancelWeapon then self.services.cancelWeapon() end
 self:archive(c)
 d.active=nil
 -- Starting the next command is deferred to the next fixed simulation tick.
end
function D:manage(name,abort,time)
 local d=self.devices[name]; if not d then return Value.result("deviceUnavailable") end
 if abort then
  if d.active then self:terminal(d,d.active,"cancelled","commandCancelled",time) end
 else
  for _,c in d.queue do c.state="cancelled"; c.reason="commandCancelled"; c.completed=time; if name:sub(1,6)=="sensor" then c.result=Value.result("commandCancelled",{sensor=c.instruction.value}) end; self:archive(c) end
  d.queue={}
 end
 return Value.result()
end
function D:stopThread(thread,time)
 if self.steeringThread==thread then self.steering=0; self.steeringThread=nil end
 for _,d in self.devices do
  local retained={}
  for _,c in d.queue do
   if c.thread==thread then
    c.state="cancelled"; c.reason="commandCancelled"; c.completed=time
    if d.name:sub(1,6)=="sensor" then c.result=Value.result("commandCancelled",{sensor=c.instruction.value}) end
    self:archive(c)
   else table.insert(retained,c) end
  end
  d.queue=retained
  if d.active and d.active.thread==thread then self:terminal(d,d.active,"cancelled","commandCancelled",time) end
 end
end
function D:stop(time,reason)
 self.steering=0
 for name,d in self.devices do
  self:manage(name,false,time)
  if d.active then self:terminal(d,d.active,"cancelled",reason or "commandCancelled",time) end
 end
end
function D:status(id)
 local c=self.commands[id]; if not c then return Value.result("invalidArgument") end
 return Value.result(nil,{commandId=c.id,state=c.state,completionReason=c.reason or Value.Null,device=c.device})
end
function D:busy()
 for _,d in self.devices do if d.active or #d.queue>0 then return true end end
 return false
end
function D:steerInput()
 local mobility=self.components.Mobility
 return if self.components.Capabilities.Steer then self.steering/mobility.MaxSteer else 0
end
function D:step(state,dt,time)
 local input=Input.neutral()
 if state.health<=0 or state.generation~=self.generation then self:stop(time,"tankDestroyed"); return input end
 local drive=self.devices.drivetrain
 if drive and drive.performance>0 and self.components.Mobility.Kind=="Wheeled" then input.steer=self:steerInput() end
 local names={}; for name in self.devices do table.insert(names,name) end; table.sort(names)
 -- The query-budget guard is shared, but sensor cooldowns are not. Rotate
 -- acquisition priority each cooldown interval so fixed lexical order cannot
 -- repeatedly deny the same lens when many sensors become ready together.
 local sensors={}
 for _,name in names do if name:sub(1,6)=="sensor" then table.insert(sensors,name) end end
 table.sort(sensors,function(a,b) return tonumber(a:sub(7))<tonumber(b:sub(7)) end)
 if #sensors>0 then
  local start=math.floor(time/ScannerConfig.SensorCooldown+1e-7)%#sensors
  local index=0
  for i,name in names do
   if name:sub(1,6)=="sensor" then names[i]=sensors[(index+start)%#sensors+1]; index+=1 end
  end
 end
 for _,name in names do
  local d=self.devices[name]
  if not d.active and #d.queue>0 then d.active=table.remove(d.queue,1) end
  local c=d.active
  if not c then continue end
  if c.continuous then
   c.state="running"; c.started=c.started or time
   input.throttle=if c.instruction.op=="forward" then 1 else -1
   input.steer=self:steerInput()
   continue
  end
  if c.state~="running" then
   c.state="running"; c.started=time
   if name:sub(1,6)=="sensor" then c.acquireAt=math.max(time+(d.spec.acquisition or Hardware.AcquisitionSeconds)/d.performance,d.readyAt or 0)
   else
    local instruction=table.clone(c.instruction); instruction.bestEffort=false
    c.executor=Physical.new({instruction},state,if name=="drivetrain" and self.components.Capabilities.Steer then {followSteering=true} else nil)
   end
  end
  if c.acquireAt then
   if time+1e-8<c.acquireAt then continue end
   local observation,reason
   d.readyAt=time+(d.spec.cooldown or self.components.Sensor.Cooldown)
   d.scanAttempts=(d.scanAttempts or 0)+1
   if self.services.scan then observation,reason=self.services.scan(c.instruction.value,d.performance,time,{range=d.spec.range,distancePercent=d.spec.distancePercent,coneWidth=d.spec.coneWidth,cooldown=d.spec.cooldown,originHeight=d.spec.originHeight}) else reason="deviceUnavailable" end
   if observation then
    d.scanSuccesses=(d.scanSuccesses or 0)+1
    d.lastScan={status="success",count=observation.value.count or 0,timestamp=observation.timestamp or time}
    c.observation=observation; c.result=observation.value
    self:terminal(d,c,"completed",nil,time)
   else
    d.scanFailures=(d.scanFailures or 0)+1; d.lastScan={status="fail",reason=reason or "deviceUnavailable",timestamp=time}
    c.result=Value.result(reason or "deviceUnavailable",{sensor=c.instruction.value}); self:terminal(d,c,"failed",reason,time) end
  else
   local command=c.executor:step(state,dt)
   if name=="drivetrain" then
    input.throttle=command.throttle
    if c.instruction.op=="forward" or c.instruction.op=="back" then
     input.steer=if self.components.Mobility.Kind=="Tracked" and command.throttle==0 then 0 else self:steerInput()
    else input.steer=command.steer end
   elseif name=="turret" then input.turretX=command.turretX; input.turretY=command.turretY
   elseif name=="weapon" then input.fire=command.fire end
   if c.executor.status=="error" and c.executor.message:find("Internal device error:",1,true) then error(c.executor.message,0) end
   if c.executor.status~="running" then
    self:terminal(d,c,if c.executor.status=="completed" then "completed" else "failed",if c.executor.status=="completed" then nil elseif c.executor.message:find("No progress",1,true) then "stuck" elseif c.executor.message:find("timed out",1,true) then "commandTimedOut" else "executionFailed",time)
   end
  end
 end
 return input
end
function D:diagnostics()
 local out={}
 for name,d in self.devices do
  local queue={}; for _,c in d.queue do table.insert(queue,{id=c.id,op=c.instruction.op,thread=c.thread}) end
  out[name]={steeringDegrees=if name=="drivetrain" then math.deg(self.steering) else nil,bus=d.spec.bus,allocation=d.spec.allocation,performance=d.performance,scanAttempts=d.scanAttempts or 0,scanSuccesses=d.scanSuccesses or 0,scanFailures=d.scanFailures or 0,lastScan=d.lastScan,capacity=Hardware.Tiers[self.config.tier].queue,
   active=if d.active then {id=d.active.id,op=d.active.instruction.op,thread=d.active.thread,state=d.active.state} else false,queue=queue}
 end
 return out
end
return D
