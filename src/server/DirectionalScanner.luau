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
function Scanner:execute(source,angle,time)
	if type(angle)~="number" or angle~=angle or math.abs(angle)==math.huge then return nil,"Scanner expects a finite angle." end
	if source.state.health<=0 then return nil,"Destroyed tanks cannot scan." end
	angle=Geometry.normalize(angle)
	local sensor=Geometry.sensorIndex(angle)
	local times=source.sensorScanTimes or {}; source.sensorScanTimes=times
	if time-(times[sensor] or -math.huge)<Config.SensorCooldown-1e-8 then return nil,string.format("Scanner sensor %d rate limit: allow %g seconds before reusing this sensor.",sensor,Config.SensorCooldown) end
	self.tokens=math.min(Config.ServerBurst,self.tokens+math.max(0,time-self.lastTime)*Config.ServerRate); self.lastTime=time
	if self.tokens<1 then return nil,"Server scanner budget is busy; try a later instruction." end
	self.tokens-=1; times[sensor]=time
	local state=source.state
	local origin=state.position+Vector3.new(0,Config.OriginHeight,0)
	local parts,records=self.scene()
	local allowed,physical={},{}
	for _,p in parts do
		if p~=source.hitbox and p.CanQuery~=false then allowed[p]=true; table.insert(physical,p) end
	end
	local overlap=OverlapParams.new(); overlap.FilterType=Enum.RaycastFilterType.Include
	overlap.FilterDescendantsInstances=physical; overlap.RespectCanCollide=false; overlap.MaxParts=Config.MaxSpatialParts+1
	local candidates=self.world:GetPartBoundsInRadius(origin,Config.MaxRange,overlap)
	if #candidates>Config.MaxSpatialParts then return nil,"Scanner scene exceeds the bounded geometry budget." end
	local ordered={}
	for _,p in candidates do
		if allowed[p] then
			local probes=Geometry.probes(p,origin,state.yaw,angle)
			if #probes>0 then table.insert(ordered,{part=p,probes=probes,lower=probes[1].distance,key=(records[p] and records[p].id or p:GetFullName())..string.format("/%.17g/%.17g/%.17g",p.CFrame.Position.X,p.CFrame.Position.Y,p.CFrame.Position.Z)}) end
		end
	end
	table.sort(ordered,function(a,b)
		if math.abs(a.lower-b.lower)>1e-9 then return a.lower<b.lower end
		return a.key<b.key
	end)
	local ray=RaycastParams.new(); ray.FilterType=Enum.RaycastFilterType.Include
	ray.FilterDescendantsInstances=physical; ray.RespectCanCollide=false; ray.IgnoreWater=true
	local best,bestDistance,casts=nil,math.huge,0
	for i,candidate in ordered do
		if candidate.lower>=bestDistance-Config.SurfaceTolerance then break end
		if i>Config.MaxCandidates then return nil,"Scanner scene exceeds the bounded candidate budget." end
		for _,probe in candidate.probes do
			if bestDistance<=candidate.lower+Config.SurfaceTolerance then break end
			if casts>=Config.MaxRaycasts then return nil,"Scanner scene exceeds the bounded ray budget." end
			casts+=1
			local direction=(probe.point-origin).Unit
			local hit=self.world:Raycast(origin,direction*Config.MaxRange,ray)
			if hit and allowed[hit.Instance] then
				local delta=hit.Position-origin; local distance=delta.Magnitude
				if distance>=Config.MinRange and distance<=Config.MaxRange+1e-8 and Geometry.inCone(state.yaw,angle,delta) and distance<bestDistance then
					best,bestDistance=hit,distance
				end
			end
		end
	end
	local result
	if best then
		local record=records[best.Instance]
		local tank=record and record.state.health>0
		local affiliation=if tank then (if source.teamId~=nil and source.teamId==record.teamId then "teammate" else "enemy") else nil
		result=Value.scan(if tank then "tank" else "wall",bestDistance,Geometry.bearing(state.yaw,best.Position-origin),
			if tank then Scanner.identity(record) else nil,affiliation)
	else result=Value.scan() end
	self.completed+=1; self.lastRaycasts=casts
	return Value.observation(result,time,origin,state.yaw)
end
return Scanner
