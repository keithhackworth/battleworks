local G=require("WorldObjectGeometry")
local Objects=require("WorldObjects")
local Sim=require("TankSimulation")
local Contacts=require("VehicleContacts")
local Components=require("VehicleComponents")
local Input=require("InputCommand")
local Environment=require("Environment")
local registry=Objects.new()
local function add(id,position,rotation,size)
 local box=G.from(position,rotation,size,1)
 local frame=CFrame.new(box.position)*CFrame.Angles(math.rad(rotation[1]),math.rad(rotation[2]),math.rad(rotation[3]))
 local model={}
 function model:GetBoundingBox()return frame,Vector3.new(table.unpack(size))end
 function model:GetDescendants()return {}end
 function model:SetAttribute()end
 return registry:add(model,{id=id,position=Vector3.new(table.unpack(position)),rotation=Vector3.new(table.unpack(rotation)),interaction={solid=true,destructible=true,hp=100,fractions=Vector3.new(1,1,1)}})
end
for _,rotation in {{15,37,-12},{-25,135,15},{45,90,20}} do
 local r,u,b=G.axes(rotation)
 local cf=CFrame.Angles(math.rad(rotation[1]),math.rad(rotation[2]),math.rad(rotation[3]))
 check((r-cf.RightVector).Magnitude<1e-6 and (u-cf.UpVector).Magnitude<1e-6 and (b+cf.LookVector).Magnitude<1e-6,"authoring oriented bounds use identical Euler axes to native placement")
end
local ramp=add("ramp",{0,0,0},{15,0,0},{16,.2,30})
check(math.abs(ramp.proxy.CFrame.UpVector.Z-math.sin(math.rad(15)))<1e-6,"projectile/damage proxy follows ramp pitch")
local top=G.support(ramp.geometry,0,0,100)
check(top and top>4 and top<4.2,"server samples actual oriented upper face")
check(not G.support(ramp.geometry,0,0,1.5),"grounded tank cannot teleport to a raised surface")
local deckHeight=30*math.sin(math.rad(15))+.2*math.cos(math.rad(15))-.2
local bridge=add("bridge",{0,deckHeight,-26.5},{0,0,0},{16,.2,24})
add("down_ramp",{0,0,-53},{-15,0,0},{16,.2,30})
check(bridge.body.bottom+bridge.body.state.position.Y>7.7,"raised solid collision preserves clearance underneath")
local env={size=Vector2.new(230,230),rocks={},logs={},trees={},zones={},worldObjects=registry}
local function step(state,command)
 Sim.step(state,command,1/60,Vector2.new(230,230),env,true)
 Contacts.solve({Contacts.body("tank",state,Components.get(state).Chassis)},registry:obstacles(),1/60)
 Sim.reconcileGround(state,env)
end
for _,kind in {"Boomer","Rattler"} do
 local state=Sim.new(Vector3.new(0,0,30),kind);local cmd=Input.neutral();cmd.throttle=1
 local highest,onDeck=0,false
 for _=1,360 do
  step(state,cmd);highest=math.max(highest,state.position.Y)
  if state.position.Z< -22 and state.position.Z> -32 and state.position.Y>7 then onDeck=true end
 end
 check(highest>7 and onDeck,"existing simulation climbs a shallow ramp onto raised bridge: "..kind)
 check(state.position.Z< -70 and state.position.Y<.5,"tank descends opposite ramp back to ground: "..kind)
