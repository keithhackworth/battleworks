-- Explicit server-owned test configuration. A private server ID alone never
-- grants Studio-save access: real reserved battles also have private IDs.
local Context={}
local Diagnostics=require(script.Parent.WorldStorageDiagnostics)
function Context.resolve(run,place,configuration)
 local localStudio=run:IsStudio()
 local reserved=not localStudio and place.PrivateServerId~="" and place.PrivateServerOwnerId==0
 local flag=configuration and configuration:FindFirstChild("TeamTestMode")
 Diagnostics.log(nil,"context_resolved_inputs",{mode="Resolving",rawIsStudio=localStudio,teamTestEnabled=flag~=nil and flag.Value==true,privateServer=place.PrivateServerId~=""})
 if not flag or flag.Value~=true then return {studio=localStudio,reserved=reserved,mode=if localStudio then "StudioLocal" elseif reserved then "ReservedWorld" else "Live",rawIsStudio=localStudio,teamTestEnabled=false,privateServer=place.PrivateServerId~=""} end
 assert(localStudio or reserved,"TeamTestMode only works in Studio or a private test server; disable it for public play")
 local setting=configuration:FindFirstChild("TeamTestHostUserId")
 local host=setting and tonumber(setting.Value)
 if not host or host==0 then
  assert(place.CreatorType==Enum.CreatorType.User,"For group-owned experiences, set TeamTestHostUserId to the test host's Roblox user ID")
  host=place.CreatorId
 end
 assert(type(host)=="number" and host>0 and host%1==0,"TeamTestHostUserId must be a positive Roblox user ID")
 local provider=configuration:FindFirstChild("WorldStorageProvider")
 assert(provider and provider.Value=="Http","TeamTestMode requires HTTP storage to load persistent Studio saves")
 return {studio=true,reserved=false,testHost=host,mode="TeamTest",rawIsStudio=localStudio,teamTestEnabled=true,privateServer=place.PrivateServerId~=""}
end
return Context
