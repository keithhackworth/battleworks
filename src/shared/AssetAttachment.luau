-- Rigid placement frame. Scale and resizing affect the asset, not its child offsets.
local Geometry=require(script.Parent.WorldObjectGeometry)
local Attachment={}
local function vector(values) return Vector3.new(table.unpack(values)) end
local function array(v) return {v.X,v.Y,v.Z} end
local function rotation(v) return CFrame.Angles(math.rad(v[1]),math.rad(v[2]),math.rad(v[3])) end
function Attachment.frame(position,angles)
 return CFrame.new(vector(position))*rotation(angles)
end
function Attachment.relative(parent,child)
 local relative=Attachment.frame(parent.position,parent.rotation):ToObjectSpace(Attachment.frame(child.position,child.rotation))
 return {parent=parent.id,position=array(relative.Position),rotation=Geometry.rotation(relative.RightVector,relative.UpVector,relative.LookVector*-1)}
end
function Attachment.apply(parent,child)
 local link=child.attachment
 local pose=Attachment.frame(parent.position,parent.rotation)*Attachment.frame(link.position,link.rotation)
 Attachment.setPose(child,pose)
end
function Attachment.setPose(child,pose)
 child.position=array(pose.Position)
 child.rotation=Geometry.rotation(pose.RightVector,pose.UpVector,pose.LookVector*-1)
end
function Attachment.valid(link)
 if type(link)~="table" or type(link.parent)~="string" or not link.parent:match("^[a-zA-Z][a-zA-Z0-9_-]*$") or #link.parent>64 then return false end
 for key in link do if key~="parent" and key~="position" and key~="rotation" then return false end end
 for _,key in {"position","rotation"} do
  local values=link[key]
  if type(values)~="table" or #values~=3 then return false end
  for i,n in values do
   if type(i)~="number" or i%1~=0 or i<1 or i>3 or type(n)~="number" or n~=n or math.abs(n)>8000 then return false end
  end
 end
 return true
end
function Attachment.follow(parentPivot,restParentPivot,childPivot)
 return parentPivot*restParentPivot:ToObjectSpace(childPivot)
end
return Attachment
