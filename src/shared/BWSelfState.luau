-- Own-entity introspection only. Whitelisted BW values; no live tables, Instances,
-- world queries or references to any opponent are exposed to a program.
local Value=require(script.Parent.BWValue)
local Components=require(script.Parent.VehicleComponents)
local Hardware=require(script.Parent.BWChassis)
local Adapter=require(script.Parent.BWTankAdapter)
local Simulation=require(script.Parent.TankSimulation)
local Aim=require(script.Parent.TurretAim)
local Timing=require(script.Parent.WeaponTiming)
local Read={Names={get_weapon_speed=true,get_current_coordinates=true,get_weapon_type=true,is_weapon_ready=true,get_turret_direction=true,get_tank_direction=true,get_drivetrain_type=true,get_bus_configuration=true,get_tank_state=true}}
-- Static value shapes for the existing const/alias analyzer. `true` means a
-- scalar (including null), `*` describes collection entries. Never live state.
local function shape(keys,children)
 local result=children or {}
 for key in keys:gmatch("%S+")do result[key]=true end
 return result
end
local positionShape=shape("x y z")
local turretShape=shape("world_direction mount_yaw mount_pitch world_pitch max_rotation_speed effective_rotation_speed min_pitch max_pitch",{pivot=positionShape,muzzle_position=positionShape,direction=positionShape})
local readinessShape=shape("ready state remaining_seconds operation heat max_heat burst_seconds max_burst_seconds overheat_seconds fire_interval_seconds effective_fire_interval_seconds preparation_seconds effective_preparation_seconds")
local busShape=shape("tier bus_count",{buses={["*"]=shape("index allocated available")},devices={["*"]=shape("bus allocation performance")},
 allocations=shape("drivetrain turret weapon scanners"),tuning=shape("scanners weapon")})
local motionShape=shape("speed forward_speed vertical_speed max_speed max_reverse_speed effective_max_speed effective_reverse_speed drivetrain_type drivetrain_id mobility_id steering_mode steering_angle max_steering_angle wheelbase wheel_count turning_radius min_turning_radius can_pivot can_reverse immobilized airborne terrain_speed_scale ground_max_speed")
local sensorShape=shape("device id mounting_degrees reference world_direction cone_degrees effective_cone_degrees catalog_range max_range distance_percent configured_range effective_range performance enabled acquisition_seconds cooldown_seconds origin_height ground_observations ground_operational")
local snapshotShape=shape("scanner_count",{coordinates=positionShape,chassis=shape("world_direction turn_rate max_turn_rate effective_max_turn_rate"),turret=turretShape,motion=motionShape,
 weapon=shape("id kind projectile_speed projectile_model range",{readiness=readinessShape,ammo=shape("mode remaining capacity")}),
 health=shape("current max damage"),equipment={["*"]=true},bus=busShape,scanners={["*"]=sensorShape},simulation=shape("time tick step_seconds")})
local function resultShape(fields)
 local copy={status=true,reason=true};for k,v in fields do copy[k]=v end;return copy
end
Read.Shapes={get_weapon_speed=resultShape(shape("kind speed units")),get_current_coordinates=resultShape(positionShape),
 get_weapon_type=resultShape(shape("weapon_type")),is_weapon_ready=resultShape(readinessShape),get_turret_direction=resultShape(turretShape),
 get_tank_direction=resultShape(shape("world_direction")),get_drivetrain_type=resultShape(shape("drivetrain_type drivetrain_id mobility_id")),
 get_bus_configuration=resultShape(busShape),get_tank_state=resultShape(snapshotShape)}
local function dict(fields)return Value.dictionary(fields,true)end
Read.Shapes.Scanner=resultShape(shape("sensor timestamp range cone_degrees count type distance relative_direction world_direction player relation object_id name",{
 point=positionShape,detections={["*"]=shape("type distance relative_direction world_direction player relation object_id name",{point=positionShape})},
 terrain=shape("supported operational status reference_elevation footprint_width count continuity distance_to_edge edge_near edge_far drop_depth max_distance max_drop max_rise",{
  samples={["*"]=shape("lane lateral_offset horizontal_distance forward_distance confidence ground_detected elevation relative_elevation_change elevation_rate slope_angle interval_elevation_rate surface_type transition drop_depth reference_support wetness material_depth consistency",{point=positionShape})}})}))
