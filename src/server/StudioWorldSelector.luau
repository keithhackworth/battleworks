-- Studio startup selection; bounded registered native-model placements.
-- No substitutes, GLB parsing, live switching or client requests.
local Placement=require(script.Parent.StudioAssetPlacement)
local WorldObjects=require(script.Parent.WorldObjects)
local WorldSettings=require(game.ReplicatedStorage.Shared.WorldSettings)
local Selector={}
local DEFAULT={id="default",name="Default Test Arena",status="ready",reason="Built-in BattleWorks arena."}
local function child(parent,name) return if parent then parent:FindFirstChild(name) else nil end
local function text(parent,name)
 local item=child(parent,name)
 return if item and item:IsA("StringValue") then item.Value else nil
end
local function typed(parent,name,class)
 local item=child(parent,name); return if item and item:IsA(class) then item.Value else nil
end
local function placement(source)
 return {id=text(source,"InstanceId"),asset=text(source,"AssetId"),source=text(source,"Source"),template=text(source,"Template"),
  position=typed(source,"Position","Vector3Value"),rotation=typed(source,"Rotation","Vector3Value"),scale=typed(source,"Scale","NumberValue"),
  interaction=if child(source,"Solid") then {solid=typed(source,"Solid","BoolValue"),destructible=typed(source,"Destructible","BoolValue"),hp=typed(source,"Health","NumberValue"),fractions=typed(source,"ColliderFractions","Vector3Value")} else nil}
end
function Selector.catalog(configuration)
 local records={table.clone(DEFAULT)}
 local folder=child(configuration,"WorldCatalog"); local seen={default=true}
 if folder then
  for _,entry in folder:GetChildren() do
   if not entry:IsA("Configuration") then continue end
   local id=text(entry,"WorldId"); local name=text(entry,"DisplayName")
   if type(id)~="string" or id=="" or seen[id] then continue end
   seen[id]=true
   local settings,settingsError
   local raw=text(entry,"BuilderSettings")
   if raw then
    local ok,value=pcall(function() return WorldSettings.validate(game:GetService("HttpService"):JSONDecode(raw)) end)
    if ok then settings=value else settingsError=tostring(value) end
   end
   local source=child(entry,"Placement")
   local multiple=child(entry,"Placements")
   local specs={}
   if multiple then
    for _,node in multiple:GetChildren() do if node:IsA("Configuration") then table.insert(specs,placement(node)) end end
    table.sort(specs,function(a,b) return tostring(a.id)<tostring(b.id) end)
   end
   table.insert(records,{id=id,name=if type(name)=="string" and name~="" then name else id,
    status=if text(entry,"Status")=="asset-dependent" and not settingsError and (source or #specs>0 or settings) then "asset-dependent" else "preview-only",
    settings=settings,reason=settingsError or text(entry,"Reason") or "No supported imported-model placement is registered.",manifest=text(entry,"ManifestPath") or "",
    placement=if source then placement(source) else nil,placements=if #specs>0 or settings then specs else nil})
  end
 end
 table.sort(records,function(a,b) if a.id=="default" then return true elseif b.id=="default" then return false else return a.id<b.id end end)
 return records
end
function Selector.resolve(requested,records,isStudio,load)
 local result={active=table.clone(DEFAULT),requested="default",status="ready",reason=""}
 if not isStudio then return result end
 requested=if type(requested)=="string" then requested:match("^%s*(.-)%s*$") else ""
 if requested=="" or requested=="default" then return result end
 result.requested=requested; result.status="fallback"
 for _,record in records do
  if record.id==requested then
   if record.status=="asset-dependent" and (record.placement or record.placements) and load then
    local model,reason=load(record.placements or record.placement,record.settings)
    if model then result.active={id=record.id,name=record.name,status="ready",profile="single-model",settings=record.settings}; result.status="ready"; return result end
    result.reason=(reason or "Imported model unavailable.").." Using Default Test Arena [default]."; return result
   end
   -- A catalog label alone cannot load arbitrary compiled scenery.
   result.reason=(record.reason or "Compiled-world loading is not implemented.").." Requested world '"..record.name.."' ["..record.id.."] is unavailable; using Default Test Arena [default]."
   return result
  end
 end
 result.reason="Unknown world ID '"..requested.."'; using Default Test Arena [default]. Regenerate the Studio catalog to register compiled manifests."
 return result
end
function Selector.start(runService,storage,arena,log,productionId)
 if not runService:IsStudio() and not productionId then return Selector.resolve(nil,{},false) end
 log=log or print
 local prefix=if productionId then "[BattleWorks World]" else "[BattleWorks Studio]"
 local configuration=child(storage,"BattleWorksStudio")
 local records=Selector.catalog(configuration)
 for _,record in records do log(string.format("%s Available world: %s [%s] - %s%s",prefix,record.name,record.id,record.status,if record.id=="default" then "" else " - "..record.reason)) end
 local objects=WorldObjects.new()
 local selected=child(configuration,"SelectedWorld")
 local result=Selector.resolve(productionId or text(configuration,"SelectedWorld"),records,true,function(spec,settings)
  local candidate=WorldObjects.new()
  local specs=if spec.id then {spec} else spec
  local models,reason=Placement.placeMany(child(storage,"BattleWorksAssets"),specs,arena,function(model,p)
   if p.interaction then candidate:add(model,p) end
   if settings then WorldSettings.checkSpawns(settings,candidate:obstacles()) end
  end,child(storage,"BattleWorksBuiltinAssets"))
  if models then objects=candidate end
  return models,reason
 end)
 result.objects=objects
 if not productionId and selected and not selected:IsA("StringValue") then
  result.status="fallback"; result.reason="SelectedWorld must be a StringValue; using Default Test Arena [default]."
 end
 arena:SetAttribute("WorldId",result.active.id); arena:SetAttribute("WorldName",result.active.name)
 arena:SetAttribute("RequestedWorldId",result.requested); arena:SetAttribute("WorldSelectionStatus",result.status); arena:SetAttribute("WorldSelectionReason",result.reason)
 if result.reason~="" then log(prefix.." "..result.reason) end
 log(string.format("%s Active world: %s [%s]. %s",prefix,result.active.name,result.active.id,if productionId then "Published repository world selected at server startup." else "Selection is read once at startup; select a world in the World Builder before the next Play session."))
 return result
end
return Selector
