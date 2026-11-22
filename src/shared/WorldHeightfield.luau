-- Optional authoring-v2 terrain. Integer samples are eighth-studs; the surface
-- between samples is the same two triangles in the renderer and simulation.
local H={MaxHeight=96,Unit=8,Chunk=6}
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
 for k in field do assert(k=="version" or k=="columns" or k=="rows" or k=="heights","Unknown terrain property") end
 local n=(columns+1)*(rows+1)
 assert(type(field.heights)=="table" and #field.heights==n,"Incorrect terrain sample count")
 local count=0
 for k,value in field.heights do
  assert(type(k)=="number" and k%1==0 and k>=1 and k<=n,"Invalid terrain sample index")
  assert(type(value)=="number" and value%1==0 and math.abs(value)<=H.MaxHeight*H.Unit,"Invalid terrain height")
  count+=1
 end
 assert(count==n,"Missing terrain sample")
end
function H.index(field,x,z) return z*(field.columns+1)+x+1 end
function H.height(field,x,z) return field.heights[H.index(field,x,z)]/H.Unit end
function H.sample(field,width,depth,x,z)
 if not field then return 0 end
 local u=math.clamp((x/width+.5)*field.columns,0,field.columns)
 local v=math.clamp((z/depth+.5)*field.rows,0,field.rows)
 local i,j=math.min(math.floor(u),field.columns-1),math.min(math.floor(v),field.rows-1)
 local a,b,c,d=H.height(field,i,j),H.height(field,i+1,j),H.height(field,i,j+1),H.height(field,i+1,j+1)
 local s,t=u-i,v-j
 if s+t<=1 then return a+(b-a)*s+(c-a)*t end
 return d+(c-d)*(1-s)+(b-d)*(1-t)
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
