-- Deterministic additions to PlaygroundTerrain, not a second world/physics engine.
local Materials=require(script.Parent.TerrainMaterials)
local L={Size=Vector2.new(800,640)}
function L.extend(data)
 data.provingGround=true;data.staticBoxes={};data.trees={};data.strips={};data.targets={}
 data.openField={x0=50,x1=350,z0=-135,z1=145}
 data.boundaries={{id="Pavement",x=45,z=0,rx=8,rz=150,profile=Materials.profile("Pavement",0,0,1)},
  {id="Dirt",x=205,z=166,rx=150,rz=6,profile=Materials.profile("Dirt",0,0,1)},
  {id="BarracksFloor",x=170,z=245,rx=80,rz=50,profile=Materials.profile("Pavement",0,0,1)}}
 local function box(name,x,y,z,sx,sy,sz)
  table.insert(data.staticBoxes,{id="proving:wall:"..(#data.staticBoxes+1),name=name,x=x,y=y,z=z,sx=sx,sy=sy,sz=sz})
 end
 -- Open-roof four-room barracks. All dimensions are collision dimensions.
 -- Hall z229..261; opposing exterior doors z233..257 (24-stud clearance).
 for _,x in {90,250}do
  box("end-n-"..x,x,6,214,2,12,38)
  box("end-s-"..x,x,6,276,2,12,38)
  box("door-header-"..x,x,11,245,2,2,24)
 end
 local function wallWithWindows(z)
  -- Windows x121..139 and201..219, vertically y2..9.
  for i,r in {{90,121},{139,201},{219,250}}do box("outer-"..z.."-"..i,(r[1]+r[2])/2,6,z,r[2]-r[1],12,2)end
  for _,x in {130,210}do
   box("sill-"..z.."-"..x,x,1,z,18,2,2)
   box("window-header-"..z.."-"..x,x,10.5,z,18,3,2)
  end
 end
 wallWithWindows(195);wallWithWindows(295)
 for _,z in {229,261}do
  -- 18-stud room doorways at x121..139 and201..219.
  for i,r in {{90,121},{139,201},{219,250}}do box("partition-"..z.."-"..i,(r[1]+r[2])/2,6,z,r[2]-r[1],12,2)end
  for _,x in {130,210}do box("room-header-"..z.."-"..x,x,11,z,18,2,2)end
 end
 box("north-room-divider",170,6,212,2,12,32)
 box("south-room-divider",170,6,278,2,12,32)
 -- Alternate sightline between the southern rooms; northern rooms are dead ends.
 data.staticBoxes[#data.staticBoxes]=nil
 box("south-divider-low",170,1,278,2,2,32)
 box("south-divider-a",170,6,266,2,12,8)
 box("south-divider-b",170,6,290,2,12,8)
 box("south-divider-top",170,10.5,278,2,3,16)
 -- The existing tree renderer/collider path: box trunks and nonquery foliage.
 for row=1,4 do for column=1,5 do
  local x=-330+(column-1)*34+((row*7+column*3)%7-3)
  local z=156+(row-1)*35+((column*5+row)%9-4)
  -- Wide continuous north/south lanes around x-270 and x-200.
  if math.abs(x+270)>12 and math.abs(x+200)>12 then
   table.insert(data.trees,{x=x,z=z,radius=2.3,height=12+(row+column)%4,box=true})
  end
 end end
 table.insert(data.trees,{x=-320,z=205,radius=2.3,height=13,box=true})
 table.insert(data.trees,{x=-302,z=205,radius=2.3,height=14,box=true})
 -- Equal160-stud lanes, each22 studs wide with a6-stud grass separator.
 local specs={{"Pavement",0,0,1},{"Pavement",1,0,1},{"Dirt",0,0,1},{"Dirt",1,.2,.7},
  {"Grass",0,0,1},{"Grass",1,0,1},{"Snow",0,.25,.9},{"Snow",1,1,.35},
  {"Ice",0,0,1},{"Ice",1,0,1},{"Mud",1,.25,.7},{"Mud",1,1.5,.25}}
 for i,s in specs do
  local x=-370+(i-1)*28
  local profile=Materials.profile(table.unpack(s))
  table.insert(data.strips,{id="strip:"..i,x=x,z=-220,rx=11,rz=80,profile=profile})
 end
 local function target(id,x,z,y)table.insert(data.targets,{id=id,x=x,y=y or 3.5,z=z})end
 target("field-north-west",80,-145);target("field-north-east",345,-145)
 target("field-east",370,0);target("field-south-east",345,155)
 target("field-long-range",370,-110);target("window-north",130,212)
 target("hall-end",235,254);target("window-south",210,278)
 target("forest-peek",-316,239);target("terrain-transition",30,-180)
 -- Exposed surface layers: top stays at land elevation, no collision seam step.
 return data
end
return L