local function nullable(n)return if n==nil then Value.Null else n end
local function performance(ctx,name)
 return Hardware.effective(ctx.hardware,name,ctx.components)
end
local function coordinates(ctx)local p=ctx.state.position;return {x=p.X,y=p.Y,z=p.Z}end
local function velocity(ctx)
 local s=ctx.state
 local v=s.linearVelocity or Vector3.new(s.velocityX or -math.sin(s.yaw)*(s.speed or 0),s.verticalSpeed or 0,s.velocityZ or -math.cos(s.yaw)*(s.speed or 0))
 return v,-math.sin(s.yaw)*v.X-math.cos(s.yaw)*v.Z
end
local function turret(ctx)
 local s,c=ctx.state,ctx.components
 local origin,direction=Simulation.shotPose(s)
 local function vector(v)return dict({x=v.X,y=v.Y,z=v.Z})end
 local flat=math.sqrt(direction.X^2+direction.Z^2)
 local yaw,pitch=Simulation.turretAngles(s)
 return {pivot=vector(Aim.pivot(s)),muzzle_position=vector(origin+direction*c.Weapon.MuzzleOffset),direction=vector(direction),world_direction=if flat<1e-7 then Value.Null else Adapter.heading(math.atan2(-direction.X,-direction.Z)),
  mount_yaw=Adapter.heading(yaw-s.yaw),mount_pitch=math.deg(pitch),world_pitch=math.deg(math.atan2(direction.Y,flat)),
  max_rotation_speed=math.deg(c.Turret.TraverseSpeed),effective_rotation_speed=math.deg(c.Turret.TraverseSpeed)*performance(ctx,"turret"),
  min_pitch=math.deg(c.Turret.MinPitch),max_pitch=math.deg(c.Turret.MaxPitch)}
end
local function readiness(ctx)
 local s,c,tank=ctx.state,ctx.components,ctx.tank
 local state,remaining="ready",0
 if s.health<=0 then state="destroyed"
 elseif not ctx.hardware.devices.weapon then state="unavailable"
 elseif performance(ctx,"weapon")<=0 then state="disabled"
 elseif tank and tank.requireFireRelease then state="release_required"
 elseif tank and tank.pendingShot then state="preparing";remaining=tank.pendingShot.remaining
 elseif c.Weapon.Operation=="Heat"then
  local heat=tank and tank.rattler
  if not heat then
   if (s.weaponCooldown or 0)>0 then state="overheated";remaining=s.weaponCooldown
   else state="unknown";remaining=Value.Null end
  elseif heat.cooldown>0 or heat.heat>=c.Weapon.MaxHeat or heat.burst>=c.Weapon.MaxBurst then state="overheated";remaining=heat.cooldown
  elseif heat.shotClock>1e-6 then state="cooldown";remaining=heat.shotClock end
 elseif (s.cooldown or 0)>0 then state="cooldown";remaining=s.cooldown end
 local w=c.Weapon;local p,windup=Hardware.weaponStats(ctx.hardware,c);local heat=tank and tank.rattler
 return {ready=if state=="unknown"then Value.Null else state=="ready",state=state,remaining_seconds=remaining,
  operation=w.Operation,heat=if w.Operation=="Heat"and heat then heat.heat else Value.Null,
  max_heat=nullable(w.MaxHeat),burst_seconds=if w.Operation=="Heat"and heat then heat.burst else Value.Null,
  max_burst_seconds=nullable(w.MaxBurst),overheat_seconds=if w.Operation=="Heat"and heat then heat.cooldown else Value.Null,
  fire_interval_seconds=w.Cooldown,effective_fire_interval_seconds=nullable(Timing.interval(w,p)),
  preparation_seconds=nullable(w.FireWindup),effective_preparation_seconds=nullable(Timing.preparation(w,windup))}
