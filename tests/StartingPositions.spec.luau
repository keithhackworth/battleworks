local Settings=require("WorldSettings")
local Document=require("WorldEditorDocument")
local State=require("WorldEditorState")
local Areas=require("StartingAreas")
local state=State.new(Document.editorFresh());state.snap=false
local points={Vector3.new(-60,0,-60),Vector3.new(0,0,-60),Vector3.new(60,0,-60),Vector3.new(-60,0,60),Vector3.new(60,0,60)}
local function settings()local s=State.copy(state.document.settings);s.spawns=State.copy(state.document.spawns);s.zones={};return s end
for i=0,4 do
 check(pcall(Settings.validate,settings(),true),"incomplete numbered starts remain valid drafts")
 local ready,reason=pcall(Settings.ready,settings())
 check(not ready,"incomplete starts cannot launch")
 check(tostring(reason):find("not playable",1,true) and tostring(reason):find(i.."/5",1,true),"readiness explains the missing-zone requirement with the actual count")
 check(not pcall(Settings.validate,settings()),"runtime cannot accept incomplete starting areas")
 local id=state:addStart(points[i+1]);check(state:find(id).slot==i+1,"placement assigns next number")
end
check(pcall(Settings.ready,settings()),"five unique starts are playable")
check(not pcall(state.addStart,state,Vector3.zero),"sixth start is rejected")
state:select("start_2");state:delete();check(#state.document.spawns==4,"start deletion is supported")
state:undo();check(state:find("start_2").slot==2,"undo deletion preserves slot numbering")
state:redo();local id=state:addStart(points[2]);check(id=="start_2" and state:find("start_3").slot==3,"replacement fills missing number without renumbering other players")
local s=settings();Settings.validate(s)
local bodies={}
for i=1,3 do
 local p,yaw=Settings.spawn(s,"Boomer",3,bodies)
 check(math.abs(p.X-60)<=12.001 and p.Z==-60,"three owned tanks fit in player 3's marked starting area")
 for _,body in bodies do check((body.state.position-p).Magnitude>=12,"tank bays do not overlap") end
 table.insert(bodies,{state={position=p,yaw=yaw},halfX=4,halfZ=5,bottom=0,top=5})
end
local bad=State.copy(s);bad.spawns[5].slot=3;check(not pcall(Settings.validate,bad,true),"duplicate slot numbers rejected")
for _,heading in {45,90,135,270} do
 local rotated=State.copy(s);for _,p in rotated.spawns do if p.slot==3 then p.heading=heading end end
 local occupied={};local yaw=-math.rad(heading)
 for i=1,3 do
  local p=Settings.spawn(rotated,"Boomer",3,occupied)
  local dx,dz=p.X-60,p.Z+60
  check(math.abs(math.cos(yaw)*dx-math.sin(yaw)*dz)<=12.001 and math.abs(math.sin(yaw)*dx+math.cos(yaw)*dz)<1e-5,"rotated three-tank bays stay inside visible caution area")
  table.insert(occupied,{state={position=p,yaw=yaw},halfX=4,halfZ=5,bottom=0,top=5})
 end
end
bad=State.copy(s);bad.spawns[1].position[2]=5;check(not pcall(Settings.validate,bad,true),"starting areas stay on base ground")
bad=State.copy(s);bad.spawns[2].position={-40,0,-60};check(not pcall(Settings.validate,bad,true),"three-tank areas cannot overlap")
bad=State.copy(s);bad.spawns[1].position={100,0,-60};check(not pcall(Settings.validate,bad,true),"full area must remain inside world boundary")
local factory=Instance.new
Instance.new=function(class)
 local p=factory(class)
 local isA=p.IsA;function p:IsA(kind)return (kind=="BasePart" and class=="Part") or isA(self,kind)end
 function p:FindFirstChild(name)for _,child in self.children do if child.Name==name then return child end end end
 setmetatable(p,{__newindex=function(self,k,value)rawset(self,k,value);if k=="Parent" and value then table.insert(value.children,self) end end})
 return p
end
local parent=Instance.new("Folder")
local live=Areas.make(parent,state:find("start_3"),false)
local floor=live:FindFirstChild("CautionArea")
check(floor.Size.X==36 and floor.Size.Z==16,"caution marking covers three tank bays")
check(live:FindFirstChild("Number3")~=nil and live:FindFirstChild("CautionStripe")~=nil,"number and stripes are real geometry in both viewport and gameplay")
for _,p in live:GetDescendants() do if p:IsA("BasePart") then check(not p.CanCollide and not p.CanTouch and not p.CanQuery,"live starting markings cannot interfere with simulation or hits") end end
local editable=Areas.make(parent,state:find("start_3"),true)
check(editable:FindFirstChild("CautionArea").CanQuery and editable:GetAttribute("EditorObjectId")=="start_3","editor area has a selectable identity")
local doc=Document.export(state.document,Document.catalog({}))
check(#doc.spawns==5 and doc.spawns[3].slot~=nil,"numbered areas survive normal world export")
Instance.new=factory
print(string.format("Five three-tank starting positions passed: %d assertions",count))
