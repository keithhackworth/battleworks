-- Authoring-only bounding-box contacts. Pins are undoable editor state, never
-- runtime welds or world-schema fields. Fitted poses use the existing uniform scale.
local G=require(script.Parent.WorldObjectGeometry)
local State=require(script.Parent.WorldEditorState)
local Snap={Radius=2}
local function dot(a,b)return a.X*b.X+a.Y*b.Y+a.Z*b.Z end
local function cross(a,b)return Vector3.new(a.Y*b.Z-a.Z*b.Y,a.Z*b.X-a.X*b.Z,a.X*b.Y-a.Y*b.X)end
local function array(v)return {v.X,v.Y,v.Z}end
local function vector(v)return Vector3.new(table.unpack(v))end
function Snap.box(entry)return G.from(entry.position,entry.rotation,entry.bounds,entry.scale)end
function Snap.ends(entry,side)
 local box=Snap.box(entry)
 local axis=if box.size.X>box.size.Z then box.right else box.back
 local span=math.max(box.size.X,box.size.Z)
 local width=if box.size.X>box.size.Z then box.back*(box.size.Z/2) else box.right*(box.size.X/2)
 local top=box.position+box.up*(box.size.Y/2*(if box.up.Y>=0 then 1 else -1))+width*(side or 0)
 return {A=top-axis*(span/2),B=top+axis*(span/2)},box
end
function Snap.anchor(entry,pin)
 local ends=Snap.ends(entry,pin.side)
 local delta=vector(pin.point)-ends[pin.endpoint]
 entry.position={entry.position[1]+delta.X,entry.position[2]+delta.Y,entry.position[3]+delta.Z}
 return entry
end
function Snap.fit(base,endpoint,target,pin)
 assert(endpoint~=pin.endpoint,"Release the pinned end before moving it")
 local fixed=vector(pin.point);local free=vector(target.point)
 local delta=if pin.endpoint=="A" then free-fixed else fixed-free
 assert(delta.Magnitude>.05,"Endpoints are too close to fit")
 local result=State.copy(base)
 result.scale=delta.Magnitude/math.max(base.bounds[1],base.bounds[3])
 assert(result.scale>=.001 and result.scale<=1000,"Auto-fit exceeds the allowed scale range")
 local direction=delta.Unit
 local _,oldUp=G.axes(base.rotation)
 local desired=if pin.normal then vector(pin.normal) else oldUp
 local up=desired-direction*dot(desired,direction)
 if up.Magnitude<.001 then up=Vector3.new(0,1,0)-direction*direction.Y end
 if up.Magnitude<.001 then up=Vector3.new(1,0,0)-direction*direction.X end
 up=up.Unit
 local right,back
 if base.bounds[1]>base.bounds[3] then right=direction;back=cross(right,up).Unit
 else back=direction;right=cross(up,back).Unit end
 up=cross(back,right).Unit
 result.rotation=G.rotation(right,up,back)
 Snap.anchor(result,pin)
 return result
end
function Snap.pin(endpoint,target,side)
 return {endpoint=endpoint,point=State.copy(target.point),normal=State.copy(target.normal or {0,1,0}),targetId=target.targetId,kind=target.kind,side=side or 0}
end
function Snap.top(entry)
 local box=Snap.box(entry)
 local axes={box.right,box.up,box.back};local size={box.size.X,box.size.Y,box.size.Z}
 local index=1;for i=2,3 do if math.abs(axes[i].Y)>math.abs(axes[index].Y) then index=i end end
 local sign=if axes[index].Y>=0 then 1 else -1
 local normal=axes[index]*sign
 local center=box.position+normal*(size[index]/2)
 local other={};for i=1,3 do if i~=index then table.insert(other,i) end end
 local a,b=axes[other[1]]*(size[other[1]]/2),axes[other[2]]*(size[other[2]]/2)
 return {center-a-b,center+a-b,center+a+b,center-a+b},normal,center
end
function Snap.closest(a,b,point)
 local delta=b-a
 local t=math.clamp(dot(point-a,delta)/math.max(dot(delta,delta),1e-12),0,1)
 return a+delta*t
end
function Snap.target(entry,point,radius,previous)
 radius=radius or Snap.Radius
 local corners,normal,center=Snap.top(entry)
 if previous and previous.targetId==entry.id and previous.kind=="corner" and (vector(previous.point)-point).Magnitude<=radius*.45 then return State.copy(previous) end
 local nearest,best=nil,math.huge
 for _,corner in corners do
  local d=(corner-point).Magnitude
  if d<=radius*.3 and d<best then nearest={point=array(corner),normal=array(normal),targetId=entry.id,kind="corner"};best=d end
 end
 if nearest then return nearest,best end
 for i,a in corners do
  local b=corners[i%4+1];local close=Snap.closest(a,b,point);local d=(close-point).Magnitude
  if d<=radius and d<best then nearest={point=array(close),normal=array(normal),targetId=entry.id,kind="edge",edge={array(a),array(b)}};best=d end
 end
 if nearest then return nearest,best end
 -- The face itself is also a useful contact when the pointer is on its top.
 local offset=dot(point-center,normal)
 if math.abs(offset)<=.15 then
  local p=point-normal*offset
  local a,b=corners[2]-corners[1],corners[4]-corners[1]
  local q=p-corners[1]
  local x,z=dot(q,a)/dot(a,a),dot(q,b)/dot(b,b)
  if x>=0 and x<=1 and z>=0 and z<=1 then return {point=array(p),normal=array(normal),targetId=entry.id,kind="face"},math.abs(offset) end
 end
end
function Snap.nearby(document,entry,onlyEndpoint,onlySide)
 local best,chosen=Snap.Radius,nil
 for _,side in (if onlySide~=nil then {onlySide} else {0,-1,1}) do
 local ends=Snap.ends(entry,side)
 for _,endpoint in {"A","B"} do
  if onlyEndpoint and endpoint~=onlyEndpoint then continue end
  for _,other in document.objects do
   if other.id~=entry.id then
    local target,d=Snap.target(other,ends[endpoint],Snap.Radius)
    -- Body dragging only magnetizes to actual edges/corners, not distant faces.
    if target and target.kind~="face" and d<best then best=d;chosen={endpoint=endpoint,target=target,side=side} end
   end
  end
 end
 end
 return chosen
end
return Snap
