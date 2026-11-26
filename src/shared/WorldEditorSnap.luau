-- Authoring-only collision and bounding-box contacts. Pins are undoable editor state, never
-- runtime welds or world-schema fields. Stretch factors are part of saved geometry.
local G=require(script.Parent.WorldObjectGeometry)
local State=require(script.Parent.WorldEditorState)
local Boundary=require(script.Parent.SnapBoundary)
local Snap={Radius=2}
local function dot(a,b)return a.X*b.X+a.Y*b.Y+a.Z*b.Z end
local function cross(a,b)return Vector3.new(a.Y*b.Z-a.Z*b.Y,a.Z*b.X-a.X*b.Z,a.X*b.Y-a.Y*b.X)end
local function array(v)return {v.X,v.Y,v.Z}end
local function vector(v)return Vector3.new(table.unpack(v))end
function Snap.bounds(entry)
 local s=entry.stretch or {1,1,1};return {entry.bounds[1]*s[1],entry.bounds[2]*s[2],entry.bounds[3]*s[3]}
end
function Snap.box(entry)return G.from(entry.position,entry.rotation,Snap.bounds(entry),entry.scale)end
function Snap.opposite(endpoint)return ({A="B",B="A",C="D",D="C"})[endpoint]end
function Snap.axis(entry,endpoint)
 local alongX=if endpoint=="C" or endpoint=="D" then entry.bounds[1]<=entry.bounds[3] else entry.bounds[1]>entry.bounds[3]
 return if alongX then 1 else 3
end
local sourceEdges=setmetatable({},{__mode="k"})
function Snap.hasGeometry(profile)
 return profile and (profile.snap~=nil or profile.fit=="faces" or profile.fit=="mesh")
end
local function supportFaces(profile)
 if profile.fit=="faces" then return profile.faces,profile.bases end
 local triangles,bases={},{}
 for _,cell in profile.boxes or {} do
  local x,y,z=table.unpack(cell.center)
  local w,h,d=table.unpack(cell.size)
  y+=h/2
  local a,b,c,v={x-w/2,y,z-d/2},{x-w/2,y,z+d/2},{x+w/2,y,z+d/2},{x+w/2,y,z-d/2}
  table.insert(triangles,{a,b,c});table.insert(triangles,{a,c,v})
  table.insert(bases,y-h);table.insert(bases,y-h)
 end
 return triangles,bases
end
local function sourceGeometry(profile)
 if not Snap.hasGeometry(profile) then return end
 local cached=sourceEdges[profile]
 if not cached then
  local triangles,bases=supportFaces(profile)
  local edges=Boundary.edges(if profile.snap then profile.snap.faces or {} else triangles,profile.snap,if not profile.snap then bases else nil)
  local minX,maxX,minZ,maxZ=math.huge,-math.huge,math.huge,-math.huge
  for _,edge in edges do
   for _,v in {edge.a,edge.b} do
    minX=math.min(minX,v.X);maxX=math.max(maxX,v.X)
    minZ=math.min(minZ,v.Z);maxZ=math.max(maxZ,v.Z)
   end
  end
  cached={edges=edges,minX=minX,maxX=maxX,minZ=minZ,maxZ=maxZ,handles={}}
  sourceEdges[profile]=cached
 end
 return cached
end
local function collisionEnds(entry,side,profile)
 local cached=sourceGeometry(profile)
 if not cached or #cached.edges==0 then return end
 local minX,maxX,minZ,maxZ=cached.minX,cached.maxX,cached.minZ,cached.maxZ
 local mx,mz=(minX+maxX)/2,(minZ+maxZ)/2
 local mainX=Snap.axis(entry,"A")==1
 local key=(if mainX then 3 else 0)+(side or 0)
 if cached.handles[key] then return cached.handles[key] end
 local across=if mainX then mz+(maxZ-mz)*(side or 0) else mx+(maxX-mx)*(side or 0)
 local desired=if mainX then {{minX,across},{maxX,across},{mx,minZ},{mx,maxZ}}
  else {{across,minZ},{across,maxZ},{minX,mz},{maxX,mz}}
 local result={}
 for i,label in {"A","B","C","D"} do
  local goal=desired[i]
  local best,point=math.huge,nil
  for _,edge in cached.edges do
   local a,b=edge.a,edge.b
   local dx,dz=b.X-a.X,b.Z-a.Z
   local t=math.clamp(((goal[1]-a.X)*dx+(goal[2]-a.Z)*dz)/math.max(dx*dx+dz*dz,1e-12),0,1)
   local p=a+(b-a)*t
   local distance=(goal[1]-p.X)^2+(goal[2]-p.Z)^2
   if distance<best-1e-10 or (math.abs(distance-best)<=1e-10 and (not point or p.Y>point.Y)) then best=distance;point=p end
  end
  result[label]=point
 end
 cached.handles[key]=result
 return result
