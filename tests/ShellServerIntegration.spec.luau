check(next(snapshots)==nil and next(battleStates)==nil,"joining experience allocates no tanks")
input.OnServerEvent:Fire(first,command,"101")
bwRun.OnServerEvent:Fire(first,"fire(8)",1,"101")
reset.OnServerEvent:Fire(first)
advance(10)
check(next(snapshots)==nil and #shots==0,"menu remotes cannot drive, fire, run BW or reset a battle")
for _,bad in {{"Enter",0},{"Enter",0/0},{"Enter","1"},{"Enter",math.huge},{"Unexpected",1},{"Enter",{}},{"Enter",1.5}} do session.OnServerEvent:Fire(first,table.unpack(bad)) end
advance(4)
check(next(snapshots)==nil,"admission validates action and request IDs")
session.OnServerEvent:Fire(second,"Enter",1); advance(5)
check(snapshots["102"] and snapshots["102:Rattler"] and not snapshots["101"],"only admitted player's collection is spawned")
check(not battleStates["102"].multiplayer,"menu presence does not turn solo gameplay into multiplayer")
local untouched=snapshots["102"].generation
session.OnServerEvent:Fire(first,"Enter",1); advance(5)
check(snapshots["101"] and snapshots["101:Rattler"] and battleStates["102"].multiplayer,"admission uses existing shared battle and collection ownership")
check(sessionReadings[#sessionReadings].recipient==first and sessionReadings[#sessionReadings].args[2]==true,"server acknowledges admission only to requester")
local generation=snapshots["101"].generation
session.OnServerEvent:Fire(first,"Enter",2); advance(3)
check(snapshots["101"].generation==generation,"duplicate enter does not replace or duplicate tanks")
session.OnServerEvent:Fire(first,"Leave",3); advance(4)
check(not snapshots["101"] and not snapshots["101:Rattler"] and not battleStates["101"],"menu return removes complete owned collection")
check(snapshots["102"].generation==untouched,"returning to menu does not reset another player's battle")
input.OnServerEvent:Fire(first,command,"102")
bwRun.OnServerEvent:Fire(first,"fire(8)",99,"102")
session.OnServerEvent:Fire(first,"Enter",2); advance(4)
check(not snapshots["101"] and not snapshots["102"].bwRunning,"late Enter and gameplay messages cannot restore participation or control others")
session.OnServerEvent:Fire(first,"Enter",4); advance(3)
check(not snapshots["101"] and sessionReadings[#sessionReadings].args[2]==false,"rapid admission is server rate limited")
advance(65);session.OnServerEvent:Fire(first,"Enter",5);advance(5)
check(snapshots["101"].generation>generation and snapshots["101"].health==100,"re-entering creates a fresh lifecycle generation")
bwRun.OnServerEvent:Fire(first,"fire(8)",1,"101"); advance(15)
session.OnServerEvent:Fire(first,"Leave",6); advance(5)
check(not snapshots["101"] and not snapshots["101:Rattler"],"menu return also removes programmed tanks")
for _,p in created do
 if p.Name=="TankHitbox" and p:GetAttribute("OwnerId")==101 then check(p.destroyed,"menu return destroys all owned hitboxes") end
 if p.Name=="Shell_101" then check(p.destroyed,"menu return destroys owned shells") end
end
session.OnServerEvent:Fire(second,"Leave",2);advance(4)
check(next(snapshots)==nil,"all-menu experience contains no simulated tanks")
advance(65);session.OnServerEvent:Fire(first,"Enter",7);advance(5)
check(not battleStates["101"].multiplayer and snapshots["101:Rattler"],"fresh solo entry retains original persistent pair behavior")
players.PlayerRemoving:Fire(first);players.PlayerRemoving:Fire(second);advance(5)
check(next(snapshots)==nil,"disconnect and menu cleanup share the existing lifecycle")
os.clock=savedClock
print(string.format("Shell admission/server isolation passed: %d assertions",count))
end
CFrame.new,CFrame.Angles,CFrame.lookAt=saveNew,saveAngles,saveLookAt
Instance.new,game.GetService=saveInstance,saveService
