-- Trust boundary for player-authored v2 documents. Uses the existing schema,
-- native catalog, placement loader and interaction system; accepts no code.
local Shared=game.ReplicatedStorage.Shared
local Document=require(Shared.WorldEditorDocument)
local Settings=require(Shared.WorldSettings)
local Paths=require(Shared.AssetPaths)
local Placement=require(Shared.ModelPlacement)
local Visual=require(Shared.AssetGeometry)
local Fit=require(script.Parent.MeshCollisionFit)
local Adapter={}
local function keys(value,allowed)
 assert(type(value)=="table","Expected a world record")
 for key in value do assert(allowed[key],"Unsupported world property: "..tostring(key)) end
end
local function array(value,limit)
 assert(type(value)=="table" and #value<=limit,"World array exceeds its limit")
 for k in value do assert(type(k)=="number" and k%1==0 and k>=1 and k<=#value,"Invalid world array") end
end
function Adapter.validate(raw,items,assets)
 keys(raw,{schemaVersion=true,id=true,name=true,description=true,settings=true,objects=true,spawns=true,gameplay=true})
 assert(raw.schemaVersion==2,"Expected authoring schema v2")
 assert(type(raw.description)=="string" and #raw.description<=1000,"Description exceeds 1000 characters")
 keys(raw.settings,{width=true,depth=true,ground=true,boundary=true,terrain=true})
 keys(raw.settings.ground,{material=true,color=true});array(raw.settings.ground.color,3)
 array(raw.objects,512);array(raw.spawns,5);keys(raw.gameplay,{})
 local settings={width=raw.settings.width,depth=raw.settings.depth,ground=raw.settings.ground,boundary=raw.settings.boundary,terrain=raw.settings.terrain,spawns=raw.spawns,zones={}}
 local ids={}
 for _,spawn in raw.spawns do
  keys(spawn,{id=true,tank=true,slot=true,position=true,heading=true});array(spawn.position,3)
  assert(type(spawn.id)=="string" and spawn.id:match("^[a-zA-Z][a-zA-Z0-9_-]*$") and #spawn.id<=64 and not ids[spawn.id],"Invalid spawn ID")
  ids[spawn.id]=true
 end
 Settings.validate(settings,true)
 local catalog=Document.catalog(items)
 local specs={}
 for _,object in raw.objects do
  keys(object,{id=true,type=true,asset=true,position=true,rotation=true,scale=true,stretch=true,solid=true,destructible=true,hp=true,bounds=true})
  array(object.position,3);array(object.rotation,3)
  local item=catalog.byPath[object.asset]
  assert(item and item.id==object.type and item.available,"Asset is not available in this experience")
  local model=assert(Paths.resolve(assets,item.model),"Native asset unavailable")
  local _,size=Visual.measure(model)
  -- Never trust client-supplied dimensions for spawn/boundary validation.
  object.bounds={size.X,size.Y,size.Z}
  if object.stretch then
   array(object.stretch,3)
   item.stretchable=Placement.stretchPart(model)~=nil and not item.zone
   item.resizeAxes=Placement.resizeAxes(model,item.resizeAxes)
  end
  if item.collider and item.collider.fit=="mesh" then item.collider.boxes=Fit.profile(model) end
  if item.collider then Visual.checkFaceProfile(size,item.collider)end
  Document.checkEntry(raw,catalog,object)
  if object.stretch and item.resizeAxes then Placement.checkResizeSize(model,object.scale,object.stretch) end
  local spec={id=object.id,asset=item.model,source=item.source,template=item.model,
   position=Vector3.new(table.unpack(object.position)),rotation=Vector3.new(table.unpack(object.rotation)),scale=object.scale,stretch=object.stretch,resizeAxes=item.resizeAxes}
  if item.collider then
   local c=item.collider
   spec.interaction={solid=object.solid,destructible=object.destructible,hp=object.hp,fractions=Vector3.new(c.widthFraction,c.heightFraction,c.depthFraction),fit=c.fit,boxes=c.boxes,faces=c.faces,bases=c.bases,walls=c.walls,sourceSize=c.sourceSize}
  end
  table.insert(specs,spec)
  if item.zone then table.insert(settings.zones,{kind=item.zone,x=object.position[1],z=object.position[3],rx=size.X*object.scale/2,rz=size.Z*object.scale/2,speed=if item.zone=="Water" then .9 else .75}) end
 end
 Settings.validate(settings,true)
 return Document.export(raw,catalog),specs,settings
end
return Adapter
