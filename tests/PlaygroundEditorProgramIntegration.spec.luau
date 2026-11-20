advance(4)
local boxes={}
for _,p in created do if p.Name=="TankHitbox"then boxes[p:GetAttribute("TankId")]=p end end
local ids={};for id in snapshots do table.insert(ids,id)end;table.sort(ids)
local a=ids[1]
local BW=require("BWController");local realInput=BW.input;local editorTank
BW.input=function(tank,...)if tank.id==a then editorTank=tank end;return realInput(tank,...)end
roots[101].CFrame=CFrame.new(snapshots[a].position+Vector3.new(0,3,0))
remote.OnServerEvent:Fire(first,"Enter",1,a,snapshots[a].controlEpoch);advance(4)
BW.input=realInput
local runtimeTanks={[snapshots[a].personalityId]=editorTank}
local oldClock=os.clock;local wall=oldClock()+1;os.clock=function()return wall end
editorTank.state.position=Vector3.new(110,0,40)
local editorTank=runtimeTanks[snapshots[a].personalityId]
editorTank.state.yaw=0
wall+=1
bwRun.OnServerEvent:Fire(first,require("BWConfig").DefaultSource,1,a,controls[101].epoch)
local userRuntime=editorTank.bw;local userSerial=editorTank.state.bwProgramSerial
check(userRuntime and editorTank.state.bwProgramKind=="Player"and not editorTank.autonomyActive,"editor Run explicitly detaches built-in personality lifecycle")
advance(1200)
check(userRuntime.status=="completed"and editorTank.bw==userRuntime and editorTank.state.bwProgramSerial==userSerial,"completed editor program is never silently replaced with personality")
check(editorTank.state.controlMode=="Manual"and not editorTank.state.bwRunning,"completed editor program returns occupant to Manual")
local ownLogs=0
for _,event in privateOutputs do
 if event.recipient==first and event.args[1]==a and event.args[4].programSerial==userSerial then
  ownLogs+=1
  check(not event.args[4].text:find("turn_right",1,true),"posted editor program cannot emit a personality right-turn log")
  check(event.args[4].programKind=="Player","private logs identify actual program origin")
 end
end
check(ownLogs>0,"production user program produced private output")
wall+=1
bwRun.OnServerEvent:Fire(first,"forward()\nwait_for_clock(get_clock().time + 30)",2,a,controls[101].epoch);advance(8)
network:FindFirstChild("BWStop").OnServerEvent:Fire(first,3,a,controls[101].epoch);advance(130)
check(not editorTank.state.bwRunning and editorTank.state.controlMode=="Manual"and not editorTank.autonomyActive,"Stop cannot cause the public Auto retry loop to resume a personality")
wall+=1
os.clock=oldClock
print("Playground editor program isolation passed: "..count.." assertions")
end
CFrame.new,CFrame.Angles,CFrame.lookAt=saveNew,saveAngles,saveLookAt
Instance.new,game.GetService=saveInstance,saveService
