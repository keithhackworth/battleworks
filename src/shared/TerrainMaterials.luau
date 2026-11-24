-- Shared tuning for the opt-in proving-ground terrain model. No hazards or
-- path/traversability decisions: these are contact and sensor properties.
local M={TrackedBaseSpeed=0.90,MinimumSpeed=0.12}
M.Definitions=table.freeze({
 Pavement=table.freeze({speed=1,wetSpeed=.92,static=16,kinetic=12,wetGrip=.72,depthDrag=0,trackBenefit=0}),
 Dirt=table.freeze({speed=.94,wetSpeed=.74,static=10,kinetic=7,wetGrip=.7,depthDrag=.25,trackBenefit=.1}),
 Grass=table.freeze({speed=1,wetSpeed=.85,static=12,kinetic=8,wetGrip=.65,depthDrag=.1,trackBenefit=.04}),
 Rock=table.freeze({speed=1,wetSpeed=.86,static=14,kinetic=10,wetGrip=.68,depthDrag=0,trackBenefit=0}),
 Sand=table.freeze({speed=.78,wetSpeed=.71,static=9,kinetic=6,wetGrip=.8,depthDrag=.3,trackBenefit=.22}),
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
local aliases={Asphalt="Pavement",Concrete="Pavement",Pavement="Pavement",Ground="Dirt",Dirt="Dirt",Grass="Grass",LeafyGrass="Grass",
 Rock="Rock",Slate="Rock",Cobblestone="Rock",Wood="Rock",WoodPlanks="Rock",Sand="Sand",Snow="Snow",Ice="Ice",Mud="Mud"}
local dryProfiles,wetProfiles={},{}
function M.fromMaterial(material,wet)
 local name=if type(material)=="string" then material else material and material.Name
 local kind=aliases[name] or "Grass"
 local profiles=if wet then wetProfiles else dryProfiles
 if not profiles[kind] then
  local loose=if kind=="Sand" or kind=="Mud" then .7 elseif kind=="Dirt" then .4 else 0
  profiles[kind]=M.profile(kind,if wet then 1 else 0,loose,1)
 end
 return profiles[kind]
end
function M.forGround(material,zone)
 return if zone=="Mud" then M.fromMaterial("Mud") else M.fromMaterial(material,zone=="Water")
end
M.TunableTraction=table.freeze({Grass=true,Mud=true,Snow=true,Ice=true})
M.TreadTractionPoints=10
function M.defaultTraction(kind)
 return M.fromMaterial(kind).staticFriction/M.Definitions.Pavement.static*100
end
local overridesCache=setmetatable({},{__mode="k"})
local defaultTractionCache={}
function M.withTraction(profile,overrides)
 if profile.assetTraction then return profile end
 if not M.TunableTraction[profile.surfaceType] then return profile end
 local percent=overrides and overrides[profile.surfaceType]
 local default=M.defaultTraction(profile.surfaceType)
 percent=percent or default
 local cache=if overrides then overridesCache[overrides] else defaultTractionCache
 if not cache then cache={};overridesCache[overrides]=cache end
 local cached=cache[profile]
 if cached and cached.percent==percent then return cached.profile end
 local tuned=table.clone(profile)
 tuned.authoredTraction=percent/100
 local tracked=math.min(100,percent+M.TreadTractionPoints)
 tuned.trackedTraction=tracked/100
 tuned.staticFriction=profile.staticFriction*percent/default
 tuned.kineticFriction=profile.kineticFriction*percent/default
 tuned.trackedStaticFriction=profile.staticFriction*tracked/default
 tuned.trackedKineticFriction=profile.kineticFriction*tracked/default
 table.freeze(tuned)
 cache[profile]={percent=percent,profile=tuned}
 return tuned
end
function M.withAssetTraction(profile,percent)
 if percent==nil then return profile end
 local tuned=table.clone(profile)
 local pavement=M.Definitions.Pavement
 local wheels=percent/100
 local tracks=math.min(100,percent+M.TreadTractionPoints)/100
 tuned.assetTraction=true
 tuned.authoredTraction=wheels;tuned.trackedTraction=tracks
 tuned.staticFriction=pavement.static*wheels;tuned.kineticFriction=pavement.kinetic*wheels
 tuned.trackedStaticFriction=pavement.static*tracks;tuned.trackedKineticFriction=pavement.kinetic*tracks
 return table.freeze(tuned)
end
return M
