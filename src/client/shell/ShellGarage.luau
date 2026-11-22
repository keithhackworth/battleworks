local View=require(script.Parent.ShellView)
local UIS=game:GetService("UserInputService")
local Shared=game.ReplicatedStorage.Shared
local Hardware=require(Shared.BWChassis)
local Components=require(Shared.VehicleComponents)
local Timing=require(Shared.WeaponTiming)
local Screen={}
local labels={drivetrain="Drivetrain",turret="Turret",weapon="Weapon",scanners="Scanner array",retaliatorMesh=Hardware.RetaliatorMesh.DisplayName}
local meshMinimum=Hardware.RetaliatorMesh.Properties.MinimumAllocation
local categories=table.clone(Hardware.Categories)
table.insert(categories,"retaliatorMesh")
local tradeoffs={weapon={"Projectile Speed","Reload / Fire Rate"},scanners={"Cone Width","Range"}}
local function label(parent,text,x,y,width,height)
 local item=Instance.new("TextLabel")
 item.BackgroundTransparency=1;item.Text=text;item.Font=Enum.Font.GothamMedium
 item.TextColor3=Color3.fromRGB(232,239,223);item.TextSize=13
 item.Position=UDim2.new(x,0,0,y);item.Size=UDim2.new(width,0,0,height);item.Parent=parent
 return item
end
local function slider(parent,y)
 local track=Instance.new("Frame")
 track.Name="Slider";track.BackgroundColor3=Color3.fromRGB(53,70,74)
 track.Position=UDim2.new(.05,0,0,y);track.Size=UDim2.new(.9,0,0,16);track.Active=true;track.Parent=parent
 local railCorner=Instance.new("UICorner");railCorner.CornerRadius=UDim.new(0,6);railCorner.Parent=track
 local thumb=Instance.new("Frame")
 thumb.Name="Thumb";thumb.AnchorPoint=Vector2.new(.5,.5);thumb.Size=UDim2.fromOffset(12,20)
 thumb.BackgroundColor3=Color3.fromRGB(240,158,69);thumb.Parent=track
 local thumbCorner=Instance.new("UICorner");thumbCorner.CornerRadius=UDim.new(0,4);thumbCorner.Parent=thumb
 local tooltip=label(parent,"",0,y-24,.76,22)
 tooltip.BackgroundColor3=Color3.fromRGB(12,22,25);tooltip.BackgroundTransparency=0
 tooltip.ZIndex=5;tooltip.Visible=false
 return {track=track,thumb=thumb,tooltip=tooltip}
end
local function updateSlider(slider,value)
 slider.thumb.Position=UDim2.fromScale(value,.5)
 slider.tooltip.Position=UDim2.new(math.clamp(.05+.9*value-.38,0,.24),0,0,slider.tooltip.Position.Y.Offset)
end
local function readout(config,profile,name)
 local p=Hardware.effective(config,name,profile)
 if name=="drivetrain" then
  local forward,reverse,turn=Hardware.driveRates(profile,p)
  return string.format("Forward %.1f | Reverse %.1f studs/sec",forward,reverse),string.format("Rated turn %.1f°/sec before terrain",math.deg(turn))
 elseif name=="turret" then
  return string.format("Yaw / pitch %.1f°/sec",math.deg(profile.Turret.TraverseSpeed*p))
 elseif name=="weapon" then
  local _,windup,speed=Hardware.weaponStats(config,profile)
  if p<=0 then return "Weapon disabled" end
  local interval=if profile.Weapon.Operation=="Heat" then "Interval" else "Reload"
  local detail=if profile.Weapon.Operation=="Heat" then string.format("Overheat cooldown %.2f sec",profile.Weapon.OverheatCooldown)
   else string.format("Windup %.2f sec",Timing.preparation(profile.Weapon,windup))
  return string.format("Projectile %.1f studs/sec | %s %.2f sec",speed,interval,Timing.interval(profile.Weapon,p)),detail
 elseif name=="retaliatorMesh" then
  return if p>0 then "Operational • OnDamageTaken" else string.format("Inactive • requires %.0f%% bus",meshMinimum)
 end
 local angle=next(profile.Sensors)
 local lens=angle and config.devices["sensor"..angle]
 if not lens or lens.allocation<=0 then return "Scanner array disabled" end
 local power=Hardware.effective(config,"sensor"..angle,profile)
 return string.format("Cone %.1f° | Range %.1f studs",lens.coneWidth,lens.range*lens.distancePercent/100),string.format("BW acquisition %.2f sec per lens",lens.acquisition/power)
end

