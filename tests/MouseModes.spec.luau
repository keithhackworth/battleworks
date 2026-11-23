local Mouse=require("MouseAim")
local Targets=require("AimTargetSelector")
local Controller=require("InputController")
local count=0
local function check(ok,message)assert(ok,message);count+=1 end
local function near(a,b)return math.abs(a-b)<1e-6 end
for _,v in {Vector2.zero,Vector2.new(20,20),Vector2.new(Mouse.DeadZone,0)}do
 local x,y=Mouse.joystick(v,Vector2.zero);check(x==0 and y==0,"generous circular dead zone holds both axes")
end
local x,y=Mouse.joystick(Vector2.new(Mouse.Radius,0),Vector2.zero)
check(near(x,1)and y==0,"joystick reaches existing maximum rate")
x,y=Mouse.joystick(Vector2.new(10000,-10000),Vector2.zero)
check(near(math.sqrt(x*x+y*y),1)and x>0 and y>0,"diagonal joystick speed is circularly bounded")
local half=Mouse.DeadZone+(Mouse.Radius-Mouse.DeadZone)/2
check(near(Mouse.joystick(Vector2.new(half,0),Vector2.zero),.5),"joystick displacement continuously maps speed")
local arena=Instance.new("Folder")
local function part(name,attributes,solid)
 local p=Instance.new("Part");p.Name=name;p.CanQuery=true;p.CanCollide=solid or false
 for k,v in attributes or {}do p:SetAttribute(k,v)end
 table.insert(arena.children,p);p.Parent=arena
 function p:IsA(kind)return kind=="BasePart"or kind=="Part"end
 return p
