-- Viewport picking independent of Workspace/current camera and native gizmos.
local Math={}
local Geometry=require(script.Parent.WorldObjectGeometry)
local function dot(a,b)return a.X*b.X+a.Y*b.Y+a.Z*b.Z end
function Math.rotationBasis(base,kind)
 -- Euler order is Rx * Ry * Rz. Display and drag each ring around the
 -- axis that actually changes when its corresponding field is edited.
 if kind=="RotatePitch" then return Vector3.new(0,1,0),Vector3.new(0,0,1),Vector3.new(1,0,0) end
 local right,up,back=Geometry.axes({base.rotation[1],if kind=="RotateRoll" then base.rotation[2] else 0,0})
 if kind=="RotateRoll" then return right,up,back end
 return right,back,up
end
-- AbsolutePosition uses core-safe GUI coordinates; GetMouseLocation does not.
-- GetInsetArea(None).Min is the fullscreen origin in that GUI coordinate space.
function Math.guiPoint(screenPoint,screenOrigin) return screenPoint+screenOrigin end
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
  copy.rotation[axis]=(base.rotation[axis]+(if snap then math.round(delta/15)*15 else delta))%360
 elseif kind=="Scale" then
  local center=Vector3.new(table.unpack(base.position))
  local old=math.max(.01,(startPoint-center).Magnitude)
  copy.scale=math.clamp(base.scale*(point-center).Magnitude/old,.001,1000)
 end
 return copy
end
return Math
