-- Execute production model creation/animation with numeric transform stand-ins.
-- These assertions validate anchors/lifecycle, not rasterized Roblox appearance.
local count=0
local function check(ok,message) assert(ok,message); count+=1 end
local saveNew,saveAngles,saveLookAt= CFrame.new,CFrame.Angles,CFrame.lookAt
local saveInstance,saveService=Instance.new,game.GetService
local created,garbage={},{}
local identity={1,0,0,0,1,0,0,0,1}
local mt={}
local function frame(p,m) return setmetatable({p=p,m=m or identity},mt) end
local function rotate(m,v)
 return Vector3.new(m[1]*v.X+m[2]*v.Y+m[3]*v.Z,m[4]*v.X+m[5]*v.Y+m[6]*v.Z,m[7]*v.X+m[8]*v.Y+m[9]*v.Z)
end
mt.__index=function(f,key)
 if key=="Position" then return f.p end
 if key=="RightVector" then return Vector3.new(f.m[1],f.m[4],f.m[7]) end
 if key=="UpVector" then return Vector3.new(f.m[2],f.m[5],f.m[8]) end
 if key=="LookVector" then return Vector3.new(-f.m[3],-f.m[6],-f.m[9]) end
 if key=="PointToWorldSpace" then return function(self,v) return self.p+rotate(self.m,v) end end
end
mt.__mul=function(a,b)
 local m={}
 for row=0,2 do for col=0,2 do
  m[row*3+col+1]=0
  for k=0,2 do m[row*3+col+1]+=a.m[row*3+k+1]*b.m[k*3+col+1] end
 end end
 return frame(a.p+rotate(a.m,b.p),m)
end
CFrame.new=function(x,y,z) return frame(if type(x)=="number" then Vector3.new(x,y,z) else x or Vector3.zero) end
CFrame.Angles=function(x,y,z)
 local cx,sx,cy,sy,cz,sz=math.cos(x),math.sin(x),math.cos(y),math.sin(y),math.cos(z),math.sin(z)
 return frame(Vector3.zero,{1,0,0,0,cx,-sx,0,sx,cx})*frame(Vector3.zero,{cy,0,sy,0,1,0,-sy,0,cy})*frame(Vector3.zero,{cz,-sz,0,sz,cz,0,0,0,1})
end
CFrame.lookAt=function(position,target)
 local f=(target-position).Unit
 local r=Vector3.new(-f.Z,0,f.X).Unit
 local u=Vector3.new(r.Y*f.Z-r.Z*f.Y,r.Z*f.X-r.X*f.Z,r.X*f.Y-r.Y*f.X)
 return frame(position,{r.X,u.X,-f.X,r.Y,u.Y,-f.Y,r.Z,u.Z,-f.Z})
end
Vector3.one=Vector3.new(1,1,1)
Instance.new=function(class)
 local p=saveInstance(class)
 p.Play=function(self) self.played=true end
 p.Destroy=function(self)
  for _,child in self.children do child:Destroy() end
  self.destroyed=true; self.Parent=nil
 end
 setmetatable(p,{__index=function(self,key)
  if key=="CFrame" and rawget(self,"Position") then return CFrame.new(self.Position) end
 end,__newindex=function(self,key,value)
  rawset(self,key,value)
  if key=="Parent" and value and value.children then table.insert(value.children,self) end
 end})
 table.insert(created,p); return p
end
local tweenService={Create=function(_,p,info,goal) return {Play=function() end,Completed=signal()} end}
local debris={AddItem=function(_,p,lifetime) table.insert(garbage,{part=p,lifetime=lifetime}) end}
game.GetService=function(self,name)
 if name=="TweenService" then return tweenService end
 if name=="Debris" then return debris end
 return saveService(self,name)
