local arena=workspace:FindFirstChild("Arena")
local worlds=network:FindFirstChild("PlayerWorlds")
check(worlds and worlds.OnServerInvoke,"published world service initialized")
local doc=require("WorldEditorDocument").fresh();doc.id="cloud_forest"
local saved=worlds.OnServerInvoke(first,"Save",{document=doc,revision=0})
check(saved.ok and not saved.temporary and cloudProfile["player:101"].worlds[doc.id],"published saves commit to private DataStore")
check(not cloudProfile["player:102"] and not worlds.OnServerInvoke(second,"Load",doc.id).ok,"published reads/writes cannot change another player's storage")
session.OnServerEvent:Fire(first,"Leave",2);advance(61)
local result=worlds.OnServerInvoke(first,"Play",{id=doc.id,revision=1})
check(result.ok and result.teleporting and #teleportCalls==1,"published Play launches while another player remains in combat")
local call=teleportCalls[1]
check(call.place==55 and #call.players==1 and call.players[1]==first,"teleport targets same place with only its requesting player")
check(call.options.ReservedServerId=="server-generated-reservation" and call.options.data.owner==101 and call.options.data.revision==1,"server generates isolated destination and references authoritative saved revision")
check(call.options.data.document==nil and call.options.data.objects==nil,"teleport never trusts or transports client-supplied geometry")
check(arena:GetAttribute("WorldId")=="builder_demo" and snapshots["102"] and not snapshots[boomerId],"public battlefield and remaining player's tanks survive a private launch")
teleportFailed:Fire(first,"Failure","network unavailable")
local event=sessionReadings[#sessionReadings]
check(event.recipient==first and event.args[1]==0 and event.args[3]:find("network unavailable",1,true),"asynchronous teleport failure reaches requesting client")
players.PlayerRemoving:Fire(first);players.PlayerAdded:Fire(first)
check(#worlds.OnServerInvoke(first,"List").worlds==1,"durable worlds survive disconnect and re-entry")
print(string.format("Player worlds published server integration passed: %d assertions",count))
end -- server fixture
