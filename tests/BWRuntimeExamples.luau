-- The checker injects every Python code fence directly from the user-facing docs.
local Hardware=require(Shared.BWChassis)
local Parser=require(Shared.BWParser)
local Runtime=require(Shared.BWExecution)
local Value=require(Shared.BWValue)
local Sim=require(Shared.TankSimulation)
local Windup=require(Shared.WeaponWindup)
local Weapon=require(Shared.RattlerWeapon)
local Recoil=require(Shared.RattlerRecoil)
local Components=require(Shared.VehicleComponents)
for index,source in examples do
 local instructions,err=Parser.parse(source); assert(instructions,"Documentation example "..index..": "..tostring(err and err.message))
 for _,kind in {"Boomer","Rattler"} do
  local state=Sim.new(Vector3.zero,kind); local pending; local tuning=Components.get(state).Weapon; local weapon=Weapon.new(tuning)
  local runtime=Runtime.new(instructions,state,{scan=function(angle,performance,time)
   return Value.observation(Value.result(nil,{count=1,range=150,detections=Value.array({Value.dictionary({type="tank",distance=40,relative_direction=0,world_direction=0,player="test.enemy#1",relation="enemy",point=Value.dictionary({x=time*2,y=2.5,z=-40},true)},true)}),type="tank",distance=40,relative_direction=0,world_direction=0,player="test.enemy#1",relation="enemy",sensor=angle,timestamp=time,
    point=Value.dictionary({x=time*2,y=2.5,z=-40},true)}),time,state.position,0)
  end,cancelWeapon=function() pending=nil end},Hardware.default(if index==6 or index==9 then "Bunny" elseif index==1 or index==7 or index==8 then "Dual" else "Hexadeca"))
  for tick=1,10802 do
   local input=runtime:step(state,1/60)
   local rapid=Weapon.step(weapon,tuning.Operation=="Heat",input.fire,1/60)
   Sim.step(state,input,1/60)
   if tuning.Operation=="Heat" and rapid then
    state.weaponActivationSerial=(state.weaponActivationSerial or 0)+1; state.weaponShotSerial=(state.weaponShotSerial or 0)+1
    local _,direction=Sim.shotPose(state); Recoil.kick(state,weapon.heat,direction)
   elseif tuning.Operation=="Windup" then
    if pending then local done,origin=Windup.step(pending,state,1/60); if done then pending=nil; if origin then state.weaponShotSerial=(state.weaponShotSerial or 0)+1 end end end
    if not pending then pending=Windup.begin(state,input); if pending then state.weaponActivationSerial=(state.weaponActivationSerial or 0)+1 end end
   end
   if runtime.status~="running" then break end
  end
  assert(runtime.status=="completed","Documentation example "..index.." "..kind..": "..runtime.message)
 end
end
print("Documentation samples passed: "..#examples.." programs on both physical tank simulations")
