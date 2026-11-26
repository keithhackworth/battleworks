-- Use the vehicle's position with camera-relative left/right orientation.
local SoundService=game:GetService("SoundService")
local Listener={}
local current,vehicleId

function Listener.set(part,id)
 vehicleId=if part then id else nil
 if current==part then return end
 SoundService:SetListener(if part then Enum.ListenerType.ObjectPosition else Enum.ListenerType.Camera,part)
 current=part
end
function Listener.vehicleId()
 return if current and current.Parent then vehicleId else nil
end

function Listener.position(camera)
 if current and current.Parent then return current.Position end
 return camera and camera.CFrame.Position
end

return Listener
