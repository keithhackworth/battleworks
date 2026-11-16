game.PrivateServerId="cloud-team-test";game.PrivateServerOwnerId=0;game.CreatorId=101;game.CreatorType=Enum.CreatorType.User
local flag=Instance.new("BoolValue");flag.Name="TeamTestMode";flag.Value=true;flag.Parent=config
local host=Instance.new("StringValue");host.Name="TeamTestHostUserId";host.Value="0";host.Parent=config
local provider=Instance.new("StringValue");provider.Name="WorldStorageProvider";provider.Value="Http";provider.Parent=config
local testStore=require("PlayerWorldStore").new(ds,false,function()return "json"end);testStore.kind="Http"
loaders.PlayerWorldStorage=function()return {create=function(_,_,studio)
 check(studio,"cloud Team Test chooses the Studio save namespace despite IsStudio=false")
 return testStore
end}end
