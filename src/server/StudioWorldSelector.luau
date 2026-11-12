-- Studio startup selection; only a single registered imported model is supported.
-- No substitutes, GLB parsing, live switching or client requests.
local Placement=require(script.Parent.StudioAssetPlacement)
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
function Selector.catalog(configuration)
 local records={table.clone(DEFAULT)}
 local folder=child(configuration,"WorldCatalog"); local seen={default=true}
 if folder then
  for _,entry in folder:GetChildren() do
   if not entry:IsA("Configuration") then continue end
   local id=text(entry,"WorldId"); local name=text(entry,"DisplayName")
   if type(id)~="string" or id=="" or seen[id] then continue end
   seen[id]=true
   local source=child(entry,"Placement")
   table.insert(records,{id=id,name=if type(name)=="string" and name~="" then name else id,
    status=if text(entry,"Status")=="asset-dependent" and source then "asset-dependent" else "preview-only",
    reason=text(entry,"Reason") or "No supported imported-model placement is registered.",manifest=text(entry,"ManifestPath") or "",
    placement=if source then {id=text(source,"InstanceId"),asset=text(source,"AssetId"),source=text(source,"Source"),template=text(source,"Template"),
     position=typed(source,"Position","Vector3Value"),rotation=typed(source,"Rotation","Vector3Value"),scale=typed(source,"Scale","NumberValue")} else nil})
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
   if record.status=="asset-dependent" and record.placement and load then
    local model,reason=load(record.placement)
    if model then result.active={id=record.id,name=record.name,status="ready",profile="single-model"}; result.status="ready"; return result end
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
function Selector.start(runService,storage,arena,log)
 if not runService:IsStudio() then return Selector.resolve(nil,{},false) end
 log=log or print
 local configuration=child(storage,"BattleWorksStudio")
 local records=Selector.catalog(configuration)
 for _,record in records do log(string.format("[BattleWorks Studio] Available world: %s [%s] - %s%s",record.name,record.id,record.status,if record.id=="default" then "" else " - "..record.reason)) end
 local selected=child(configuration,"SelectedWorld")
 local result=Selector.resolve(text(configuration,"SelectedWorld"),records,true,function(spec)
  return Placement.place(child(storage,"BattleWorksAssets"),spec,arena)
 end)
 if selected and not selected:IsA("StringValue") then
  result.status="fallback"; result.reason="SelectedWorld must be a StringValue; using Default Test Arena [default]."
 end
 arena:SetAttribute("WorldId",result.active.id); arena:SetAttribute("WorldName",result.active.name)
 arena:SetAttribute("RequestedWorldId",result.requested); arena:SetAttribute("WorldSelectionStatus",result.status); arena:SetAttribute("WorldSelectionReason",result.reason)
 if result.reason~="" then log("[BattleWorks Studio] "..result.reason) end
 log(string.format("[BattleWorks Studio] Active world: %s [%s]. Selection is read once at startup; edit SelectedWorld outside Play for the next session.",result.active.name,result.active.id))
 return result
end
return Selector
