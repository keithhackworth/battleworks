local Shared=game.ReplicatedStorage.Shared
local Hardware=require(Shared.BWChassis)
local Components=require(Shared.VehicleComponents)
local Config=require(Shared.BattleRoyaleConfig)
local Autonomy=require(script.Parent.PlaygroundAutonomy)
local Programs=require(script.Parent.PlaygroundPrograms)
local Retaliator=require(script.Parent.InnovationLabProgram)
local Lab={Size=Vector2.new(150,150)}
Lab.__index=Lab
local experiment={id="lab:retaliator",name="Retaliator Mesh",source=Retaliator}
local crazyIndex
for index,entry in Programs do
 if entry.id=="P02" then crazyIndex=index;break end
end
function Lab.new(owner)
 assert(crazyIndex,"Crazy is missing from the personality pack")
 return setmetatable({owner=owner,fixedOwner=owner,serial=0},Lab)
end
function Lab.loadout(index)
 return Config.loadout(index) -- tracked Cannon and wheeled Gatling, respectively
end
function Lab.pose(index)
 return if index==1 then Vector3.new(-20,0,0) else Vector3.new(20,0,0),
  if index==1 then -math.pi/2 else math.pi/2
end
Lab.autonomy={
 PersonalityCount=Autonomy.PersonalityCount,
 hardware=Autonomy.hardware,start=Autonomy.start,step=Autonomy.step,
 attach=function(tank,index,focus,previous)
  if index==2 then Autonomy.attach(tank,crazyIndex,focus,previous);return end
  tank.personality=experiment
  tank.state.personalityId=experiment.id;tank.state.personalityName=experiment.name
  tank.hitbox:SetAttribute("Personality",experiment.name)
  tank.spawnHardware=assert(Hardware.fromCategories({
   allocations={drivetrain=40,turret=10,weapon=15,scanners=10,retaliatorMesh=25},
   tuning={weapon=.5,scanners=.5},
  },Components.get(tank.state),"Bunny"))
  Autonomy.hardware(tank)
 end,
}
function Lab:start(royale,member,id)
 if self.owner and self.owner~=member.player.UserId then return false,"This experiment belongs to another player." end
 if id~="retaliator" then return false,"This technology has no runnable experiment yet." end
 self.serial+=1
 if not royale:resetPool(2,"lab:"..self.serial..":") then
  royale:resetPool(0)
  return false,"Could not place both tanks. Try restarting the experiment."
 end
 self.owner=member.player.UserId
 return true
end
function Lab:clear(royale,player,disconnecting)
 if self.owner~=player.UserId then return end
 royale:resetPool(0)
 if disconnecting then self.owner=self.fixedOwner end
end
return Lab
