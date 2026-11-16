local Context=require("WorldTestContext")
local count=0
local function check(ok,message)assert(ok,message);count+=1 end
local localRun={IsStudio=function()return true end}
local cloudRun={IsStudio=function()return false end}
local place={PrivateServerId="test-private",PrivateServerOwnerId=0,CreatorType=Enum.CreatorType.User,CreatorId=101}
local values={TeamTestMode={Value=false},TeamTestHostUserId={Value="0"},WorldStorageProvider={Value="Http"}}
local config={FindFirstChild=function(_,name)return values[name]end}
local c=Context.resolve(cloudRun,place,config)
check(not c.studio and c.reserved and not c.testHost,"private IDs alone do not enable Studio-save access")
values.TeamTestMode.Value=true;c=Context.resolve(cloudRun,place,config)
check(c.studio and not c.reserved and c.testHost==101,"explicit cloud test uses Studio saves and the authoritative experience owner")
check(Context.resolve(localRun,place,config).testHost==101,"explicit mode also supports local testing")
place.CreatorType=Enum.CreatorType.Group
check(not pcall(Context.resolve,cloudRun,place,config),"group ID cannot be mistaken for a user ID")
values.TeamTestHostUserId.Value="303"
check(Context.resolve(cloudRun,place,config).testHost==303,"group-owned test can name a trusted host explicitly")
place.PrivateServerId=""
check(not pcall(Context.resolve,cloudRun,place,config),"explicit test cannot expose Studio saves in a public server")
place.PrivateServerId="test-private";values.WorldStorageProvider.Value="Session"
check(not pcall(Context.resolve,cloudRun,place,config),"cloud test cannot silently fall back to temporary saves")
values.TeamTestMode.Value=false;c=Context.resolve(localRun,place,config)
check(c.studio and not c.reserved and not c.testHost,"ordinary local Studio behavior stays unchanged")
print(string.format("World Team Test context passed: %d assertions",count))
