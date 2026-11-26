-- Compare automatically copied GLB surfaces with the loaded Roblox mesh.
-- Authored colliders and explicit per-asset alignments are handled by the catalog.
local Visual=require(game.ReplicatedStorage.Shared.AssetGeometry)
local Alignment={}

local function point(p,axes)
 local x,z=axes[1],axes[3]
 return {math.sign(x)*p[math.abs(x)],p[2],math.sign(z)*p[math.abs(z)]}
end

function Alignment.apply(profile,axes)
 local reflected=(if math.abs(axes[1])==3 then -1 else 1)*math.sign(axes[1]*axes[3])<0
 local function faces(source)
  local result={}
  for i,f in source do
   result[i]={point(f[1],axes),point(f[if reflected then 3 else 2],axes),point(f[if reflected then 2 else 3],axes)}
  end
  return result
 end
 local result=table.clone(profile)
 result.sourceSize={profile.sourceSize[math.abs(axes[1])],profile.sourceSize[2],profile.sourceSize[math.abs(axes[3])]}
 result.faces=faces(profile.faces)
 if profile.walls then result.walls=faces(profile.walls) end
 if profile.snap then
  result.snap={faces=faces(profile.snap.faces or {}),segments={}}
  for i,segment in profile.snap.segments or {} do
   result.snap.segments[i]={point(segment[1],axes),point(segment[2],axes)}
  end
 end
 return result
end

function Alignment.choose(profile,size,hit)
 local samples={}
 local stride=math.max(1,math.ceil(#profile.faces/96))
 for i=1,#profile.faces,stride do
  local a,b,c=table.unpack(profile.faces[i])
  table.insert(samples,{(a[1]+b[1]+c[1])/3,(a[2]+b[2]+c[2])/3,(a[3]+b[3]+c[3])/3})
 end
 local current,best,second,winner=0,-1,-1,nil
 for _,order in {{1,3},{3,1}} do
  local sourceSize={profile.sourceSize[order[1]],profile.sourceSize[2],profile.sourceSize[order[2]]}
  if not pcall(Visual.checkFaceProfile,size,{fit="faces",sourceSize=sourceSize}) then continue end
  for _,sx in {1,-1} do for _,sz in {1,-1} do
   local axes={sx*order[1],2,sz*order[2]}
   local score=0
   for _,p in samples do if hit(point(p,axes)) then score+=1 end end
   if axes[1]==1 and axes[3]==3 then current=score end
   if score>best then second,best,winner=best,score,axes else second=math.max(second,score) end
  end end
 end
 local total=#samples
 local details=string.format("current %d/%d, best %d/%d, runner-up %d/%d",current,total,math.max(best,0),total,math.max(second,0),total)
 if not winner or best<math.max(4,total*.22) then return nil,"Native collision alignment could not be verified ("..details..")" end
 if winner[1]==1 and winner[3]==3 then
  if best-second<math.max(3,total*.06) and current<total*.75 then
   return nil,"Native collision alignment is ambiguous ("..details..")"
  end
  return winner,details
 end
 local margin=math.max(3,total*.06)
 if best-second<margin or best-current<margin then
  if current>=total*.75 then return {1,2,3},details end
  return nil,"Native collision alignment is ambiguous ("..details..")"
 end
 return winner,details
end

function Alignment.inspect(model,profile)
 local world=Instance.new("WorldModel");world.Name="BattleWorksCollisionAlignment"
 local parent=model.Parent
 local parts=Visual.parts(model)
 local ok,axes,details=pcall(function()
  for _,p in parts do p.CanQuery=true end
  model.Parent=world;world.Parent=workspace
  local frame,size=Visual.measure(model)
  local params=RaycastParams.new()
  params.FilterType=Enum.RaycastFilterType.Include;params.FilterDescendantsInstances=parts;params.RespectCanCollide=false
  local reach=math.max(.0001,size.Y*.025)
  local up=frame.UpVector*reach
  return Alignment.choose(profile,size,function(p)
   local localPoint=Vector3.new(p[1]*size.X,p[2]*size.Y,p[3]*size.Z)
   return world:Raycast(frame:PointToWorldSpace(localPoint)+up,up*-2,params)~=nil
  end)
 end)
 model.Parent=parent
 for _,p in parts do p.CanQuery=false end
 world:Destroy()
 if not ok then return nil,"Native collision alignment probe failed: "..tostring(axes) end
 return axes,details
end

return Alignment