end
local function worldPoint(box,p)
 return box.position+box.right*(p.X*box.size.X)+box.up*(p.Y*box.size.Y)+box.back*(p.Z*box.size.Z)
end
local function worldNormal(box,n)
 return (box.right*(n.X/box.size.X)+box.up*(n.Y/box.size.Y)+box.back*(n.Z/box.size.Z)).Unit
end
function Snap.sourceOptions(entry,profile)
 local geometry=sourceGeometry(profile)
 if not geometry then return nil end
 local box=Snap.box(entry)
 local alongX=Snap.axis(entry,"A")==1
 local options={}
 for i,edge in geometry.edges do
  local outward=cross(edge.b-edge.a,edge.normal)
  local side
  if math.abs(outward.X)>math.abs(outward.Z) then
   side=if alongX then (if outward.X<0 then "A" else "B") else (if outward.X<0 then "C" else "D")
  else
   side=if alongX then (if outward.Z<0 then "C" else "D") else (if outward.Z<0 then "A" else "B")
  end
  options[i]={index=i,side=side,a=worldPoint(box,edge.a),b=worldPoint(box,edge.b),normal=worldNormal(box,edge.normal)}
 end
 return options
end
local function edgeMidpoint(profile,index,fraction)
 local source=sourceGeometry(profile)
 local edge=source and source.edges[index]
 return if edge then edge.a+(edge.b-edge.a)*(fraction or .5) else nil
end
function Snap.contact(entry,endpoint,side,profile,index,fraction)
 local point=index and edgeMidpoint(profile,index,fraction)
 if point then return worldPoint(Snap.box(entry),point) end
 local ends=Snap.ends(entry,side,profile)
 return ends[endpoint]
end
function Snap.ends(entry,side,profile)
 local box=Snap.box(entry)
 local contacts=collisionEnds(entry,side,profile)
 if contacts then
  local ends={}
  for label,p in contacts do
   ends[label]=worldPoint(box,p)
  end
  return ends,box
 end
 if Snap.hasGeometry(profile) then return {},box end
 local mainX=entry.bounds[1]>entry.bounds[3]
 local axis=if mainX then box.right else box.back
 local span=if mainX then box.size.X else box.size.Z
 local width=if mainX then box.back*(box.size.Z/2) else box.right*(box.size.X/2)
 local top=box.position+box.up*(box.size.Y/2*(if box.up.Y>=0 then 1 else -1))+width*(side or 0)
 local middle=box.position+box.up*(box.size.Y/2*(if box.up.Y>=0 then 1 else -1))
 return {A=top-axis*(span/2),B=top+axis*(span/2),C=middle-width,D=middle+width},box
end
function Snap.anchor(entry,pin,profile)
 local delta=vector(pin.point)-Snap.contact(entry,pin.endpoint,pin.side,profile,pin.edgeIndex,pin.edgeFraction)
 entry.position={entry.position[1]+delta.X,entry.position[2]+delta.Y,entry.position[3]+delta.Z}
 return entry