function Screen.new(context)
 local inWorld=context.inWorld==true
 local view=View.new(context,if inWorld then "Tank Configuration" else "Garage",
  if inWorld then "Stop in the bay to swap equipment. Tune how this tank uses its shared bus." else "Allocate up to 100% of the bus. Save a setup before taking control.")
 local choices,index,draft,profile={},1,nil,nil
 local actual
 local selectedKind,selectedWeapon
 local drag,requesting
 local revision=0
 local rows={}
 local function connect(event,handler) table.insert(view.connections,event:Connect(handler)) end
 local remote=context.garageRequest
 local function request(...)
  if not remote then return {ok=false,message="Garage unavailable in this session."} end
  local ok,result=pcall(remote,...)
  if not ok or type(result)~="table" then return {ok=false,message="Garage request failed. Try again."} end
  return result
 end
 local function refresh() end
 local function select(choice)
  draft=Hardware.categoryDraft(choice.draft)
  actual=choice.current
  selectedKind,selectedWeapon=choice.kind,choice.weapon
  profile=if choice.assembly then Components.resolve(choice.assembly) else Components.forWeapon(choice.kind,choice.weapon)
 end
 local picker=view:button("Loadout","Load loadouts",function()
  if requesting then return end
  if inWorld and draft then return end
  if #choices>0 then index=index%#choices+1 else view:loadChoices();return end
  select(choices[index])
  refresh()
 end)
 local mobility,weapon
 local function preview(kind,id)
  if not draft or requesting or drag then return end
  local assembly=Components.zoneAssembly(choices[index].assembly,kind,id)
  if not assembly then return end
  selectedKind,selectedWeapon=kind,id
  profile=Components.resolve(assembly);actual=nil;refresh()
 end
 if inWorld then
  view.frame.BackgroundColor3=Color3.fromRGB(13,30,46)
  view.frame.BackgroundTransparency=0
  picker.Size=UDim2.new(1,-4,0,32)
  mobility=view:button("ZoneDrivetrain","Drivetrain",function()
   preview(if selectedKind=="Boomer" then "Rattler" else "Boomer",selectedWeapon)
  end)
  weapon=view:button("ZoneWeapon","Weapon",function()
   preview(selectedKind,if selectedWeapon=="weapon.cannon" then "weapon.gatling" else "weapon.cannon")
  end)
 end
 local total=view:paragraph("BusTotal","")
 local mesh,status
 for _,name in categories do
  if name=="retaliatorMesh" then
   mesh=view:button("RetaliatorMesh","Equip Retaliator Mesh",function()
    if not draft or requesting or drag then return end
    if draft.allocations.retaliatorMesh~=nil then
     draft.allocations.retaliatorMesh=nil
    else
     draft.allocations.retaliatorMesh=0
    end
    actual=nil;status.Text="";refresh()
   end)
  end
  local secondary=tradeoffs[name]
  view.order+=1
  local card=Instance.new("Frame")
  card.Name="Allocation_"..name;card.Size=UDim2.new(1,-6,0,if secondary then 137 elseif name=="drivetrain" then 81 else 64)
  card.LayoutOrder=view.order;card.BackgroundColor3=if inWorld then Color3.fromRGB(23,47,67) else Color3.fromRGB(32,47,52);card.Parent=view.content
  local corner=Instance.new("UICorner");corner.CornerRadius=UDim.new(0,8);corner.Parent=card
  local title=label(card,labels[name],0,0,1,21)
  local master=slider(card,25)
  local stats=label(card,"",0,if secondary then 94 else 43,1,20)
  local row={card=card,title=title,master=master,stats=stats}
  if secondary or name=="drivetrain" then row.detail=label(card,"",0,if secondary then 113 else 62,1,20) end
  rows[name]=row
  if secondary then
   label(card,secondary[1],.02,49,.47,20).TextXAlignment=Enum.TextXAlignment.Left
   label(card,secondary[2],.51,49,.47,20).TextXAlignment=Enum.TextXAlignment.Right
   row.secondary=slider(card,73)
  end
  local function dragAt(slide,input)
   if not draft or requesting or not view.frame.Visible then return end
   local kind=input.UserInputType
   if kind~=Enum.UserInputType.MouseButton1 and kind~=Enum.UserInputType.Touch then return end
   if drag then return end
   drag={slide=slide,input=input,name=name,touch=kind==Enum.UserInputType.Touch}
   view:updateDrag(input.Position.X)
  end
  connect(master.track.InputBegan,function(input) dragAt(master,input) end)
  if row.secondary then connect(row.secondary.track.InputBegan,function(input) dragAt(row.secondary,input) end) end
 end
 status=view:paragraph("GarageStatus","")
 local save=view:button("SaveBus",if inWorld then "Apply to this tank" else "Save setup for this session",function()
  if not draft or requesting then return end
  requesting=true
  local choice=choices[index]
  local version=revision
  local payload=table.clone(draft)
  if inWorld then payload.kind=selectedKind;payload.weapon=selectedWeapon end
  local result=request("Save",choice.id,payload)
  if version~=revision then return end
  requesting=false
  if result.ok then
   actual=nil
   if result.kind then choice.kind=result.kind;choice.weapon=result.weapon;choice.assembly=result.assembly end
   choice.draft=result.draft;draft=Hardware.categoryDraft(result.draft)
   refresh()
  end
  status.Text=if not result.ok then result.message elseif inWorld then "Applied to this tank and saved for this session." else "Saved. Applies when you take manual control."
 end,true)
 if inWorld then view:button("CloseConfiguration","Close",context.home) else view:back() end
 refresh=function()
  local choice=choices[index]
  if not choice or not draft then
   for _,row in rows do row.card.Visible=false end
   total.Text="";save.Visible=false;mesh.Visible=false
   if mobility then mobility.Visible=false;weapon.Visible=false end
   return
  end
  local config=actual or assert(Hardware.fromCategories(draft,profile,choice.tier))
  picker.Text=if inWorld then "CONFIGURATION BAY" else choice.kind.." / "..profile.Weapon.WeaponType.."  ›"
  if mobility then
   mobility.Visible=true;weapon.Visible=true
   mobility.Text="Drivetrain  ·  "..(if selectedKind=="Boomer" then "Tracks" else "Wheels").."  ›"
   weapon.Text="Weapon  ·  "..profile.Weapon.WeaponType.."  ›"
  end
  local sum=0
  mesh.Visible=choice.allowRetaliatorMesh~=false
  mesh.Text=if draft.allocations.retaliatorMesh==nil then "Equip Retaliator Mesh" else "Remove Retaliator Mesh"
  for name,row in rows do
   local allocation=draft.allocations[name]
   row.card.Visible=allocation~=nil
   if allocation==nil then continue end
   sum+=allocation
   row.title.Text=string.format("%s  %.1f%%",labels[name],allocation)
   local value,detail=readout(config,profile,name)
   row.stats.Text=value;row.master.tooltip.Text=value
   if row.detail then row.detail.Text=detail or "" end
   updateSlider(row.master,allocation/100)
   if row.secondary then
    updateSlider(row.secondary,draft.tuning[name])
    row.secondary.tooltip.Text=value
   end
  end
  total.Text=string.format("Bus allocated %.1f / 100%%",sum);save.Visible=true
 end
 function view:updateDrag(x)
  local slide=drag.slide
  local width=slide.track.AbsoluteSize.X
  if width<=0 then return end
  local fraction=math.clamp((x-slide.track.AbsolutePosition.X)/width,0,1)
  local name=drag.name
  actual=nil
  if slide==rows[name].master then
   local used=0
   for category,value in draft.allocations do if category~=name then used+=value end end
   draft.allocations[name]=math.min(math.max(0,100-used),math.floor(fraction*1000+.5)/10)
  else
   draft.tuning[name]=math.floor(fraction*100+.5)/100
  end
  status.Text="";refresh()
  slide.tooltip.Visible=true
 end
 connect(UIS.InputChanged,function(input)
  if not drag then return end
  if (drag.touch and input==drag.input) or (not drag.touch and input.UserInputType==Enum.UserInputType.MouseMovement) then
   view:updateDrag(input.Position.X)
  end
 end)
 local function endDrag()
  if drag then drag.slide.tooltip.Visible=false;drag=nil end
 end
 connect(UIS.InputEnded,function(input)
  if drag and (input==drag.input or not drag.touch and input.UserInputType==Enum.UserInputType.MouseButton1) then endDrag() end
 end)
 connect(UIS.WindowFocusReleased,endDrag)
 function view:loadChoices()
  requesting=true
  local version=revision
  local result=request("Read")
  if version~=revision then return end
  requesting=false
  if result.ok and #result.choices>0 then
   choices=result.choices;index=math.min(index,#choices)
   select(choices[index])
   status.Text=""
  else
   status.Text=result.message or "No loadouts available."
   picker.Text="Retry loading loadouts"
  end
  refresh()
 end
 function view:enter()
  View.enter(self)
  if inWorld then draft=nil;choices={};index=1;picker.Text="Loading tank…";refresh() end
  if not draft then self:loadChoices() end
 end
 function view:exit()
  revision+=1;requesting=false
  endDrag()
  View.exit(self)
 end
 refresh()
 return view
end
return Screen
