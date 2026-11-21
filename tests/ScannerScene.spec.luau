local Scene=require("ScannerScene")
local Scanner=require("DirectionalScanner")
local Sim=require("TankSimulation")
local count=0
local function check(ok,message) assert(ok,message);count+=1 end
local function part(name,queryable)
 local p=Instance.new("Part")
 p.Name=name;p.CanQuery=queryable;p.CFrame=CFrame.new(0,2.5,-30);p.Size=Vector3.new(4,5,6)
 return p
end
local arena=Instance.new("Folder")
local world={}
local native=Instance.new("Terrain")
function world:FindFirstChild(name) if name=="Terrain" then return native end end
local floor=part("Floor",true)
local wall=part("wall",true)
local terrainOnly=part("raised ground",true)
terrainOnly:SetAttribute("ScannerTerrainOnly",true)
local visits=0
local getDescendants=arena.GetDescendants
function arena:GetDescendants() visits+=1;return getDescendants(self) end
arena.children={floor,wall,terrainOnly}
local tanks,targets={},{}
local scene=Scene.new(arena,world,floor,tanks,targets)
local function add(p)
 p.Parent=arena;table.insert(arena.children,p);arena.DescendantAdded:Fire(p)
end
local function remove(p)
 arena.DescendantRemoving:Fire(p);table.remove(arena.children,table.find(arena.children,p));p.Parent=nil
end
check(visits==0,"scene rebuild is lazy")
local geometry,records,terrain=scene:read()
check(visits==1 and #geometry==1 and geometry[1]==wall,"first scanner read collects regular obstacles")
check(#terrain==4 and table.find(terrain,wall) and table.find(terrain,terrainOnly) and table.find(terrain,floor) and table.find(terrain,native),"terrain receives ordinary geometry, terrain-only parts, floor and native Terrain")
local g,r,t=scene:read()
check(visits==1 and g==geometry and r==records and t==terrain,"repeated reads reuse arrays and skip arena traversal")
local particle=Instance.new("ParticleEmitter")
local decoration=part("decoration",false)
add(particle);add(decoration);remove(particle);scene:read()
check(visits==1 and not table.find(geometry,decoration) and not table.find(terrain,decoration),"irrelevant and nonqueryable descendants do not dirty the scene")
decoration.CanQuery=true;decoration:GetPropertyChangedSignal("CanQuery"):Fire();scene:read()
check(visits==2 and table.find(geometry,decoration),"CanQuery becoming true adds formerly excluded geometry")
decoration.CanQuery=false;decoration:GetPropertyChangedSignal("CanQuery"):Fire();scene:read()
check(visits==3 and not table.find(terrain,decoration),"CanQuery becoming false removes geometry")
remove(decoration);scene:read()
check(visits==3,"removing excluded geometry does not rebuild")
local added=part("new cover",true)
add(added);scene:read()
check(visits==4 and table.find(geometry,added) and table.find(terrain,added),"queryable addition invalidates both lists")
added:SetAttribute("ScannerTerrainOnly",true);added:GetAttributeChangedSignal("ScannerTerrainOnly"):Fire();scene:read()
check(visits==5 and not table.find(geometry,added) and table.find(terrain,added),"terrain-only changes update detection classification")
remove(added);scene:read()
check(visits==6 and not table.find(terrain,added),"queryable removal drops references on rebuild")

local source={state=Sim.new(Vector3.zero),hitbox=part("source",true)}
local other={kind="Boomer",playerName="Pilot",state=Sim.new(Vector3.new(0,0,-30)),hitbox=part("moving hitbox",true)}
local target=part("practice target",false)
for _,p in {source.hitbox,other.hitbox,target} do scene:markDynamic(p);add(p) end
tanks.source=source;tanks.other=other;targets[target]={}
scene:read()
check(visits==6 and records[other.hitbox].state==other.state and records[other.hitbox].id=="other","moving hitboxes and identities are collected outside static rebuilds")
target.CanQuery=true;scene:read()
check(visits==6 and table.find(geometry,target) and table.find(terrain,target),"practice target respawn is visible immediately")
remove(target);scene:read()
check(visits==6 and not table.find(geometry,target),"detached practice target no longer participates even before its record is dropped")

-- Use the actual scanner path with a controlled live broad phase and ray hit.
local hitbox=other.hitbox
function world:GetPartBoundsInRadius(_,_,params)
 return if table.find(params.FilterDescendantsInstances,hitbox) then {hitbox} else {}
end
function world:Raycast(origin,direction,params)
 if direction.Z>=0 or not table.find(params.FilterDescendantsInstances,hitbox) then return nil end
 local scale=(hitbox.CFrame.Position.Z+hitbox.Size.Z/2-origin.Z)/direction.Z
 local position=origin+direction*scale
 if math.abs(position.X)>2 or math.abs(position.Y-2.5)>2.5 then return nil end
 return {Instance=hitbox,Position=position}
end
local scanner=Scanner.new(world,function()return scene:read()end)
local first=assert(scanner:execute(source,0,1)).value
check(first.type=="tank" and first.player=="Pilot.Boomer#other" and math.abs(first.distance-27)<.01,"cached scene preserves the detection of a visible tank")
other.state=Sim.new(Vector3.new(0,0,-45))
hitbox.CFrame=CFrame.new(0,2.5,-45);other.playerName="Renamed"
local second=assert(scanner:execute(source,0,2)).value
check(second.player=="Renamed.Boomer#other" and math.abs(second.distance-42)<.01 and records[hitbox].state==other.state and visits==6,"the next scan uses live pose, identity and state without rebuilding")
hitbox.CanQuery=false;scene:read()
check(not table.find(geometry,hitbox) and not table.find(terrain,hitbox) and visits==6,"dead hitboxes disappear from queries without a static rebuild")
tanks.other=nil;remove(hitbox);scene:read()
check(not records[hitbox] and visits==6,"retired hitboxes and records are dropped without a rebuild")
print("Scanner scene cache passed: "..count.." assertions")
