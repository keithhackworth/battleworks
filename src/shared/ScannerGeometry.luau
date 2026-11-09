-- Clip an oriented collision box against the two vertical cone planes, then
-- find nearest points on its clipped faces. This includes edge-only visibility.
local Config=require(script.Parent.ScannerConfig)
local G={}
function G.normalize(angle) local value=angle%360; return if value>=360 then 0 else value end
function G.sensorIndex(angle) return math.floor(G.normalize(angle)/360*Config.SensorCount+0.5)%Config.SensorCount+1 end
local function dot(a,b) return a.X*b.X+a.Y*b.Y+a.Z*b.Z end
G.dot=dot
function G.direction(yaw,angle)
	local a=yaw-math.rad(angle)
	return Vector3.new(-math.sin(a),0,-math.cos(a))
end
function G.worldBearing(delta)
 if delta.X^2+delta.Z^2<1e-20 then return 0 end
 return G.normalize(math.deg(math.atan2(delta.X,-delta.Z)))
end
function G.bearing(yaw,delta)
	if delta.X^2+delta.Z^2<1e-20 then return 0 end
	return G.normalize(G.worldBearing(delta)+math.deg(yaw))
end
function G.inCone(yaw,angle,delta)
	local bearing=G.bearing(yaw,delta)
	return math.abs((bearing-angle+180)%360-180)<=Config.ConeWidth/2+Config.AngularEpsilon
end
local function clip(poly,origin,normal)
	local output={}
	for i,a in poly do
		local b=poly[i%#poly+1]
		local da,db=dot(a-origin,normal),dot(b-origin,normal)
		if da>=-1e-9 then table.insert(output,a) end
		if (da<0 and db>0) or (da>0 and db<0) then table.insert(output,a+(b-a)*(da/(da-db))) end
	end
	return output
end
local function closestTriangle(p,a,b,c)
	local ab,ac,ap=b-a,c-a,p-a
	local d1,d2=dot(ab,ap),dot(ac,ap)
	if d1<=0 and d2<=0 then return a end
	local bp=p-b; local d3,d4=dot(ab,bp),dot(ac,bp)
	if d3>=0 and d4<=d3 then return b end
	local vc=d1*d4-d3*d2
	if vc<=0 and d1>=0 and d3<=0 then return a+ab*(d1/(d1-d3)) end
	local cp=p-c; local d5,d6=dot(ab,cp),dot(ac,cp)
	if d6>=0 and d5<=d6 then return c end
	local vb=d5*d2-d1*d6
	if vb<=0 and d2>=0 and d6<=0 then return a+ac*(d2/(d2-d6)) end
	local va=d3*d6-d5*d4
	if va<=0 and d4-d3>=0 and d5-d6>=0 then return b+(c-b)*((d4-d3)/((d4-d3)+(d5-d6))) end
	local sum=va+vb+vc
	if math.abs(sum)<1e-20 then return a end
	return a+ab*(vb/sum)+ac*(vc/sum)
end
function G.probes(part,origin,yaw,angle,range)
	local half=part.Size/2
	local corners={}
	for _,v in { {-1,-1,-1},{1,-1,-1},{1,1,-1},{-1,1,-1},{-1,-1,1},{1,-1,1},{1,1,1},{-1,1,1} } do
		table.insert(corners,part.CFrame:PointToWorldSpace(Vector3.new(v[1]*half.X,v[2]*half.Y,v[3]*half.Z)))
	end
	local left=G.direction(yaw,angle-Config.ConeWidth/2)
	local right=G.direction(yaw,angle+Config.ConeWidth/2)
	local normals={Vector3.new(-left.Z,0,left.X),Vector3.new(right.Z,0,-right.X)}
	local points={}
	local function add(p)
		local delta=p-origin
		if delta.Magnitude>1e-8 and delta.Magnitude<=(range or Config.MaxRange)+Config.SurfaceTolerance and G.inCone(yaw,angle,delta) then
			table.insert(points,{point=p,distance=delta.Magnitude})
		end
	end
	for _,face in {{1,2,3,4},{5,8,7,6},{1,5,6,2},{4,3,7,8},{1,4,8,5},{2,6,7,3}} do
		local poly={}; for _,i in face do table.insert(poly,corners[i]) end
		for _,n in normals do poly=clip(poly,origin,n) end
		if #poly==0 then continue end
		local center=Vector3.zero; for _,p in poly do center+=p end; center/=#poly
		add(center)
		for i,p in poly do
			-- A tiny inward inset avoids grazing a shared box edge in engine queries.
			add(p+(center-p)*1e-6)
			add((p+poly[i%#poly+1])/2)
		end
		for i=2,#poly-1 do add(closestTriangle(origin,poly[1],poly[i],poly[i+1])) end
	end
	table.sort(points,function(a,b) return a.distance<b.distance end)
	return points
end
return G
