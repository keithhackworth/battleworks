local Snap=require("WorldEditorSnap")
local State=require("WorldEditorState")
local Math=require("WorldEditorMath")
local Fill=require("AudioSurfaceFill")
local count=0
local function check(ok,message)assert(ok,message);count+=1 end
local function quad(faces,a,b,c,d)
 table.insert(faces,{a,b,c});table.insert(faces,{a,c,d})
end
local function rectangle(faces,x0,x1,y,z0,z1)
 quad(faces,{x0,y,z0},{x0,y,z1},{x1,y,z1},{x1,y,z0})
end
local unit={position={0,-.5,0},rotation={0,0,0},bounds={1,1,1},scale=1}
do
 local function face(a,b,c)
  return {vertices={Vector3.new(table.unpack(a)),Vector3.new(table.unpack(b)),Vector3.new(table.unpack(c))}}
 end
 local seed=face({0,0,0},{0,0,8},{8,0,8})
 local adjacent=face({0,0,0},{8,0,8},{8,0,0})
 local snapped=face({8.06,0,2},{8.06,0,6},{16,2,4})
 local stacked=face({0,3,0},{0,3,8},{8,3,8})
 local corner=face({0,0,0},{-8,0,-8},{-8,0,0})
 local region=Fill.connected({seed,adjacent,snapped,stacked,corner},seed)
 check(#region==3,"bucket crosses snapped partial edges and excludes stacked and corner-only surfaces")
 local points=Fill.sample(region,Vector3.new(2,0,6),Vector3.new(4,4,4),64)
 local ramp=false
 for _,p in points do if p.X>8.06 and p.Y>0 then ramp=true end end
 check(ramp,"bucket stamps follow the connected ramp elevation")
 check(Fill.sample(region,Vector3.new(2,0,6),Vector3.new(4,4,4),1)==nil,"oversized bucket fills do not return a partial result")
end
do
 local function flume(curved)
  local slices=8
  local faces={}
  local width={-.15,-.07,.07,.15}
  local height={.3,0,0,.3}
  local function point(i,j)
   if not curved then return {width[j],height[j],i/slices-.5} end
   local theta=i/slices*math.pi/2
   local radius=.3+width[j]
   return {radius*math.cos(theta),height[j],radius*math.sin(theta)}
  end
  for i=0,slices-1 do
   for j=1,3 do quad(faces,point(i,j),point(i+1,j),point(i+1,j+1),point(i,j+1)) end
  end
  local profile={fit="faces",faces=faces}
  local edges=Snap.sourceOptions(unit,profile)
  check(#edges==(if curved then slices*2+6 else 8),"flume snap geometry contains the outer rims and the two end profiles")
  check(#Snap.collisionGeometry(unit,profile).edges==#edges,"source and target snapping share the flume boundary")
  if curved then
   for _,edge in edges do
    local a,b=edge.a,edge.b
    if math.abs(a.Y-.3)<1e-5 and math.abs(b.Y-.3)<1e-5 then
     check((a-b).Magnitude<.1,"curved rims retain their individual chords and the concave opening")
    end
   end
  end
 end
 flume(false);flume(true)
end
do
 local faces={}
 rectangle(faces,-.5,0,0,-.5,.5)
 rectangle(faces,.000003,.5,0,-.5,0)
 rectangle(faces,.000003,.5,0,0,.5)
 rectangle(faces,-.25,.25,0,-.3,.3)
 rectangle(faces,-.5,0,0,-.5,.5)
 local edges=Snap.sourceOptions(unit,{fit="faces",faces=faces})
 check(#edges==4,"T-junctions, partial overlap, duplicated triangles and near-coincident seams leave four merged exterior edges")
 for _,edge in edges do
  check(math.abs((edge.b-edge.a).Magnitude-1)<1e-5,"each side is contiguous across the original collision pieces")
 end
end
do
 local faces={}
 rectangle(faces,-.5,.2,.4,-.5,.5)
 rectangle(faces,-.2,.15,.1,-.2,.2)
 rectangle(faces,.2,.5,-.25,-.5,.5)
 local edges=Snap.sourceOptions(unit,{fit="faces",faces=faces,bases={-.4,-.4,0,0,-.4,-.4}})
 check(#edges==8,"buried seams disappear while the adjacent lower step retains its own perimeter")
 for _,edge in edges do check(math.abs(edge.a.Y-.1)>1e-5,"an edge inside the combined collision volume is hidden") end
end
do
 local collision,snap={},{}
 rectangle(collision,-.5,.5,.4,-.5,.5)
 quad(snap,{-.2,-.2,-.1},{-.2,-.1,.1},{.2,-.1,.1},{.2,-.2,-.1})
 local profile={fit="faces",faces=collision,snap={faces=snap}}
 local placed={position={12,4,-8},rotation={25,48,12},bounds={4,7,9},stretch={2,.5,1.5},scale=2}
 local options=Snap.sourceOptions(placed,profile)
 local geometry=Snap.collisionGeometry(placed,profile)
 local box=Snap.box(placed)
 check(#options==4 and #geometry.edges==4 and #geometry.faces==2,"explicit snap mesh replaces automatically derived edges and leaves collision faces intact")
 for i,edge in options do
  local localPoint=edge.a-box.position
  local z=(localPoint.X*box.back.X+localPoint.Y*box.back.Y+localPoint.Z*box.back.Z)/box.size.Z
  local contact=Snap.contact(placed,edge.side,0,profile,i,.5)
  check(math.abs(math.abs(z)-.1)<1e-5 and (edge.b+edge.a-contact*2).Magnitude<1e-5,"authored contacts follow rotation and nonuniform resize")
  local direction=(edge.b-edge.a).Unit
  check(math.abs(direction.X*edge.normal.X+direction.Y*edge.normal.Y+direction.Z*edge.normal.Z)<1e-5,"transformed normals remain perpendicular to authored edges")
 end
 check(not Snap.collisionTarget(placed,geometry,box.position,0,box.up),"explicit mode does not offer collision-face targets")
 local line={fit="faces",faces=collision,snap={segments={{{-.3,0,0},{0,0,0}},{{0,0,0},{.3,0,0}}}}}
 check(#Snap.sourceOptions(placed,line)==1,"authored line primitives merge into a single snap edge")
end
do
 local rock={id="stacked",position={0,0,0},rotation={0,0,0},bounds={12,12,20},scale=1}
 local profile={fit="faces",faces={}}
 for _,y in {-.4,-.1,.15,.45} do
  table.insert(profile.faces,{{-.5,y,-.5},{-.5,y,.5},{.5,y,-.5}})
  table.insert(profile.faces,{{.5,y,-.5},{-.5,y,.5},{.5,y,.5}})
 end
 local sameSide={}
 for _,edge in Snap.sourceOptions(rock,profile) do if edge.side=="A" then table.insert(sameSide,edge) end end
 check(#sameSide==4,"four ledges on one collision side each have a selectable marker")
 local function project(p)return Vector2.new(p.X*10,p.Y*10),20 end
 local point=(sameSide[2].a+sameSide[2].b)/2
 local picked,markers=Snap.screenEdges(sameSide,project,project(point),32)
 check(#markers==4 and picked.edge==sameSide[2] and picked.fraction==.5,"the lower dot selects its own ledge even when upper ledges are present")
 local line=Snap.screenEdges(sameSide,project,project(point+Vector3.new(3,0,0)),32)
 check(line.edge==sameSide[2] and (line.point-point).Magnitude>2.9,"the line selects a point away from the midpoint on the same ledge")
 local pin=Snap.pin("A",{point={point.X,point.Y,point.Z}},0,picked.edge.index,picked.fraction)
 local target={point={5,8,27}}
 local fitted=Snap.fit(rock,"B",target,pin,"Scale",profile)
 local fixed=Snap.contact(fitted,"A",0,profile,pin.edgeIndex,pin.edgeFraction)
 local moving=Snap.contact(fitted,"B",0,profile)
 check((fixed-point).Magnitude<1e-5 and (moving-Vector3.new(table.unpack(target.point))).Magnitude<1e-5,"a fitted piece retains the selected lower source ledge")
end
do
 local deck={id="deck",position={0,0,0},rotation={0,0,0},bounds={20,10,20},scale=1,stretch={1,1,2}}
 local profile={fit="faces",faces={
  {{-.25,-.3,-.5},{-.25,-.3,.5},{.25,-.3,-.5}},
  {{.25,-.3,-.5},{-.25,-.3,.5},{.25,-.3,.5}},
 }}
 local geometry=Snap.collisionGeometry(deck,profile)
 check(#geometry.edges==4,"coplanar triangle seams do not become snap lines")
 local handles=Snap.ends(deck,0,profile)
 check(handles.A.Z==-20 and handles.B.Z==20 and handles.C.X==-5 and handles.D.X==5,"all four handles sit on the collision perimeter")
 for _,p in handles do check(math.abs(p.Y-2)<1e-5,"source handles sit at deck height below the render bounds") end
 for _,mode in {"Scale","Stretch"} do
  local pin=Snap.pin("A",{point={0,5,0},normal={0,1,0}})
  local fitted=Snap.fit(deck,"B",{point={60,5,0}},pin,mode,profile)
  local ends=Snap.ends(fitted,0,profile)
  check((ends.A-Vector3.new(0,5,0)).Magnitude<1e-5 and (ends.B-Vector3.new(60,5,0)).Magnitude<1e-5,"fitting keeps both collision edges exactly on their targets")
 end
 local down=Vector3.new(0,-1,0)
 local hit=Snap.collisionHit(geometry,Vector3.new(4.5,30,5),down,100)
 check(hit and math.abs(hit.point.Y-2)<1e-5,"snap ray hits the low collision deck below the visual top")
 local follow=Snap.collisionHit(geometry,Vector3.new(4.5,30,5),down,100,true)
 check(follow and math.abs(follow.point.Y-2)<1e-5 and not Snap.collisionHit(geometry,Vector3.new(8,30,5),down,100,true),
  "collision following finds support within the real deck and rejects the surrounding render bounds")
 local target=Snap.collisionTarget(deck,geometry,hit.point,Snap.Radius,hit.normal)
 check(target.kind=="edge" and target.point[1]==5,"snap picks the deck boundary inside the visible bounding box")
 check(Snap.collisionHit(geometry,Vector3.new(8,30,0),down,100)==nil,"ray misses decorative geometry outside the deck")
 local center=Snap.collisionTarget(deck,geometry,Vector3.new(0,2,0),Snap.Radius,Vector3.new(0,1,0))
 check(center.kind=="face","the triangulated deck center is a face rather than a diagonal edge")
 deck.rotation[2]=90
 geometry=Snap.collisionGeometry(deck,profile)
 hit=Snap.collisionHit(geometry,Vector3.new(19,30,0),down,100)
 check(hit and math.abs(hit.point.Y-2)<1e-5,"snap profile follows asset rotation and independent length resize")
 local rock={id="rock",position={0,0,0},rotation={12,35,0},bounds={12,8,17},scale=1}
 local rocky={fit="faces",faces={{{-.4,-.2,-.4},{-.2,.05,.4},{.4,.3,-.25}}}}
 local rockyGeometry=Snap.collisionGeometry(rock,rocky)
 local rockyEnds=Snap.ends(rock,0,rocky)
 for _,p in rockyEnds do
  local onEdge=false
  for _,edge in rockyGeometry.edges do if (Snap.closest(edge.a,edge.b,p)-p).Magnitude<1e-5 then onEdge=true end end
  check(onEdge,"uneven non-bridge geometry places each handle on a real collision edge")
 end
 local pin=Snap.pin("A",{point={0,4,0},normal={0,1,0}})
 local fitted=Snap.fit(rock,"B",{point={12,7,15}},pin,"Scale",rocky)
 local ends=Snap.ends(fitted,0,rocky)
 check((ends.A-Vector3.new(0,4,0)).Magnitude<1e-5 and (ends.B-Vector3.new(12,7,15)).Magnitude<1e-5,"irregular collision handles fit both contacts even when the source heights differ")
end
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
