-- Explicit provider selection. Never silently fall back after a failed save/read.
local HttpStore=require(script.Parent.HttpWorldStore)
local Store=require(script.Parent.PlayerWorldStore)
local Storage={}
local Diagnostics=require(script.Parent.WorldStorageDiagnostics)
function Storage.create(http,configuration,studio,context)
 assert(not context or context.studio==studio,"World storage selection does not match the resolved runtime context")
 local setting=configuration and configuration:FindFirstChild("WorldStorageProvider")
 local provider=if setting then setting.Value else (if studio then "Session" else "DataStore")
 local selected={provider=provider,mode=if context then context.mode else (if studio then "StudioLocal" else "Live"),expectedNamespace=if studio then "studio" else "live",
  secretStore=if context and (context.rawIsStudio==false or (context.mode=="TeamTest" and context.privateServer)) then "CreatorDashboard" elseif studio then "StudioLocalSecrets" else "CreatorDashboard",
  rawIsStudio=context and context.rawIsStudio,teamTestEnabled=context and context.teamTestEnabled,privateServer=context and context.privateServer}
 if provider=="Http" then
  selected.secretName=if studio then "BattleWorksStudioWorlds" else "BattleWorksLiveWorlds"
  Diagnostics.log(nil,"storage_selected",selected)
  return HttpStore.new(http,"https://groupboard.app/api/battleworks/v1",selected.secretName,selected)
 end
 Diagnostics.log(nil,"storage_selected",selected)
 assert(provider=="Session" or provider=="DataStore","Unknown WorldStorageProvider")
 assert(provider~="Session" or studio,"Temporary world storage is Studio-only")
 local dataStore=if provider=="DataStore" then game:GetService("DataStoreService"):GetDataStore(if studio then "BattleWorksStudioWorlds_v1" else "BattleWorksPlayerWorlds_v1") else nil
 return Store.new(dataStore,provider=="Session",function(value)return http:JSONEncode(value)end)
end
return Storage
