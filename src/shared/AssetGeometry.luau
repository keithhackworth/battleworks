-- Visual/selection bounds only. Collision profiles and native surface queries
-- remain separate; mesh vertices are not inferred from a bounding rectangle.
local A={}
function A.isCollisionNode(name)
 return type(name)=="string" and string.lower(string.sub(name,1,10))=="collision_"
end
function A.visible(part)
 return part:IsA("BasePart") and (part.Transparency or 0)<1 and part.Name~="WorldObstacleHitbox" and not (part.GetAttribute and part:GetAttribute("BattleWorksIgnoreBounds"))
end
function A.parts(model)
 local parts={};for _,p in model:GetDescendants() do if A.visible(p) then table.insert(parts,p) end end;return parts
end
function A.checkFaceProfile(size,collider,stretch)
 if collider.fit~="faces" then return end
 local source=collider.sourceSize;assert(type(source)=="table" and #source==3,"Missing GLB profile dimensions")
 local scale=size.X/source[1]/(stretch and stretch[1] or 1)
 for i,n in {size.X,size.Y,size.Z}do assert(type(source[i])=="number" and source[i]>0 and math.abs(n/source[i]/(stretch and stretch[i] or 1)/scale-1)<.01,"GLB collision profile dimensions do not match native model")end
end
local function dot(a,b)return a.X*b.X+a.Y*b.Y+a.Z*b.Z end
function A.measure(model)
 local frame,size=model:GetBoundingBox()
 local parts=A.parts(model);assert(#parts>0,"Asset has no visible BasePart geometry")
 local low={math.huge,math.huge,math.huge};local high={-math.huge,-math.huge,-math.huge};local count=0
 local axes={frame.RightVector,frame.UpVector,frame.LookVector*-1}
 for _,p in parts do if p.Size and p.CFrame then
  count+=1
  for _,x in {-1,1} do for _,y in {-1,1} do for _,z in {-1,1} do
   local point=p.CFrame:PointToWorldSpace(Vector3.new(p.Size.X*x/2,p.Size.Y*y/2,p.Size.Z*z/2))-frame.Position
   for i=1,3 do local n=dot(point,axes[i]);low[i]=math.min(low[i],n);high[i]=math.max(high[i],n) end
  end end end
 end end
 -- Compatibility for minimal native-model adapters lacking individual part data.
 if count==0 then return frame,size end
 local center=Vector3.new((low[1]+high[1])/2,(low[2]+high[2])/2,(low[3]+high[3])/2)
 return frame*CFrame.new(center),Vector3.new(high[1]-low[1],high[2]-low[2],high[3]-low[3])
end
return A
