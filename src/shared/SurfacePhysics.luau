-- Independent contact fields. Rendering/terrain kind does not select physics.
local S={}
S.Profiles=table.freeze({
 Normal=table.freeze({staticFriction=16,kineticFriction=12,resistance=1}),
 Ice=table.freeze({staticFriction=0.025,kineticFriction=0.015,resistance=0.02}),
})
local function finite(n) return type(n)=="number" and n==n and math.abs(n)<math.huge end
local function validate(p)
 assert(finite(p.staticFriction) and finite(p.kineticFriction) and p.staticFriction>=p.kineticFriction and p.kineticFriction>=0,"Invalid static/kinetic friction")
 assert(finite(p.resistance) and p.resistance>=0,"Invalid surface resistance")
 assert(p.passiveGrip==nil or (finite(p.passiveGrip) and p.passiveGrip>=0 and p.passiveGrip<=1),"Invalid passive grip fraction")
end
function S.validateRegion(r)
 assert(type(r.id)=="string" and #r.id>0 and finite(r.priority or 0),"Region needs stable ID/priority")
 assert(finite(r.x) and finite(r.z) and finite(r.rx) and finite(r.rz) and r.rx>0 and r.rz>0,"Invalid region bounds")
 assert(r.shape==nil or r.shape=="ellipse" or r.shape=="box","Unsupported region shape")
 assert(finite(r.transition or 0) and (r.transition or 0)>=0,"Invalid region transition")
 validate(r.surface)
end
-- Prepare once, outside simulation. Stable sorting avoids map insertion order
-- affecting floating-point blends. Higher priorities overlay lower priorities.
function S.prepare(regions)
 local out,seen={},{}
 for _,r in regions or {} do
  S.validateRegion(r); assert(not seen[r.id],"Duplicate region ID"); seen[r.id]=true
  local c=table.clone(r); c.surface=table.freeze(table.clone(r.surface)); table.insert(out,table.freeze(c))
 end
 table.sort(out,function(a,b) return if (a.priority or 0)==(b.priority or 0) then a.id<b.id else (a.priority or 0)<(b.priority or 0) end)
 return table.freeze(out)
end
function S.weight(r,x,z)
 local dx,dz=math.abs(x-r.x),math.abs(z-r.z)
 local edge
 if r.shape=="box" then edge=math.min(r.rx-dx,r.rz-dz)
 else edge=(1-math.sqrt((dx/r.rx)^2+(dz/r.rz)^2))*math.min(r.rx,r.rz) end
 if edge<0 then return 0 end
 if (r.transition or 0)==0 then return 1 end
 local t=math.clamp(edge/r.transition,0,1); return t*t*(3-2*t)
end
function S.contact(prepared,position,yaw,chassis)
 local a,b,c,d=0,0,0,0; local s,co=math.sin(yaw),math.cos(yaw)
 for _,side in {-1,1} do for _,endSign in {-1,1} do
  local x=side*chassis.ContactWidth/2; local z=endSign*chassis.ContactLength/2
  local sa,sb,sc,sd=S.sample(prepared,position.X+co*x+s*z,position.Z-s*x+co*z)
  a+=sa/4; b+=sb/4; c+=sc/4; d+=sd/4
 end end
 return a,b,c,d
end
function S.sample(prepared,x,z,base)
 base=base or S.Profiles.Normal
 local a,b,c,d=base.staticFriction,base.kineticFriction,base.resistance,base.passiveGrip or 1
 local i=1
 while prepared and i<=#prepared do
  local priority=prepared[i].priority or 0; local sum,sa,sb,sc,sd,coverage=0,0,0,0,0,0
  while i<=#prepared and (prepared[i].priority or 0)==priority do
   local r=prepared[i]; local w=S.weight(r,x,z); local p=r.surface
   sum+=w; sa+=w*p.staticFriction; sb+=w*p.kineticFriction; sc+=w*p.resistance; sd+=w*(p.passiveGrip or 1); coverage=math.max(coverage,w); i+=1
  end
  if sum>0 then a+=(sa/sum-a)*coverage; b+=(sb/sum-b)*coverage; c+=(sc/sum-c)*coverage; d+=(sd/sum-d)*coverage end
 end
 return a,b,c,d
end
return S
