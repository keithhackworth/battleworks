-- Bounded physical observations only. No driving decisions, maps or enemy data.
local Shared=game.ReplicatedStorage.Shared
local Values=require(Shared.BWValue)
local Geometry=require(Shared.ScannerGeometry)
local Config=require(Shared.ScannerConfig)
local Terrain={}
local function dict(value)return Values.dictionary(value,true)end
local function scalar(value)return if value==nil then Values.Null else value end
local function measurement(part,name,maximum)
 if part:GetAttribute(name.."Observable")~=true then return Values.Null end
 local value=part:GetAttribute(name)
 return if type(value)=="number"and value==value and value>=0 and value<=maximum then value else Values.Null
end
local function point(v)return dict({x=v.X,y=v.Y,z=v.Z})end
local function material(hit)
 if hit.Material==Enum.Material.Water then return "Water"end
 local tag=hit.Instance and hit.Instance:GetAttribute("ScannerSurface")
 if tag=="Water"then return "Water"end
 if require(Shared.TerrainMaterials).Definitions[tag]then return tag end
 local value=hit.Material or(hit.Instance and hit.Instance.Material)
 return if value and value.Name then value.Name else "unknown"
end
function Terrain.observe(world,parts,records,state,angle,range,cone,origin,sensor,budget)
 local enabled=sensor.GroundObservations==true
 local chassis=require(Shared.VehicleComponents).get(state).Chassis
 local radians=math.rad(angle)
 local width=math.abs(math.cos(radians))*chassis.ContactWidth+math.abs(math.sin(radians))*chassis.ContactLength
 local result={supported=enabled,operational=enabled and range>0,status=if enabled then "unknown"else "unsupported",reference_elevation=state.position.Y,
  footprint_width=width,count=0,samples=Values.array({}),continuity="unknown",distance_to_edge=Values.Null,edge_near=Values.Null,edge_far=Values.Null,drop_depth=Values.Null,
  max_distance=0,max_drop=Config.TerrainDrop,max_rise=Config.TerrainRise}
 if not enabled or not parts then return dict(result),0 end
 local params=RaycastParams.new();params.FilterType=Enum.RaycastFilterType.Include;params.FilterDescendantsInstances=parts
 params.RespectCanCollide=false;params.IgnoreWater=false
 local used=0;local exhausted=false
 local function cast(from,delta)
  if used>=math.min(budget,Config.TerrainMaxRaycasts)then exhausted=true;return nil end
  used+=1;return world:Raycast(from,delta,params)
 end
 local direction=Geometry.direction(state.yaw,angle)
 local side=Vector3.new(-direction.Z,0,direction.X)
 local samples={};local discontinuity=false;local anyObserved=false
 for lane,offset in {-width/2,0,width/2}do
  local previous
  for _,distance in Config.TerrainDistances do
   if distance>range then break end
   local flat=direction*distance+side*offset
   if not Geometry.inCone(state.yaw,angle,flat,cone)or flat.Magnitude>range then continue end
   local sample={lane=lane-1,lateral_offset=offset,horizontal_distance=flat.Magnitude,forward_distance=distance,
    confidence="unknown",ground_detected=Values.Null,point=Values.Null,elevation=Values.Null,relative_elevation_change=Values.Null,
    elevation_rate=Values.Null,slope_angle=Values.Null,interval_elevation_rate=Values.Null,surface_type="unknown",transition="unknown",drop_depth=Values.Null,reference_support=Values.Null,wetness=Values.Null,material_depth=Values.Null,consistency=Values.Null}
   local column=origin+flat
   local vertical=math.sqrt(math.max(0,range*range-flat.Magnitude^2))
   local rise,drop=math.min(Config.TerrainRise,vertical),math.min(Config.TerrainDrop,vertical)
   local hit=if rise+drop>1e-6 then cast(column+Vector3.new(0,rise,0),Vector3.new(0,-rise-drop,0))else nil
   local candidate=hit and hit.Position
   local visible=false
   if candidate and not records[hit.Instance]and(candidate-origin).Magnitude<=range and Geometry.inCone(state.yaw,angle,candidate-origin,cone)then
    local delta=candidate-origin
    local sight=cast(origin,delta.Unit*math.min(range,delta.Magnitude+Config.SurfaceTolerance))
    visible=sight~=nil and sight.Instance==hit.Instance and not records[sight.Instance]and(sight.Position-candidate).Magnitude<=Config.SurfaceTolerance
   end
   if visible and not exhausted then
    sample.confidence="observed";anyObserved=true
    sample.surface_type=material(hit)
    -- Only exposed surface-layer metadata is observable. No zone/map lookup.
    sample.wetness=measurement(hit.Instance,"TerrainWetness",1)
    sample.material_depth=measurement(hit.Instance,"TerrainDepth",5)
    sample.consistency=measurement(hit.Instance,"TerrainConsistency",1)
    sample.ground_detected=sample.surface_type~="Water"and hit.Instance:GetAttribute("ScannerGroundSupport")~=false
    sample.point=point(candidate);sample.elevation=candidate.Y;sample.relative_elevation_change=candidate.Y-state.position.Y
    local normal=hit.Normal
    if normal and normal.Y>.05 and sample.ground_detected then
     local rate=-(normal.X*direction.X+normal.Z*direction.Z)/normal.Y
     sample.elevation_rate=rate;sample.slope_angle=math.deg(math.atan(rate))
    end
    sample.reference_support=sample.ground_detected
    sample.transition="first"
    if previous then
     local gap=sample.forward_distance-previous.forward_distance
     local rise=sample.elevation-previous.elevation
     local predicted=if previous.elevation_rate~=Values.Null then previous.elevation_rate*gap else 0
     local differentSlope=sample.elevation_rate~=Values.Null and previous.elevation_rate~=Values.Null and math.abs(sample.elevation_rate-previous.elevation_rate)>.005
     if (math.abs(rise-predicted)>Config.SurfaceTolerance and not differentSlope)or sample.ground_detected~=previous.ground_detected then
      sample.transition="discontinuity";discontinuity=true
      if rise<0 then sample.drop_depth=-rise end
      if rise< -Config.SurfaceTolerance or not sample.ground_detected then
       if result.edge_far==Values.Null or distance<result.edge_far then result.edge_near=previous.forward_distance;result.edge_far=distance;result.drop_depth=sample.drop_depth end
      end
     elseif differentSlope then
      sample.transition="slope_change";discontinuity=true
     elseif sample.elevation_rate~=Values.Null and previous.elevation_rate~=Values.Null then sample.transition="sampled";sample.interval_elevation_rate=rise/gap
     else sample.transition="unknown_interval"end
    end
    previous=sample
   elseif previous and not exhausted then
    -- Is the previously observed support plane visibly absent here? A clear
    -- sight ray is evidence at that elevation, not proof about hidden depths.
    local rate=if previous.elevation_rate==Values.Null then 0 else previous.elevation_rate
    local expected=previous.elevation+rate*(distance-previous.forward_distance)
    local probe=Vector3.new(column.X,expected-.05,column.Z)
    if (probe-origin).Magnitude<=range then
     local sight=cast(origin,probe-origin)
     if not sight and not exhausted then
      sample.reference_support=false;sample.confidence="observed";sample.transition="missing_reference_support";anyObserved=true;discontinuity=true
      if result.edge_far==Values.Null or distance<result.edge_far then result.edge_near=previous.forward_distance;result.edge_far=distance end
     end
    end
    previous=nil
   end
   result.max_distance=math.max(result.max_distance,distance)
   table.insert(samples,dict(sample))
  end
 end
 result.samples=Values.array(samples);result.count=#samples
 result.status=if exhausted then "partial_budget"elseif anyObserved then "observed"else "unknown"
 result.continuity=if discontinuity then "discontinuity"elseif anyObserved then "sampled"else "unknown"
 -- edge bounds, not a falsely precise edge or a traversability classification.
 result.distance_to_edge=result.edge_near
 return dict(result),used
end
return Terrain
