-- Cosmetic ground markings shared by the private editor and the live arena.
-- No collision, ray queries, hit claims or simulation bodies in live play.
local Areas={}
local patterns={"bc","abged","abgcd","fgbc","afgcd"}
function Areas.make(parent,spawn,editable,height)
 local model=Instance.new("Model");model.Name="StartingPosition"..tostring(spawn.slot);model.Parent=parent
 model:SetAttribute("EditorObjectId",if editable then spawn.id else nil)
 local frame=CFrame.new(spawn.position[1],(height or 0)+.035,spawn.position[3])*CFrame.Angles(0,-math.rad(spawn.heading),0)
 local function piece(name,x,z,w,d,color,y,angle)
  local p=Instance.new("Part");p.Name=name;p.Anchored=true;p.CanCollide=false;p.CanTouch=false;p.CanQuery=false
  p.Size=Vector3.new(w,.025,d);p.CFrame=frame*CFrame.new(x,y or 0,z)*CFrame.Angles(0,angle or 0,0);p.Color=color;p.Material=Enum.Material.SmoothPlastic;p.Parent=model
  return p
 end
 local yellow=Color3.fromRGB(250,196,45);local black=Color3.fromRGB(30,32,33);local white=Color3.fromRGB(250,250,235)
 local base=piece("CautionArea",0,0,36,16,black);base.CanQuery=editable or false
 for i=-15,15 do
  local offset=i*1.6;local a=math.max(-17.7,-7.7-offset);local b=math.min(17.7,7.7-offset)
  if b>a then piece("CautionStripe",(a+b)/2,(a+b)/2+offset,.65,(b-a)*math.sqrt(2),yellow,.03,math.pi/4) end
 end
 for _,x in {-6,6} do piece("BayDivider",x,0,.15,15.5,white,.04) end
 piece("NumberPanel",0,0,5.6,7,black,.06)
 local segments={a={0,-2,2.5,.5},b={1.25,-1,.5,2},c={1.25,1,.5,2},d={0,2,2.5,.5},e={-1.25,1,.5,2},f={-1.25,-1,.5,2},g={0,0,2.5,.5}}
 local pattern=patterns[spawn.slot] or ""
 for i=1,#pattern do local s=segments[pattern:sub(i,i)];piece("Number"..spawn.slot,s[1],s[2],s[3],s[4],white,.1) end
 piece("Heading",0,-4.2,.3,1.4,white,.1)
 piece("HeadingLeft",-.35,-4.65,.25,1,white,.1,-math.pi/4)
 piece("HeadingRight",.35,-4.65,.25,1,white,.1,math.pi/4)
 return model
end
return Areas
