-- Production layout, builder, solver, scanner and target lifecycle; raycasts use
-- analytic box intersections, not native Studio physics/rendering.
local T=require("PlaygroundTerrain")
local E=require("Environment")
local S=require("TankSimulation")
local C=require("VehicleComponents")
local Contacts=require("VehicleContacts")
local Input=require("InputCommand")
local Materials=require("TerrainMaterials")
local Surface=require("SurfacePhysics")
local Builder=require("PlaygroundBuilder")
local Scanner=require("DirectionalScanner")
local Targets=require("PracticeTargets")
local Value=require("BWValue")
local count=0
local function check(ok,m)count+=1;assert(ok,m)end
local function near(a,b,epsilon)return math.abs(a-b)<(epsilon or .001)end
local size=T.ReferenceSize
local env=E.create(size);local data=T.configure(env,size)
check(size.X==800 and size.Y==640 and data.provingGround,"expanded deterministic default Playground")
local compact=T.create(T.DefaultSize)
local areaRatio=T.DefaultSize.X*T.DefaultSize.Y/(size.X*size.Y)
check(math.abs(areaRatio-1/3)<.001 and compact.provingGround,"compact Playground keeps about one third of the reference area")
check(#compact.staticBoxes==#data.staticBoxes and #compact.strips==#data.strips and #compact.targets==#data.targets,"compact layout retains barracks, lanes and targets")
for _,zone in compact.configurationZones do
 check(zone.halfX>=12 and zone.halfZ>=12 and T.safe(compact,Vector3.new(zone.x,zone.y,zone.z),7),"compact configuration pad fits a tank on supported ground")
end
for _,region in compact.regions do
 if region.name=="Bridge" then check(region.z1-region.z0==24,"compact bridge preserves driving clearance") end
end
check(#data.targets==10 and #data.staticBoxes<50 and #data.trees>=12,"bounded scenery and intentional target placements")
check(#data.configurationZones==3,"three configuration pads use the proving-ground layout")
local Motion=require("VehicleMotion")
local west=data.configurationZones[1]
local zoneBounds=Contacts.obstacles({playground=data},size)
for _,manual in {false,true} do
 local state=S.new(Vector3.new(west.x+west.halfX+8,0,west.z),"Boomer")
 Motion.setVelocity(state,Vector3.new(-1800,0,0))
 local body=Contacts.body("zone-test",state,C.get(state).Chassis)
 body.ignoreConfigurationZones=manual
 Contacts.solve({body},zoneBounds,1/60)
 check((T.configurationZone(data,state.position)==west)==manual,
  "continuous collision blocks autonomous entry at speed and allows manual passage")
end
check(T.configurationZone(data,Vector3.new(west.x,15,west.z))==west,"protection remains within the pad footprint while airborne")
local other=T.create(size)
for i,r in data.staticBoxes do
 local b=other.staticBoxes[i];check(r.id==b.id and r.x==b.x and r.z==b.z,"layout stable across rebuilds")
end
check(not T.create(Vector2.new(230,230)).provingGround,"legacy small-layout factory stays available")
local classical=E.create(size)
check(not classical.materialTerrain and not classical.playground,"Classic unchanged unless explicitly configured")
for _,p in data.spawns do
 check(T.safe(data,p,7),"all six public spawn anchors on dry land")
 for _,r in data.staticBoxes do check(math.abs(p.X-r.x)>r.sx/2+7 or math.abs(p.Z-r.z)>r.sz/2+7,"no building spawn traps")end
 for _,t in data.trees do check(math.abs(p.X-t.x)>t.radius+7 or math.abs(p.Z-t.z)>t.radius+7,"no tree spawn traps")end
end
local field=data.openField
for _,r in data.staticBoxes do check(r.x+r.sx/2<field.x0 or r.x-r.sx/2>field.x1 or r.z+r.sz/2<field.z0 or r.z-r.sz/2>field.z1,"field central area has no building")end
for _,t in data.trees do check(t.x<field.x0 or t.x>field.x1 or t.z<field.z0 or t.z>field.z1,"field central area has no trees")end
for _,target in data.targets do check(target.x<field.x0 or target.x>field.x1 or target.z<field.z0 or target.z>field.z1,"targets remain around field/perception exercise perimeter")end
for _,n in {15,50,100}do
 local bodies={}
 for i=1,n do
  local p=Vector3.new(80+((i-1)%10)*26,0,-115+math.floor((i-1)/10)*26)
  check(p.X>field.x0+5 and p.X<field.x1-5 and p.Z>field.z0+5 and p.Z<field.z1-5 and T.safe(data,p,5),"benchmark grid on open land")
  local state=S.new(p,"Boomer");table.insert(bodies,Contacts.body(tostring(i),state,C.get(state).Chassis))
 end
 Contacts.solve(bodies,Contacts.obstacles(env,size),1/60)
 for _,b in bodies do check(near(b.state.position.Y,0),"benchmark smoke does not create population/respawn state")end
end
-- The actual native builder emits openings, not transparent whole-wall boxes.
local saveFactory=Instance.new
local made={}
Instance.new=function(class)local p=saveFactory(class);if class=="Part"then table.insert(made,p)end;return p end
local root=Instance.new("Folder");root.FindFirstChild=function()return nil end;local floor=Instance.new("Part")
Builder.build(root,data,floor)
require("EnvironmentBuilder").build(root,env,nil)
Instance.new=saveFactory
local walls,trunks,terrainParts={},{},{}
local pads,signs,stripes=0,0,0
for _,p in made do
 if p.Name=="BarracksWall"then table.insert(walls,p);check(p.Anchored and p.CanCollide and p.CanQuery,"native walls solid and queryable")end
 if p.Name=="TreeTrunk"then table.insert(trunks,p);check(p.CanCollide and p.CanQuery,"trunks block avatars and scans")end
 if p.Name=="TreeCrown"then check(not p.CanQuery and not p.CanCollide,"foliage stays cosmetic")end
 if p.Name=="ConfigurationZone" then
  pads+=1;check(p:GetAttribute("ConfigurationZoneId")~=nil and not p.CanQuery and not p.CanCollide,"zone pads are identified and cosmetic")
 elseif p.Name=="ConfigurationZoneLabel" then
  signs+=1
 elseif p.Name=="ConfigurationStripe" then
  stripes+=1;check(not p.CanQuery and not p.CanCollide,"zone paint cannot block native rays or movement")
 end
 if p:GetAttribute("TerrainWetnessObservable")then table.insert(terrainParts,p)end
end
check(pads==3 and signs==3 and stripes>pads,"each configuration zone has a striped pad and ground sign")
check(#walls==#data.staticBoxes and #trunks==#data.trees,"native and custom collision geometry share exact definitions")
local function intersection(p,origin,delta)
 local a=origin-p.CFrame.Position;local h=p.Size/2;local low,high=0,1;local normal=Vector3.new(0,1,0)
 for _,axis in {"X","Y","Z"}do
  if math.abs(delta[axis])<1e-10 then if math.abs(a[axis])>h[axis]then return nil end
  else
   local lo,hi=(-h[axis]-a[axis])/delta[axis],(h[axis]-a[axis])/delta[axis]
   local sign=-1
   if lo>hi then lo,hi=hi,lo;sign=1 end
   if lo>low then low=lo;normal=Vector3.new(if axis=="X"then sign else 0,if axis=="Y"then sign else 0,if axis=="Z"then sign else 0)end
   high=math.min(high,hi);if low>high+1e-8 then return nil end
  end
 end
 return low,normal
end
local world={}
function world:GetPartBoundsInRadius(_,_,params)return params.FilterDescendantsInstances end
function world:Raycast(origin,delta,params)
 local best,t,normal=nil,2,nil
 for _,p in params.FilterDescendantsInstances do
  if p.CanQuery~=false then local hit,n=intersection(p,origin,delta);if hit and hit<t then best,t,normal=p,hit,n end end
 end
 if best then return{Instance=best,Position=origin+delta*t,Normal=normal,Material=best.Material,Distance=delta.Magnitude*t}end
end
local enemy=Instance.new("Part");enemy.Name="VisibleTank";enemy.Size=Vector3.new(7,7,5);enemy.CFrame=CFrame.new(130,3.5,212);enemy.CanQuery=true
local parts=table.clone(walls);table.insert(parts,enemy)
local source={state=S.new(Vector3.new(130,0,170)),id="own"}
local records={[enemy]={id="enemy",state={health=100,tankType="Boomer"},playerName="Opponent"}}
local scanner=Scanner.new(world,function()return parts,records end)
local function sees(from,angle,time)
 source.state.position=from
 local obs,reason=scanner:execute(source,angle,time)
 check(obs~=nil,tostring(reason))
 for _,hit in obs.value.detections do if hit.type=="tank"then return true end end
 return false
end
check(sees(Vector3.new(130,0,170),180,1),"enemy genuinely visible through north room window")
check(not sees(Vector3.new(170,0,170),225,2),"moving behind adjacent opaque wall actually occludes enemy")
local rayParams=RaycastParams.new();rayParams.FilterDescendantsInstances=walls
check(world:Raycast(Vector3.new(130,3.6,170),Vector3.new(0,0,42),rayParams)==nil,"cannon barrel-height line passes through window")
check(world:Raycast(Vector3.new(170,3.6,170),Vector3.new(-40,0,42),rayParams)~=nil,"same weapon ray blocked by neighboring wall")
-- Real custom physics crosses both exterior doors and an interior doorway.
local drive=Input.neutral();drive.throttle=1
for _,kind in {"Boomer","Rattler"}do
 local state=S.new(Vector3.new(72,0,240),kind);state.yaw=-math.pi/2;state.turretYaw=state.yaw
 for _=1,540 do S.step(state,drive,1/60,size,env)end
 check(state.position.X>260 and near(state.position.Z,240,.2),"both drivetrains traverse full central hallway/opposing doors")
 local room=S.new(Vector3.new(130,0,245),kind)
 for _=1,180 do S.step(room,drive,1/60,size,env)end
 check(room.position.Z<220 and room.position.Z>199,"interior room entry works, exterior windowsill remains solid")
end
local tree=data.trees[1]
local blocked=S.new(Vector3.new(tree.x,0,tree.z+22),"Boomer")
for _=1,180 do S.step(blocked,drive,1/60,size,env)end
check(blocked.position.Z>=tree.z+tree.radius+4.9,"tree trunk is a real custom-physics obstacle")
local treeWorldParts=table.clone(trunks);enemy.CFrame=CFrame.new(tree.x,3.5,tree.z-15);table.insert(treeWorldParts,enemy)
local treeScanner=Scanner.new(world,function()return treeWorldParts,records end)
source.state.position=Vector3.new(tree.x,0,tree.z+20)
local forestObs=assert(treeScanner:execute(source,0,3))
local hidden=true;for _,hit in forestObs.value.detections do if hit.type=="tank"then hidden=false end end
check(hidden,"actual scanner cannot see enemy through trunk")
enemy.CFrame=CFrame.new(-316,3.5,239)
source.state.position=Vector3.new(-320,0,180)
local centerRay=RaycastParams.new();centerRay.FilterDescendantsInstances=treeWorldParts
local centerHit=world:Raycast(source.state.position+Vector3.new(0,2.5,0),enemy.CFrame.Position-source.state.position-Vector3.new(0,2.5,0),centerRay)
local peek=assert(treeScanner:execute(source,180,3.3))
local edgeVisible=false;for _,hit in peek.value.detections do if hit.type=="tank"then edgeVisible=true end end
check(centerHit and centerHit.Instance~=enemy and edgeVisible,"forest target center obscured while an actual edge remains scannable")
-- Surface layers use real scan hits, not unseen zone/map queries.
local wetPart
for _,p in terrainParts do if p:GetAttribute("ScannerSurface")=="Snow"and p:GetAttribute("TerrainWetness")==1 then wetPart=p end end
check(wetPart~=nil,"wet snow visibly represented")
local terrainScanner=Scanner.new(world,function()return{}, {},{wetPart}end)
source.state.position=Vector3.new(wetPart.CFrame.Position.X,9,-180)
local wet=assert(terrainScanner:execute(source,0,4,{coneWidth=90})).value.terrain
check(wet.samples[1].surface_type=="Snow"and wet.samples[1].wetness==1,"visible ground returns modeled surface and observable wetness: "..Value.format(wet.samples[1]))
check(wet.samples[1].material_depth==Value.Null and wet.samples[1].consistency==Value.Null,"buried thickness/compaction are unknown without a physical measurement")
-- Existing target damage timer restores full health AND original pose.
local p=Instance.new("Part");p.Position=Vector3.new(370,3.5,-110);p.CFrame=CFrame.new(p.Position);p.Size=Vector3.new(7,7,5)
local target=Targets.new(p)
for i=1,4 do Targets.impact({Instance=p},{[p]=target},10,25)end
check(target.health==0 and not p.CanQuery and p.Transparency==1 and target.resetAt==15,"authoritative four hits destroy once, schedule five seconds")
p.Position=Vector3.new(0,0,0);p.CFrame=CFrame.new(p.Position)
Targets.update(p,target,14.99,{})
check(target.health==0,"no early target respawn")
Targets.update(p,target,15,{})
check(target.health==100 and p.CanQuery and p.Position.X==370 and p.CFrame.Position.Z== -110,"five-second respawn restores original full-health pose")
-- A painted material boundary must not manufacture an edge in G5.
local plateau
for _,part in made do if part.Name=="WestPlateau"then plateau=part end end
local boundaryScanner=Scanner.new(world,function()return{}, {},{wetPart,plateau}end)
source.state.position=Vector3.new(wetPart.CFrame.Position.X,9,-143)
local boundary=assert(boundaryScanner:execute(source,180,6,{coneWidth=90})).value.terrain
check(boundary.edge_near==Value.Null,"material query skins do not create artificial ground discontinuities")
wetPart:SetAttribute("TerrainWetness","invalid")
source.state.position=Vector3.new(wetPart.CFrame.Position.X,9,-180)
check(assert(boundaryScanner:execute(source,0,7,{coneWidth=90})).value.terrain.samples[1].wetness==Value.Null,"invalid measurement data stays unknown")
-- Respawn clearance is checked at the original anchor, even after a moved prop.
Targets.damage(p,target,20,100);p.Position=Vector3.zero;p.CFrame=CFrame.new(Vector3.zero)
Targets.update(p,target,25,{{state=S.new(Vector3.new(370,0,-110))}})
check(target.health==0 and target.resetAt==25.25,"existing occupancy retry protects original respawn location")
Targets.update(p,target,25.25,{})
check(target.health==100 and p.Position.X==370,"cleared original anchor respawns without duplicate timer")
-- Real cannon windup, release pose, swept projectile and authoritative damage
-- across290 studs of the open field. No client hit or damage claim is used.
local Projectiles=require("ProjectileSimulation")
local Windup=require("WeaponWindup")
local projectileWorld={GetPartBoundsInRadius=function()return{}end}
function projectileWorld:Spherecast(origin,radius,delta)
 if not p.CanQuery then return nil end
 local expanded={CFrame=p.CFrame,Size=p.Size+Vector3.new(radius*2,radius*2,radius*2)}
 local t,normal=intersection(expanded,origin,delta)
 if t then return{Instance=p,Position=origin+delta*t,Distance=delta.Magnitude*t,Normal=normal}end
end
local shooter=S.new(Vector3.new(80,0,-110),"Boomer")
local aim=Input.neutral();aim.aimMode="World";aim.aim=p.Position
for _=1,180 do S.step(shooter,aim,1/60,size,env)end
local now=30
for _=1,4 do
 local fire=table.clone(aim);fire.fire=true
 local pending=Windup.begin(shooter,fire);check(pending~=nil,"native cannon preparation accepts ready long-range shot")
 local origin,direction
 for _=1,120 do
  S.step(shooter,aim,1/60,size,env)
  local done,o,d=Windup.step(pending,shooter,1/60)
  if done then origin,direction=o,d;break end
 end
 local shell=Projectiles.launch(projectileWorld,origin,direction,{},C.get(shooter).Weapon,0,{airborne=false,physical=true})
 local hit
 for _=1,1000 do
  now+=1/60;S.step(shooter,aim,1/60,size,env)
  hit=Projectiles.step(projectileWorld,shell,1/60)
  if hit then break end
 end
 check(hit and hit.Instance==p,"actual swept cannon projectile reaches long-range perimeter target")
 Targets.impact(hit,{[p]=target},now,C.get(shooter).Weapon.Damage)
end
check(target.health==0 and target.resetAt==now+5,"long-range destruction uses same five-second authoritative lifecycle")
local lane=S.new(Vector3.new(-270,0,140),"Rattler");lane.yaw=math.pi
for _=1,360 do S.step(lane,drive,1/60,size,env)end
check(lane.position.Z>285 and near(lane.position.X,-270,.05),"wheeled vehicle has a continuous clear route through the forest")
print("Playground proving geometry/scanner/targets passed: "..count.." assertions")
