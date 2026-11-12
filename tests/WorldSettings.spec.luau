local Settings=require("WorldSettings")
local Contacts=require("VehicleContacts")
local count=0
local function check(v,m)count+=1;assert(v,m)end
local v={width=120,depth=90,boundary=true,ground={material="Grass",color={100,112,86}},zones={},spawns={{tank="Boomer",position={-22,0,20},heading=90},{tank="Rattler",position={22,0,20},heading=270}}}
check(Settings.validate(v)==v,"settings retain authored dimensions and spawns")
local block=Contacts.box("tree",Vector3.new(-22,4,20),2,2,-4,4,0)
check(not pcall(function()Settings.checkSpawns(v,{block})end),"actual runtime collider rejects unsafe spawn even if source bounds were wrong")
local p,yaw=Settings.spawn(v,"Boomer",1,{})
check(p.X==-22 and p.Z==20 and yaw==-math.pi/2,"configured initial pose and compass heading")
local shifted=Settings.spawn(v,"Boomer",2,{})
check(shifted.Z~=p.Z,"additional local pairs have deterministic separate spawn rows")
local safe=Settings.spawn(v,"Boomer",1,{block})
check(safe.Z~=20,"reset finds safe adjacent position if an object blocks anchor")
local bad=table.clone(v);bad.width=24;check(not pcall(function()Settings.validate(bad)end),"invalid dimensions")
bad=table.clone(v);bad.boundary=false;check(not pcall(function()Settings.validate(bad)end),"unsupported open boundaries explicit")
bad=table.clone(v);bad.zones={{kind="Lava",x=0,z=0,rx=2,rz=2,speed=.5}};check(not pcall(function()Settings.validate(bad)end),"unknown behavior rejected")
print(string.format("World settings suite passed: %d assertions",count))
