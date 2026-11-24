-- Contact state is published by the fixed-step server. Sound creation and
-- attenuation are local so distant blocks do not stream playback updates.
local Collection=game:GetService("CollectionService")
local Run=game:GetService("RunService")
local Rules=require(game.ReplicatedStorage.Shared.WorldSound)
local playerGui=game:GetService("Players").LocalPlayer:WaitForChild("PlayerGui")
local tag="BattleWorksSoundBlock"
local entries={}
local warned={}
local clock=0
local function stop(entry)
 if entry.sound then entry.sound:Destroy();entry.sound=nil end
end
local function source(part)
 local target=part:FindFirstChild("SfxSource")
 local emitter=target and target.Value
 return if emitter and emitter:IsDescendantOf(workspace) then emitter else part
end
local function nearby(part,emitter)
 local camera=workspace.CurrentCamera
 local distance=part:GetAttribute("Sfx_maxDistance")
 if not camera or not distance or not part:IsDescendantOf(workspace) then return false end
 if playerGui:GetAttribute("BattleWorksGameplayActive")==false then return false end
 local listener=camera.CFrame.Position
 return ((emitter or source(part)).Position-listener).Magnitude<=distance+8
end
local function play(part,entry,looped)
 if entry.failed or not nearby(part,entry.sound and entry.sound.Parent) then return false end
 local id=part:GetAttribute("Sfx_AssetId")
 if not id then return false end
 local sound=entry.sound
 if sound and (sound.IsPlaying or not sound.IsLoaded) then return false end
 local emitter=source(part)
 if sound and sound.Parent~=emitter then stop(entry);sound=nil end
 if not sound then
  sound=Instance.new("Sound")
  sound.Name="WorldSfx"
  sound.SoundId="rbxassetid://"..id
  sound.Volume=part:GetAttribute("Sfx_volume")
  sound.PlaybackSpeed=part:GetAttribute("Sfx_speed")
  sound.RollOffMinDistance=part:GetAttribute("Sfx_minDistance")
  sound.RollOffMaxDistance=part:GetAttribute("Sfx_maxDistance")
  sound.RollOffMode=Enum.RollOffMode[part:GetAttribute("Sfx_rollOff")]
  sound.Parent=emitter;entry.sound=sound
 end
 sound.Looped=looped;entry.loadDeadline=clock+8
 sound:Play()
 return true
end
local function add(part)
 if entries[part] or not part:IsA("BasePart") then return end
 local entry={nextPlay=0,once=false}
 entries[part]=entry
 entry.pulse=part:GetAttributeChangedSignal("Sfx_Pulse"):Connect(function()
  if (part:GetAttribute("Sfx_Pulse") or 0)<=0 then return end
  local mode=part:GetAttribute("Sfx_playback")
  local active=part:GetAttribute("Sfx_Active")
  if mode=="Once" or not active then play(part,entry,false)
  elseif play(part,entry,mode=="Loop") then entry.nextPlay=clock+(part:GetAttribute("Sfx_interval") or 3) end
 end)
 entry.reset=part:GetAttributeChangedSignal("Sfx_Reset"):Connect(function()
  stop(entry);entry.once=false;entry.nextPlay=0;entry.failed=false
 end)
end
local function remove(part)
 local entry=entries[part]
 if not entry then return end
 entry.pulse:Disconnect();entry.reset:Disconnect();stop(entry);entries[part]=nil
end
Collection:GetInstanceAddedSignal(tag):Connect(add)
Collection:GetInstanceRemovedSignal(tag):Connect(remove)
for _,part in Collection:GetTagged(tag) do add(part) end
local elapsed=0
Run.Heartbeat:Connect(function(dt)
 clock+=dt;elapsed+=dt
 if elapsed<.2 then return end
 elapsed=0
 for part,entry in entries do
  if entry.sound and not entry.sound.Parent then stop(entry) end
  if not nearby(part,entry.sound and entry.sound.Parent) then stop(entry);continue end
  if entry.sound and not entry.sound.IsLoaded and clock>=entry.loadDeadline then
   local id=part:GetAttribute("Sfx_AssetId")
   if id and not warned[id] then
    warned[id]=true
    warn("BattleWorks sound is unavailable: "..id..". Verify moderation and experience audio permissions.")
   end
   stop(entry);entry.failed=true
  end
  if entry.failed then continue end
  local mode=part:GetAttribute("Sfx_playback")
  local active=part:GetAttribute("Sfx_Active")
  local action=Rules.playbackAction(part:GetAttribute("Sfx_activation"),mode,active,clock,entry.nextPlay,entry.once)
  if action=="Loop" then
   play(part,entry,true)
  elseif action=="Repeat" then
   if play(part,entry,false) then entry.nextPlay=clock+(part:GetAttribute("Sfx_interval") or 3) end
  elseif action=="Once" then
   entry.once=play(part,entry,false)
  elseif not active and entry.sound and entry.sound.Looped then stop(entry) end
 end
end)