end
local function buses(ctx)
 local hardware=ctx.hardware;local devices,sums={},{}
 for name,d in hardware.devices do
  devices[name]=dict({bus=d.bus,allocation=d.allocation,performance=performance(ctx,name)})
  sums[d.bus]=(sums[d.bus]or 0)+d.allocation
 end
 local buses={}
 local count=if hardware.allocations then 1 else Hardware.Tiers[hardware.tier].threads
 for i=1,count do table.insert(buses,dict({index=i,allocated=sums[i]or 0,available=100-(sums[i]or 0)}))end
 return {tier=hardware.tier,bus_count=#buses,buses=Value.array(buses),devices=dict(devices),
  allocations=if hardware.allocations then dict(table.clone(hardware.allocations)) else Value.Null,
  tuning=if hardware.tuning then dict(table.clone(hardware.tuning)) else Value.Null}
end
local function scanners(ctx)
 local result={};local c,s=ctx.components,ctx.state
 for _,angle in Hardware.Angles do
  local sensor=c.Sensors[angle]
  if sensor then
   local name="sensor"..angle;local d=ctx.hardware.devices[name]or {};local p=performance(ctx,name)
   local range=d.range or sensor.Range;local percent=d.distancePercent or sensor.DistancePercent
   table.insert(result,dict({device=name,id=c.Installed[name],ground_observations=sensor.GroundObservations==true,ground_operational=sensor.GroundObservations==true and p>0 and range*percent>0,mounting_degrees=angle,reference="chassis",world_direction=(Adapter.heading(s.yaw)+angle)%360,
    cone_degrees=d.coneWidth or sensor.ConeWidth,catalog_range=sensor.Range,max_range=range,distance_percent=percent,
    effective_cone_degrees=if p>0 then d.coneWidth or sensor.ConeWidth else 0,
    configured_range=range*percent/100,effective_range=if p>0 then range*percent/100 else 0,performance=p,enabled=p>0,
    acquisition_seconds=if p>0 then (d.acquisition or sensor.Acquisition)/p else Value.Null,
    cooldown_seconds=d.cooldown or sensor.Cooldown,origin_height=d.originHeight or sensor.OriginHeight}))
  end
 end
 return Value.array(result)
end
local function motion(ctx)
 local s,c=ctx.state,ctx.components;local m=c.Mobility;local v,forward=velocity(ctx)
 local p=performance(ctx,"drivetrain");local steering=if c.Capabilities.Steer then s.steeringAngle or 0 else 0
 local radius,minRadius=Value.Null,Value.Null
 local speed=math.sqrt(v.X^2+v.Z^2)
 local omega=s.angularVelocity and s.angularVelocity.Y or 0
 if m.Kind=="Wheeled"and c.Capabilities.Steer then
  minRadius=m.Wheelbase/math.tan(m.MaxSteer)
  if math.abs(steering)>1e-7 and math.abs(forward)>1e-7 then radius=math.max(m.Wheelbase/math.abs(math.tan(steering)),math.abs(forward)/m.MaxYawRate)end
 elseif c.Capabilities.Pivot then
  minRadius=0
  if speed<1e-7 and math.abs(omega)>1e-7 then radius=0 end
 end
 return {terrain_speed_scale=nullable(s.terrainSpeedScale),ground_max_speed=if s.terrainSpeedScale then c.Drivetrain.Speed*p*s.terrainSpeedScale else Value.Null,speed=speed,forward_speed=forward,vertical_speed=v.Y,max_speed=c.Drivetrain.Speed,max_reverse_speed=c.Drivetrain.ReverseSpeed,
  effective_max_speed=c.Drivetrain.Speed*p,effective_reverse_speed=c.Drivetrain.ReverseSpeed*p,
  drivetrain_type=m.Kind,drivetrain_id=c.Installed.Drivetrain,mobility_id=c.Installed.Mobility,
  steering_mode=if not c.Capabilities.Steer then "none"elseif m.Kind=="Wheeled"then "front_wheel"else "differential",
  steering_angle=if m.Kind=="Wheeled"and c.Capabilities.Steer then math.deg(steering)else Value.Null,
  max_steering_angle=if m.Kind=="Wheeled"and c.Capabilities.Steer then math.deg(m.MaxSteer)else Value.Null,
  wheelbase=nullable(m.Wheelbase),wheel_count=Value.Null,turning_radius=radius,min_turning_radius=minRadius,
  can_pivot=c.Capabilities.Pivot,can_reverse=c.Drivetrain.ReverseSpeed>0,immobilized=s.immobilized==true,
  airborne=(s.lift or 0)>1e-6 or v.Y>1e-6}
