-- Authored settings and pure contact/audio activation rules.
local Sound={}
Sound.Asset="Builtin/BW_sound_block"
Sound.Modes=table.freeze({"Always","Entry","Exit","Occupied"})
Sound.Playback=table.freeze({"Once","Loop","Repeat"})
Sound.RollOff=table.freeze({"Inverse","Linear","LinearSquare","InverseTapered"})
Sound.Filters=table.freeze({"Tanks","Moving","Both","Specific","Terrain"})
Sound.Origins=table.freeze({"Block","Trigger"})
Sound.Default=table.freeze({effect="",activation="Always",playback="Loop",interval=3,cooldown=.5,volume=.6,speed=1,minDistance=8,maxDistance=100,rollOff="InverseTapered",filter="Tanks",origin="Block"})
local limits={interval={.1,3600},cooldown={0,3600},volume={0,10},speed={.1,4},minDistance={0,1000},maxDistance={1,2000}}
function Sound.validate(value)
 assert(type(value)=="table","Invalid Sound Block settings")
 for key in value do assert(Sound.Default[key]~=nil or key=="targets","Unknown Sound Block setting") end
 assert(type(value.effect)=="string" and #value.effect<=160 and (value.effect=="" or value.effect:match("^[%w][%w_-]*$")),"Invalid sound catalog key")
 assert(table.find(Sound.Modes,value.activation) and table.find(Sound.Playback,value.playback) and table.find(Sound.RollOff,value.rollOff),"Invalid Sound Block mode")
 for key,range in limits do
  local n=value[key]
  assert(type(n)=="number" and n>=range[1] and n<=range[2],"Invalid Sound Block "..key)
 end
 assert(table.find(Sound.Filters,value.filter or "Tanks") and table.find(Sound.Origins,value.origin or "Block"),"Invalid trigger filter or origin")
 if value.targets~=nil then
  assert(type(value.targets)=="table" and #value.targets<=32,"Select up to 32 trigger assets")
  local seen={}
  for i,id in value.targets do
   assert(type(i)=="number" and i%1==0 and i>=1 and i<=#value.targets and type(id)=="string" and #id<=64 and id:match("^[a-zA-Z][a-zA-Z0-9_-]*$") and not seen[id],"Invalid trigger asset reference")
   seen[id]=true
  end
 end
 assert(value.minDistance<=value.maxDistance,"Minimum audible distance exceeds maximum")
end
local function radius(axis,tank,body)
 return math.abs(axis:Dot(tank.RightVector))*body.halfX+math.abs(axis:Dot(tank.UpVector))*(body.top-body.bottom)/2+math.abs(axis:Dot(tank.LookVector))*body.halfZ
end
local function sweep(frame,half,subject,body,start,finish,padding)
 local a,b,c=frame.RightVector,frame.UpVector,frame.LookVector
 local x,y,z=subject.RightVector,subject.UpVector,subject.LookVector
 local travel=finish-start
 local enter,leave=0,1
 local function separates(axis)
  local h=math.abs(axis:Dot(a))*half.X+math.abs(axis:Dot(b))*half.Y+math.abs(axis:Dot(c))*half.Z+
   radius(axis,subject,body)+padding*axis.Magnitude+1e-6
  local offset,distance=axis:Dot(start),axis:Dot(travel)
  if math.abs(distance)<1e-8 then return math.abs(offset)>h end
  local first,last=(-h-offset)/distance,(h-offset)/distance
  enter=math.max(enter,math.min(first,last));leave=math.min(leave,math.max(first,last))
  return enter>leave
 end
 if separates(a) or separates(b) or separates(c) or separates(x) or separates(y) or separates(z) then return false end
 return not (separates(a:Cross(x)) or separates(a:Cross(y)) or separates(a:Cross(z)) or separates(b:Cross(x)) or separates(b:Cross(y)) or separates(b:Cross(z)) or separates(c:Cross(x)) or separates(c:Cross(y)) or separates(c:Cross(z)))
end
function Sound.tankFrames(body)
 local state=body.state
 local offset=Vector3.new(0,(body.top+body.bottom)/2,0)
 return CFrame.new((state.motionStepStart or state.position)+offset)*CFrame.Angles(0,state.motionYawStart or state.yaw,0),
  CFrame.new(state.position+offset)*CFrame.Angles(0,state.yaw,0)
end
function Sound.overlap(before,after,half,body,orbitalPadding)
 local old,tank=body.before,body.after
 if not old then old,tank=Sound.tankFrames(body) end
 local finish=tank.Position-after.Position
 local inside=sweep(after,half,tank,body,finish,finish,0)
 if inside then return true,true end
 if old==tank and before==after then return false,false end
 local move=(before.RightVector-after.RightVector).Magnitude+(before.UpVector-after.UpVector).Magnitude
 local turn=(old.RightVector-tank.RightVector).Magnitude+(old.UpVector-tank.UpVector).Magnitude
 local padding=move*half.Magnitude+turn*math.sqrt(body.halfX^2+body.halfZ^2+((body.top-body.bottom)/2)^2)+(orbitalPadding or 0)
 return false,sweep(before,half,old,body,old.Position-before.Position,finish,padding)
end
function Sound.accepts(config,parent,blockId,subjectId,isAsset,isMoving)
 if isAsset and (subjectId==parent or subjectId==blockId) then return false end
 local filter=config.filter or "Tanks"
 if filter=="Specific" then return isAsset and table.find(config.targets or {},subjectId)~=nil end
 return if isAsset then isMoving and (filter=="Moving" or filter=="Both") else filter=="Tanks" or filter=="Both"
end
local function groundContact(frame,half,height,clearance)
 -- Face centers and edge midpoints can catch a ridge that misses all corners.
 for x=-1,1 do for y=-1,1 do for z=-1,1 do
  if x==0 and y==0 and z==0 then continue end
  local point=frame:PointToWorldSpace(Vector3.new(x*half.X,y*half.Y,z*half.Z))
  local ground=height(point)
  if ground~=nil and point.Y<=ground+clearance then return true end
 end end end
 return false
end
function Sound.terrainOverlap(before,after,half,height,occupied,orbitalPadding)
 if groundContact(after,half,height,if occupied then .08 else .025) then return true,true end
 if before==after then return false,false end
 local turn=(before.RightVector-after.RightVector).Magnitude+(before.UpVector-after.UpVector).Magnitude
 local travel=(before.Position-after.Position).Magnitude+turn*half.Magnitude+(orbitalPadding or 0)
 local samples=math.clamp(math.ceil(travel/.25),2,12)
 for i=1,samples-1 do
  if groundContact(before:Lerp(after,i/samples),half,height,.025) then return false,true end
 end
 return false,false
end
function Sound.transition(config,tracker,entered,exited,occupied,now)
 local mode=config.activation
 local pulse=if mode=="Entry" then entered elseif mode=="Exit" then exited elseif mode=="Occupied" then (occupied or (entered and exited)) and not tracker.occupied else false
 if pulse and now>=tracker.nextPlay then
  tracker.nextPlay=now+(if mode=="Always" then 0 else config.cooldown)
  tracker.started=true
 else pulse=false end
 tracker.occupied=occupied
 local active=mode=="Always" or (tracker.started and (if mode=="Exit" then not occupied else occupied))
 if not active then tracker.started=false end
 return active,pulse
end
function Sound.playbackAction(activation,mode,active,now,nextPlay,played)
 if not active then return "Idle" end
 if mode=="Loop" then return "Loop" end
 if mode=="Repeat" and now>=nextPlay then return "Repeat" end
 if mode=="Once" and activation=="Always" and not played then return "Once" end
 return "Idle"
end
return Sound
