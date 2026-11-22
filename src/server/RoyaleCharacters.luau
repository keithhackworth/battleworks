-- Native character lifecycle only. Tanks continue to use the existing custom
-- simulation; characters never become damage/hit claims or tank physics bodies.
local Characters={};Characters.__index=Characters
local SprintMultiplier=1.5
function Characters.new(findSafe)
 return setmetatable({findSafe=findSafe,records={},sprinting={}},Characters)
end
function Characters:root(player)
 local character=player.Character
 return character and character:FindFirstChild("HumanoidRootPart"),character and character:FindFirstChildOfClass("Humanoid")
end
function Characters:alive(player)
 local root,humanoid=self:root(player)
 return root and humanoid and humanoid.Health>0 and root.Parent~=nil
end
function Characters:setSprinting(player,enabled)
 local previous=self.sprinting[player]
 if not enabled then
  self.sprinting[player]=nil
  if previous and previous.humanoid.Parent then previous.humanoid.WalkSpeed=previous.speed end
  return
 end
 if previous or self.records[player] then return end
 local root,humanoid=self:root(player)
 if not root or root.Anchored or not humanoid or humanoid.Health<=0 or humanoid.WalkSpeed<=0 then return end
 self.sprinting[player]={humanoid=humanoid,speed=humanoid.WalkSpeed}
 humanoid.WalkSpeed*=SprintMultiplier
end
function Characters:hide(player,position)
 self:setSprinting(player,false)
 local root,humanoid=self:root(player);assert(root and humanoid and humanoid.Health>0,"Character unavailable")
 local record={root=root,humanoid=humanoid,parts={},speed=humanoid.WalkSpeed,jump=humanoid.JumpPower,rotate=humanoid.AutoRotate,display=humanoid.DisplayDistanceType,anchored=root.Anchored}
 self.records[player]=record -- rollback remains possible if presentation fails
 local function hidePart(part)
  if part:IsA("BasePart")and not record.parts[part]then record.parts[part]={part.Transparency,part.CanCollide,part.CanTouch,part.CanQuery};part.Transparency=1;part.CanCollide=false;part.CanTouch=false;part.CanQuery=false end
 end
 for _,part in player.Character:GetDescendants()do hidePart(part)end
 record.connection=player.Character.DescendantAdded:Connect(hidePart)
 root.Anchored=true;root.CFrame=CFrame.new(position+Vector3.new(0,3,0))
 humanoid.WalkSpeed=0;humanoid.JumpPower=0;humanoid.AutoRotate=false
 humanoid.DisplayDistanceType=Enum.HumanoidDisplayDistanceType.None
end
function Characters:restore(player,preferred,kill,ejection)
 self:setSprinting(player,false)
 local record=self.records[player];self.records[player]=nil
 if record then
  if record.connection then record.connection:Disconnect()end
  for part,values in record.parts do if part.Parent then part.Transparency=values[1];part.CanCollide=values[2];part.CanTouch=values[3];part.CanQuery=values[4]end end
  if record.root.Parent then record.root.Anchored=record.anchored end
  if record.humanoid.Parent then record.humanoid.WalkSpeed=record.speed;record.humanoid.JumpPower=record.jump;record.humanoid.AutoRotate=record.rotate;record.humanoid.DisplayDistanceType=record.display end
 end
 local root,humanoid=self:root(player)
 if root and humanoid then
  local position=if ejection then ejection.position else self.findSafe(preferred,player)
  if not position then
   -- A crowded arena must never leave a fresh avatar at Roblox's default
   -- origin (which may be over water). Retry through native respawn.
   root.Anchored=true;humanoid.Health=0;return false
  end
  if position then
   root.CFrame=CFrame.new(position+(if ejection then Vector3.zero else Vector3.new(0,3,0)))
   root.AssemblyLinearVelocity=if ejection then ejection.velocity else Vector3.zero
   root.AssemblyAngularVelocity=Vector3.zero
  end
  if kill then humanoid.Health=0 end
 end
end
function Characters:forget(player)
 self:setSprinting(player,false)
 local record=self.records[player]
 if record and record.connection then record.connection:Disconnect()end
 self.records[player]=nil
end
return Characters
