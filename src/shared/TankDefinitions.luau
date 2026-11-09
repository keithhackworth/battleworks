-- Compatibility view for model/visual code and old fixtures. Tuning lives in components.
local Components=require(script.Parent.VehicleComponents)
local Assemblies=require(script.Parent.VehicleAssemblies)
local Definitions={}
for id in Assemblies do
 local c=Components.default(id)
 local drive
 if c.Mobility.Kind=="Wheeled" then
  drive=Components.copy(c.Drivetrain); for k,v in c.Mobility do drive[k]=v end; table.freeze(drive)
 end
 Definitions[id]=table.freeze({Id=id,DisplayName=c.DisplayName,WeaponType=c.Weapon.WeaponType,Weapon=c.Weapon,Aim=c.Aim,Drive=drive,Recoil=c.Recoil})
end
function Definitions.valid(id) return type(id)=="string" and Assemblies[id]~=nil end
function Definitions.get(id) return Definitions[id] or Definitions.Boomer end
return table.freeze(Definitions)
