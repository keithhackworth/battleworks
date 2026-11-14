local DefaultFootprint=require(script.Parent.ComponentCatalog)["chassis.standard"].Properties
-- Deterministic terrain descriptions shared by rendering and authoritative movement.
local Environment = {}
local Surface=require(script.Parent.SurfacePhysics)
local Motion=require(script.Parent.VehicleMotion)
local WorldGeometry=require(script.Parent.WorldObjectGeometry)
-- Gentle crosswind exceeds passive rolling resistance, not powered ice grip.
Environment.IceWind=table.freeze({direction=Vector3.new(1,0,-0.35).Unit,maxForce=1.2,driftSpeed=1.5})
Environment.WindyIce=table.freeze({staticFriction=Surface.Profiles.Ice.staticFriction,kineticFriction=Surface.Profiles.Ice.kineticFriction,resistance=Surface.Profiles.Ice.resistance,passiveGrip=0.15})
function Environment.applyForces(data,state)
 local wind=data and data.wind
 if not wind then return end
 local v=Motion.ensure(state)
 local along=v.X*wind.direction.X+v.Z*wind.direction.Z
 local strength=wind.maxForce*math.clamp(1-along/wind.driftSpeed,0,1)
 Motion.force(state,wind.direction*strength)
end
function Environment.setPhysicsSurfaces(data,regions)
 data.physicsSurfaces=Surface.prepare(regions)
end
local function noise(i, seed)
	local n = math.sin(i*127.1+seed*311.7)*43758.5453
	return n-math.floor(n)
end
local function inside(zone, x, z)
	return ((x-zone.x)/zone.rx)^2+((z-zone.z)/zone.rz)^2 <= 1
end
function Environment.create(size,weather)
 weather=weather or "Normal"
 assert(weather=="Normal" or weather=="IceWind","Unknown arena weather preset")
	local w,d=size.X,size.Y
	local data={size=size,weather=weather,rocks={},logs={},trees={},zones={
		{kind="Water",x=w*0.28,z=0,rx=w*0.16,rz=d*0.13,speed=0.9},
		{kind="Mud",x=-w*0.27,z=-d*0.04,rx=w*0.17,rz=d*0.14,speed=0.75},
		{kind="Woods",x=w*0.27,z=-d*0.36,rx=w*0.16,rz=d*0.11,speed=1},
	}}
	-- Keep the target row, central passage and southern spawn strip open.
	local function clear(x,z,r)
		return math.abs(x)+r<w/2-6 and math.abs(z)+r<d/2-6
			and math.abs(x)>10+r and z+r<d*0.12
			and math.abs(z+d*65/230)>10+r
	end
	if math.min(w,d)>=60 then
		for i=1,18 do
			local x=-w*0.28+(noise(i,1)-0.5)*w*0.28
			local z=-d*0.28+(noise(i,2)-0.5)*d*0.3
			local rx=2.5+noise(i,3)*2.5; local rz=2.5+noise(i,4)*2.5
			if clear(x,z,math.max(rx,rz)) then
				table.insert(data.rocks,{x=x,z=z,rx=rx,rz=rz,height=1+noise(i,5)*1.8})
			end
		end
		for i=1,5 do
			local x=-w*0.18+(noise(i,6)-0.5)*w*0.14
			local z=-d*0.07+(noise(i,7)-0.5)*d*0.12
			local half=4+noise(i,8)*2
			if clear(x,z,half) then table.insert(data.logs,{x=x,z=z,half=half,radius=0.65+noise(i,9)*0.3}) end
		end
		local woods=data.zones[3]
		for i=1,18 do
			local x=woods.x+(noise(i,10)-0.5)*woods.rx*1.7
			local z=woods.z+(noise(i,11)-0.5)*woods.rz*1.7
			local separated=true
			for _,tree in data.trees do if (tree.x-x)^2+(tree.z-z)^2<100 then separated=false end end
			if separated and clear(x,z,3.5) then table.insert(data.trees,{x=x,z=z,radius=0.9,height=9+noise(i,12)*4}) end
		end
	end
 if weather=="IceWind" then
  Environment.setPhysicsSurfaces(data,{{id="arena-ice",shape="box",x=0,z=0,rx=w/2+10,rz=d/2+10,priority=10,surface=Environment.WindyIce}})
  data.wind=Environment.IceWind
 end
	return data