end
local function chassis(ctx)
 local s=ctx.state
 local _,_,effective,maxRate=Hardware.driveRates(ctx.components,performance(ctx,"drivetrain"))
 return {world_direction=Adapter.heading(s.yaw),turn_rate=-math.deg(s.angularVelocity and s.angularVelocity.Y or 0),max_turn_rate=math.deg(maxRate),effective_max_turn_rate=math.deg(effective)}
end
function Read.read(name,state,config,time,services)
 assert(Read.Names[name],"Unknown own-state query")
 local tank,timestamp,tick,step
 if services and services.getOwnTank then
  tank,timestamp,tick,step=services.getOwnTank()
  if not tank or tank.state~=state then return Value.result("stateUnavailable")end
 end
 if not state or not state.position then return Value.result("stateUnavailable")end
 local ctx={state=state,tank=tank,components=Components.get(state),hardware=if tank then tank.hardware else config}
 if not ctx.hardware then ctx.hardware=Hardware.forTank(state)end
 local c=ctx.components
 if name=="get_current_coordinates"then return Value.result(nil,coordinates(ctx))end
 local _,_,shotSpeed=Hardware.weaponStats(ctx.hardware,c)
 if name=="get_weapon_speed"then return Value.result(nil,{kind="projectile",speed=shotSpeed,units="studs/second"})end
 if name=="get_weapon_type"then return Value.result(nil,{weapon_type=c.Installed.Weapon})end
 if name=="get_tank_direction"then return Value.result(nil,{world_direction=Adapter.heading(state.yaw)})end
 if name=="get_turret_direction"then return Value.result(nil,turret(ctx))end
 if name=="get_drivetrain_type"then return Value.result(nil,{drivetrain_type=c.Mobility.Kind,drivetrain_id=c.Installed.Drivetrain,mobility_id=c.Installed.Mobility})end
 if name=="is_weapon_ready"then return Value.result(nil,readiness(ctx))end
 if name=="get_bus_configuration"then return Value.result(nil,buses(ctx))end
 local equipment={};for slot,id in c.Installed do equipment[slot]=id end
 local sensors=scanners(ctx)
 return Value.result(nil,{coordinates=dict(coordinates(ctx)),chassis=dict(chassis(ctx)),turret=dict(turret(ctx)),motion=dict(motion(ctx)),
  weapon=dict({id=c.Installed.Weapon,kind=c.Weapon.WeaponType,projectile_speed=shotSpeed,projectile_model="projectile",range=c.Weapon.Range,
   readiness=dict(readiness(ctx)),ammo=dict({mode="unlimited",remaining=Value.Null,capacity=Value.Null})}),
  health=dict({current=state.health,max=c.Chassis.Health,damage=c.Chassis.Health-state.health}),equipment=dict(equipment),bus=dict(buses(ctx)),scanners=sensors,scanner_count=#sensors,
  simulation=dict({time=timestamp or time or 0,tick=nullable(tick),step_seconds=nullable(step)})})
end
-- Reuse the production evaluator through the serial compatibility entry only
-- when a program contains these new value calls. Historical serial programs
-- retain their existing timing and behavior.
function Read.used(tree)
 local seen={}
 local function visit(node)
  if type(node)~="table"or seen[node]then return false end
  seen[node]=true
  if node.op=="aim_at"or(node.kind=="call"and(Read.Names[node.name]or node.name=="aim_at"))then return true end
  for _,value in node do if type(value)=="table"and visit(value)then return true end end
  return false
 end
 return visit(tree)
end
return Read
