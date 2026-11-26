-- Contact state is published by the fixed-step server. Sound creation and
-- attenuation are local so distant blocks do not stream playback updates.
local Collection=game:GetService("CollectionService")
local Run=game:GetService("RunService")
local Rules=require(game.ReplicatedStorage.Shared.WorldSound)
local Catalog=require(game.ReplicatedStorage.Shared.CatalogData)
local Http=game:GetService("HttpService")
local SoundService=game:GetService("SoundService")
local Listener=require(script.Parent.BattleAudioListener)
local playerGui=game:GetService("Players").LocalPlayer:WaitForChild("PlayerGui")
local tag="BattleWorksSoundBlock"
local entries={}
local warned={}
local clock=0
local function stop(entry)
 if entry.sound then entry.sound:Destroy();entry.sound=nil end
end
local function source(part,entry,listener)
 local target=part:FindFirstChild("SfxSource")
 local emitter=target and target.Value
 if emitter and emitter:IsDescendantOf(workspace) then return emitter end
 if not part:GetAttribute("Sfx_HasTrail") then return part end
 if not entry.trailOffsets then
  local data=part:FindFirstChild("SfxTrail")
  if not data or data.Value=="" then return nil end
  local ok,points=pcall(Catalog.decode,data,Http,"pending")
  if not ok or not points then return nil end
  entry.trailOffsets={}
  for i,point in points do entry.trailOffsets[i]=Rules.trailOffset(point,part.Size) end
 end
 local position=Rules.nearestTrailOffset(entry.trailOffsets,part.CFrame:PointToObjectSpace(listener),math.max(part.Size.X,part.Size.Z)*1.5)
 if not position then return nil end
 if not entry.trailEmitter then
  local attachment=Instance.new("Attachment")
  attachment.Name="PaintedAudioEmitter"
  attachment.Parent=part
  attachment.Position=position
  entry.trailEmitter=attachment
 end
 if (entry.trailEmitter.Position-position).Magnitude>math.max(20,part.Size.Magnitude*3) then
  entry.trailEmitter.Position=position
 end
 entry.trailGoal=position
 return entry.trailEmitter
end
local function nearbySource(part,entry)
 local distance=part:GetAttribute("Sfx_maxDistance")
 if not distance or not part:IsDescendantOf(workspace) then return nil end
 if playerGui:GetAttribute("BattleWorksGameplayActive")==false then return nil end
 local vehicleId=Listener.vehicleId()
 local occupants=part:GetAttribute("Sfx_TankOccupants")
 if vehicleId and occupants and occupants:find("\n"..vehicleId.."\n",1,true) then return SoundService end
 local listener=Listener.position(workspace.CurrentCamera)
 if not listener then return nil end
 local emitter=source(part,entry,listener)
 if not emitter then return nil end
 local position=if emitter==entry.trailEmitter then part.CFrame:PointToWorldSpace(entry.trailGoal)
  elseif emitter:IsA("Attachment") then emitter.WorldPosition else emitter.Position
 return if (position-listener).Magnitude<=distance+8 then emitter else nil
end
local function play(part,entry,looped,emitter)
 if entry.failed or not emitter then return false end
 local id=part:GetAttribute("Sfx_AssetId")
 if not id then return false end
 local sound=entry.sound
 if sound and sound.Parent~=emitter then sound.Parent=emitter end
 if sound and (sound.IsPlaying or not sound.IsLoaded) then return false end
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
  local emitter=nearbySource(part,entry)
  if mode=="Once" or not active then play(part,entry,false,emitter)
  elseif play(part,entry,mode=="Loop",emitter) then entry.nextPlay=clock+(part:GetAttribute("Sfx_interval") or 3) end
 end)
 entry.reset=part:GetAttributeChangedSignal("Sfx_Reset"):Connect(function()
  stop(entry);entry.once=false;entry.nextPlay=0;entry.failed=false
 end)
end
local function remove(part)
 local entry=entries[part]
 if not entry then return end
 entry.pulse:Disconnect();entry.reset:Disconnect();stop(entry);entries[part]=nil
 if entry.trailEmitter then entry.trailEmitter:Destroy() end
end
Collection:GetInstanceAddedSignal(tag):Connect(add)
Collection:GetInstanceRemovedSignal(tag):Connect(remove)
for _,part in Collection:GetTagged(tag) do add(part) end
local elapsed=0
Run.Heartbeat:Connect(function(dt)
 clock+=dt;elapsed+=dt
 local alpha=1-math.exp(-dt/.08)
 for _,entry in entries do
  if entry.sound and entry.trailEmitter and entry.trailGoal then
   local emitter=entry.trailEmitter
   emitter.Position=emitter.Position:Lerp(entry.trailGoal,alpha)
  end
 end
 if elapsed<.2 then return end
 elapsed=0
 for part,entry in entries do
  if entry.sound and not entry.sound.Parent then stop(entry) end
  local emitter=nearbySource(part,entry)
  if not emitter then stop(entry);continue end
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
   play(part,entry,true,emitter)
  elseif action=="Repeat" then
   if play(part,entry,false,emitter) then entry.nextPlay=clock+(part:GetAttribute("Sfx_interval") or 3) end
  elseif action=="Once" then
   entry.once=play(part,entry,false,emitter)
  elseif not active and entry.sound and entry.sound.Looped then stop(entry) end
 end
end)
