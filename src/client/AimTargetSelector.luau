-- Cursor interpretation only. No movement, damage, or hit claims.
local Selector={Distance=1500,VerticalSearch=512}
local names={Floor=true,WestBank=true,EastBank=true,WestSlope=true,WestPlateau=true,NorthLand=true,SouthLand=true,Bridge=true,Rock=true,FallenLog=true,TreeTrunk=true,Boundary=true,Target=true}
function Selector.eligible(part,ownId)
 if not part then return false end
 if part:IsA("Terrain")then return true end
 if part.CanQuery==false then return false end
 local id=part:GetAttribute("TankId")
 if id then return tostring(id)~=tostring(ownId)end
 if part:GetAttribute("WorldObjectId")then
  local model=part.Parent
  while model do
   local solid=model:GetAttribute("Solid")
   if solid~=nil then return solid==true end
   model=model.Parent
  end
  return false
 end
 return part.CanCollide==true or names[part.Name]==true or part:IsA("Terrain")
end
function Selector.cast(world,arena,origin,direction,ownId)
 if not arena or not world.Raycast then return nil end
 local params=RaycastParams.new();params.FilterType=Enum.RaycastFilterType.Include
 local include={arena};local terrain=world:FindFirstChild("Terrain");if terrain then table.insert(include,terrain)end
 params.FilterDescendantsInstances=include;params.IgnoreWater=false
 local remaining=direction.Magnitude;local unit=direction.Unit
 -- Queryable non-solid destructibles/own hitbox may obscure the ray. Walk
 -- through them without admitting arbitrary Workspace decorations as targets.
 local excluded={}
 for _=1,24 do
  local hit=world:Raycast(origin,unit*remaining,params)
  if not hit then return nil end
  if Selector.eligible(hit.Instance,ownId)then return hit end
  -- Rebuild an include list only on a rejected hit, so thin/compound own
  -- geometry cannot trap subsequent rays inside the same part.
  excluded[hit.Instance]=true
  include={}
  for _,p in arena:GetDescendants()do if p:IsA("BasePart")and not excluded[p]then table.insert(include,p)end end
  if terrain then table.insert(include,terrain)end
  params.FilterDescendantsInstances=include
 end
 return nil
end
function Selector.select(world,arena,ray,ownId)
 local hit=Selector.cast(world,arena,ray.Origin,ray.Direction*Selector.Distance,ownId)
 if not hit then return ray.Origin+ray.Direction.Unit*Selector.Distance end
 local ground=not hit.Instance:GetAttribute("TankId")and hit.Normal and hit.Normal.Y>.7
 if ground then
  local above=Selector.cast(world,arena,hit.Position+Vector3.new(0,.05,0),Vector3.new(0,Selector.VerticalSearch,0),ownId)
  if above then return above.Position end
 end
 return hit.Position
end
return Selector
