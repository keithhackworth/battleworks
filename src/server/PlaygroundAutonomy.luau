-- Public personality policy; execution stays in the ordinary BW interpreter.
local BW=require(script.Parent.BWController)
local Hardware=require(game.ReplicatedStorage.Shared.BWChassis)
local Components=require(game.ReplicatedStorage.Shared.VehicleComponents)
local Programs=require(script.Parent.PlaygroundPrograms)
local A={}
function A.attach(tank,index)
 local entry=Programs[(index-1)%#Programs+1]
 tank.personality=entry
 tank.state.personalityId=entry.id;tank.state.personalityName=entry.name;tank.state.personalityHash=entry.hash
 tank.hitbox:SetAttribute("Personality",entry.name)
 A.hardware(tank)
end
function A.hardware(tank)
 Components.withComputer(tank.state,"Bunny")
 tank.hardware=Hardware.playgroundDefault(Components.get(tank.state));BW.applyHardware(tank)
end
function A.start(tank,now)
 BW.clearInputs(tank)
 tank.state.controlMode="Auto";tank.autoRestartAt=nil;tank.autonomyActive=true
 tank.state.bwProgramKind="Personality";tank.state.bwProgramName=tank.personality.name
 local ok=BW.start(tank,tank.personality.source)
 if not ok then
  tank.autoRestartAt=now+5
  warn("[Playground Auto] "..tank.personality.id..": "..tostring(tank.state.bwMessage))
 end
 return ok
end
function A.step(tank,now)
 if not tank.autonomyActive then
  if tank.state.controlMode=="Auto"and not BW.running(tank)then tank.state.controlMode="Manual"end
  return
 end
 if tank.state.controlMode~="Auto"or tank.state.health<=0 or tank.state.publicRetired or BW.running(tank)then return end
 -- Preserve the runtime's 180s safety limit. A new bounded invocation starts
 -- with fresh variables after normal timeout, or a delayed failed-run retry.
 if not tank.autoRestartAt then tank.autoRestartAt=now+1 end
 if now>=tank.autoRestartAt then A.start(tank,now)end
end
return A
