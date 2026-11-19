-- Pure mouse math; outputs the existing normalized Rate contract.
local M={Modes={"Mouse Points","Mouse Direct","Mouse Joystick"},Sensitivity=.006,DeadZone=55,Radius=170}
function M.direct(delta,dt,speed)
 local scale=M.Sensitivity/math.max(.0001,dt*speed)
 return math.clamp(delta.X*scale,-1,1),math.clamp(-delta.Y*scale,-1,1)
end
function M.joystick(point,center)
 local delta=point-center;local distance=delta.Magnitude
 if distance<=M.DeadZone then return 0,0 end
 local strength=math.clamp((distance-M.DeadZone)/(M.Radius-M.DeadZone),0,1)
 return delta.X/distance*strength,-delta.Y/distance*strength
end
return M
