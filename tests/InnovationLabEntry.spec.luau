check(network:GetAttribute("GameMode")=="BattleRoyale" and controls[101].mode=="OnFoot","public server ignores lab arrival data and stays Playground")
local travel=network:FindFirstChild("InnovationLabTravel")
travel.OnServerEvent:Fire(first,"Enter")
local call=departures[1]
check(call and call.place==game.PlaceId and call.party[1]==first and #call.party==1,"only the requesting player travels to the lab")
check(call.options.ReservedServerId=="test-reservation" and call.options.teleportData.mode=="InnovationLab"
 and call.options.teleportData.owner==first.UserId,"server sends its own reserved route and player identity")
check(#royale.slots==15 and controls[102].mode=="OnFoot","opening the lab does not replace the shared Playground")
print("Innovation Lab published entry routing passed")
end
CFrame.new,CFrame.Angles,CFrame.lookAt=saveNew,saveAngles,saveLookAt
Instance.new,game.GetService=saveInstance,saveService
