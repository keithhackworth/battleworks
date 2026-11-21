local Contacts=require("VehicleContacts")
local Original=require("ContactsBaseline")
local Reference=require("ContactsBaselineStats")
local Motion=require("VehicleMotion")
local DT=1/60
local EPSILON=1e-7
local checks=0
local function check(ok,message) assert(ok,message);checks+=1 end
local function tank(id,x,z,vx,vz,yaw,omega,y)
 local state={position=Vector3.new(x,y or 0,z),yaw=yaw or 0}
 Motion.configure(state,10+id%3,20+id%5)
 Motion.setVelocity(state,Vector3.new(vx or 0,0,vz or 0))
 Motion.setYawVelocity(state,omega or 0)
 return Contacts.body(string.format("tank:%02d",id),state,{CollisionWidth=4,CollisionLength=6,HitboxHeight=1,Hitbox=Vector3.new(4,2,6)})
end
local function box(id,x,z,hx,hz,yaw,y)
 return Contacts.box(id,Vector3.new(x,y or 0,z),hx,hz,-2,3,yaw)
end
local function plane(id,x,nx,nz)
 local p=box(id,0,0,1,1)
 p.plane={nx=nx,nz=nz,offset=x}
 return p
end
local function obstacleField()
 local statics={}
 for i=1,63 do
  statics[i]=box(string.format("static:%02d",i),(i%9)*27-110,math.floor((i-1)/9)*30-90,2+i%4,2+i%3,i*.07)
 end
 return statics
end
local scenarios={
 {"15 separated + 63",function()
  local bodies={}
  for i=1,15 do bodies[i]=tank(i,(i%5)*35-70,math.floor((i-1)/5)*35+135,8,-4,i*.1) end
  return bodies,obstacleField()
 end},
 {"15 clustered + 63",function()
  local bodies={}
  for i=1,15 do bodies[i]=tank(i,(i%5)*3.8,math.floor((i-1)/5)*5.5,3-i%6,i%7-3,i*.03) end
  return bodies,obstacleField()
 end},
 {"rapid near obstacles",function()
  local bodies,statics={},obstacleField()
  for i=1,15 do
   local obstacle=statics[i+10].state.position
   bodies[i]=tank(i,obstacle.X-13,obstacle.Z+3,600,25,i*.04,i%4)
  end
  return bodies,statics
 end},
 {"rotating corners",function()
  local bodies,statics={},obstacleField()
  for i=1,6 do
   bodies[i]=tank(i,i*13,3.2,25,-16,.55+i*.04,17+i)
   table.insert(statics,box("corner:"..i,i*13+3,-1,1.1,1.5,.3))
  end
  table.insert(statics,plane("wall:north",-1,0,1))
  return bodies,statics
 end},
 {"simultaneous contacts",function()
  return {tank(1,-5,0,100,0),tank(2,-.7,0,0,0),tank(3,3.5,0,-110,0),tank(4,0,5,4,-40)},
   {box("wall:right",5,1,1,8),box("wall:left",-8,-2,.5,8,.15),plane("wall:north",-3,0,1)}
 end},
 {"high-speed CCD chain",function()
  return {tank(1,-18,0,3000,0),tank(2,0,0,0,0)},
   {box("thin wall",15,0,.2,15),box("grazing corner",8,6,.3,.4,.27)}
 end},
 {"correction crosses bounds",function()
  return {tank(1,0,0,0,0)}, {plane("a:boundary",12,1,0),box("z:cover",16.5,0,2,3)}
 end},
 {"oblique polygon and grazing",function()
  return {tank(1,-11,4.9,700,0,.12,4),tank(2,-8,0,90,0,-.55),tank(3,0,0,0,0,0,0,8)},
   {assert(Contacts.polygon("oblique", {Vector3.new(-1,0,-4),Vector3.new(2,0,0),Vector3.new(-.5,0,4)},-1,3)),
    box("grazing",3,5,1,1,.15)}
 end},
}
local function near(a,b) return math.abs(a-b)<=EPSILON end
local function compare(a,b,name)
 for i,body in a do
  local s,t=body.state,b[i].state
  check((s.position-t.position).Magnitude<=EPSILON,name.." position")
  check((s.linearVelocity-t.linearVelocity).Magnitude<=EPSILON,name.." linear velocity")
  check((s.angularVelocity-t.angularVelocity).Magnitude<=EPSILON,name.." angular velocity")
  check(near(s.yaw,t.yaw) and near(s.motionYawTravel or 0,t.motionYawTravel or 0),name.." yaw and travel")
  check(near(s.motionForwardTravel or 0,t.motionForwardTravel or 0),name.." forward travel")
  check(((s.motionCorrection or Vector3.zero)-(t.motionCorrection or Vector3.zero)).Magnitude<=EPSILON,name.." positional correction")
  check(s.motionContactLimited==t.motionContactLimited,name.." event cap")
 end