end
function Snap.fit(base,endpoint,target,pin,mode,profile,edgeIndex,edgeFraction)
 assert(endpoint~=pin.endpoint,"Release the pinned end before moving it")
 local fixed=vector(pin.point);local free=vector(target.point)
 local delta=if pin.endpoint=="A" or pin.endpoint=="C" then free-fixed else fixed-free
 assert(delta.Magnitude>.05,"Endpoints are too close to fit")
 local result=State.copy(base)
 local index=Snap.axis(base,endpoint)
 local contacts=collisionEnds(base,pin.side,profile)
 local along,localDirection
 if contacts then
  local fixedLocal=(pin.edgeIndex and edgeMidpoint(profile,pin.edgeIndex,pin.edgeFraction)) or contacts[pin.endpoint]
  local freeLocal=(edgeIndex and edgeMidpoint(profile,edgeIndex,edgeFraction)) or contacts[endpoint]
  local span=freeLocal-fixedLocal
  if pin.endpoint=="B" or pin.endpoint=="D" then span=span*-1 end
  local dimensions=Snap.bounds(base)
  localDirection=Vector3.new(span.X*dimensions[1],span.Y*dimensions[2],span.Z*dimensions[3])
  along=array(localDirection)[index]
  assert(localDirection.Magnitude>.00001,"These collision handles overlap")
 end
 if mode=="Stretch" then
  result.stretch=State.copy(base.stretch or {1,1,1})
  if localDirection then
   local remaining=(delta.Magnitude/base.scale)^2-(dot(localDirection,localDirection)-along*along)
   assert(remaining>0 and math.abs(along)>1e-6,"Collision handles cannot fit that distance along this axis")
   local ratio=math.sqrt(remaining)/math.abs(along)
   result.stretch[index]*=ratio
   local v=array(localDirection);v[index]*=ratio;localDirection=vector(v)
  else result.stretch[index]=delta.Magnitude/(base.bounds[index]*base.scale) end
  assert(result.stretch[index]>=.001 and result.stretch[index]<=1000,"Stretch exceeds the allowed range")
 else result.scale=delta.Magnitude/(if localDirection then localDirection.Magnitude else base.bounds[index]*(base.stretch or {1,1,1})[index]) end
 assert(result.scale>=.001 and result.scale<=1000,"Auto-fit exceeds the allowed scale range")
 local direction=delta.Unit
 local _,oldUp=G.axes(base.rotation)
 local desired=if pin.normal then vector(pin.normal) else oldUp
 local up=desired-direction*dot(desired,direction)
 if up.Magnitude<.001 then up=Vector3.new(0,1,0)-direction*direction.Y end
 if up.Magnitude<.001 then up=Vector3.new(1,0,0)-direction*direction.X end
 up=up.Unit
 local right,back
 if index==1 then right=direction;back=cross(right,up).Unit
 else back=direction;right=cross(up,back).Unit end
 up=cross(back,right).Unit
 if localDirection then
  local forward=localDirection.Unit
  local localUp=Vector3.new(0,1,0)-forward*forward.Y
  if localUp.Magnitude<.001 then localUp=Vector3.new(1,0,0)-forward*forward.X end
  localUp=localUp.Unit
  local localSide=cross(forward,localUp)
  local worldSide=cross(direction,up)
  local function axis(x,y,z)
   local v=Vector3.new(x,y,z)
   return direction*dot(v,forward)+up*dot(v,localUp)+worldSide*dot(v,localSide)
  end
  result.rotation=G.rotation(axis(1,0,0),axis(0,1,0),axis(0,0,1))
 else result.rotation=G.rotation(right,up,back) end
 Snap.anchor(result,pin,profile)
 return result
end
function Snap.pin(endpoint,target,side,edgeIndex,edgeFraction)
 return {endpoint=endpoint,point=State.copy(target.point),normal=State.copy(target.normal or {0,1,0}),targetId=target.targetId,kind=target.kind,side=side or 0,edgeIndex=edgeIndex,edgeFraction=edgeFraction}
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
function Snap.collisionGeometry(entry,profile,hitOnly)
 local box=Snap.box(entry)
 local triangles,bases=supportFaces(profile)
 local faces=if #triangles>0 then G.faces(box,triangles,bases,profile.walls) else {}
 return {faces=faces,edges=if hitOnly then nil else Snap.sourceOptions(entry,profile),
  center=box.position,radius=box.size.Magnitude/2+.02,explicit=profile.snap~=nil}
end
function Snap.isSupportFace(face)
 return not face.wall and face.up.Y>=G.MinSupportNormal
end
function Snap.collisionHit(geometry,origin,direction,limit,supportOnly)
 local delta=geometry.center-origin
 local along=math.clamp(dot(delta,direction),0,limit)
 if (delta-direction*along).Magnitude>geometry.radius then return end
 local hit
 for _,face in geometry.faces do
  if supportOnly and not Snap.isSupportFace(face) then continue end
  local a,b,c=table.unpack(face.vertices)
  local denominator=dot(direction,face.up)
  if math.abs(denominator)>1e-8 then
   local distance=dot(a-origin,face.up)/denominator
   if distance>=0 and distance<limit then
    local p=origin+direction*distance
    local u,v,w=b-a,c-b,a-c
    if dot(cross(u,p-a),face.up)>=-1e-5 and dot(cross(v,p-b),face.up)>=-1e-5 and dot(cross(w,p-c),face.up)>=-1e-5 then
     limit=distance;hit={point=p,normal=face.up,face=face}
    end
   end
  end
 end
 return hit,limit
