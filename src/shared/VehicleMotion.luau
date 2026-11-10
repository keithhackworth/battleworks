-- Generic body math: no tank/components, Instances or Roblox physics ownership.
-- Angular representation is extensible; this release integrates yaw only.
local M={}
local function finite(n) return type(n)=="number" and n==n and math.abs(n)<math.huge end
local function vector(v) assert(v and finite(v.X) and finite(v.Y) and finite(v.Z),"Invalid motion vector") end
function M.configure(body,mass,inertia)
 assert(finite(mass) and mass>0 and finite(inertia) and inertia>0,"Positive mass/inertia required")
 body.motionMass=mass; body.yawInertia=inertia
end
function M.ensure(body)
 if not body.linearVelocity then
  body.linearVelocity=Vector3.new(body.velocityX or -math.sin(body.yaw or 0)*(body.speed or 0),body.verticalSpeed or 0,body.velocityZ or -math.cos(body.yaw or 0)*(body.speed or 0))
 end
 body.angularVelocity=body.angularVelocity or Vector3.zero
 body.motionMass=body.motionMass or 1; body.yawInertia=body.yawInertia or 1
 return body.linearVelocity
end
function M.sync(body)
 local v=M.ensure(body)
 body.velocityX=v.X; body.velocityZ=v.Z; body.verticalSpeed=v.Y
 body.speed=-math.sin(body.yaw or 0)*v.X-math.cos(body.yaw or 0)*v.Z
end
function M.setVelocity(body,v)
 vector(v); body.linearVelocity=v; M.sync(body)
end
function M.setYawVelocity(body,omega)
 assert(finite(omega),"Invalid yaw velocity"); M.ensure(body)
 body.angularVelocity=Vector3.new(0,omega,0)
end
function M.impulse(body,impulse,point)
 vector(impulse); local v=M.ensure(body)
 body.linearVelocity=v+impulse/body.motionMass
 if point then
  vector(point); local r=point-body.position
  M.setYawVelocity(body,body.angularVelocity.Y+(r.Z*impulse.X-r.X*impulse.Z)/body.yawInertia)
 end
 M.sync(body)
end
function M.angularImpulse(body,impulse)
 vector(impulse); M.ensure(body)
 M.setYawVelocity(body,body.angularVelocity.Y+impulse.Y/body.yawInertia)
end
function M.force(body,force,point)
 vector(force); M.ensure(body)
 body.motionForce=(body.motionForce or Vector3.zero)+force
 if point then vector(point); local r=point-body.position; M.torque(body,r.Z*force.X-r.X*force.Z) end
end
function M.torque(body,yawTorque)
 assert(finite(yawTorque),"Invalid torque"); body.motionTorque=(body.motionTorque or 0)+yawTorque
end
-- One-step forces are consumed exactly once. Producers resubmit continuous
-- forces each fixed step; impulses never receive a dt multiplier.
function M.beginStep(body,dt)
 assert(finite(dt) and dt>=0,"Invalid motion timestep"); local v=M.ensure(body)
 body.motionWasResting=v.X*v.X+v.Z*v.Z<0.0004 and math.abs(body.angularVelocity.Y)<0.02
 M.setVelocity(body,v+(body.motionForce or Vector3.zero)*(dt/body.motionMass))
 M.setYawVelocity(body,body.angularVelocity.Y+(body.motionTorque or 0)*dt/body.yawInertia)
 body.motionForce=nil; body.motionTorque=nil
end
function M.integrateHorizontal(body,dt)
 local v=M.ensure(body)
 body.yaw=(body.yaw or 0)+body.angularVelocity.Y*dt
 body.position=body.position+Vector3.new(v.X*dt,0,v.Z*dt)
 M.sync(body)
end
return M
