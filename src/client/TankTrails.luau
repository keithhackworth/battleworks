-- Local cosmetic trails. Emitters share spacing, lifetime, and a bounded pool.
-- A future equipped trail ID comes from the server snapshot.
local Trails={}
local function snowMark(part,frame,length,width)
 part.Name="SnowTankTrack"
 part.Color=Color3.fromRGB(122,146,164)
 part.Size=Vector3.new(width,.035,length+.12)
 part.CFrame=frame
end
local styles={
 snow_tracks={surface="Snow",lifetime=3,fade=.65,opacity=.56,interval=.20,spacing=1.1,draw=snowMark},
}
local limit=16
local maxJump=24
local treadOffset=3.8

local function newMark(parent)
 local part=Instance.new("Part");part.Name="TankTrailMark"
 part.Anchored=true;part.CanCollide=false;part.CanTouch=false;part.CanQuery=false;part.CastShadow=false
 part.Material=Enum.Material.SmoothPlastic;part.Transparency=1;part.Parent=parent
 return part
end

function Trails.reset(renderer)
 local trail=renderer.trail
 if not trail then return end
 trail.previous=nil
 for _,mark in trail.marks do
  mark.expires=nil
  mark.left.Transparency=1;mark.right.Transparency=1
 end
end

local function emit(renderer,trail,style,previous,current,now)
 local tracked=renderer.components.Mobility.Kind=="Tracked"
 local offset=if tracked then treadOffset else 3.5
 local width=if tracked then 1.55 else .82
 trail.index=trail.index%limit+1
 local mark=trail.marks[trail.index]
 if not mark then
  local folder=trail.folder
  if not folder then
   folder=Instance.new("Folder");folder.Name="TankTrails";folder.Parent=renderer.model
   trail.folder=folder
  end
  mark={left=newMark(folder),right=newMark(folder)}
  trail.marks[trail.index]=mark
 end
 local contactHeight=.045
 for i,part in {mark.left,mark.right} do
  local lane=Vector3.new((if i==1 then -1 else 1)*offset,contactHeight,0)
  local a,b=previous:PointToWorldSpace(lane),current:PointToWorldSpace(lane)
  local length=(b-a).Magnitude
  if length>.05 then
   local midpoint=(a+b)/2
   style.draw(part,CFrame.lookAt(midpoint,b,current.UpVector),length,width)
   part.Transparency=1-style.opacity
  else part.Transparency=1 end
 end
 mark.expires=now+style.lifetime
 mark.style=style
end

function Trails.update(renderer,state,dt)
 local style=styles[state.trailEffect] or styles.snow_tracks
 local grounded=state.health>0 and (state.lift or 0)<=.25 and not state.waitingForSpawn
 local eligible=grounded and (not style.surface or state.surface==style.surface)
 local trail=renderer.trail
 if not trail then
  if not eligible then return end
  trail={time=0,index=0,marks={}}
  renderer.trail=trail
 end
 trail.time+=math.max(0,dt)
 local now=trail.time
 for _,mark in trail.marks do
  if mark.expires then
   local remaining=mark.expires-now
   if remaining<=mark.style.fade then
    local transparency=1-mark.style.opacity*math.clamp(remaining/mark.style.fade,0,1)
    if mark.left.Transparency<1 then mark.left.Transparency=transparency end
    if mark.right.Transparency<1 then mark.right.Transparency=transparency end
    if remaining<=0 then mark.expires=nil end
   end
  end
 end
 if not eligible then trail.previous=nil;return end
 local position=renderer.position or state.position
 local yaw=renderer.yaw or state.yaw
 local current=CFrame.new(position)*CFrame.Angles(0,yaw,0)
  *CFrame.Angles(state.groundPitch or 0,0,state.groundRoll or 0)
 if trail.style~=style or not trail.previous then
  trail.previous=current;trail.yaw=yaw;trail.last=now;trail.style=style
  return
 end
 local previous=trail.previous
 local delta=position-previous.Position
 local distance=math.sqrt(delta.X^2+delta.Z^2)
 local turn=math.abs(math.atan2(math.sin(yaw-trail.yaw),math.cos(yaw-trail.yaw)))
 local treadTravel=if renderer.components.Mobility.Kind=="Tracked" then turn*treadOffset else 0
 if distance>maxJump or turn>math.pi/2 then
  trail.previous=current;trail.yaw=yaw;trail.last=now
 elseif math.max(distance,treadTravel)>=style.spacing and now-trail.last>=style.interval then
  emit(renderer,trail,style,previous,current,now)
  trail.previous=current;trail.yaw=yaw;trail.last=now
 end
end
return Trails