end
function Snap.collisionTarget(entry,geometry,point,radius,normal)
 if not geometry.explicit and (point-geometry.center).Magnitude>geometry.radius+radius then return end
 local nearest,best,corner=nil,radius,nil
 for _,edge in geometry.edges do
  local close=Snap.closest(edge.a,edge.b,point)
  local distance=(close-point).Magnitude
  local endpoint=if (edge.a-point).Magnitude<=(edge.b-point).Magnitude then edge.a else edge.b
  local endDistance=(endpoint-point).Magnitude
  if endDistance<=radius*.3 and (not corner or endDistance<best) then
   nearest={point=array(endpoint),normal=array(edge.normal),targetId=entry.id,kind="corner"}
   best=endDistance;corner=true
  elseif not corner and distance<best then
   nearest={point=array(close),normal=array(edge.normal),targetId=entry.id,kind="edge",edge={array(edge.a),array(edge.b)}}
   best=distance
  end
 end
 if nearest then return nearest,best end
 if normal and not geometry.explicit then return {point=array(point),normal=array(normal),targetId=entry.id,kind="face"},0 end
end
-- Project a small neighborhood around the pointer. A dot selects a fixed
-- midpoint, while a line selects the perspective-correct point along it.
function Snap.screenEdges(edges,project,pixel,limit)
 local candidates={}
 local chosen,bestPriority,bestDistance,bestDepth=nil,0,math.huge,math.huge
 for _,edge in edges do
  local a,depthA=project(edge.a)
  local b,depthB=project(edge.b)
  if a and b then
   local depth=(depthA+depthB)/2
   local middle=(a*depthA+b*depthB)/(depthA+depthB)
   local midpointDistance=(middle-pixel).Magnitude
   local delta=b-a
   local offset=pixel-a
   local t=math.clamp((offset.X*delta.X+offset.Y*delta.Y)/math.max(delta.X^2+delta.Y^2,1e-8),0,1)
   local lineDistance=(a+delta*t-pixel).Magnitude
   local priority=if midpointDistance<=9 then 2 elseif lineDistance<=6 then 1 else 0
   if midpointDistance<=110 or lineDistance<=60 then
    table.insert(candidates,{pixel=middle,edge=edge,distance=math.min(midpointDistance,lineDistance)})
   end
   if priority>0 then
    local distance=if priority==2 then midpointDistance else lineDistance
    if priority>bestPriority or (priority==bestPriority and (distance<bestDistance or (distance==bestDistance and depth<bestDepth))) then
     local fraction=if priority==2 then .5 else t*depthA/((1-t)*depthB+t*depthA)
     chosen={edge=edge,fraction=fraction,point=edge.a+(edge.b-edge.a)*fraction,distance=distance,priority=priority}
     bestPriority,bestDistance,bestDepth=priority,distance,depth
    end
   end
  end
 end
 table.sort(candidates,function(a,b)return a.distance<b.distance end)
 for i=#candidates,limit+1,-1 do candidates[i]=nil end
 return chosen,candidates
end
function Snap.edgeTarget(entry,choice)
 local edge=choice.edge
 return {point=array(choice.point),normal=array(edge.normal),targetId=entry.id,kind="edge",edge={array(edge.a),array(edge.b)}}
end
function Snap.nearby(document,entry,onlyEndpoint,onlySide,findTarget,profile)
 local best,chosen=Snap.Radius,nil
 for _,side in (if onlySide~=nil then {onlySide} else {0,-1,1}) do
 local ends=Snap.ends(entry,side,profile)
 for _,endpoint in {"A","B"} do
  if not ends[endpoint] or (onlyEndpoint and endpoint~=onlyEndpoint) then continue end
  for _,other in document.objects do
   if other.id~=entry.id then
    local target,d
    if findTarget then target,d=findTarget(other,ends[endpoint]) else target,d=Snap.target(other,ends[endpoint],Snap.Radius) end
    -- Body dragging only magnetizes to actual edges/corners, not distant faces.
    if target and target.kind~="face" and d<best then best=d;chosen={endpoint=endpoint,target=target,side=side} end
   end
  end
 end
 end
 return chosen
end
return Snap
