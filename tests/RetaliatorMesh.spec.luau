local Battle=require("LocalBattle")
local Controller=require("BWController")
local Hardware=require("BWChassis")
local Components=require("VehicleComponents")
local Simulation=require("TankSimulation")
local Value=require("BWValue")
local Geometry=require("ScannerGeometry")
local Limits=require("BWConfig")
local battle={multiplayer=true}
local size=Vector2.new(230,230)
local kind="Boomer"
local source={owner=2,state=Simulation.new(Vector3.zero,kind)}
local observer=[[function react(const event):
    print(event)
    wait_for_clock(get_clock().time + 1)
on_event("OnDamageTaken", react)]]
local function draft(allocation)
 return {allocations={drivetrain=40,turret=10,weapon=15,scanners=10,retaliatorMesh=allocation},tuning={weapon=.5,scanners=.5}}
end
local function hardware(allocation)
 return assert(Hardware.fromCategories(draft(allocation),Components.get(kind),"Bunny"))
end
local function tank(allocation,program)
 local prints={}
 local target={owner=1,kind=kind,state=Simulation.new(Vector3.zero,kind),hardware=hardware(allocation),
  hitbox=Instance.new("Part"),bwServices={onPrint=function(text)table.insert(prints,text)end}}
 Controller.applyHardware(target)
 assert(Controller.start(target,program or observer),target.state.bwMessage)
 return target,prints
end
local function hit(target,amount,travel)
 return Battle.damage(battle,target,source,amount,"Cannon",target.state.position,travel)
end
local function advance(target,frames)
 for _=1,frames do Controller.input(target,1/60)end
end
local over=draft(25.1)
local invalid,reason=Hardware.fromCategories(over,Components.get(kind),"Bunny")
assert(not invalid and reason=="busOverallocated","mesh shares the actual 100-point bus")
assert(not Hardware.fromCategories(draft(0/0),Components.get(kind),"Bunny"))
assert(Hardware.validate(hardware(25)) and Hardware.retaliatorOperational(Hardware.copy(hardware(25))),"installed equipment survives configuration copying")
local forged=Hardware.copy(hardware(25))
forged.devices.retaliatorMesh.componentId="sensor.standard"
assert(not Hardware.validate(forged) and not Hardware.retaliatorOperational(forged),"only the installed Mesh provides this capability")
local cardinal=tank(25)
assert(hit(cardinal,5,Vector3.new(-1,0,0)) and cardinal.bw.events.queue[1].payload.direction==90,
 "a projectile traveling west arrived from the right of a north-facing chassis")

local equipped,printed=tank(25)
equipped.state.yaw=math.rad(57)
local toward=Geometry.direction(equipped.state.yaw,135)
assert(hit(equipped,25,toward * -1))
local payload=equipped.bw.events.queue[1].payload
assert(payload.amount==25 and math.abs(payload.direction-135)<1e-7 and payload.remaining_hp==75)
assert(payload.attacker==nil and payload.position==nil and table.isfrozen(payload))
assert(#printed==0,"authoritative damage enqueues without running the handler inline")
advance(equipped,2)
assert(#printed==1 and equipped.bw.threads[1].event=="OnDamageTaken")
assert(hit(equipped,10,nil) and hit(equipped,5,Vector3.new(0,-1,0)))
assert(#equipped.bw.events.queue==2 and equipped.bw.events.queue[1].payload.direction==Value.Null
 and equipped.bw.events.queue[2].payload.direction==Value.Null,"hits during an active handler queue with explicit unknown bearings")
assert(equipped.bw.events.queue[1].payload.remaining_hp==65 and equipped.bw.events.queue[2].payload.remaining_hp==60)
advance(equipped,180)
assert(#printed==3 and printed[2]:find('"amount": 10',1,true) and printed[3]:find('"amount": 5',1,true),"rapid hits resume in FIFO order")
assert(not hit(equipped,0) and not hit(equipped,-1) and #equipped.bw.events.queue==0,"nonpositive impacts do not emit")
equipped.state.configurationZone="test"
assert(not hit(equipped,5) and equipped.state.health==60 and #equipped.bw.events.queue==0,"zone protection blocks damage and events")

for _,allocation in {0,24.9} do
 local unpowered=tank(allocation)
 assert(hit(unpowered,25) and unpowered.state.health==75 and #unpowered.bw.events.queue==0,
  "underpowered mesh neither absorbs damage nor emits")
end
local absent=tank(nil)
assert(hit(absent,25) and absent.state.health==75 and #absent.bw.events.queue==0,"registration alone does not enable impact events")
local legacy=tank(25,"wait_for_clock(2)")
assert(hit(legacy,25) and legacy.state.health==75 and legacy.bw.events==nil,"legacy source remains unaffected")

local reconfigured=tank(25)
assert(hit(reconfigured,5) and #reconfigured.bw.events.queue==1)
Controller.stop(reconfigured)
reconfigured.hardware=hardware(nil)
assert(Controller.start(reconfigured,observer))
assert(hit(reconfigured,5) and #reconfigured.bw.events.queue==0,"removing equipment stops new notifications and restarting discards old work")
Controller.stop(reconfigured)
reconfigured.hardware=hardware(0)
assert(Controller.start(reconfigured,observer))
assert(hit(reconfigured,5) and #reconfigured.bw.events.queue==0,"disabling installed equipment blocks notifications")

local crowded=tank(25)
for _=1,Limits.MaxQueuedEvents+3 do assert(hit(crowded,1))end
assert(#crowded.bw.events.queue==Limits.MaxQueuedEvents and crowded.bw.events.dropped==3 and crowded.state.health==65)
local old=crowded.bw
advance(crowded,2)
assert(old.threads[1].pending and #old.events.queue>0)
assert(hit(crowded,1000) and crowded.state.health==0 and old.status=="stopped" and #old.events.queue==0)
assert(not old.devices:busy() and old.totalCallFrames==0 and old.events.sequence==1,"death clears active and queued handlers and dispatches no lethal event")
local newFrame,angles=CFrame.new,CFrame.Angles
local frameType={__mul=function(a)return a end}
CFrame.new=function(position)return setmetatable({Position=position},frameType)end
CFrame.Angles=function()return CFrame.new(Vector3.zero)end
assert(Battle.resetTank(crowded,size,1,"Respawn"))
CFrame.new,CFrame.Angles=newFrame,angles
assert(crowded.state.health==100 and crowded.bw==nil and Controller.start(crowded,observer))
assert(crowded.bw~=old and #crowded.bw.events.queue==0 and hit(crowded,5) and #crowded.bw.events.queue==1,"fresh runtime receives only fresh damage")

local demo=tank(25,retaliatorDemo)
assert(hit(demo,5,Geometry.direction(demo.state.yaw,270)*-1))
local start=demo.state.position
for _=1,600 do
 local command=assert(Controller.input(demo,1/60),demo.state.bwMessage)
 Simulation.step(demo.state,command,1/60,size)
end
assert((demo.state.position-start).Magnitude>5 and demo.bw.devices.nextId==2,"the tracked demonstration turns and moves following actual damage")
print("Retaliator Mesh damage, equipment, lifecycle, and demonstration passed")
