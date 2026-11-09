-- One bounded server observation per BW instruction or scheduled driver sweep step.
local Shared=game.ReplicatedStorage.Shared
local Config=require(Shared.ScannerConfig)
local Geometry=require(Shared.ScannerGeometry)
local Value=require(Shared.BWValue)
local Scanner={}
Scanner.__index=Scanner
-- Stable record IDs distinguish multiple tanks of the same type and owner.
function Scanner.identity(record)
	local owner=record.playerName or "AI"
	local name=record.tankName or record.state.tankType or "Tank"
	return owner.."."..name.."#"..tostring(record.id)
end
function Scanner.new(world,scene)
	return setmetatable({world=world,scene=scene,tokens=Config.ServerBurst,lastTime=0,completed=0},Scanner)
end
function Scanner:execute(source,angle,time,hardware)
 -- Range is explicit hardware data, independent of operating/acquisition performance.
 hardware=if type(hardware)=="table" then hardware else {}
 local ratedRange=hardware.range or Config.MaxRange
 local percent=hardware.distancePercent or Config.DistancePercent
 if type(ratedRange)~="number" or ratedRange~=ratedRange or ratedRange<=0 or ratedRange>Config.MaxHardwareRange
  or type(percent)~="number" or percent~=percent or percent<0 or percent>100 then return nil,"invalidArgument" end
 local range=ratedRange*percent/100
	if type(angle)~="number" or angle~=angle or math.abs(angle)==math.huge then return nil,"invalidArgument" end
	if source.state.health<=0 then return nil,"tankDestroyed" end
	angle=Geometry.normalize(angle)
	local sensor=Geometry.sensorIndex(angle)
	local times=source.sensorScanTimes or {}; source.sensorScanTimes=times
	if time-(times[sensor] or -math.huge)<Config.SensorCooldown-1e-8 then return nil,"sensorCooldown" end
	self.tokens=math.min(Config.ServerBurst,self.tokens+math.max(0,time-self.lastTime)*Config.ServerRate); self.lastTime=time
	if self.tokens<1 then return nil,"scannerBusy" end
	self.tokens-=1; times[sensor]=time
	local state=source.state
 local yaw=state.yaw -- one authoritative orientation for this entire observation
	local origin=state.position+Vector3.new(0,Config.OriginHeight,0)
	local parts,records=self.scene()
	local allowed,physical={},{}
	for _,p in parts do
		if p~=source.hitbox and p.CanQuery~=false then allowed[p]=true; table.insert(physical,p) end
	end
	local overlap=OverlapParams.new(); overlap.FilterType=Enum.RaycastFilterType.Include
	overlap.FilterDescendantsInstances=physical; overlap.RespectCanCollide=false; overlap.MaxParts=Config.MaxSpatialParts+1
	local candidates=self.world:GetPartBoundsInRadius(origin,range,overlap)
	if #candidates>Config.MaxSpatialParts then return nil,"scannerBusy" end
	local ordered={}
	for _,p in candidates do
		if allowed[p] then
			local probes=Geometry.probes(p,origin,yaw,angle,range)
			if #probes>0 then table.insert(ordered,{part=p,probes=probes,lower=probes[1].distance,key=(records[p] and records[p].id or p:GetFullName())..string.format("/%.17g/%.17g/%.17g",p.CFrame.Position.X,p.CFrame.Position.Y,p.CFrame.Position.Z)}) end
		end
	end
	table.sort(ordered,function(a,b)
		if math.abs(a.lower-b.lower)>1e-9 then return a.lower<b.lower end
		return a.key<b.key
	end)
	local ray=RaycastParams.new(); ray.FilterType=Enum.RaycastFilterType.Include
	ray.FilterDescendantsInstances=physical; ray.RespectCanCollide=false; ray.IgnoreWater=true
	local visible,casts={},0
 local keys={}; for _,candidate in ordered do keys[candidate.part]=candidate.key end
 local function keyFor(part)
  local record=records[part]
  return if record and record.state.health>0 then "tank/"..tostring(record.id) else "wall/"..(keys[part] or part:GetFullName())
 end
 for i,candidate in ordered do
  if i>Config.MaxCandidates then return nil,"scannerBusy" end
  for _,probe in candidate.probes do
   local found=visible[keyFor(candidate.part)]
   -- Only this object's lower bound may prune its own probes; a nearer object
   -- must never suppress another visible object elsewhere inside the cone.
   if found and found.distance<=candidate.lower+Config.SurfaceTolerance then break end
   if casts>=Config.MaxRaycasts then return nil,"scannerBusy" end
   casts+=1
   local direction=(probe.point-origin).Unit
   local hit=self.world:Raycast(origin,direction*range,ray)
   if hit and allowed[hit.Instance] then
    local delta=hit.Position-origin; local distance=delta.Magnitude
    if distance>=Config.MinRange and distance<=range+1e-8 and Geometry.inCone(yaw,angle,delta) then
     local key=keyFor(hit.Instance); local old=visible[key]
     if not old or distance<old.distance then visible[key]={hit=hit,distance=distance,key=key} end
    end
   end
  end
 end
 local found={}; for _,entry in visible do table.insert(found,entry) end
 table.sort(found,function(a,b) if a.distance~=b.distance then return a.distance<b.distance end; return a.key<b.key end)
 if #found>Config.MaxCandidates then return nil,"scannerBusy" end
 local detections={}
 for _,entry in found do
  local hit=entry.hit; local record=records[hit.Instance]; local tank=record and record.state.health>0
  local affiliation=if tank then (if source.teamId~=nil and source.teamId==record.teamId then "teammate" else "enemy") else nil
  table.insert(detections,Value.dictionary({type=if tank then "tank" else "wall",distance=entry.distance,
   relative_direction=Geometry.bearing(yaw,hit.Position-origin),world_direction=Geometry.worldBearing(hit.Position-origin),player=if tank then Scanner.identity(record) else Value.Null,relation=affiliation or Value.Null,
   point=Value.dictionary({x=hit.Position.X,y=hit.Position.Y,z=hit.Position.Z},true)},true))
 end
 local nearest=detections[1] or {}
 -- Nearest fields remain as conveniences for existing programs; detections is
 -- the authoritative complete visible-object list, zero-indexed in BW.
 local result=Value.result(nil,{sensor=angle,timestamp=time,range=range,count=#detections,detections=Value.array(detections),
  type=nearest.type or Value.Null,distance=nearest.distance or Value.Null,relative_direction=nearest.relative_direction or Value.Null,world_direction=nearest.world_direction or Value.Null,
  player=nearest.player or Value.Null,relation=nearest.relation or Value.Null,point=nearest.point or Value.Null})
	self.completed+=1; self.lastRaycasts=casts
	return Value.observation(result,time,origin,yaw)
end
return Scanner
