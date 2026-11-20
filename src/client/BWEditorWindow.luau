-- Pointer-only title-bar dragging. Does not compete with editing/gameplay keys.
local Window={}
function Window.attach(gui,frame,handle,connect)
 local UIS=game:GetService("UserInputService")
 local drag
 local function finish()drag=nil end
 connect(handle.InputBegan,function(input)
  local kind=input.UserInputType
  if not frame.Visible or(kind~=Enum.UserInputType.MouseButton1 and kind~=Enum.UserInputType.Touch)then return end
  drag={input=input,touch=kind==Enum.UserInputType.Touch,pointer=input.Position,position=frame.Position,origin=frame.AbsolutePosition}
 end)
 connect(UIS.InputChanged,function(input)
  if not drag then return end
  if (drag.touch and input~=drag.input)or(not drag.touch and input.UserInputType~=Enum.UserInputType.MouseMovement)then return end
  local delta=input.Position-drag.pointer
  local viewport=gui.AbsoluteSize;local size=frame.AbsoluteSize;local origin=gui.AbsolutePosition or Vector2.zero
  local x=math.clamp(drag.origin.X+delta.X,origin.X-math.max(0,size.X-80),origin.X+math.max(0,viewport.X-80))
  local y=math.clamp(drag.origin.Y+delta.Y,origin.Y,origin.Y+math.max(0,viewport.Y-24))
  frame.Position=UDim2.new(drag.position.X.Scale,drag.position.X.Offset+x-drag.origin.X,drag.position.Y.Scale,drag.position.Y.Offset+y-drag.origin.Y)
 end)
 connect(UIS.InputEnded,function(input)
  if drag and ((drag.touch and input==drag.input)or(not drag.touch and input.UserInputType==Enum.UserInputType.MouseButton1))then finish()end
 end)
 connect(UIS.WindowFocusReleased,finish)
 return {stop=finish}
end
return Window
