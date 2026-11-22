local Autonomy=require("PlaygroundAutonomy")
local Programs=require("PlaygroundPrograms")
local Config=require("BattleRoyaleConfig")
local Royale=require("BattleRoyale")
local Simulation=require("TankSimulation")
local setting={FindFirstChild=function(_,name)
 return if name=="PublicTankCount" then {Value=50} else nil
end}
local count=Config.settings(setting).count
assert(count==50,"the configured pool accepts 50 tanks")
assert(Autonomy.PersonalityCount==#Programs,"the rotation length matches the packaged deck")

-- Run real pool creation and hardware assignment with no world or BW ticks.
local prompt=Royale.attachPrompt
Royale.attachPrompt=function()end
local royale=Royale.new({
 count=count,
 autonomy={attach=Autonomy.attach,start=function()end,PersonalityCount=Autonomy.PersonalityCount},
 clock=function()return 0 end,
 create=function(_,kind,_,assembly)
  return {state=Simulation.new(Vector3.zero,kind,nil,assembly),hitbox=Instance.new("Part")}
 end,
})
Royale.attachPrompt=prompt
assert(#royale.slots==50,"all configured slots are created")
for index,slot in royale.slots do
 local expected=Programs[(index-1)%#Programs+1]
 assert(slot.tank.personality==expected,"spawned tanks wrap around the personality deck")
 local score=royale.tankScores[index]
 assert(score.name==(if index>#Programs then expected.name.." #"..index else expected.name),"repeated personalities retain distinct score rows")
end
print("Playground population passed: "..#royale.slots.." assigned tanks")
