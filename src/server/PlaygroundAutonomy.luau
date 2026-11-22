-- Public personality policy; execution stays in the ordinary BW interpreter.
local BW=require(script.Parent.BWController)
local Hardware=require(game.ReplicatedStorage.Shared.BWChassis)
local Components=require(game.ReplicatedStorage.Shared.VehicleComponents)
local Programs=require(script.Parent.PlaygroundPrograms)
local A={PersonalityCount=#Programs}
-- Spawn policy for the public pool. These are independent of the source-pack
-- constraints used for the standalone personality scenarios.
local busRules={
 P02={disabled="scanners"},    -- Crazy fights without scanner observations.
 P03={disabled="drivetrain"},  -- Tower fights from its spawn position.
 P04={primary="turret"},      -- Sniper aims and leads targets.
 P06={primary="drivetrain"},  -- Hunter needs pursuit speed.
 P07={primary="scanners"},    -- Sentinel sweeps the sectors.
 P10={primary="scanners"},    -- Prospector prioritizes information.
 P15={primary="scanners"},    -- Trailblazer samples the terrain.
}
local minimum=5
local function rollHardware(tank,focus,previous)
 local allocations,flexible={},{}
 local rule=busRules[tank.personality.id]
 local disabled=rule and rule.disabled
 local primary=rule and rule.primary
 if not rule then primary=Hardware.Categories[focus or math.random(1,#Hardware.Categories)] end
 local remaining=100
 if primary then
  allocations[primary]=if rule then 75 else math.random(50,70)
  remaining-=allocations[primary]
 end
 for _,category in Hardware.Categories do
  if category==disabled then
   allocations[category]=0
  elseif category~=primary then
   allocations[category]=minimum
   remaining-=minimum
   table.insert(flexible,category)
  end
 end
 -- Randomize both the split and the device order so each flexible category
 -- can receive a large share.
 for index=#flexible,2,-1 do
  local other=math.random(index)
  flexible[index],flexible[other]=flexible[other],flexible[index]
  local share=math.random(0,remaining)
  allocations[flexible[index]]+=share
  remaining-=share
 end
 allocations[flexible[1]]+=remaining
 if previous then
  local identical=true
  for _,category in Hardware.Categories do if previous[category]~=allocations[category] then identical=false;break end end
  if identical then
   for index,category in flexible do
    if allocations[category]>minimum then
     allocations[category]-=1
     allocations[flexible[index%#flexible+1]]+=1
     break
    end
   end
  end
 end
 return assert(Hardware.fromCategories({allocations=allocations,tuning={scanners=.5,weapon=.5}},Components.get(tank.state),"Bunny"))
end
function A.attach(tank,index,focus,previous)
 local entry=Programs[(index-1)%A.PersonalityCount+1]
 tank.personality=entry
 tank.state.personalityId=entry.id;tank.state.personalityName=entry.name;tank.state.personalityHash=entry.hash
 tank.hitbox:SetAttribute("Personality",entry.name)
 tank.spawnHardware=rollHardware(tank,focus,previous)
 A.hardware(tank)
end
function A.hardware(tank)
 Components.withComputer(tank.state,"Bunny")
 tank.hardware=Hardware.copy(tank.spawnHardware);BW.applyHardware(tank)
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
