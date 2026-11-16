-- Validated editor metadata; it never contains executable world behavior.
local Settings={}
local function finite(n) return type(n)=="number" and n==n and math.abs(n)<math.huge end
local materials={Grass=true,Concrete=true,Sand=true,Slate=true,Ice=true,Mud=true,Asphalt=true,WoodPlanks=true}
local function vector(v,n,limit)
 assert(type(v)=="table" and #v==n,"Invalid world vector")
 for _,x in v do assert(finite(x) and math.abs(x)<=limit,"Invalid world vector value") end
end
function Settings.numbered(v)return #v.spawns==0 or v.spawns[1].slot~=nil end
function Settings.ready(v)
 local count=0;local seen={}
 for _,p in v.spawns do if type(p.slot)=="number" and p.slot%1==0 and p.slot>=1 and p.slot<=5 and not seen[p.slot] then seen[p.slot]=true;count+=1 end end
 assert(count==5 and #v.spawns==5,"World is not playable: five starting zones must be defined first ("..count.."/5 placed). Use Place start zone in the top toolbar. You can still Save this draft.")
 local slots={};for _,p in v.spawns do assert(type(p.slot)=="number" and p.slot%1==0 and p.slot>=1 and p.slot<=5 and not slots[p.slot],"Starting positions must be numbered 1–5 exactly once");slots[p.slot]=true end
end
function Settings.validate(v,draft)
 assert(type(v)=="table","Missing world settings")
 for _,n in {v.width,v.depth} do assert(finite(n) and n>=25 and n<=2000 and n%1==0,"World dimensions must be integers in [25,2000]") end
 assert(v.boundary==true,"World boundaries must be enabled")
 assert(type(v.ground)=="table" and materials[v.ground.material],"Invalid ground material")
 vector(v.ground.color,3,255); for _,c in v.ground.color do assert(c>=0,"Invalid ground color") end
 assert(type(v.spawns)=="table","Missing starting positions")
 local numbered=Settings.numbered(v)
 assert(if numbered then #v.spawns<=5 and (draft or #v.spawns==5) else #v.spawns==2,"Place all five tank starting positions (1–5) before playing")
 local seen={}
 for _,p in v.spawns do
  local key=if numbered then p.slot else p.tank
  assert((if numbered then type(key)=="number" and key%1==0 and key>=1 and key<=5 else key=="Boomer" or key=="Rattler") and not seen[key],"Duplicate/invalid tank starting position")
  seen[key]=true; vector(p.position,3,2000)
  assert(p.position[2]==0 and math.abs(p.position[1])<=v.width/2-(if numbered then 20 else 7) and math.abs(p.position[3])<=v.depth/2-(if numbered then 20 else 7),"Spawn outside playable ground")
  assert(finite(p.heading),"Invalid spawn heading")
 end
 for i,p in v.spawns do for j=1,i-1 do local a,b=p.position,v.spawns[j].position;assert((a[1]-b[1])^2+(a[3]-b[3])^2>=(if numbered then 40^2 else 14^2),"Tank starting areas overlap; numbered centers need 40 studs clearance") end end
 assert(type(v.zones)=="table" and #v.zones<=512,"Invalid environmental zones")
 for _,z in v.zones do
  assert(z.kind=="Water" or z.kind=="Mud","Unsupported environmental behavior")
  for _,k in {"x","z","rx","rz","speed"} do assert(finite(z[k]),"Invalid environmental region") end
  assert(z.rx>0 and z.rz>0 and z.rx<=2000 and z.rz<=2000 and z.speed>0 and z.speed<=1,"Invalid region limits")
 end
 return v
end
function Settings.blocked(position,body,radius)
 radius=radius or 6
 local p=body.state.position; local yaw=body.state.yaw or 0
 if body.bottom and body.top and (p.Y+body.bottom>=position.Y+6 or p.Y+body.top<=position.Y) then return false end
 local dx,dz=position.X-p.X,position.Z-p.Z; local c,s=math.cos(yaw),math.sin(yaw)
 return math.abs(c*dx-s*dz)<body.halfX+radius and math.abs(s*dx+c*dz)<body.halfZ+radius
end
function Settings.checkSpawns(v,bodies)
 for _,spawn in v.spawns do
  local p=Vector3.new(table.unpack(spawn.position))
  for _,body in bodies do assert(not Settings.blocked(p,body,if Settings.numbered(v) then 20 else 6),"Starting position "..tostring(spawn.slot or spawn.tank).." intersects solid "..tostring(body.id)) end
 end
end
function Settings.spawn(v,kind,index,bodies)
 local anchor
 local numbered=Settings.numbered(v)
 for _,p in v.spawns do if (numbered and p.slot==(index-1)%5+1) or (not numbered and p.tank==kind) then anchor=p end end
 assert(anchor,"Missing tank spawn")
 -- Additional local player pairs reuse configured headings and find free nearby
 -- positions deterministically; never move into an authored solid obstacle.
 for attempt=0,511 do
  local offset=if numbered then math.max(0,attempt-2)*14 elseif index==1 and attempt==0 then 0 else (index-1+attempt)*14
  local x=anchor.position[1]; local z=anchor.position[3]-offset
  if numbered and attempt<3 then
   local side=({0,-12,12})[attempt+1];local yaw=-math.rad(anchor.heading)
   x=anchor.position[1]+math.cos(yaw)*side;z=anchor.position[3]-math.sin(yaw)*side
  end
  if z< -v.depth/2+7 then z=anchor.position[3]; x+=offset end
  local p=Vector3.new(x,0,z)
  local clear=math.abs(x)<=v.width/2-7 and math.abs(z)<=v.depth/2-7
  if clear then for _,body in bodies do if Settings.blocked(p,body) then clear=false; break end end end
  if clear then return p,-math.rad(anchor.heading) end
 end
 error("No safe spawn available for "..kind)
end
return Settings
