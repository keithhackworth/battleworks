check(network:GetAttribute("GameMode")=="InnovationLab" and controls[101].mode=="Menu","published reserved arrival chooses the separate lab catalog")
remote.OnServerEvent:Fire(first,"Join",1,"retaliator")
check(#royale.slots==2,"departure fixture has an active experiment")
local travel=network:FindFirstChild("InnovationLabTravel")
travel.OnServerEvent:Fire(first,"Enter")
check(#departures==0,"lab server rejects the Playground-to-Lab action")
travel.OnServerEvent:Fire(first,"Return")
check(#departures==1 and departures[1].place==game.PlaceId and departures[1].party[1]==first
 and departures[1].options.ForcePublicServer,"return requests a public server from the same place")
travel.OnServerEvent:Fire(first,"Return")
check(#departures==1,"a pending teleport blocks duplicate requests")
teleport.TeleportInitFailed:Fire(first,Enum.TeleportResult.Failure,"Try again")
check(travelFailure=="Try again","asynchronous Roblox teleport failure is reported")
travel.OnServerEvent:Fire(first,"Return")
check(#departures==2,"a failed return can be retried")
players.PlayerRemoving:Fire(first)
check(next(royale.options.tanks)==nil and royale.members[101]==nil,"travel departure leaves no lab tank or membership")
print("Innovation Lab reserved arrival and return routing passed")
end
CFrame.new,CFrame.Angles,CFrame.lookAt=saveNew,saveAngles,saveLookAt
Instance.new,game.GetService=saveInstance,saveService
