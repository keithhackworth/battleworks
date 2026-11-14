-- Shared authoring-v2 validation. Server validation supplies trusted native bounds.
local State=require(script.Parent.WorldEditorState)
local Paths=require(script.Parent.AssetPaths)
local Geometry=require(script.Parent.WorldObjectGeometry)
local Document={}
function Document.fresh()
 return {schemaVersion=2,id="ingame_world",name="My BattleWorks World",description="",settings={width=230,depth=230,ground={material="Grass",color={100,112,86}},boundary=true},objects={},spawns={{id="boomer_spawn",tank="Boomer",position={-22,0,34.5},heading=90},{id="rattler_spawn",tank="Rattler",position={22,0,34.5},heading=270}},gameplay={}}
end
local function finite(n,min,max) return type(n)=="number" and n==n and n>=min and n<=max end
function Document.catalog(items)
 local byType,byPath={},{}
 for _,item in items do byType[item.id]=item;byPath[item.model]=item end
 return {items=items,byType=byType,byPath=byPath}
end
function Document.checkEntry(doc,catalog,o)
 local item=catalog.byPath[o.asset]
 assert(item and item.id==o.type and Paths.valid(o.asset),"Asset identity is missing or conflicting")
 assert(type(o.id)=="string" and o.id:match("^[a-zA-Z][a-zA-Z0-9_-]*$") and #o.id<=64,"Invalid instance ID")
 assert(type(o.solid)=="boolean" and type(o.destructible)=="boolean","Collision and destructibility must be boolean")
 assert(finite(o.hp,1,100000),"HP must be in [1,100000]")
 assert(not (o.solid or o.destructible) or item.collider,"This asset has no registered collider")
 assert(finite(o.scale,.001,1000),"Uniform scale must be in [.001,1000]")
 assert(type(o.position)=="table" and #o.position==3,"Position requires X, Y and Z")
 assert(type(o.rotation)=="table" and #o.rotation==3,"Rotation requires pitch, yaw and roll")
 for _,n in o.rotation do assert(finite(n,-360000,360000),"Invalid rotation") end
 for _,n in o.position do assert(finite(n,-2000,2000),"Invalid position") end
 assert(type(o.bounds)=="table" and #o.bounds==3,"Native bounds are required")
 for _,n in o.bounds do assert(finite(n,.001,10000),"Invalid native bounds") end
 assert(not item.zone or (o.position[2]==0 and o.rotation[1]%360==0 and o.rotation[3]%360==0),"Water/mud regions must stay level at ground height")
 local box=Geometry.from(o.position,o.rotation,o.bounds,o.scale)
 local extents=Geometry.extents(box)
 assert(box.position.Y+extents.Y<=2000 and box.position.Y-extents.Y>=-2000,"Object height exceeds [-2000,2000]")
 assert(math.abs(box.position.X)+extents.X<=doc.settings.width/2+.001 and math.abs(box.position.Z)+extents.Z<=doc.settings.depth/2+.001,"Object footprint crosses the world boundary")
 if o.solid then
  local f=item.collider
  local collider=Geometry.from(o.position,o.rotation,o.bounds,o.scale,{f.widthFraction,f.heightFraction,f.depthFraction})
  for _,spawn in doc.spawns do
   assert(not Geometry.spawnBlocked(collider,math.rad(o.rotation[2]),spawn.position),"Solid object overlaps a reserved tank spawn")
  end
 end
 return true
end
function Document.export(doc,catalog)
 assert(doc.schemaVersion==2 and #doc.objects<=512,"Invalid authoring document")
 assert(doc.id:match("^[a-zA-Z][a-zA-Z0-9_-]*$") and doc.id~="default" and #doc.id<=64,"Invalid world ID")
 assert(type(doc.name)=="string" and #doc.name>0 and #doc.name<=100,"World name must contain 1–100 characters")
 local ids={}
 for _,spawn in doc.spawns do ids[spawn.id]=true end
 for _,o in doc.objects do assert(not ids[o.id],"Duplicate object ID");ids[o.id]=true;Document.checkEntry(doc,catalog,o) end
 return State.copy(doc)
end
function Document.tree(catalog,prefix,query)
 prefix=prefix or "";query=(query or ""):lower()
 local folders,assets={},{}
 for _,item in catalog.items do
  if query~="" then
   if (item.model.." "..item.name):lower():find(query,1,true) then table.insert(assets,item) end
  elseif item.model:sub(1,#prefix)==prefix then
   local rest=item.model:sub(#prefix+1);local folder=rest:match("^([^/]+)/")
   if folder then folders[folder]=true else table.insert(assets,item) end
  end
 end
 local directories={};for name in folders do table.insert(directories,name) end;table.sort(directories)
 table.sort(assets,function(a,b) return a.model<b.model end)
 return directories,assets
end
return Document
