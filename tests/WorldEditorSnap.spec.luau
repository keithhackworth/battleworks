local Snap=require("WorldEditorSnap")
local State=require("WorldEditorState")
local Math=require("WorldEditorMath")
local count=0
local function check(ok,message)assert(ok,message);count+=1 end
local function v(a)return Vector3.new(table.unpack(a))end
local function near(a,b,message)check((a-b).Magnitude<1e-5,message)end
local function object(bounds,rotation)return {id="board",asset="Builtin/Board",type="board",bounds=bounds,position={5,8,-12},rotation=rotation,scale=1,solid=true,destructible=true,hp=100}end
for _,bounds in {{20,1,4},{4,1,20}} do
 for _,rotation in {{0,0,0},{0,90,0},{20,90,30},{-30,270,15}} do
  for _,fixed in {"A","B"} do
   for _,side in {0,-1,1} do
    local base=object(bounds,rotation)
    local free=if fixed=="A" then "B" else "A"
    local pin=Snap.pin(fixed,{point={-20,15,-25},normal={0,1,0},kind="edge"},side)
    Snap.anchor(base,pin)
    near(Snap.ends(base,side)[fixed],v(pin.point),"first contact is exact regardless of lowest-point placement contract")
    for _,point in {{10,25,-10},{-5,0,-30},{-15,15,-5}} do
     local fit=Snap.fit(base,free,{point=point},pin)
     local ends=Snap.ends(fit,side)
     near(ends[fixed],v(pin.point),"fitting never moves pinned corner/edge")
     near(ends[free],v(point),"free end fits uneven platform/ground")
     check(math.abs(fit.scale-(v(point)-v(pin.point)).Magnitude/20)<1e-6,"uniform scale matches span")
     check(fit.asset==base.asset and fit.hp==base.hp and fit.id==base.id,"fit preserves asset identity/influences")
     local box=Snap.box(fit)
     check(math.abs(box.size.Y-bounds[2]*fit.scale)<1e-6,"thickness scales uniformly")
    end
    local rotated=State.copy(base);rotated.rotation[1]+=25
    Snap.anchor(rotated,pin);near(Snap.ends(rotated,side)[fixed],v(pin.point),"local rotation preserves pin")
    rotated.scale*=1.7;Snap.anchor(rotated,pin)
    near(Snap.ends(rotated,side)[fixed],v(pin.point),"scaling preserves pin")
    local u,w=Math.rotationBasis(base,"RotatePitch")
    local pivot=v(pin.point)
    rotated=Math.transform(base,"RotatePitch",pivot+u*10,pivot+w*10,false,1,pivot)
    rotated.bounds=base.bounds
    Snap.anchor(rotated,pin)
    near(Snap.ends(rotated,side)[fixed],pivot,"production local rotation gesture pivots at contact")
    local scaled=Math.transform(base,"Scale",pivot+u*10,pivot+u*15,false,1,pivot)
    scaled.bounds=base.bounds
    Snap.anchor(scaled,pin)
    near(Snap.ends(scaled,side)[fixed],pivot,"production scale gesture pivots at contact")
    check(math.abs(scaled.scale-base.scale*1.5)<1e-6,"scale distance measured from contact")
   end
  end
 end
end
local target=object({20,4,12},{15,90,20});target.id="platform"
local corners,normal,center=Snap.top(target)
local contact=Snap.target(target,corners[1]+normal*.1)
check(contact.kind=="corner","top corner is discoverable on rotated platform")
near(v(contact.point),corners[1],"corner target exact")
check(Snap.target(target,corners[1]+normal*.8,2,contact).kind=="corner","corner hysteresis avoids flicker")
local edge=(corners[1]+corners[2])*.5
contact=Snap.target(target,edge+normal*.1)
check(contact.kind=="edge" and contact.edge~=nil,"top edge feedback contains endpoints")
near(v(contact.point),edge,"edge target exact")
check(Snap.target(target,center).kind=="face","face can be explicitly targeted")
check(Snap.target(target,center+normal*10)==nil,"distant surface does not attract")
local base=object({20,1,4},{0,0,0})
check(Snap.nearby({objects={base}},base)==nil,"self excluded from magnetic search")
local platform=object({12,4,12},{0,0,0});platform.id="other"
local corner=Snap.top(platform)[1]
Snap.anchor(base,Snap.pin("B",{point={corner.X,corner.Y,corner.Z}},1))
local nearby=Snap.nearby({objects={base,platform}},base,"B",1)
check(nearby and nearby.endpoint=="B" and nearby.side==1 and nearby.target.targetId=="other","body magnetic search honors free corner and target ownership")
local pin=Snap.pin("A",{point={0,0,0}},-1)
check(not pcall(Snap.fit,base,"A",{point={10,0,0}},pin),"cannot drag fixed end")
check(not pcall(Snap.fit,base,"B",{point={0,0,0}},pin),"degenerate fit rejected")
check(not pcall(Snap.fit,base,"B",{point={100000,0,0}},pin),"oversize fit rejected")
local state=State.new({objects={base},spawns={}});state:select(base.id)
local before=state:snapshot();state.pins[base.id]=pin
check(not state:record(before) and #state.past==0,"pin-only interaction does not create an undo step")
check(not state:undo() and state.pins[base.id].side==-1,"undo skips transient pin changes")
state:duplicate();local duplicate=next(state.selection)
check(state.pins[duplicate]==nil and state.pins[base.id]~=nil,"duplicate does not inherit pin")
state:select(base.id);state:delete();check(state.pins[base.id]==nil,"deletion cleans pins")
state:undo();check(state.pins[base.id]~=nil,"undo deletion restores pin")
check(state.document.pins==nil,"pins never enter world schema")
for _,bounds in {{20,1,4},{4,1,20},{8,2,8}} do
 for _,endpoint in {"A","B","C","D"} do
  local source=object(bounds,{20,90,10});source.scale=2
  local fixed=Snap.opposite(endpoint)
  local ends=Snap.ends(source)
  local pin=Snap.pin(fixed,{point={ends[fixed].X,ends[fixed].Y,ends[fixed].Z},normal={0,1,0}})
  local target={point={-12,16,-24}}
  local scaled=Snap.fit(source,endpoint,target,pin,"Scale")
  near(Snap.ends(scaled)[endpoint],v(target.point),"four-side proportional scale hits target")
  near(Snap.ends(scaled)[fixed],ends[fixed],"four-side proportional scale keeps opposite side fixed")
  local result=Snap.fit(source,endpoint,target,pin,"Stretch")
  local fitted=Snap.ends(result)
  near(fitted[fixed],ends[fixed],"four-side stretch keeps opposite side fixed")
  near(fitted[endpoint],v(target.point),"four-side stretch hits target")
  check(result.scale==source.scale and result.stretch[2]==1,"stretch preserves uniform scale and thickness")
  local alongX=if endpoint=="C" or endpoint=="D" then bounds[1]<=bounds[3] else bounds[1]>bounds[3]
  check(result.stretch[if alongX then 3 else 1]==1,"stretch preserves perpendicular dimension")
  local repeated=Snap.fit(result,endpoint,{point={-18,12,-30}},pin,"Stretch")
  near(Snap.ends(repeated)[fixed],ends[fixed],"repeated stretching keeps original contact")
 end
end
print(string.format("World editor snapping passed: %d assertions",count))
