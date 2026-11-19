-- Shared tuning for the opt-in proving-ground terrain model. No hazards or
-- path/traversability decisions: these are contact and sensor properties.
local M={TrackedBaseSpeed=0.90,MinimumSpeed=0.12}
M.Definitions=table.freeze({
 Pavement=table.freeze({speed=1,wetSpeed=.92,static=16,kinetic=12,wetGrip=.72,depthDrag=0,trackBenefit=0}),
 Dirt=table.freeze({speed=.94,wetSpeed=.74,static=10,kinetic=7,wetGrip=.7,depthDrag=.25,trackBenefit=.1}),
 Grass=table.freeze({speed=1,wetSpeed=.85,static=12,kinetic=8,wetGrip=.65,depthDrag=.1,trackBenefit=.04}),
 Snow=table.freeze({speed=.8,wetSpeed=.62,static=5,kinetic=3,wetGrip=.8,depthDrag=.5,trackBenefit=.25}),
 Ice=table.freeze({speed=.9,wetSpeed=.78,static=.04,kinetic=.025,wetGrip=.65,depthDrag=0,trackBenefit=0}),
 Mud=table.freeze({speed=.65,wetSpeed=.45,static=4,kinetic=2.5,wetGrip=.8,depthDrag=.7,trackBenefit=.35}),
})
M.Materials=table.freeze({Pavement="Asphalt",Dirt="Ground",Grass="Grass",Snow="Snow",Ice="Ice",Mud="Mud"})
M.Colors=table.freeze({Pavement={75,80,84},Dirt={143,111,76},Grass={100,130,81},Snow={224,232,237},Ice={160,206,225},Mud={91,66,42}})
function M.profile(kind,wetness,depth,consistency)
 local d=assert(M.Definitions[kind],"Unknown terrain material")
 wetness=wetness or 0;depth=depth or 0;consistency=consistency or 1
 assert(type(wetness)=="number"and wetness>=0 and wetness<=1 and type(depth)=="number"and depth>=0 and depth<=5 and type(consistency)=="number"and consistency>=0 and consistency<=1,"Invalid terrain properties")
 if kind=="Mud"then wetness=1 end -- saturated dirt, not a dry-mud variant
 local wet=d.speed+(d.wetSpeed-d.speed)*wetness
 local drag=1+d.depthDrag*depth*(1.5-consistency)
 local wheel=math.max(M.MinimumSpeed,wet/drag)
 local track=math.max(M.MinimumSpeed,wet/(1+(drag-1)*(1-d.trackBenefit)))
 local grip=(1-wetness*(1-d.wetGrip))*(if kind=="Snow"or kind=="Mud"then .7+.3*consistency else 1)
 -- Positive grip and target speed preserve powered progress on every solid
 -- material; resistance does not add an opposing permanent-stop force.
 return table.freeze({staticFriction=d.static*grip,kineticFriction=d.kinetic*grip,resistance=1+depth*d.depthDrag,
  trackedStaticFriction=d.static*grip*(1+d.trackBenefit*depth),trackedKineticFriction=d.kinetic*grip*(1+d.trackBenefit*depth),
  wheelSpeed=wheel,trackSpeed=track,surfaceType=kind,wetness=wetness,depth=depth,consistency=consistency})
end
function M.annotate(part,profile)
 part:SetAttribute("ScannerSurface",profile.surfaceType)
 part:SetAttribute("TerrainWetness",profile.wetness)
 part:SetAttribute("TerrainWetnessObservable",true)
 part:SetAttribute("TerrainDepth",profile.depth)
 part:SetAttribute("TerrainConsistency",profile.consistency)
end
return M