end
function Environment.sample(data,x,z,maxHeight)
	local height,kind,speed=0,if data.weather=="IceWind" then "Ice" else "Grass",1
 local supportingSurface
	for _,zone in data.zones do
		if inside(zone,x,z) and data.weather~="IceWind" then kind=zone.kind; speed=zone.speed end
	end
	for _,rock in data.rocks do
		local q=((x-rock.x)/rock.rx)^2+((z-rock.z)/rock.rz)^2
		if q<1 then height=math.max(height,rock.height*math.sqrt(1-q)); kind="Rock" end
	end
	for _,log in data.logs do
		local q=(z-log.z)/log.radius
		if math.abs(x-log.x)<=log.half and math.abs(q)<1 then
			height=math.max(height,log.radius*math.sqrt(1-q*q)); kind="Log"
		end
	end
 if data.worldObjects and maxHeight then
  local h,surface=data.worldObjects:support(x,z,maxHeight)
  if h and h>=height then height=h;kind="Structure";speed=1;supportingSurface=surface end
 end
	return height,kind,speed,supportingSurface
end
function Environment.blocked(data,x,z,radius)
	for _,tree in data.trees do
		if (x-tree.x)^2+(z-tree.z)^2<(radius+tree.radius)^2 then return true end
	end
	return false
end
function Environment.pose(data,position,yaw,footprint)
 local shape=footprint or DefaultFootprint
 local length,width=shape.ContactLength,shape.ContactWidth
	local x,z=position.X,position.Z
	local s,c=math.sin(yaw),math.cos(yaw)
 local maxHeight=position.Y+WorldGeometry.MaxStep
 local points={{x,z},{x-s*length/2,z-c*length/2},{x+s*length/2,z+c*length/2},{x+c*width/2,z-s*width/2},{x-c*width/2,z+s*width/2}}
 local heights,surfaces={},{}
 local kind,speed
 for i,point in points do
  local h,k,v,surface=Environment.sample(data,point[1],point[2],maxHeight)
  heights[i]=h;surfaces[i]=surface
  if i==1 then kind=k;speed=v end
 end
 -- The step limit selects a reachable surface, not a maximum height for
 -- every point along that same slope. Feet ahead on an incline can naturally
 -- be more than one step above the chassis center.
 local reference=surfaces[1]
 if not reference then
  local best=heights[1]
  for i=2,5 do
   if surfaces[i] then
    local projected=WorldGeometry.planeHeight(surfaces[i],x,z)
    if projected and projected>=best and projected<=maxHeight+.001 then reference=surfaces[i];best=projected end
   end
  end
 end
 if reference then
  kind="Structure";speed=1
  for i,point in points do
   local projected=WorldGeometry.planeHeight(reference,point[1],point[2])
   local h,_,_,surface=Environment.sample(data,point[1],point[2],math.max(maxHeight,projected+WorldGeometry.MaxStep))
   -- A real contact under another part of the footprint can support a track
   -- over a narrow board edge or short join. Once all contacts leave, no
   -- reference survives and ordinary gravity resumes. Overhead structures
   -- cannot become references without first passing the original step limit.
   heights[i]=if surface then h else math.max(h,projected)
  end
 end
 local center,front,rear,right,left=table.unpack(heights)
	return math.max(center,(front+rear+right+left)/4), math.atan2(front-rear,length),
		math.atan2(right-left,width),kind,speed
end
return Environment