end
local function penetration(bodies,statics)
 local depth=0
 for i,a in bodies do
  for j=i+1,#bodies do depth=math.max(depth,Reference.penetration(a,bodies[j])) end
  for _,b in statics do depth=math.max(depth,Reference.penetration(a,b)) end
 end
 return depth
end
local function measure(make,solver)
 local samples={}
 for i=1,85 do
  local bodies,statics=make()
  local start=os.clock()
  solver.solve(bodies,statics,DT)
  local elapsed=os.clock()-start
  if i>5 then table.insert(samples,elapsed*1000) end
 end
 table.sort(samples)
 local sum=0; for _,sample in samples do sum+=sample end
 return sum/#samples,samples[math.ceil(#samples*.95)],samples[#samples]
end
for _,scenario in scenarios do
 local name,make=scenario[1],scenario[2]
 local a,x=make();local b,y=make()
 local old,new={},{}
 Reference.solve(a,x,DT,old);Contacts.solve(b,y,DT,new)
 compare(a,b,name)
 check(near(penetration(a,x),penetration(b,y)),name.." residual penetration")
 check(old.contacts==new.contacts,name.." contact counts")
 check(new.correctionPasses<=old.correctionPasses,name.." bounded correction passes")
 if name=="15 separated + 63" then
  check(new.candidateChecks+new.pairVisits<old.pairVisits/2,"separated field avoids most pair checks")
 elseif name=="correction crosses bounds" then
  check(new.correctionRebuilds>0,"a correction beyond the reserved bound rebuilds the static list within its pass")
 elseif name=="high-speed CCD chain" then
  check(new.rebuilds>#b,"impact transfer expands a subsequent sweep")
  check(b[2].state.position.X<13,"transferred high-speed motion cannot tunnel through the wall")
 end
 if benchmarkContacts then
  local oldMean,oldP95,oldMax=measure(make,Original)
  local newMean,newP95,newMax=measure(make,Contacts)
  print(string.format("CONTACT BENCH | %s | ms mean/p95/max %.3f/%.3f/%.3f -> %.3f/%.3f/%.3f | pairs %d -> %d (%d build + %d visit) | narrow %d -> %d | points %d -> %d | correction passes %d -> %d | SAT axis tables %d -> 0",
   name,oldMean,oldP95,oldMax,newMean,newP95,newMax,old.pairVisits,new.candidateChecks+new.pairVisits,new.candidateChecks,new.pairVisits,
   old.narrowTests,new.narrowTests,old.contacts,new.contacts,old.correctionPasses,new.correctionPasses,old.boxSatTests*5))
 end
 for _=1,4 do
  Original.solve(a,x,DT);Contacts.solve(b,y,DT)
  compare(a,b,name.." repeated step")
 end
end
-- Local deterministic LCG. The fixtures interleave the IDs to exercise the
-- original tank/static ordering and vary starting penetration, yaw, and speed.
local seed=437
local function random()
 seed=(seed*48271)%2147483647
 return seed/2147483647
end
for _=1,28 do
 local a,b,x,y={},{},{},{}
 for i=1,5 do
  local px,pz,vx,vz,yaw,w=random()*24-12,random()*24-12,random()*1800-900,random()*1800-900,random()*7,random()*24-12
  a[i]=tank(i,px,pz,vx,vz,yaw,w);b[i]=tank(i,px,pz,vx,vz,yaw,w)
 end
 for i=1,10 do
  local px,pz,hx,hz,yaw=random()*36-18,random()*36-18,random()*4+.25,random()*4+.25,random()*7
  x[i]=box("fixture:"..i,px,pz,hx,hz,yaw);y[i]=box("fixture:"..i,px,pz,hx,hz,yaw)
 end
 Original.solve(a,x,DT);Contacts.solve(b,y,DT)
 compare(a,b,"seeded contact scene")
 check(near(penetration(a,x),penetration(b,y)),"seeded residual penetration")
end
print("Vehicle contact solver parity passed: "..checks.." assertions")
