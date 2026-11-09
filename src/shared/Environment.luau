local DefaultFootprint=require(script.Parent.ComponentCatalog)["chassis.standard"].Properties
-- Deterministic terrain descriptions shared by rendering and authoritative movement.
local Environment = {}
local function noise(i, seed)
	local n = math.sin(i*127.1+seed*311.7)*43758.5453
	return n-math.floor(n)
end
local function inside(zone, x, z)
	return ((x-zone.x)/zone.rx)^2+((z-zone.z)/zone.rz)^2 <= 1
end
function Environment.create(size)
	local w,d=size.X,size.Y
	local data={size=size,rocks={},logs={},trees={},zones={
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
	return data
end
function Environment.sample(data,x,z)
	local height,kind,speed=0,"Grass",1
	for _,zone in data.zones do
		if inside(zone,x,z) then kind=zone.kind; speed=zone.speed end
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
	return height,kind,speed
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
	local center,kind,speed=Environment.sample(data,x,z)
	local front=Environment.sample(data,x-s*length/2,z-c*length/2)
	local rear=Environment.sample(data,x+s*length/2,z+c*length/2)
	local right=Environment.sample(data,x+c*width/2,z-s*width/2)
	local left=Environment.sample(data,x-c*width/2,z+s*width/2)
	return math.max(center,(front+rear+right+left)/4), math.atan2(front-rear,length),
		math.atan2(right-left,width),kind,speed
end
return Environment
