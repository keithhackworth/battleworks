local UIS=game:GetService("UserInputService")
local GuiService=game:GetService("GuiService")
local Shared=game.ReplicatedStorage.Shared
local Command=require(Shared.InputCommand)
local Components=require(Shared.VehicleComponents)
local Mouse=require(script.Parent.MouseAim)
local Targets=require(script.Parent.AimTargetSelector)
local Provider={};Provider.__index=Provider
function Provider.new()
 local self=setmetatable({held={},focused=true,active=false,mouseMode="Mouse Points",delta=Vector2.zero,armed=false},Provider)
 UIS.InputBegan:Connect(function(input,processed)
  if not self.active then return end
  if input.KeyCode==Enum.KeyCode.LeftAlt or input.KeyCode==Enum.KeyCode.RightAlt then self.freeCursor=true;self:reset();self:cursor();return end
  if processed or self.uiBlocked or self.freeCursor then return end
  if input.KeyCode==Enum.KeyCode.C and self.mouseMode=="Mouse Joystick"then self.recenter=true end
  self.held[input.KeyCode]=true;self.held[input.UserInputType]=true
 end)
 UIS.InputChanged:Connect(function(input,processed)
  if self.active and self.focused and not processed and not self.uiBlocked and not self.freeCursor and input.UserInputType==Enum.UserInputType.MouseMovement then
   self.delta+=Vector2.new(input.Delta.X,input.Delta.Y)
  end
 end)
 UIS.InputEnded:Connect(function(input)
  self.held[input.KeyCode]=nil;self.held[input.UserInputType]=nil
  if input.KeyCode==Enum.KeyCode.LeftAlt or input.KeyCode==Enum.KeyCode.RightAlt then self.freeCursor=false;self:reset();self:cursor()end
 end)
 UIS.WindowFocusReleased:Connect(function()self.focused=false;self.freeCursor=false;self:reset();self:cursor()end)
 UIS.WindowFocused:Connect(function()self.focused=true;self:cursor()end)
 UIS.TextBoxFocused:Connect(function()self:reset();self:cursor()end)
 return self
end
function Provider:cursor()
 local lock=self.active and self.focused and self.mouseMode=="Mouse Direct"and not self.freeCursor and not self.uiBlocked and not UIS:GetFocusedTextBox()
 if lock and not self.locked then self.oldBehavior=UIS.MouseBehavior;self.oldIcon=UIS.MouseIconEnabled;self.locked=true end
 if lock then UIS.MouseBehavior=Enum.MouseBehavior.LockCenter;UIS.MouseIconEnabled=false
 elseif self.locked then UIS.MouseBehavior=self.oldBehavior or Enum.MouseBehavior.Default;UIS.MouseIconEnabled=self.oldIcon~=false;self.locked=false end
end
function Provider:reset()self.held={};self.delta=Vector2.zero;self.center=nil;self.armed=false;self.recenter=false end
function Provider:setMode(mode)
 assert(table.find(Mouse.Modes,mode),"Unknown mouse aiming mode")
 self.mouseMode=mode;self:reset();self:cursor()
end
function Provider:setUIBlocked(blocked)self.uiBlocked=blocked;self:reset();self:cursor()end
function Provider:setActive(active)self.active=active;self.freeCursor=false;self:reset();self:cursor()end
function Provider:sample(camera,context,dt)
 local command=Command.neutral();self:cursor()
 if not self.active or not self.focused or self.uiBlocked or self.freeCursor or UIS:GetFocusedTextBox()then self.delta=Vector2.zero;return command end
 local function down(key)return if self.held[key]then 1 else 0 end
 command.throttle=down(Enum.KeyCode.W)-down(Enum.KeyCode.S);command.steer=down(Enum.KeyCode.A)-down(Enum.KeyCode.D)
 command.fire=self.held[Enum.UserInputType.MouseButton1]==true
 local mouse=UIS:GetMouseLocation()+GuiService:GetInsetArea(Enum.ScreenInsets.None).Min
 if self.mouseMode=="Mouse Points"then
  command.aimMode="World"
  local ray=camera:ScreenPointToRay(mouse.X,mouse.Y)
  local arena=workspace.FindFirstChild and workspace:FindFirstChild("Arena")
  command.aim=Targets.select(workspace,arena,ray,context and context.id)
 elseif self.mouseMode=="Mouse Direct"then
  local state=context and context.state
  local speed=if state then Components.get(state).Turret.TraverseSpeed*(state.turretPerformance or 1)else Components.get("Boomer").Turret.TraverseSpeed
  command.turretX,command.turretY=Mouse.direct(self.delta,dt or 1/30,math.max(speed,.001))
 else
  self.center=self.center or camera.ViewportSize/2
  if self.recenter then
   local viewport=camera.ViewportSize
   local mx,my=math.min(Mouse.DeadZone,viewport.X/2),math.min(Mouse.DeadZone,viewport.Y/2)
   self.center=Vector2.new(math.clamp(mouse.X,mx,viewport.X-mx),math.clamp(mouse.Y,my,viewport.Y-my))
   self.armed=(mouse-self.center).Magnitude<=Mouse.DeadZone;self.recenter=false
  end
  if (mouse-self.center).Magnitude<=Mouse.DeadZone then self.armed=true end
  if self.armed then command.turretX,command.turretY=Mouse.joystick(mouse,self.center)end
  self.pointer=mouse
 end
 self.delta=Vector2.zero
 return command
end
return Provider
