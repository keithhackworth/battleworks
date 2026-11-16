local worlds=network:FindFirstChild("PlayerWorlds")
check(not snapshots[boomerId] and not snapshots["102"],"cloud test participants wait in menu until host loads a world")
local doc=require("WorldEditorDocument").editorFresh();doc.id="studio_test_world"
for i,p in {{-60,0,-60},{0,0,-60},{60,0,-60},{-60,0,60},{60,0,60}} do table.insert(doc.spawns,{id="start_"..i,slot=i,position=p,heading=0})end
testStore:save(101,doc,0)
local list=worlds.OnServerInvoke(first,"List")
check(list.ok and list.teamTest and #list.worlds==1,"cloud host sees an existing Studio world")
check(not worlds.OnServerInvoke(second,"Load",doc.id).ok,"collaborator cannot access host's private save")
local launch=worlds.OnServerInvoke(first,"Play",{id=doc.id,revision=1})
check(launch.ok and launch.launch and #teleportCalls==0,"test host loads the world into the shared server without teleport")
check(workspace:FindFirstChild("Arena"):GetAttribute("WorldId")==doc.id,"server installs the host's selected test world")
session.OnServerEvent:Fire(first,"Enter",2);session.OnServerEvent:Fire(second,"Enter",2);advance(4)
check(snapshots[boomerId] and snapshots["102"],"both computers can enter the same loaded world")
check(math.abs(snapshots["102"].position.X)<1e-5 and math.abs(snapshots["102"].position.Z+60)<1e-5,"collaborator starts at player 2's authored area")
print(string.format("Cloud Team Test host/guest integration passed: %d assertions",count))
end -- server fixture
