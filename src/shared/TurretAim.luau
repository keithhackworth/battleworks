-- Shared mount geometry. Target intent never modifies barrel pose directly.
local Components=require(script.Parent.VehicleComponents)
local Aim={}
function Aim.pivot(state)
 return state.position+Vector3.new(0,Components.get(state).Turret.MuzzleHeight+(state.bounce or 0),0)
end
function Aim.toWorld(state,v)
 local cr,sr=math.cos(state.bodyRoll or 0),math.sin(state.bodyRoll or 0)
 local x,y=cr*v.X-sr*v.Y,sr*v.X+cr*v.Y
 local cp,sp=math.cos(state.bodyPitch or 0),math.sin(state.bodyPitch or 0)
 local z; y,z=cp*y-sp*v.Z,sp*y+cp*v.Z
 local c,s=math.cos(state.yaw),math.sin(state.yaw)
 return Vector3.new(c*x+s*z,y,-s*x+c*z)
end
function Aim.toMount(state,v)
 local c,s=math.cos(state.yaw),math.sin(state.yaw)
 local x,z=c*v.X-s*v.Z,s*v.X+c*v.Z
 local cp,sp=math.cos(state.bodyPitch or 0),math.sin(state.bodyPitch or 0)
 local y;y,z=cp*v.Y+sp*z,-sp*v.Y+cp*z
 local cr,sr=math.cos(state.bodyRoll or 0),math.sin(state.bodyRoll or 0)
 return Vector3.new(cr*x+sr*y,-sr*x+cr*y,z)
end
function Aim.target(state,point)
 local delta=Aim.toMount(state,point-Aim.pivot(state))
 if delta.Magnitude<.001 then return state.turretYaw,state.turretPitch end
 local flat=math.sqrt(delta.X*delta.X+delta.Z*delta.Z)
 local yaw=if flat>.001 then state.yaw+math.atan2(-delta.X,-delta.Z)else state.turretYaw
 local mount=Components.get(state).Turret
 return yaw,math.clamp(math.atan2(delta.Y,flat),mount.MinPitch,mount.MaxPitch)
end
function Aim.approach(current,target,step)
 local delta=math.atan2(math.sin(target-current),math.cos(target-current))
 return current+math.clamp(delta,-step,step)
end
function Aim.step(state,command,dt)
 local mount=Components.get(state).Turret
 local step=mount.TraverseSpeed*(state.turretPerformance or 1)*dt
 if command.aimMode=="Rate"then
  state.turretYaw-=command.turretX*step
  state.turretPitch=math.clamp(state.turretPitch+command.turretY*step,mount.MinPitch,mount.MaxPitch)
 else
  local yaw,pitch=Aim.target(state,command.aim)
  state.turretYaw=Aim.approach(state.turretYaw,yaw,step)
  state.turretPitch=Aim.approach(state.turretPitch,pitch,step)
 end
end
return Aim
