-- Static, client-local presentation. Future replay presenters implement the same
-- enter()/exit()/destroy() interface; navigation never knows about scene data.
local Background={}; Background.__index=Background
local roots={Floor=true,Boundary=true,Environment=true,WorldScenery=true,CenterStick=true}
local visualChildren={SpecialMesh=true,BlockMesh=true,CylinderMesh=true,SurfaceAppearance=true,Decal=true,Texture=true}
local MAX_PARTS=600
function Background.new(parent,arena)
 -- Studio startup isolation: native preview rendering is opt-in until the
 -- reported Windows Play crash is identified. Published clients retain 3D.
 local preview=workspace:GetAttribute("BattleWorksMenu3D")
 if preview==false or (preview~=true and game:GetService("RunService"):IsStudio()) then
  local plain=Instance.new("Frame");plain.Name="MenuBackground";plain.Size=UDim2.fromScale(1,1)
  plain.BackgroundColor3=Color3.fromRGB(12,22,28);plain.BorderSizePixel=0;plain.Parent=parent
  return setmetatable({viewport=plain,shade=plain,dirty=false},Background)
 end
 local viewport=Instance.new("ViewportFrame"); viewport.Name="MenuBattlefield"
 viewport.Size=UDim2.fromScale(1,1); viewport.BackgroundColor3=Color3.fromRGB(12,22,28)
 viewport.BorderSizePixel=0; viewport.Ambient=Color3.fromRGB(150,169,184)
 viewport.LightColor=Color3.fromRGB(255,227,179); viewport.LightDirection=Vector3.new(-1,-1,-.5)
 viewport.Active=false; viewport.Parent=parent
 -- Static anchored geometry does not need another native physics world.
 -- Only the interactive editor creates a WorldModel, when that screen opens.
 local world=Instance.new("Folder"); world.Name="StaticArena"; world.Parent=viewport
 local camera=Instance.new("Camera"); camera.Name="MenuCamera"; camera.FieldOfView=44; camera.Parent=viewport
 viewport.CurrentCamera=camera
 local shade=Instance.new("Frame"); shade.Name="MenuShade"; shade.Size=UDim2.fromScale(1,1)
 shade.BackgroundColor3=Color3.fromRGB(8,15,20); shade.BackgroundTransparency=.3
 shade.BorderSizePixel=0; shade.Parent=parent
 local self=setmetatable({viewport=viewport,shade=shade,world=world,camera=camera,arena=arena,dirty=true},Background)
 self.connection=arena:GetAttributeChangedSignal("MapRevision"):Connect(function()
  self.dirty=true
  if self.active then self:capture() end
 end)
 return self
end
function Background:capture()
 for _,child in self.world:GetChildren() do child:Destroy() end
 local count=0
 for _,root in self.arena:GetChildren() do
  if roots[root.Name] then
   local parts=if root:IsA("BasePart") then {root} else root:GetDescendants()
   for _,source in parts do
    if source:IsA("BasePart") and source.Transparency<1 and count<MAX_PARTS then
     local ok,copy=pcall(function() return source:Clone() end)
     if ok and copy then
      -- Only appearance children survive; no scripts, emitters, sounds, joints,
      -- gameplay attributes or collision participation are carried into the view.
      for _,child in copy:GetDescendants() do if not visualChildren[child.ClassName] then child:Destroy() end end
      for name in copy:GetAttributes() do copy:SetAttribute(name,nil) end
      copy.Anchored=true; copy.CanCollide=false; copy.CanTouch=false; copy.CanQuery=false
      copy.Parent=self.world; count+=1
     end
    end
   end
  end
 end
 local width=self.arena:GetAttribute("MapWidth") or 230
 local depth=self.arena:GetAttribute("MapDepth") or 230
 local span=math.max(width,depth)
 local focus=Vector3.new(width*.06,0,-depth*.04)
 self.camera.CFrame=CFrame.lookAt(focus+Vector3.new(span*.48,span*.52,span*.55),focus)
 self.camera.Focus=CFrame.new(focus)
 self.dirty=false
end
function Background:enter()
 self.active=true; self.viewport.Visible=true; self.shade.Visible=true
 if self.dirty then self:capture() end
end
function Background:exit() self.active=false; self.viewport.Visible=false; self.shade.Visible=false end
function Background:destroy()
 if self.connection then self.connection:Disconnect() end
 self.viewport:Destroy();if self.shade~=self.viewport then self.shade:Destroy() end
end
return Background
