-- Startup policy only; hardware is assembled from existing registered parts.
local C={Revision="playground-15-auto-v4",Mode="BattleRoyale",TankCount=15,Personalities=true,ReplenishDelay=5,InteractionDistance=12,ActionInterval=.35,EjectClearance=4,EjectSpeed=25}
function C.mode(configuration,override)
 local setting=configuration and configuration:FindFirstChild("GameMode")
 local mode=override or (setting and setting.Value) or C.Mode
 assert(mode=="Classic" or mode=="BattleRoyale","GameMode must be Classic or BattleRoyale")
 return mode
end
function C.settings(configuration)
 local function number(name,default,min,max)
  local item=configuration and configuration:FindFirstChild(name);local n=if item then item.Value else default
  assert(type(n)=="number" and n==n and n>=min and n<=max,"Invalid "..name);return n
 end
 local count=number("PublicTankCount",C.TankCount,2,16);assert(count%1==0,"PublicTankCount must be an integer")
 local flag=configuration and configuration:FindFirstChild("PlaygroundPersonalities")
 return {personalities=if flag then flag.Value==true else C.Personalities,count=count,delay=number("PublicTankReplenishDelay",C.ReplenishDelay,1,60)}
end
function C.loadout(index,random)
 local kinds={"Boomer","Rattler","Boomer","Rattler"}
 local weapons={"weapon.cannon","weapon.gatling","weapon.gatling","weapon.cannon"}
 local n=if random then random(1,4)else(index-1)%4+1
 local assembly=require(script.Parent.VehicleComponents).copy(require(script.Parent.VehicleAssemblies)[kinds[n]])
 assembly.Computer="computer.Bunny";assembly.Weapon=weapons[n]
 return kinds[n],assembly
end
return C
