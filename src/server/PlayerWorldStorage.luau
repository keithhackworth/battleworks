-- Explicit provider selection. Never silently fall back after a failed save/read.
local HttpStore=require(script.Parent.HttpWorldStore)
local Store=require(script.Parent.PlayerWorldStore)
local Storage={}
function Storage.create(http,configuration,studio)
 local setting=configuration and configuration:FindFirstChild("WorldStorageProvider")
 local provider=if setting then setting.Value else (if studio then "Session" else "DataStore")
 if provider=="Http" then
  return HttpStore.new(http,"https://groupboard.app/api/battleworks/v1",if studio then "BattleWorksStudioWorlds" else "BattleWorksLiveWorlds")
 end
 assert(provider=="Session" or provider=="DataStore","Unknown WorldStorageProvider")
 assert(provider~="Session" or studio,"Temporary world storage is Studio-only")
 local dataStore=if provider=="DataStore" then game:GetService("DataStoreService"):GetDataStore(if studio then "BattleWorksStudioWorlds_v1" else "BattleWorksPlayerWorlds_v1") else nil
 return Store.new(dataStore,provider=="Session",function(value)return http:JSONEncode(value)end)
end
return Storage
