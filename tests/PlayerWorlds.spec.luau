local State=require("WorldEditorState")
local Document=require("WorldEditorDocument")
local Adapter=require("PlayerWorldDocument")
local Store=require("PlayerWorldStore")
local Service=require("PlayerWorldService")
local assets=Instance.new("Folder")
local folder=Instance.new("Folder");folder.Name="Trees";folder.Parent=assets
local oak=Instance.new("Model");oak.Name="Oak";oak.Parent=folder
assets.children={folder};folder.children={oak}
function assets:FindFirstChild(name) if name=="Trees" then return folder end end
function folder:FindFirstChild(name) if name=="Oak" then return oak end end
function oak:GetBoundingBox() return CFrame.new(),Vector3.new(8,12,8) end
local item={id="asset.oak",model="Trees/Oak",source="Trees/Oak.glb",available=true,collider={widthFraction=.5,heightFraction=.5,depthFraction=.5}}
local doc=Document.fresh();doc.id="forest"
doc.objects={{id="oak_1",type=item.id,asset=item.model,position={0,0,0},rotation={0,25,0},scale=1,solid=true,destructible=true,hp=150,bounds={.001,.001,.001}}}
local normalized,specs,settings=Adapter.validate(State.copy(doc),{item},assets)
check(normalized.objects[1].bounds[1]==8 and specs[1].template=="Trees/Oak","server measures bounds and preserves hierarchical references")
check(specs[1].interaction.fractions.Y==.5 and specs[1].interaction.hp==150 and settings.spawns[1].tank=="Boomer","existing influence/spawn representation reused")
local function reject(change,message)
 local value=State.copy(doc);change(value)
 check(not pcall(Adapter.validate,value,{item},assets),message)