end
local under=Sim.new(Vector3.new(-30,0,-26.5),"Boomer");under.yaw=-math.pi/2
local cmd=Input.neutral();cmd.throttle=1
local high=0
for _=1,150 do step(under,cmd);high=math.max(high,under.position.Y)end
check(under.position.X>8 and high<.01,"tank drives beneath elevated deck without collision or snapping upward")
local highEnd=Sim.new(Vector3.new(0,0,-30),"Boomer");highEnd.yaw=math.pi
for _=1,120 do step(highEnd,cmd)end
check(highEnd.position.Z< -15 and highEnd.position.Y<.01,"tall end of a ramp remains a wall to a grounded tank approaching beneath the bridge")
local above=Sim.new(Vector3.new(0,deckHeight+.2,-26.5),"Boomer")
step(above,Input.neutral())
check(above.position.Y>7,"existing reconciliation supports parked vehicle on deck")
registry:impact({Instance=bridge.proxy},100,{})
for _=1,100 do step(above,Input.neutral())end
check(above.position.Y<.01 and registry:support(0,-26.5,100)==nil,"destruction removes bridge support and existing gravity drops tank")
registry:reset()
check(registry:support(0,-26.5,100)>7,"normal reset restores bridge support with existing durability")
local wall=G.from({0,0,0},{0,0,0},{8,5,8},1)
check(not G.canTraverse(wall,Vector3.zero),"ground-height walls remain blocking cover")
local steep=G.from({0,0,0},{75,0,0},{12,1,24},1)
check(not G.support(steep,0,0,100),"steep faces are obstacles rather than climbable surfaces")
local nativeLimit=G.from({0,0,0},{45,0,0},{8,.2,24},1)
nativeLimit.up=Vector3.new(0,.70710677,.70710677)
check(G.support(nativeLimit,0,0,100)~=nil,"native float rounding keeps an authored 45-degree ramp walkable")
-- Regressions: steeper boards and small joins must keep every grounded sample
-- supported, rather than merely reaching the deck at least once.
for _,angle in {30,40,45} do
 registry=Objects.new();env.worldObjects=registry
 local board=add("board",{0,0,0},{angle,0,0},{4.5,.2,24})
 local endHeight=24*math.sin(math.rad(angle))+.2*math.cos(math.rad(angle))
 local endZ=-12*math.cos(math.rad(angle))+.1*math.sin(math.rad(angle))
 add("platform",{0,endHeight-.2,endZ-12-.35},{0,0,0},{16,.2,24})
 for _,kind in {"Boomer","Rattler"} do
  local state=Sim.new(Vector3.new(0,0,25),kind);local drive=Input.neutral();drive.throttle=1
  local onBoard,onPlatform=false,false
  for _=1,200 do
   step(state,drive)
   if math.abs(state.position.Z)<3 then
    local expected=G.support(board.geometry,0,state.position.Z,100)
    check(state.position.Y>=expected-.2,"tank retains height on board at "..angle.." degrees: "..kind)
    check(state.groundPitch>0,"uphill board must not produce a nose-down terrain pose: "..kind)
    onBoard=true
   end
   if math.abs(state.position.Z-endZ)<1 then
    local expected=math.min(endHeight,G.planeHeight(board.geometry,0,state.position.Z))
    check(state.position.Y>=expected-.2,"small join retains support on every crossing tick: "..kind)
   end
   if state.position.Z<endZ-2 and state.position.Z>endZ-18 then
    check(state.position.Y>=endHeight-.2,"ramp-to-platform join must not drop support: "..kind)
    onPlatform=true
   end
  end
  check(onBoard and onPlatform,"tank crosses narrow board and small platform join: "..kind)
 end
end
registry=Objects.new();env.worldObjects=registry
local sideBoard=add("side_board",{0,0,0},{0,0,-30},{24,.2,4.5})
local sideHeight=24*math.sin(math.rad(30))+.2*math.cos(math.rad(30))
local sideEnd=-12*math.cos(math.rad(30))+.1*math.sin(math.rad(30))
add("side_platform",{sideEnd-12-.35,sideHeight-.2,0},{0,0,0},{24,.2,16})
for _,kind in {"Boomer","Rattler"} do
 local state=Sim.new(Vector3.new(25,0,0),kind);state.yaw=math.pi/2
 local drive=Input.neutral();drive.throttle=1;local crossed=false
 for _=1,160 do
  step(state,drive)
  if math.abs(state.position.X)<3 then
   check(state.groundPitch>0 and state.position.Y>=G.support(sideBoard.geometry,state.position.X,0,100)-.2,"roll-tilted board keeps forward support for sideways world heading")
  end
  if state.position.X<sideEnd-2 and state.position.X>sideEnd-18 then
   check(state.position.Y>=sideHeight-.2,"X-directed ramp joins raised platform without falling")
   crossed=true
  end
 end
 check(crossed,"both tanks traverse a board tilted around Z")
end
print(string.format("World elevation geometry and authoritative traversal passed: %d assertions",count))
