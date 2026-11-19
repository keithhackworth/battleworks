-- Cosmetic river flow only: no server updates, gameplay forces, or query parts.
local Presentation={}
function Presentation.start(arena)
 local folders,parts={},{}
 local function animate(part)
  if part.Name~="Current" or not part:IsA("BasePart")or parts[part]then return end
  parts[part]=true
  game:GetService("TweenService"):Create(part,TweenInfo.new(2,Enum.EasingStyle.Linear,Enum.EasingDirection.Out,-1,false),{CFrame=part.CFrame*CFrame.new(0,0,12)}):Play()
 end
 local function watch(folder)
  if folder.Name~="PlaygroundTerrain"or folders[folder]then return end
  folders[folder]=true
  for _,part in folder:GetChildren()do animate(part)end
  folder.ChildAdded:Connect(animate)
 end
 for _,folder in arena:GetChildren()do watch(folder)end
 arena.ChildAdded:Connect(watch)
end
return Presentation
