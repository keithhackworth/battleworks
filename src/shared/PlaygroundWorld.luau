-- Starter authoring document derived from the original Playground layout.
local Terrain=require(script.Parent.PlaygroundTerrain)
local Heightfield=require(script.Parent.WorldHeightfield)
local World={}
function World.new()
 local size=Terrain.DefaultSize
 local layout=Terrain.create(size)
 local field=Heightfield.new(size.X,size.Y)
 field.water=table.create(field.columns*field.rows,0)
 for z=0,field.rows do for x=0,field.columns do
  local px,pz=(x/field.columns-.5)*size.X,(z/field.rows-.5)*size.Y
  local height,region=Terrain.sample(layout,px,pz)
  if region and region.name=="Bridge" then height=Terrain.Depth end
  field.heights[Heightfield.index(field,x,z)]=math.round(height*Heightfield.Unit)
 end end
 for z=1,field.rows do for x=1,field.columns do
  local px,pz=((x-.5)/field.columns-.5)*size.X,((z-.5)/field.rows-.5)*size.Y
  local height,region=Terrain.sample(layout,px,pz)
  if not region or region.name=="Bridge" then
   field.water[(z-1)*field.columns+x]=Heightfield.WaterOffset-30*Heightfield.Unit
  end
 end end
 local document={schemaVersion=2,id="playground",name="Playground",description="Editable Playground terrain, bridge, barracks and forest.",
  settings={width=size.X,depth=size.Y,boundary=true,ground={material="Grass",color={100,112,86}},terrain=field},objects={},spawns={},gameplay={}}
 local function object(id,kind,bounds,x,y,z,sx,sy,sz,pitch)
  table.insert(document.objects,{id=id,type="builtin."..kind,asset="Builtin/BW_"..kind,bounds=bounds,
   position={x,y,z},rotation={pitch or 0,0,0},scale=1,stretch={sx/bounds[1],sy/bounds[2],sz/bounds[3]},
   solid=true,destructible=false,hp=100})
 end
 for i,r in layout.regions do if r.name=="Bridge" then
  local angle=-math.atan(r.slope)
  local mid=(r.z0+r.z1)/2
  local length=(r.z1-r.z0)*math.sqrt(1+r.slope*r.slope)
  local center=r.y+(mid-r.z0)*r.slope-math.cos(angle)
  object("bridge_"..i,"bridge",{12,.2,24},(r.x0+r.x1)/2,center-math.cos(angle)-length*math.abs(math.sin(angle))/2,mid-math.sin(angle),r.x1-r.x0,2,length,math.deg(angle))
 end end
 for i,r in layout.staticBoxes do
  object("barracks_"..i,"wall",{12,6,1},r.x,r.y-r.sy/2,r.z,r.sx,r.sy,r.sz)
 end
 for i,r in layout.trees do
  object("forest_"..i,"tree",{4,12,4},r.x,0,r.z,r.radius*2,r.height,r.radius*2)
 end
 for i,p in {{-100,-22},{-155,30},{77,12},{121,35},{180,123}} do
  document.spawns[i]={id="start_"..i,slot=i,position={p[1],0,p[2]},heading=0}
 end
 return document
end
return World
