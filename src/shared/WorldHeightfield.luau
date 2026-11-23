-- Optional authoring-v2 terrain. Integer samples are eighth-studs; the surface
-- between samples is the same two triangles in the renderer and simulation.
local H={MaxHeight=96,Unit=8,Chunk=6}
H.Paint={"Grass","Mud","Ice","Snow","Pavement"}
H.WaterOffset=1024
local function dimensions(width,depth)
 return math.clamp(math.ceil(width/6),4,36),math.clamp(math.ceil(depth/6),4,36)
end
function H.new(width,depth)
 local columns,rows=dimensions(width,depth)
 return {version=1,columns=columns,rows=rows,heights=table.create((columns+1)*(rows+1),0)}
end
function H.validate(field,width,depth)
 local columns,rows=dimensions(width,depth)
 assert(type(field)=="table" and field.version==1 and field.columns==columns and field.rows==rows,"Terrain grid does not match the map dimensions")
 for k in field do assert(k=="version" or k=="columns" or k=="rows" or k=="heights" or k=="paint" or k=="water","Unknown terrain property") end
 local n=(columns+1)*(rows+1)
 assert(type(field.heights)=="table" and #field.heights==n,"Incorrect terrain sample count")
 local count=0
 for k,value in field.heights do
  assert(type(k)=="number" and k%1==0 and k>=1 and k<=n,"Invalid terrain sample index")
  assert(type(value)=="number" and value%1==0 and math.abs(value)<=H.MaxHeight*H.Unit,"Invalid terrain height")
  count+=1
 end
 assert(count==n,"Missing terrain sample")
 for _,layer in {"paint","water"} do
  local values=field[layer]
  if values~=nil then
   local cells=columns*rows
   assert(type(values)=="table" and #values==cells,"Incorrect terrain layer size")
   local total=0
   for key,value in values do
    assert(type(key)=="number" and key%1==0 and key>=1 and key<=cells,"Invalid terrain layer index")
    assert(type(value)=="number" and value%1==0 and (value==0 or
     (if layer=="paint" then value>=1 and value<=#H.Paint else math.abs(value-H.WaterOffset)<=H.MaxHeight*H.Unit)),"Invalid terrain layer value")
    total+=1
   end
   assert(total==cells,"Missing terrain layer value")
  end
 end
end
function H.cell(field,width,depth,x,z)
 return math.clamp(math.floor((x/width+.5)*field.columns),0,field.columns-1),
  math.clamp(math.floor((z/depth+.5)*field.rows),0,field.rows-1)
end
function H.surface(field,width,depth,x,z)
 if not (field.paint or field.water) then return nil end
 local i,j=H.cell(field,width,depth,x,z)
 local index=j*field.columns+i+1
 local water=field.water and field.water[index]
 local level=if water and water~=0 then (water-H.WaterOffset)/H.Unit else nil
 return field.paint and H.Paint[field.paint[index]],level
end
local function mark(field,dirty,x,z)
 local cx,cz=math.floor(x/H.Chunk),math.floor(z/H.Chunk)
 local key=cz*field.columns+cx
 if not dirty[key] then dirty[key]={cx,cz} end
end
function H.paint(field,width,depth,point,radius,code)
 local dirty={}
 field.paint=field.paint or table.create(field.columns*field.rows,0)
 local dx,dz=width/field.columns,depth/field.rows
 local x0,z0=H.cell(field,width,depth,point.X-radius,point.Z-radius)
 local x1,z1=H.cell(field,width,depth,point.X+radius,point.Z+radius)
 local px,pz=H.cell(field,width,depth,point.X,point.Z)
 for z=z0,z1 do for x=x0,x1 do
  if (x==px and z==pz) or ((x+.5)*dx-width/2-point.X)^2+((z+.5)*dz-depth/2-point.Z)^2<=radius^2 then
   local index=z*field.columns+x+1
   if field.paint[index]~=code or (field.water and field.water[index]~=0) then
    field.paint[index]=code
    if field.water then field.water[index]=0 end
    mark(field,dirty,x,z)
   end
  end
 end end
 return dirty
end
-- Route water down neighboring cells, then flood connected cells below a
-- chosen basin level. Cells store a surface elevation, rather than depth.
function H.fillWater(field,width,depth,point,depthStuds)
 local dirty={}
 local columns,rows=field.columns,field.rows
 local x,z=H.cell(field,width,depth,point.X,point.Z)
 local function bed(i,j)
  return (H.height(field,i+1,j)+H.height(field,i,j+1))*.5
 end
 local offsets={{-1,0},{1,0},{0,-1},{0,1}}
 local function inside(i,j) return i>=0 and i<columns and j>=0 and j<rows end
 local function set(i,j,level)
  local index=j*columns+i+1
  local value=math.clamp(math.round(level*H.Unit),-H.MaxHeight*H.Unit,H.MaxHeight*H.Unit)+H.WaterOffset
  if field.water[index]<value then field.water[index]=value;mark(field,dirty,i,j) end
 end
 field.water=field.water or table.create(columns*rows,0)
 while true do
  local current=bed(x,z)
  local nx,nz,lowest=x,z,current
  for _,offset in offsets do
   local i,j=x+offset[1],z+offset[2]
   if inside(i,j) then
    local h=bed(i,j)
    if h<lowest then nx,nz,lowest=i,j,h end
   end
  end
  if nx==x and nz==z then break end
  set(x,z,current+math.min(depthStuds,1.5));x,z=nx,nz
 end
 local level=bed(x,z)+depthStuds
 local queue={{x,z}};local seen={[z*columns+x]=true}
 local cursor=1
 while cursor<=#queue do
  local i,j=table.unpack(queue[cursor]);cursor+=1
  set(i,j,level)
  for _,offset in offsets do
   local a,b=i+offset[1],j+offset[2];local key=b*columns+a
   if inside(a,b) and not seen[key] and bed(a,b)<level then
    seen[key]=true;table.insert(queue,{a,b})
   end
  end
 end
 return dirty
end
function H.index(field,x,z) return z*(field.columns+1)+x+1 end
function H.height(field,x,z) return field.heights[H.index(field,x,z)]/H.Unit end
function H.sample(field,width,depth,x,z,withGradient)
 if not field then return 0 end
 local u=math.clamp((x/width+.5)*field.columns,0,field.columns)
 local v=math.clamp((z/depth+.5)*field.rows,0,field.rows)
 local i,j=math.min(math.floor(u),field.columns-1),math.min(math.floor(v),field.rows-1)
 local a,b,c,d=H.height(field,i,j),H.height(field,i+1,j),H.height(field,i,j+1),H.height(field,i+1,j+1)
 local s,t=u-i,v-j
 local first=s+t<=1
 local height=if first then a+(b-a)*s+(c-a)*t else d+(c-d)*(1-s)+(b-d)*(1-t)
 if withGradient then
  return height,(if first then b-a else d-c)*field.columns/width,(if first then c-a else d-b)*field.rows/depth
 end
 return height
end
-- Resize around the world center. Resample elevation at normalized grid
-- positions and use nearest cells for discrete materials and water levels.
function H.resize(field,width,depth,newWidth,newDepth)
 local resized=H.new(newWidth,newDepth)
 if resized.columns==field.columns and resized.rows==field.rows then
  resized.heights=table.clone(field.heights)
  resized.paint=field.paint and table.clone(field.paint)
  resized.water=field.water and table.clone(field.water)
  return resized
 end
 for z=0,resized.rows do
  for x=0,resized.columns do
   local height=H.sample(field,width,depth,(x/resized.columns-.5)*width,(z/resized.rows-.5)*depth)
   resized.heights[H.index(resized,x,z)]=math.round(height*H.Unit)
  end
 end
 for _,layer in {"paint","water"} do
  local values=field[layer]
  if values then
   local result=table.create(resized.columns*resized.rows)
   for z=0,resized.rows-1 do
    for x=0,resized.columns-1 do
     local oldX=math.floor((x+.5)*field.columns/resized.columns)
     local oldZ=math.floor((z+.5)*field.rows/resized.rows)
     result[z*resized.columns+x+1]=values[oldZ*field.columns+oldX+1]
    end
   end
   resized[layer]=result
  end
 end
 return resized
end
function H.brush(field,width,depth,point,mode,radius,strength,falloff,target,dt,remainder)
 local dx,dz=width/field.columns,depth/field.rows
 local dirty={}
 local nextValues={}
 local x0=math.max(0,math.ceil((point.X-radius+width/2)/dx))
 local x1=math.min(field.columns,math.floor((point.X+radius+width/2)/dx))
 local z0=math.max(0,math.ceil((point.Z-radius+depth/2)/dz))
 local z1=math.min(field.rows,math.floor((point.Z+radius+depth/2)/dz))
 for z=z0,z1 do for x=x0,x1 do
  local distance=math.sqrt((x*dx-width/2-point.X)^2+(z*dz-depth/2-point.Z)^2)
  if distance<=radius then
   local weight=if falloff==0 then 1 else math.clamp((1-distance/radius)/falloff,0,1)
   local index=H.index(field,x,z)
   local current=field.heights[index]
   local value
   if mode=="Raise" or mode=="Lower" then
    value=current+(if mode=="Raise" then 1 else -1)*strength*dt*weight*H.Unit
   else
    local desired=target*H.Unit
    if mode=="Carve" then desired=math.min(desired,current) end
    if mode=="Smooth" then
     desired=(field.heights[H.index(field,math.max(0,x-1),z)]
      +field.heights[H.index(field,math.min(field.columns,x+1),z)]
      +field.heights[H.index(field,x,math.max(0,z-1))]
      +field.heights[H.index(field,x,math.min(field.rows,z+1))])/4
    end
    value=current+(desired-current)*math.clamp(dt*strength*.3*weight,0,1)
   end
   local exact=math.clamp(value+(remainder and remainder[index] or 0),-H.MaxHeight*H.Unit,H.MaxHeight*H.Unit)
   value=math.round(exact)
   if remainder then remainder[index]=exact-value end
   if value~=current then
    nextValues[index]=value
    for j=math.max(0,z-1),math.min(z,field.rows-1) do
     for i=math.max(0,x-1),math.min(x,field.columns-1) do
      local cx,cz=math.floor(i/H.Chunk),math.floor(j/H.Chunk)
      dirty[cz*field.columns+cx]={cx,cz}
     end
    end
   end
  end
 end end
 for index,value in nextValues do field.heights[index]=value end
 return dirty
end
function H.pick(field,width,depth,origin,direction)
 if not origin then return nil end
 local start,finish=0,4000
 for _,axis in {{origin.X,direction.X,width/2},{origin.Z,direction.Z,depth/2},{origin.Y,direction.Y,H.MaxHeight+1}} do
  local p,v,half=table.unpack(axis)
  if math.abs(v)<1e-7 then if math.abs(p)>half then return nil end
  else
   local a,b=(-half-p)/v,(half-p)/v
   start=math.max(start,math.min(a,b));finish=math.min(finish,math.max(a,b))
  end
 end
 if finish<=start then return nil end
 local function difference(t)
  local p=origin+direction*t
  return p.Y-H.sample(field,width,depth,p.X,p.Z)
 end
 local size=if field then math.min(width/field.columns,depth/field.rows) else 6
 local stride=size*.35/math.max(math.abs(direction.X),math.abs(direction.Z),.01)
 local previous=start
 while previous<finish do
  local nextPoint=math.min(finish,previous+stride)
  if difference(previous)>=0 and difference(nextPoint)<=0 then
   for _=1,10 do
    local mid=(previous+nextPoint)/2
    if difference(mid)>0 then previous=mid else nextPoint=mid end
   end
   local p=origin+direction*nextPoint
   return Vector3.new(p.X,H.sample(field,width,depth,p.X,p.Z),p.Z)
  end
  previous=nextPoint
 end
 return nil
end
return H