end
reject(function(v)v.objects[1].position={114,0,0}end,"forged tiny bounds cannot bypass boundary validation")
reject(function(v)v.objects[1].asset="Trees/../Oak"end,"unregistered hierarchical paths rejected")
reject(function(v)v.objects[1].hp=-100 end,"invalid damage properties rejected")
reject(function(v)v.objects[1].position=v.spawns[1].position end,"solid scenery cannot block authored spawn")
reject(function(v)v.spawns[2].position=v.spawns[1].position end,"overlapping spawns rejected")
reject(function(v)v.gameplay.source="execute"end,"executable gameplay rejected")
reject(function(v)v.settings.width=math.huge end,"non-finite settings rejected")
reject(function(v)v.objects[2]=State.copy(v.objects[1])end,"duplicate instance IDs rejected")
reject(function(v)v.objects[1].owner=102 end,"unexpected object authority fields rejected")
reject(function(v)v.spawns[2].id=v.spawns[1].id end,"duplicate spawn IDs rejected")
local unavailable=State.copy(item);unavailable.available=false
check(not pcall(Adapter.validate,State.copy(doc),{unavailable},assets),"missing native templates cannot be saved")
local water=State.copy(item);water.zone="Water"
local _,_,wet=Adapter.validate(State.copy(doc),{water},assets)
check(wet.zones[1].rx==4 and wet.zones[1].speed==.9,"catalog environmental influences retained")
local block={CFrame=CFrame.new(),Shape=Enum.PartType.Block}
function block:IsA(kind)return kind=="Part" or kind=="BasePart"end
function block:GetChildren()return {}end
function oak:GetDescendants()return {block}end
function oak:GetPivot()return CFrame.new()end
local stretched=State.copy(doc);stretched.objects[1].stretch={1,1,2}
local stretchDoc,stretchSpecs=Adapter.validate(stretched,{item},assets)
check(stretchDoc.objects[1].stretch[3]==2 and stretchSpecs[1].stretch[3]==2,"server carries validated stretch through saved document and native placement")
reject(function(v)v.objects[1].stretch={100,1,1}end,"stretch cannot bypass boundary validation with forged native bounds")
reject(function(v)v.objects[1].stretch={1,0,2}end,"invalid stretch factors rejected")
block.Shape=Enum.PartType.Ball
reject(function(v)v.objects[1].stretch={1,1,2}end,"server inspects actual native geometry rather than trusting client stretch support")
local data={};local failRead,failWrite=false,false
local ds={GetAsync=function(_,key)assert(not failRead,"storage read failed");return State.copy(data[key])end,UpdateAsync=function(_,key,fn)
 assert(not failWrite,"storage write failed")
 -- Model a retried callback: only the last transform is committed.
 fn(State.copy(data[key]));data[key]=State.copy(fn(State.copy(data[key])))
end}
local store=Store.new(ds,false,function()return "json"end)
-- Launch fixtures use the new five player starting areas; legacy saves above
-- remain covered for load/migration compatibility.
normalized.spawns={}
for i,p in {{-60,0,-60},{0,0,-60},{60,0,-60},{-60,0,60},{60,0,60}} do table.insert(normalized.spawns,{id="start_"..i,slot=i,position=p,heading=0}) end
local saved=store:save(101,normalized,0)
check(saved.revision==1 and #store:list(101)==1 and #store:list(102)==0,"private save/list keyed only by authenticated owner")
check(not pcall(store.load,store,102,"forest"),"another player cannot open the owner's world")
check(not pcall(store.save,store,101,normalized,0),"stale save cannot overwrite a newer revision")
check(store:save(101,normalized,1).revision==2,"known revision updates slot atomically")
failWrite=true
check(not pcall(store.save,store,101,normalized,2) and store:load(101,"forest").revision==2,"failed write never reports or caches a successful save")
failWrite=false;failRead=true
check(not pcall(store.list,store,101),"failed storage reads do not become empty profiles")
failRead=false
for i=1,9 do local copy=State.copy(normalized);copy.id="world_"..i;store:save(101,copy,0) end
local extra=State.copy(normalized);extra.id="too_many"
check(not pcall(store.save,store,101,extra,0),"per-owner save limit enforced")
local oversized=Store.new(ds,false,function()return string.rep("x",3000001)end)
check(not pcall(oversized.save,oversized,102,normalized,0),"profile storage budget enforced")
local temporary=Store.new(nil,true,function()return "json"end)
temporary:save(101,normalized,0);temporary:forget(101)
check(#temporary:list(101)==0,"Studio temporary saves cleaned on disconnect")
local time=10;local previousClock=os.clock;os.clock=function()return time end
local occupied=false;local installed=0;local teleported
local alice={UserId=101,GetJoinData=function()return {SourcePlaceId=55,TeleportData={battleWorksWorld=true,owner=101,id="forest",revision=2}}end}
local bob={UserId=102,GetJoinData=alice.GetJoinData}
local function options(studio,reserved)
 return {studio=studio,reserved=reserved,placeId=55,http={JSONEncode=function()return "json"end},items={item},assets=assets,dataStore=ds,
  isPresent=function()return true end,inBattle=function()return occupied end,
  install=function()assert(not occupied,"battlefield occupied");installed+=1 end,
  teleport=function(player,info)teleported={player=player,info=info}end}
end
local published=Service.new(options(false,false))
check(published:request(bob,"Load","forest").ok==false,"RPC cannot read another user's slot")
check(not published:request(alice,"Damage",100).ok,"unknown remote actions rejected")
local result=published:request(alice,"Play",{id="forest",revision=2})
check(result.ok and result.teleporting and installed==0 and teleported.info.owner==101 and teleported.info.revision==2,"published Play launches saved owner/revision into separate server")
check(not published:request(alice,"Play",{id="forest",revision=2}).ok,"per-action remote throttling enforced")
time+=1;occupied=true
check(not published:request(alice,"Play",{id="forest",revision=2}).ok,"battle participants must leave before world launch")
occupied=false
local destination=Service.new(options(false,true));destination:register(alice);destination:register(bob)
check(not destination:canEnter(alice) and not destination:canEnter(bob),"reserved battle denies admission until saved world validates")
result=destination:request(alice,"Bootstrap")
check(result.ok and result.launch and installed==1 and destination:canEnter(alice) and not destination:canEnter(bob),"destination reloads owner save and admits only its owner")
time+=1
check(not destination:request(alice,"Bootstrap").launch and installed==1,"duplicate bootstrap never reloads active geometry")
destination:remove(alice)
check(not destination:canEnter(alice),"disconnect clears reserved admission")
local studio=Service.new(options(true,false))
result=studio:request(alice,"Save",{document=State.copy(normalized),revision=0})
check(result.ok and result.temporary,"Studio save truthfully reports session-only persistence")
occupied=true
result=studio:request(alice,"Play",{id="forest",revision=1})
check(not result.ok and installed==1,"Studio cannot replace occupied battlefield")
occupied=false;time+=1
result=studio:request(alice,"Play",{id="forest",revision=1})
check(result.ok and result.launch and installed==2,"Studio tests through same validated installation path without teleport")
local drafting=Service.new(options(true,false))
for n=0,4 do
 time+=1
 local draft=State.copy(normalized);draft.id="unfinished";draft.spawns={}
 for i=1,n do table.insert(draft.spawns,State.copy(normalized.spawns[i])) end
 local savedDraft=drafting:request(alice,"Save",{document=draft,revision=n})
 check(savedDraft.ok,"incomplete starting areas can be saved as a draft")
 local denied=drafting:request(alice,"Play",{id=draft.id,revision=n+1})
 check(not denied.ok and denied.message:find("five",1,true) and installed==2,"server denies Play with fewer than five starts")
end
local forged=Service.new(options(false,true));bob.GetJoinData=function()return {SourcePlaceId=55,TeleportData={battleWorksWorld=true,owner=101,id="forest",revision=2}}end
forged:register(bob)
check(not forged:request(bob,"Bootstrap").launch and not forged:canEnter(bob),"spoofed cross-owner launch cannot install a world")
failRead=true;local broken=Service.new(options(false,false))
check(not broken:request(alice,"List").ok,"storage outage is an explicit RPC failure")
failRead=false;os.clock=previousClock
store.kind="Http"
local durableOptions=options(true,false);durableOptions.store=store
local durableStudio=Service.new(durableOptions)
local listed=durableStudio:request(alice,"List")
check(listed.ok and listed.temporary==false and listed.storage=="Http","Studio mode with HTTP backend reports durable saves")
durableStudio:remove(alice)
check(#store:list(101)==10,"disconnect from HTTP-backed Studio never deletes saved worlds")
local teamOptions=options(true,false);teamOptions.store=store;teamOptions.testHost=101
local team=Service.new(teamOptions)
check(not team:canEnter(alice) and not team:canEnter(bob),"Team Test waits for host installation")
check(not team:request(bob,"List").ok and not team:request(bob,"Load","forest").ok,"test collaborators cannot list or load host saves")
check(not team:request(bob,"Play",{id="forest",revision=2}).ok,"test collaborators cannot replace the shared world")
local hostList=team:request(alice,"List")
check(hostList.ok and hostList.teamTest and hostList.storage=="Http" and #hostList.worlds==10,"host sees existing Studio saves without migration")
local hostPlay=team:request(alice,"Play",{id="forest",revision=2})
check(hostPlay.ok and hostPlay.launch and installed==3,"host installs saved world in shared test server without teleport")
check(team:canEnter(alice) and team:canEnter(bob),"collaborators can join installed test world")
check(team:request(bob,"Bootstrap").launch==false,"collaborator bootstrap never reloads or teleports the world")
team:remove(alice);check(team:canEnter(bob),"host disconnect does not invalidate an installed shared test")
print(string.format("Player world validation, persistence and isolation passed: %d assertions",count))