end
local own=part("TankHitbox",{TankId="public:1"});local enemy=part("TankHitbox",{TankId="public:2"})
local ground=part("Floor");local decoration=part("Flowers");local model=Instance.new("Model");model:SetAttribute("Solid",false)
local nonSolid=part("WorldObstacleHitbox",{WorldObjectId="decor"});nonSolid.Parent=model
local solidModel=Instance.new("Model");solidModel:SetAttribute("Solid",true)
local nested=Instance.new("Folder");nested.Parent=solidModel
local building=part("MeshPart",{WorldObjectId="building"});building.Parent=nested
check(not Targets.eligible(own,"public:1")and Targets.eligible(enemy,"public:1"),"target selection excludes own tank but admits opponents")
check(not Targets.eligible(decoration)and not Targets.eligible(nonSolid)and Targets.eligible(building),"nested solid imported colliders qualify while decoration does not")
local ray={Origin=Vector3.new(0,100,0),Direction=Vector3.new(0,-1,0)}
local hits,seen,index={}, {},0
local world={FindFirstChild=function()return nil end,Raycast=function(_,origin,direction,params)
 index+=1;seen[index]={origin=origin,direction=direction,params=params};return hits[index]
end}
local function hit(p,position,normal)return {Instance=p,Position=position,Normal=normal or Vector3.new(0,1,0)}end
hits={hit(ground,Vector3.zero),hit(enemy,Vector3.new(0,4,0))}
local point=Targets.select(world,arena,ray,"public:1")
check(point.Y==4 and seen[2].direction.Y>0,"ground cursor selects first eligible vertical object above XZ")
index=0;seen={};hits={hit(ground,Vector3.zero)}
check(Targets.select(world,arena,ray,"public:1").Y==0,"empty vertical column retains ground hit")
index=0;hits={hit(building,Vector3.new(2,30,0),Vector3.new(0,0,1))}
check(Targets.select(world,arena,ray,"public:1").Y==30 and index==1,"direct elevated/vertical surface hit is preserved")
index=0;hits={hit(own,Vector3.new(0,6,0)),hit(enemy,Vector3.new(0,4,0))}
point=Targets.select(world,arena,ray,"public:1")
check(point.Y==4 and not table.find(seen[2].params.FilterDescendantsInstances,own),"rejected own geometry cannot mask next target")
index=0;hits={}
check((Targets.select(world,arena,ray,"public:1")-(ray.Origin+ray.Direction*Targets.Distance)).Magnitude<1e-6,"no suitable hit uses deterministic camera-ray fallback")
local gui=Instance.new("ScreenGui");gui.Enabled=true;local releases=0
UIS.PreferredInput=Enum.PreferredInput.KeyboardAndMouse;UIS.focusedTextBox=nil
UIS.MouseBehavior=Enum.MouseBehavior.Default;UIS.MouseIconEnabled=true
local controller=Controller.new(gui,function()releases+=1 end)
local provider=controller.providers.KeyboardMouse
local mouse=Vector2.new(640,360)
UIS.GetMouseLocation=function()return mouse end
local camera={ViewportSize=Vector2.new(1280,720),ScreenPointToRay=function()return ray end}
check(provider.mouseMode=="Mouse Points"and controller.mouseView.icon.Visible,"Points is default and desktop selector is visible")
controller:setMouseMode("Mouse Direct")
check(UIS.MouseBehavior==Enum.MouseBehavior.LockCenter and not UIS.MouseIconEnabled,"Direct locks relative mouse without edge repositioning")
UIS.InputChanged:Fire({UserInputType=Enum.UserInputType.MouseMovement,Delta=Vector3.new(100,-100,0)},false)
local command=controller:sample(camera,nil,1/30)
check(command.aimMode=="Rate"and command.turretX==1 and command.turretY==1,"Direct converts XY deltas into bounded two-axis rate")
command=controller:sample(camera,nil,1/30)
check(command.turretX==0 and command.turretY==0,"Direct stops intent when mouse stops")
local right={KeyCode=Enum.KeyCode.Unknown,UserInputType=Enum.UserInputType.MouseButton2}
local forward={KeyCode=Enum.KeyCode.W,UserInputType=Enum.UserInputType.Keyboard}
local drag={UserInputType=Enum.UserInputType.MouseMovement,Delta=Vector3.new(100,-100,0)}
UIS.InputBegan:Fire(forward,false)
UIS.InputBegan:Fire(right,false)
UIS.InputChanged:Fire(drag,false)
command=controller:sample(camera,nil,1/30)
check(command.throttle==1 and command.turretX==0 and command.turretY==0 and not command.fire,"right-drag keeps driving and suppresses turret input")
check((provider:takeOrbitDelta()-Vector2.new(100,-100)).Magnitude==0 and provider:takeOrbitDelta()==Vector2.zero,"camera consumes both drag axes exactly once")
UIS.InputEnded:Fire(right)
UIS.InputEnded:Fire(forward)
UIS.InputChanged:Fire(drag,false)
check(UIS.MouseBehavior==Enum.MouseBehavior.LockCenter and controller:sample(camera,nil,1/30).turretX==1,"ending orbit returns control to Direct")
UIS.InputBegan:Fire({KeyCode=Enum.KeyCode.LeftAlt,UserInputType=Enum.UserInputType.Keyboard},false)
check(UIS.MouseBehavior==Enum.MouseBehavior.Default and not controller:sample(camera).fire,"Alt frees cursor and suppresses gameplay intent for UI")
UIS.InputEnded:Fire({KeyCode=Enum.KeyCode.LeftAlt,UserInputType=Enum.UserInputType.Keyboard})
check(UIS.MouseBehavior==Enum.MouseBehavior.LockCenter,"Alt release resumes relative mouse")
local shortcut={KeyCode=Enum.KeyCode.C,UserInputType=Enum.UserInputType.Keyboard}
gui.Enabled=false
UIS.InputBegan:Fire(shortcut,false)
check(not controller.mouseView.panel.Visible,"shortcut does not open the hidden tank HUD")
gui.Enabled=true
UIS.InputBegan:Fire(shortcut,true)
check(not controller.mouseView.panel.Visible,"processed shortcut leaves the selector closed")
UIS.InputBegan:Fire(shortcut,false)
check(controller.mouseView.panel.Visible and UIS.MouseBehavior==Enum.MouseBehavior.Default and UIS.MouseIconEnabled,"C frees the cursor and opens the options while locked")
check(not controller:sample(camera).fire,"open options suspend gameplay intent")
UIS.InputBegan:Fire(shortcut,false)
check(not controller.mouseView.panel.Visible and UIS.MouseBehavior==Enum.MouseBehavior.LockCenter,"C again closes options and resumes Direct")
UIS.InputBegan:Fire(shortcut,false)
controller.mouseView.buttons["Mouse Joystick"].Activated:Fire()
check(provider.mouseMode=="Mouse Joystick"and not controller.mouseView.panel.Visible and UIS.MouseBehavior==Enum.MouseBehavior.Default,"selector switches mode during play")
command=controller:sample(camera)
check(command.turretX==0 and command.turretY==0 and provider.armed,"centered joystick starts neutral")
mouse=Vector2.new(640+Mouse.Radius,360-Mouse.Radius)
local first=controller:sample(camera);local second=controller:sample(camera)
check(first.turretX>0 and first.turretY>0 and near(first.turretX,second.turretX),"displaced joystick continues both axes without mouse motion")
check(controller.mouseView.ring.Visible and controller.mouseView.dot.Visible,"neutral ring and joystick position are rendered")
UIS.heldKeys={[Enum.KeyCode.LeftShift]=true}
UIS.InputBegan:Fire(shortcut,false)
UIS.heldKeys=nil
check(not controller.mouseView.panel.Visible,"Shift+C recenters without opening the selector")
command=controller:sample(camera)
check(command.turretX==0 and command.turretY==0 and (provider.center-mouse).Magnitude<1e-6,"Shift+C reliably establishes a new neutral point")
controller:setExternalControl(true)
check(not provider.active and controller:sample(camera).turretX==0,"BW/death/on-foot/menu suspension clears mouse intent")
controller:takeOrbitDelta(true)
UIS.InputBegan:Fire(right,false)
UIS.InputBegan:Fire(forward,false)
UIS.InputChanged:Fire(drag,false)
check((controller:takeOrbitDelta(true)-Vector2.new(100,-100)).Magnitude==0 and controller:sample(camera).throttle==0,"autopilot allows orbit without enabling drive input")
check(UIS.MouseBehavior==Enum.MouseBehavior.LockCurrentPosition,"autopilot locks only for the camera drag")
controller:takeOrbitDelta(false)
check(UIS.MouseBehavior==Enum.MouseBehavior.Default and not provider.orbiting,"leaving the tank view cancels autopilot drag")
UIS.InputEnded:Fire(right)
UIS.InputEnded:Fire(forward)
controller:setExternalControl(false)
check(provider.mouseMode=="Mouse Joystick"and not provider.armed,"tank/respawn handoff retains preference but requires fresh neutral input")
controller:setPreference("Touch")
check(not controller.mouseView.icon.Visible and controller.providers.Touch.active,"touch keeps existing provider without mouse UI")
local touch=controller.providers.Touch
local swipe={UserInputType=Enum.UserInputType.Touch,Position=Vector3.new(150,100,0)}
UIS.InputBegan:Fire(swipe,false)
swipe.Position=Vector3.new(210,120,0)
UIS.TouchMoved:Fire(swipe)
check((touch:takeOrbitDelta()-Vector2.new(60,20)).Magnitude==0,"swiping open space orbits on touch")
UIS.TouchEnded:Fire(swipe)
UIS.InputBegan:Fire(swipe,true)
swipe.Position=Vector3.new(260,100,0)
UIS.TouchMoved:Fire(swipe)
check(touch:takeOrbitDelta()==Vector2.zero,"touches handled by the HUD do not orbit")
controller:setPreference("Gamepad")
check(not controller.mouseView.icon.Visible and controller.providers.Gamepad.active,"gamepad keeps existing provider without mouse UI")
controller:setPreference("KeyboardMouse");controller:setMouseMode("Mouse Direct")
UIS.WindowFocusReleased:Fire()
check(UIS.MouseBehavior==Enum.MouseBehavior.Default and not provider.active,"window focus loss restores cursor and suspends direct input")
UIS.WindowFocused:Fire()
check(UIS.MouseBehavior==Enum.MouseBehavior.LockCenter and provider.mouseMode=="Mouse Direct","window return retains chosen mouse preference")
local escape={KeyCode=Enum.KeyCode.Escape,UserInputType=Enum.UserInputType.Keyboard}
local beforeEscape=releases
UIS.InputBegan:Fire(escape,true)
UIS.InputEnded:Fire(escape)
check(provider.mouseMode=="Mouse Points"and controller.mouseView.selected=="Mouse Points","processed Escape exits Direct and updates the selector")
check(releases==beforeEscape+1 and UIS.MouseIconEnabled,"Escape releases gameplay input and shows the cursor")
check(controller:sample(camera).aimMode=="World"and UIS.MouseBehavior==Enum.MouseBehavior.Default,"switching back to Points restores world targeting and cursor")
controller:setMouseMode("Mouse Direct")
local guiService=game:GetService("GuiService")
guiService.MenuOpened:Fire()
guiService.MenuClosed:Fire()
controller:sample(camera)
check(provider.mouseMode=="Mouse Points"and UIS.MouseIconEnabled and UIS.MouseBehavior==Enum.MouseBehavior.Default,"native menu handling leaves the cursor free after the menu closes")
check(releases>0,"mode changes retain existing neutral release path")
print(string.format("Mouse modes/target selection/UI lifecycle passed: %d assertions",count))
