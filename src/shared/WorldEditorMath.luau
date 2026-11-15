-- Viewport picking independent of Workspace/current camera and native gizmos.
local Math={}
local Geometry=require(script.Parent.WorldObjectGeometry)
local function dot(a,b)return a.X*b.X+a.Y*b.Y+a.Z*b.Z end
function Math.rotationBasis(base,kind)
 -- Handles use the complete object frame, not Euler component axes (which
 -- coincide at yaw=90). Numeric fields retain the existing XYZ Euler format.
 local right,up,back=Geometry.axes(base.rotation)
 if kind=="RotatePitch" then return up,back,right end
 if kind=="RotateRoll" then return right,up,back end
 return right,back,up
end
local function rotateLocal(rotation,axis,angle)
 local right,up,back=Geometry.axes(rotation)
 local c,s=math.cos(angle),math.sin(angle)
 if axis==1 then up,back=up*c+back*s,back*c-up*s
 elseif axis==2 then right,back=right*c-back*s,right*s+back*c
 else right,up=right*c+up*s,up*c-right*s end
 -- Convert the composed frame back to the existing Rx * Ry * Rz schema.
 -- atan2 avoids asin precision loss close to +/-90deg; singular frames have
 -- multiple equivalent Euler triples, so use roll=0 at that boundary.
 local cy=math.sqrt(back.Y*back.Y+back.Z*back.Z)
 local y=math.atan2(back.X,cy)
 local x=if cy>1e-6 then math.atan2(-back.Y,back.Z) else math.atan2(up.Z,up.Y)
 local z=if cy>1e-6 then math.atan2(-up.X,right.X) else 0
 return {math.deg(x)%360,math.deg(y)%360,math.deg(z)%360}
end
-- AbsolutePosition uses core-safe GUI coordinates; GetMouseLocation does not.
-- GetInsetArea(None).Min is the fullscreen origin in that GUI coordinate space.
function Math.guiPoint(screenPoint,screenOrigin) return screenPoint+screenOrigin end
function Math.cameraPitch(pitch,focusY,distance)
 -- Reach eye level without putting the private camera beneath the base floor.
 local minimum=math.asin(math.clamp((1.5-focusY)/distance,-.999,.999))
 return math.clamp(pitch,minimum,1.5)
end
function Math.cameraPan(frame,size,delta,distance,fov)
 local scale=2*distance*math.tan(math.rad(fov)/2)/math.max(size.Y,1)
 return (frame.RightVector*(-delta.X)+frame.UpVector*delta.Y)*scale
end
function Math.project(frame,size,point,fov)
 if size.X<1 or size.Y<1 then return nil end
 local p=frame:PointToObjectSpace(point)
 local depth=-p.Z
 if depth<=.0001 then return nil end
 local t=math.tan(math.rad(fov)/2)
 return Vector2.new((1+p.X/(depth*t*size.X/size.Y))*size.X/2,(1-p.Y/(depth*t))*size.Y/2),depth
end
function Math.ray(frame,size,pixel,fov)
 if size.X<1 or size.Y<1 then return nil end
 local t=math.tan(math.rad(fov)/2)
 local v=Vector3.new((pixel.X/size.X*2-1)*size.X/size.Y*t,(1-pixel.Y/size.Y*2)*t,-1)
 return frame.Position,frame:VectorToWorldSpace(v).Unit
end
function Math.ground(origin,direction,height)
 if not origin or math.abs(direction.Y)<.00001 then return nil end
 local distance=((height or 0)-origin.Y)/direction.Y
 if distance<=0 then return nil end
 return origin+direction*distance
end
function Math.dragPoint(kind,base,origin,direction,camera,pivot)
 local center=pivot or Vector3.new(table.unpack(base.position))
 if kind~="MoveY" and kind:sub(1,6)~="Rotate" then return Math.ground(origin,direction,center.Y) end
 local n
 if kind=="MoveY" then n=Vector3.new(camera.LookVector.X,0,camera.LookVector.Z) else local _,_,normal=Math.rotationBasis(base,kind);n=normal end
 local den=dot(direction,n)
 if math.abs(den)<.00001 then return nil end
 local distance=dot(center-origin,n)/den
 return if distance>0 then origin+direction*distance else nil
end
function Math.transform(base,kind,startPoint,point,snap,grid,pivot)
 local copy={position=table.clone(base.position),rotation=table.clone(base.rotation),scale=base.scale}
 local function quantize(n) return if snap then math.round(n/grid)*grid else n end
 if kind=="MoveY" then copy.position[2]=quantize(base.position[2]+point.Y-startPoint.Y)
 elseif kind=="Move" or kind=="MoveX" or kind=="MoveZ" then
  if kind~="MoveZ" then copy.position[1]=quantize(base.position[1]+point.X-startPoint.X) end
  if kind~="MoveX" then copy.position[3]=quantize(base.position[3]+point.Z-startPoint.Z) end
 elseif kind:sub(1,6)=="Rotate" then
  local u,v=Math.rotationBasis(base,kind)
  local center=pivot or Vector3.new(table.unpack(base.position))
  local a,b=startPoint-center,point-center
  local delta=math.deg(math.atan2(dot(b,v),dot(b,u))-math.atan2(dot(a,v),dot(a,u)))
  local axis=if kind=="RotatePitch" then 1 elseif kind=="RotateRoll" then 3 else 2
  if axis==2 then delta=-delta end
  delta=if snap then math.round(delta/15)*15 else delta
  if math.abs(delta)>1e-8 then copy.rotation=rotateLocal(base.rotation,axis,math.rad(delta)) end
 elseif kind=="Scale" then
  local center=Vector3.new(table.unpack(base.position))
  local old=math.max(.01,(startPoint-center).Magnitude)
  copy.scale=math.clamp(base.scale*(point-center).Magnitude/old,.001,1000)
 end
 return copy
end
return Math
