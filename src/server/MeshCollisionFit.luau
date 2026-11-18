-- Sample native mesh query geometry once per source template. Fitted cells are
-- conservative horizontal rectangles consumed by the existing rigid-body solver.
-- Intended for explicit irregular-rock profiles, never an automatic shrink rule.
local Visual=require(game.ReplicatedStorage.Shared.AssetGeometry)
local F={Resolution=8}
local cache=setmetatable({},{__mode="k"})
function F.sample(size,cast)
 local boxes={};local n=F.Resolution;local dx,dz=size.X/n,size.Z/n
 for ix=0,n-1 do for iz=0,n-1 do
  local bottom,top=math.huge,-math.huge
  for _,u in {.05,.5,.95} do for _,v in {.05,.5,.95} do
   local x,z=-size.X/2+(ix+u)*dx,-size.Z/2+(iz+v)*dz
   local lo,hi=cast(x,z)
   if lo and hi then bottom=math.min(bottom,lo);top=math.max(top,hi) end
  end end
  if top>bottom+.00001 then
   table.insert(boxes,{center={(-size.X/2+(ix+.5)*dx)/size.X,(bottom+top)/2/size.Y,(-size.Z/2+(iz+.5)*dz)/size.Z},size={1/n,(top-bottom)/size.Y,1/n}})
  end
 end end
 return boxes
end
function F.profile(model)
 if cache[model]~=nil then return cache[model] or nil end
 local world=Instance.new("WorldModel");world.Name="BattleWorksMeshMeasurement"
 local clone
 local ok,result=pcall(function()
  clone=model:Clone()
  for _,p in clone:GetDescendants() do
   if p:IsA("LuaSourceContainer") or p:IsA("Sound") or p:IsA("ParticleEmitter") or p:IsA("Trail") or p:IsA("Beam") then p:Destroy()
   elseif p:IsA("BasePart") then p.Anchored=true;p.CanCollide=false;p.CanTouch=false;p.CanQuery=Visual.visible(p) end
  end
  clone.Parent=world;world.Parent=workspace
  local frame,size=Visual.measure(clone)
  local params=RaycastParams.new();params.FilterType=Enum.RaycastFilterType.Include;params.RespectCanCollide=false;params.FilterDescendantsInstances=Visual.parts(clone)
  local up=frame.UpVector;local extent=size.Y+1
  return F.sample(size,function(x,z)
   local middle=frame:PointToWorldSpace(Vector3.new(x,0,z))
   local upper=world:Raycast(middle+up*extent,up*(-extent*2),params)
   local lower=world:Raycast(middle-up*extent,up*(extent*2),params)
   if not upper or not lower then return end
   local a,b=lower.Position-frame.Position,upper.Position-frame.Position
   local lo=a.X*up.X+a.Y*up.Y+a.Z*up.Z;local hi=b.X*up.X+b.Y*up.Y+b.Z*up.Z
   return lo,hi
  end)
 end)
 world:Destroy()
 if not ok or #result==0 then
  cache[model]=false
  warn("BattleWorks mesh collision fitting unavailable for "..model.Name.."; retaining full box. "..(if ok then "Native query returned no volume" else tostring(result)))
  return nil
 end
 cache[model]=result;return result
end
return F