end
local Renderer=require("TankRenderer")
local Sim=require("TankSimulation")
-- Boot and exercise the production server entrypoint with two simulated players.
do
 local savedClock=os.clock
 local time=10
 os.clock=function() return time end
 local players={PlayerAdded=signal(),PlayerRemoving=signal()}
 local first={UserId=101}; local second={UserId=102}
 players.GetPlayers=function() return {first,second} end
 players.GetPlayerByUserId=function(_,id) return if id==101 then first elseif id==102 then second else nil end
 local heartbeat=signal()
 local shots,prepared,snapshots,battleStates,privateOutputs,privateRuntime={}, {}, {}, {}, {}, {}
 local sessionReadings={}
 local ideProbe
 local oldFactory=Instance.new
 Instance.new=function(class)
  local p=oldFactory(class)
  p.FindFirstChild=function(self,name)
   for _,child in self.children do if child.Name==name and not child.destroyed then return child end end
  end
  if class=="RemoteEvent" then
   p.OnServerEvent=signal()
   p.FireClient=function(self,recipient,...)
   local args={...}
   if self.Name=="BattleSession" then table.insert(sessionReadings,{recipient=recipient,args=args}) end
   if ideProbe and recipient==first then
    if self.Name=="BWOutput" then ideProbe:receiveOutput(table.unpack(args)) end
    if self.Name=="BWRuntimeState" then ideProbe:receiveRuntime(table.unpack(args)) end
   end
   if self.Name=="BWOutput" then table.insert(privateOutputs,{recipient=recipient,args={...}}) elseif self.Name=="BWRuntimeState" then table.insert(privateRuntime,{recipient=recipient,args={...}}); if #privateRuntime>32 then table.remove(privateRuntime,1) end end end
   p.FireAllClients=function(self,...)
    local args={...}
    if self.Name=="Shot" then table.insert(shots,{time=time,id=args[1],kind=args[4],origin=args[2],direction=args[3],rock=args[6],weaponId=args[7]}) end
    if self.Name=="PrepareShot" then table.insert(prepared,{time=time,id=args[1],kind=args[2],weaponId=args[4]}) end
    if self.Name=="Snapshot" then
     battleStates=args[2] or {}; snapshots={}; for id,state in args[1] do
      snapshots[id]=table.clone(state)
      for _,hitbox in created do
       if hitbox.Name=="TankHitbox" and not hitbox.destroyed and hitbox:GetAttribute("TankId")==id then
        check((hitbox.CFrame.Position-(state.position+Vector3.new(0,2.5,0))).Magnitude<1e-6,"hitbox matches actual simulated recoil position at snapshot")
       end
      end
     end
     if ideProbe then ideProbe:update(snapshots["101:Rattler"]) end
    end
   end
  end
  return p
 end
 local originalWorkspaceFind=workspace.FindFirstChild
 workspace.FindFirstChild=function(self,name)
  for _,child in self.children do if child.Name==name and not child.destroyed then return child end end
 end
 workspace.GetPartBoundsInRadius=function() return {} end
 workspace.Spherecast=function() return nil end
 game.GetService=function(self,name)
  if name=="Players" then return players end
  if name=="ReplicatedStorage" then return game.ReplicatedStorage end
  if name=="RunService" then return {Heartbeat=heartbeat,IsStudio=function() return true end} end
  if name=="TweenService" then return tweenService end
  if name=="Debris" then return debris end
  return saveService(self,name)
 end
 game.ReplicatedStorage.WaitForChild=function(self,name) return self[name] end
 workspace:SetAttribute("ArenaWeather","Normal") -- historical handling/combat baseline
 workspace:SetAttribute("SoloTankPairs",true) -- explicit historical solo fixture
 require("ServerEntrypoint")
 local network
 for _,p in created do if p.Name=="TankNetwork" and not p.destroyed then network=p end end
 local session=network:FindFirstChild("BattleSession")
 session.OnServerEvent:Fire(first,"Enter",1)
 session.OnServerEvent:Fire(second,"Enter",1)
 local input=network:FindFirstChild("Input")
 local select=network:FindFirstChild("SelectTank")
 local bwRun,bwStop=network:FindFirstChild("BWRun"),network:FindFirstChild("BWStop")
 local reset=network:FindFirstChild("ResetBattle")
 local redraw=network:FindFirstChild("RedrawMap")
 local boomerId,rattlerId="101","101:Rattler"
 local command={throttle=0,steer=0,fire=false,aimMode="Rate",turretX=0,turretY=0}
 local function advance(frames)
  for _=1,frames do time+=1/60; heartbeat:Fire(1/60) end
 end
 local function selected() return battleStates["101"].selected end
 local function tick(fire)
  time+=1/60; command.fire=fire
  input.OnServerEvent:Fire(first,command,selected()); heartbeat:Fire(1/60)
 end
 advance(4)
 check(snapshots[boomerId].tankType=="Boomer" and snapshots[rattlerId].tankType=="Rattler","both tank types exist together")
 check(snapshots[boomerId].health==100 and snapshots[rattlerId].health==100,"both tanks start with 100 HP")
 for _,expected in {{boomerId,"Bunny"},{rattlerId,"Octa"}} do
  local found=false
  for _,event in privateRuntime do if event.recipient==first and event.args[1]==expected[1] and event.args[2].configuration.tier==expected[2] then found=true end end
  check(found,"production default chassis diagnostics: "..expected[2])
 end
 check((snapshots[boomerId].position-snapshots[rattlerId].position).Magnitude>10,"battle pair has separate spawns")
 check(math.abs(snapshots[boomerId].yaw+snapshots[rattlerId].yaw)<1e-6,"battle pair faces inward")
 local generation=snapshots[boomerId].generation
 local idleRattler=snapshots[rattlerId].position
 tick(false)
 for _=1,150 do tick(true) end
 check(#prepared>=2 and #shots>=2,"production Boomer prepares and releases shells")
 check(shots[1].kind=="Boomer" and shots[1].time-prepared[1].time>=0.2/snapshots[boomerId].weaponPerformance-1e-5,"Boomer production windup follows shared-bus allocation")
 check(math.abs(snapshots[boomerId].aimRecoilYaw or 0)>0,"Boomer shell release kicks its actual turret")
 local originalCount=#shots
 select.OnServerEvent:Fire(first,"Rattler")
 for _=1,5 do tick(false) end
 local start=time
 for _=1,183 do tick(true) end
 check(snapshots[rattlerId].lift>=0 and snapshots[rattlerId].lift<=6,"Rattler hops within six studs while firing")
 check(snapshots[rattlerId].weaponCooldown>1.9,"Rattler enters two-second lockout")
 local rapid=0
 for i=originalCount+1,#shots do
  check(shots[i].kind=="Rattler" and shots[i].time-start<=3+1e-5,"only Rattler rounds during allowed burst")
  rapid+=1
 end
 check(rapid>=28 and rapid<=30,"production server preserves rapid projectile rate")
 check(shots[originalCount+1].rock and math.abs(shots[originalCount+1].rock.roll)>0.1,"release event carries physical roll")
 check((shots[originalCount+1].direction-shots[originalCount+2].direction).Magnitude>0.005,"Rattler rounds use turret recoil direction")
 local lockedShots=#shots
 for _=1,114 do tick(true) end
 check(#shots==lockedShots,"held trigger blocked during lockout")
 for _=1,10 do tick(true) end
 check(#shots>lockedShots,"fire resumes after full lockout")
 select.OnServerEvent:Fire(first,"Boomer"); advance(5)
 check(snapshots[boomerId].generation==generation and snapshots[boomerId].tankType=="Boomer","selection preserves existing Boomer model generation")
 check(snapshots[rattlerId].lift>0,"unselected Rattler remains airborne and simulated")
 advance(240)
 check(snapshots[rattlerId].lift==0 and not snapshots[rattlerId].firing,"unselected tank releases manual trigger and lands")
 select.OnServerEvent:Fire(first,{tankType="Rattler"}); advance(4)
 check(selected()==boomerId,"malformed selection rejected")
 local function fresh()
  advance(40); reset.OnServerEvent:Fire(first); advance(4)
 end
 local request=0
 local function run(id,source)
  request+=1; bwRun.OnServerEvent:Fire(first,source,request,id); return request
 end
 local function stop(id)
  request+=1; bwStop.OnServerEvent:Fire(first,request,id)
 end
 -- Production hardware is ownership-validated, cannot mutate a running CPU, and diagnostics are private.
 local hardware=network:FindFirstChild("BWHardware")
 local H=require("BWChassis")
 hardware.OnServerEvent:Fire(first,H.default("Bunny"),boomerId); advance(20)
 local last=privateRuntime[#privateRuntime]
 local foundBunny=false
 for _,event in privateRuntime do if event.args[1]==boomerId and event.args[2].configuration.tier=="Bunny" then foundBunny=true end end
 check(foundBunny,"production hardware changes validated chassis")
 run(boomerId,"with thread(2):\n    forward(2)"); advance(4)
 check(snapshots[boomerId].bwStatus=="error" and not snapshots[boomerId].bwRunning,"server rejects thread above hardware capacity")
 advance(40); hardware.OnServerEvent:Fire(first,H.default(),boomerId); advance(20)
 local concurrent=[=[with thread(1):
    forward(50)
    ready = true
with thread(2):
    wait_for(ready)
    turret_right(30)
    print("coordinated")]=]
 run(boomerId,concurrent); advance(12)
 local observedThreads=false
 for _,event in privateRuntime do
  if event.args[1]==boomerId and event.args[2].runtime and event.args[2].runtime.threads[2] then
   check(event.recipient==first,"thread diagnostics private to owner")
   observedThreads=true
  end
 end
 check(observedThreads,"production diagnostics expose independent thread state")
 local configRequestCount=#privateRuntime
 hardware.OnServerEvent:Fire(first,H.default("Bunny"),boomerId); advance(2)
 local denied=false
 for i=1,#privateRuntime do if privateRuntime[i].args[2].configurationResult=="programRunning" then denied=true end end
 check(denied,"hardware cannot change while program owns devices")
 stop(boomerId); fresh()
 -- Wire the real BW scanner/private-output path against analytic tank hitboxes.
 local savedQuery,savedRaycast=workspace.GetPartBoundsInRadius,workspace.Raycast
 workspace.GetPartBoundsInRadius=function(_,origin,radius,params)
  if params.FilterType~=Enum.RaycastFilterType.Include then return {} end
  local result={}
  for _,p in params.FilterDescendantsInstances do if p.Name=="TankHitbox" and p.CanQuery then table.insert(result,p) end end
  return result
 end
 workspace.Raycast=function(_,origin,direction,params)
  local best,minimum=nil,1
  local function dot(a,b) return a.X*b.X+a.Y*b.Y+a.Z*b.Z end
  for _,p in params.FilterDescendantsInstances do
   if p.Name~="TankHitbox" or not p.CanQuery then continue end
   local f=p.CFrame; local axes={f.RightVector,f.UpVector,f.LookVector* -1}; local half=p.Size/2; local sizes={half.X,half.Y,half.Z}
   local low,high=0,1
   for i,axis in axes do
    local a,d=dot(origin-f.Position,axis),dot(direction,axis)
    if math.abs(d)<1e-10 then if math.abs(a)>sizes[i] then high=-1; break end
    else
     local left,right=(-sizes[i]-a)/d,(sizes[i]-a)/d
     if left>right then left,right=right,left end
     low=math.max(low,left); high=math.min(high,right)
    end
   end
   if low<=high and low<minimum then best=p; minimum=low end
  end
  if best then return {Instance=best,Position=origin+direction*minimum,Distance=direction.Magnitude*minimum} end
 end
 fresh()
 local beforeManualOutputs=#privateOutputs
 advance(40)
 local driven=selected(); local parked=if driven==boomerId then rattlerId else boomerId
 check(snapshots[driven].manualScannerActive and snapshots[driven].scanManual and not snapshots[parked].manualScannerActive,"production auto scanner runs only for selected manual tank")
 check(#privateOutputs==beforeManualOutputs,"continuous driver scans never flood BW IDE output")
 run(driven,"forward(100)"); advance(4)
 check(snapshots[driven].bwRunning and not snapshots[driven].manualScannerActive and snapshots[driven].scanManual==nil,"starting BW stops auto scanning and removes driver-only observations")
 stop(driven); advance(12)
 check(snapshots[driven].manualScannerActive and snapshots[driven].scanManual,"manual sweep resumes automatically after Stop")
 fresh()
 -- Exact latest user source: unconditional print of the scanner dictionary.
 local IDE=require("BWIDE")
 ideProbe=IDE.new(Instance.new("PlayerGui"),function(code) return run(rattlerId,code) end,function() stop(rattlerId); return request end)
 ideProbe:bind(rattlerId)
 local unconditional=[=[with thread(1):
    while true:
        scan0 = Scanner(position=0)
        print(scan0)
        if scan0.status == "success" and scan0.count > 0:
            print(scan0.detections[0])]=]
 ideProbe.editor.Text=unconditional; ideProbe.run.Activated:Fire(); advance(180)
 check(snapshots[rattlerId].bwRunning,"exact unconditional-print loop remains running")
 local history=ideProbe.scanOutputs[rattlerId]
 check(history and history.receivedPrints>10,"server print events reach actual IDE receiver through remotes")
 check(ideProbe.output.Text:find("print",1,true) and ideProbe.output.Text:find('"status": "success"',1,true),"unconditional print is present in visible log page")
 check(#ideProbe.outputPages>1 and #ideProbe.output.Text<=8192,"growing loop logs are displayed in bounded native text pages")
 check(ideProbe.logStatus.Text:find("Prints run:",1,true) and not ideProbe.logStatus.Text:find("run: 0",1,true),"independent header confirms actual server print execution")
 local reading=ideProbe.runtimeReadings[rattlerId]
 check(reading.runtime.threads[1].loopTests>0 and reading.runtime.threads[1].prints>0,"thread diagnostics distinguish loop tests and print dispatch")
 stop(rattlerId); fresh()
 local queryWithTargets=workspace.GetPartBoundsInRadius
 workspace.GetPartBoundsInRadius=function() return {} end
 ideProbe.editor.Text=unconditional; ideProbe.run.Activated:Fire(); advance(90)
 history=ideProbe.scanOutputs[rattlerId]
 check(history and history.receivedPrints>0,"unconditional print runs even when every scan is empty")
 check(ideProbe.output.Text:find('"count": 0',1,true),"empty scan dictionary reaches visible IDE log")
 workspace.GetPartBoundsInRadius=queryWithTargets
 stop(rattlerId); ideProbe:destroy(); ideProbe=nil
 fresh()
 local scanBlocks={}
 for position=0,7 do table.insert(scanBlocks,string.format('with thread(%d):\n    while true:\n        scan%d = Scanner(position=%d)\n        if scan%d.status == "success" and scan%d.count > 0:\n            print(scan%d.detections[0])',position+1,position,position,position,position,position)) end
 local firstOutput=#privateOutputs
 run(rattlerId,table.concat(scanBlocks,"\n\n")); advance(120)
 local active=snapshots[rattlerId].scanBW or {}; local activeCount=0
 for _,event in active do
  activeCount+=1
  check(event.player==nil and event.distance==nil and event.point==nil,"each BW light event remains coarse, without exact observations")
 end
 check(activeCount==8 and snapshots[rattlerId].bwRunning,"all eight completed BW scans survive simultaneous snapshot replication")
 local explicitPrint=false; local observedAngles={}
 for i=firstOutput+1,#privateOutputs do
  local entry=privateOutputs[i].args[4]
  if privateOutputs[i].args[1]~=rattlerId then continue end
  if entry.kind=="scan" then observedAngles[entry.angle]=true end
  if entry.kind=="print" then explicitPrint=true end
 end
 for position=0,7 do check(observedAngles[position*45],"production loop acquires sensor "..position) end
 check(explicitPrint,"actual opponent detection reaches user's explicit print guard")
 stop(rattlerId); advance(100)
 check(snapshots[rattlerId].scanBW==nil,"all BW lens events expire independently after Stop")
 fresh()
 check(snapshots[rattlerId].scanBW==nil,"reset clears per-sensor BW light state")
 local outputsBefore=#privateOutputs
 run(boomerId,"Scanner(0)"); run(rattlerId,"Scanner(0)"); advance(12)
 check(#privateOutputs==outputsBefore+2,"two independent BW programs each execute one scanner call")
 for i=outputsBefore+1,#privateOutputs do
  local output=privateOutputs[i]
  check(output.recipient==first and output.args[4].text:find('"tank"',1,true),"scanner result delivered only to owner, not broadcast")
  check(output.args[4].timestamp>=0 and output.args[2]==snapshots[output.args[1]].generation,"private result carries measurement timestamp and generation")
 end
 check(snapshots[boomerId].bwStatus=="completed" and snapshots[rattlerId].bwStatus=="completed","standalone scan completes both production runtimes")
 check(snapshots[boomerId].scanVisual.kind=="tank" and snapshots[boomerId].scanVisual.distance==nil and snapshots[boomerId].scanVisual.player==nil,"public reaction contains no exact range, identity or hidden hit position")
 check(not snapshots[boomerId].bwMessage:find("101:Rattler",1,true),"public BW status never includes private scan result")
 advance(80)
 check(snapshots[boomerId].scanVisual==nil and snapshots[rattlerId].scanVisual==nil,"public sensor state expires without another scan")
 outputsBefore=#privateOutputs
 run(boomerId,"forward(100)\nScanner(0)"); advance(2); stop(boomerId); advance(5)
 check(#privateOutputs==outputsBefore+1 and privateOutputs[#privateOutputs].args[4].kind=="result","Stop cancels pending acquisition while retaining forward acceptance log")
 fresh()
 check(snapshots[boomerId].scanVisual==nil and snapshots[rattlerId].scanVisual==nil,"reset clears both scanner reactions")
 fresh()
 local beforeDecision=#privateOutputs
 local program=[=[target = Scanner(0)
if target.type == "tank":
    print(target.player)
    forward(2)
else:
    print("nothing")]=]
 local firstRun=run(boomerId,program); local secondRun=run(rattlerId,program)
 for _=1,240 do
  advance(1)
  if (snapshots[boomerId].bwRequestId or 0)>=firstRun and (snapshots[rattlerId].bwRequestId or 0)>=secondRun and not snapshots[boomerId].bwRunning and not snapshots[rattlerId].bwRunning then break end
 end
 check(snapshots[boomerId].bwStatus=="completed" and snapshots[rattlerId].bwStatus=="completed","production v0.2 decisions and asynchronous movement execute independently on both tanks")
 local scanCount,printCount=0,0
 for i=beforeDecision+1,#privateOutputs do
  local output=privateOutputs[i]
  check(output.recipient==first,"expression values and prints stay private to program owner")
  if output.args[4].kind=="scan" then scanCount+=1 elseif output.args[4].kind=="print" then printCount+=1 end
 end
 check(scanCount==2 and printCount==2,"production output stream contains one diagnostic plus one explicit print per program")
 check(snapshots[boomerId].variables==nil and not snapshots[boomerId].bwMessage:find("AI.Rattler",1,true),"program variables and printed identities never enter public snapshots")
 workspace.GetPartBoundsInRadius=savedQuery; workspace.Raycast=savedRaycast
 for _,id in {boomerId,rattlerId} do
  fresh()
  local before=#shots
  local demoRequest=run(id,require("BWConfig").DefaultSource)
  for _=1,6000 do
   advance(1)
   if (snapshots[id].bwRequestId or 0)>=demoRequest and snapshots[id].bwStatus and snapshots[id].bwStatus~="running" then break end
  end
  check(snapshots[id].bwStatus=="completed","production BW demo completes on "..id..": "..tostring(snapshots[id].bwMessage))
  check(#shots-before>0,"production BW demo fires normal weapon on "..id)
 end
 fresh()
 local startPose=snapshots[boomerId].position
 local heading=snapshots[boomerId].yaw
 run(boomerId,"forward(100)")
 command.throttle=-1; command.steer=1
 for _=1,10 do tick(true) end
 check((snapshots[boomerId].position-startPose).Magnitude>0 and math.abs(snapshots[boomerId].yaw-heading)<1e-8,"manual inputs cannot override BW")
 select.OnServerEvent:Fire(first,"Rattler"); advance(5)
 check(snapshots[boomerId].bwRunning and selected()==rattlerId,"switch preserves unselected tank program")
 local currentBoomer=snapshots[boomerId].position
 command.throttle=1; command.steer=0
 for _=1,12 do tick(false) end
 check((snapshots[boomerId].position-currentBoomer).Magnitude>0 and (snapshots[rattlerId].position-idleRattler).Magnitude>0,"manual driving and other tank BW coexist")
 run(rattlerId,"fire(2)"); advance(5)
 check(snapshots[boomerId].bwRunning and snapshots[rattlerId].bwRunning,"two BW runtimes run simultaneously")
 stop(rattlerId); advance(5)
 check(not snapshots[rattlerId].bwRunning and snapshots[boomerId].bwRunning,"Stop affects only intended tank")
 stop(boomerId); advance(5)
 check(snapshots[boomerId].speed==0 and not snapshots[boomerId].firing,"Stop releases throttle and trigger")
 fresh()
 local before=snapshots[boomerId].position
 input.OnServerEvent:Fire(first,command,boomerId); advance(8)
 check((snapshots[boomerId].position-before).Magnitude<1e-6,"stale manual input for unselected tank is rejected")
 run(boomerId,"fire()"); advance(1); stop(boomerId)
 local stoppedShots=#shots; advance(30)
 check(#shots==stoppedShots,"Stop cancels prepared Boomer shot")
 request+=2; bwStop.OnServerEvent:Fire(first,request,boomerId)
 bwRun.OnServerEvent:Fire(first,"fire(2)",request-1,boomerId); advance(5)
 check(not snapshots[boomerId].bwRunning and snapshots[boomerId].bwRequestId==request,"late Run cannot overtake Stop")
 bwRun.OnServerEvent:Fire(second,"forward(3)",999,boomerId); advance(5)
 check(snapshots[boomerId].bwRequestId==request,"other player cannot control this tank by explicit id")
 -- The production projectile impact path, with engine sweeps returning chosen hits.
 local hitboxes={}
 for _,p in created do if p.Name=="TankHitbox" and not p.destroyed then hitboxes[p:GetAttribute("TankId")]=p end end
 local targetId,shooterId,remainingHits
 workspace.Spherecast=function(_,origin,radius,delta,params)
  local source=params.FilterDescendantsInstances[1]
  if remainingHits and remainingHits>0 and source==hitboxes[shooterId] then
   remainingHits-=1
   return {Instance=hitboxes[targetId],Position=origin+delta.Unit*0.01,Distance=0.01}
  end
 end
 fresh()
 targetId,shooterId,remainingHits=rattlerId,boomerId,1
 run(boomerId,"fire()"); advance(50)
 check(snapshots[rattlerId].damageByWeapon.Cannon==25 and snapshots[rattlerId].damageSerial==1,"production impact replicates weapon attribution and hit serial")
 check(snapshots["102"].damageSerial==0 and snapshots["102:Rattler"].damageSerial==0,"other owner receives independent injury state")
 check(snapshots[rattlerId].health==75 and snapshots[boomerId].health==100,"Boomer projectile damages only opponent by existing 25 damage")
 advance(20)
 check(snapshots[rattlerId].health==75,"one projectile cannot damage twice")
 fresh()
 targetId,shooterId,remainingHits=boomerId,boomerId,1
 run(boomerId,"fire()"); advance(50)
 check(snapshots[boomerId].health==100,"self-damage blocked even if query returns own hitbox")
 fresh()
 targetId,shooterId,remainingHits=boomerId,rattlerId,1
 run(rattlerId,"fire()"); advance(35)
 check(snapshots[boomerId].damageByWeapon.Gatling==6 and snapshots[boomerId].smokeSeverity==0,"production Gatling damage does not create cannon smoke")
 check(snapshots[boomerId].health==94,"Rattler retains six damage per shot")
 fresh()
 targetId,shooterId,remainingHits=boomerId,rattlerId,9
 run(rattlerId,"fire(0.9)")
 select.OnServerEvent:Fire(first,"Boomer"); advance(4)
 command.throttle=0; command.steer=0; command.turretX=0; tick(false)
 for _=1,150 do advance(1); if snapshots[boomerId].immobilized then break end end
 check(snapshots[boomerId].health==46 and snapshots[boomerId].immobilized,"production server schedules first Gatling immobilization at injured HP")
 local jamStart=time
 local jamPosition=snapshots[boomerId].position
 local jamYaw=snapshots[boomerId].yaw
 command.throttle=1; command.steer=1; command.turretX=0.5
 tick(false)
 for _=1,13 do tick(true) end
 check((snapshots[boomerId].position-jamPosition).Magnitude<1e-6 and snapshots[boomerId].yaw==jamYaw,"production manual throttle/steering suppressed during immobilization")
 check((snapshots[boomerId].weaponActivationSerial or 0)>0 and snapshots[boomerId].turretYaw~=jamYaw,"production victim can aim and activate weapon while immobilized")
 for _=1,30 do if not snapshots[boomerId].immobilized then break end; advance(1) end
 check(time-jamStart>=0.25 and time-jamStart<=0.36,"production scheduler advances once per simulation tick and preserves 0.3-second duration")
 command.steer=0; command.turretX=0
 for _=1,8 do tick(false) end
 check((snapshots[boomerId].position-jamPosition).Magnitude>0.1,"manual mobility resumes automatically after episode")
 command.throttle=0
 fresh()
 targetId,shooterId,remainingHits=rattlerId,boomerId,4
 run(rattlerId,"forward(100)"); run(boomerId,"fire(3)"); advance(190)
 check(snapshots[rattlerId].health==0 and battleStates["101"].winner=="Boomer","four cannon impacts destroy tank and announce winner")
 check(snapshots[rattlerId].fatalWeapon=="Cannon" and not snapshots[rattlerId].immobilized and not snapshots[rattlerId].smokeBurst,"production death records fatal weapon and stops statuses")
 check(not snapshots[rattlerId].bwRunning and not snapshots[rattlerId].firing and not hitboxes[rattlerId].CanQuery,"destruction stops BW, clears inputs and disables damage queries")
 local deathShots=#shots
 run(rattlerId,"fire(2)"); advance(220)
 check(snapshots[rattlerId].health==0 and not snapshots[rattlerId].bwRunning and #shots==deathShots,"wreck cannot fire or automatically respawn")
 fresh()
 check(next(snapshots[rattlerId].damageByWeapon)==nil and snapshots[rattlerId].fatalWeapon==nil and snapshots[rattlerId].smokeSeverity==0 and not snapshots[boomerId].immobilized,"production reset clears attribution and both injury channels")
 check(snapshots[boomerId].health==100 and snapshots[rattlerId].health==100 and not battleStates["101"].winner,"reset restores both HP and clears winner")
 check((snapshots[rattlerId].lift or 0)==0 and snapshots[rattlerId].heat==0 and snapshots[rattlerId].weaponCooldown==0,"reset clears recoil, heat and cooldown")
 check(not snapshots[boomerId].bwRunning and not snapshots[rattlerId].bwRunning and hitboxes[rattlerId].CanQuery,"reset stops both programs and restores hitboxes")
 local expected,yaw=require("LocalBattle").pose(Vector2.new(230,230),1,"Rattler")
 check((snapshots[rattlerId].position-expected).Magnitude<0.01 and snapshots[rattlerId].yaw==yaw,"reset restores original spawn and heading")
 local shellModels=0
 for _,p in created do if p.ClassName=="Model" and p.Name:sub(1,6)=="Shell_" and not p.destroyed then shellModels+=1 end end
 check(shellModels==0,"battle reset removes active projectiles")
 run(boomerId,"forward(100)"); run(rattlerId,"forward(100)"); advance(5)
 redraw.OnServerEvent:Fire(first,Vector2.new(230,230)); advance(5)
 check(not snapshots[boomerId].bwRunning and not snapshots[rattlerId].bwRunning and snapshots[boomerId].bwMessage=="Map redrawn.","redraw resets both programs")
 players.PlayerRemoving:Fire(first); advance(5)
 check(snapshots[boomerId]==nil and snapshots[rattlerId]==nil and snapshots["102"]~=nil and snapshots["102:Rattler"]~=nil,"departure removes only owner's pair")
 local liveHitboxes=0
 for _,p in created do if p.Name=="TankHitbox" and not p.destroyed then liveHitboxes+=1 end end
 check(liveHitboxes==2,"selection keeps two hitboxes per player and departure cleans both")
 print("Production battle integration passed: persistent pair, independent controls/BW, damage/death, switching/reset, ownership and cleanup")

 heartbeat=nil
 Instance.new=oldFactory; os.clock=savedClock; workspace.FindFirstChild=originalWorkspaceFind
 print("Production server integration passed: Boomer windup, Rattler burst/flight/cooldown, switch, ownership and cleanup")
end

Instance.new=saveInstance; game.GetService=saveService
CFrame.new=saveNew; CFrame.Angles=saveAngles; CFrame.lookAt=saveLookAt
print(string.format("Server integration suite passed: %d assertions",count))
