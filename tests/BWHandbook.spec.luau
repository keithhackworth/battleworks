local Handbook=require(Shared.BWHandbook)
local Hardware=require(Shared.BWChassis)
local Commands=require(Shared.BWCommands)
local Parser=require(Shared.BWParser)
local IDE=require(Client.BWIDE)
local count=0
local function check(ok,message) count+=1; assert(ok,message) end
local covered={}
check(Hardware.Costs.print==0,"debug printing configured free")
for _,command in Handbook.commands() do
 check(Commands.known(command.name),"reference documents supported function "..command.name)
 check(not covered[command.name],"unique command reference")
 covered[command.name]=true
 check(type(command.cost)=="number" and command.cost>=0,"explicit tick cost")
 check(#command.inputs>10 and #command.behavior>40 and #command.returns>30 and #command.device>0,"inputs/behavior/results/device documented")
 local parsed,err=Parser.parse(command.signature)
 check(parsed~=nil,"documented command signatures parse: "..command.name.." "..tostring(err and err.message))
end
for _,registry in {Commands.moves,Commands.turns,Commands.special,{fire=true,Scanner=true,print=true}} do
 for name in registry do check(covered[name],"no missing callable: "..name) end
end
local sections=Handbook.sections(); local all={}; local ids={}; local documented={}
local byName={}; for _,command in Handbook.commands() do byName[command.name]=command end
for _,section in sections do
 check(not ids[section.id] and #section.title>0 and #section.body>100,"unique useful topic")
 ids[section.id]=true; table.insert(all,section.body)
 if #section.commands>0 then
  check(section.body:find("COMMANDS IN THIS SECTION",1,true)==1,"command index at topic top")
  local details=assert(section.body:find("DETAILED REFERENCE",1,true))
  for _,name in section.commands do
   local entry=byName[name]
   check(entry~=nil and not documented[name],"each command has one detailed home")
   documented[name]=section.id
   local signature=section.body:find(entry.signature,1,true)
   check(signature and signature<details,"signature appears in top index: "..name)
   for _,field in {entry.inputs,entry.behavior,entry.returns} do
    local position=section.body:find(field,details,true)
    check(position~=nil,"full rendered explanation exists for "..name)
   end
   check(section.body:find("COMMAND: "..name,details,true),"dedicated detailed heading: "..name)
  end
 end
end
for name in covered do check(documented[name]~=nil,"every callable appears in actual rendered document: "..name) end
check(documented.back=="movement" and documented.turn_left=="movement" and documented.turn_right=="movement","both driving directions and chassis rotations in Movement")
check(documented.turret_left=="turret" and documented.turret_right=="turret" and documented.print=="examples","both turret directions and print have detailed homes")
all=table.concat(all,"\n")
for _,text in {"CPU TICK","CPU CYCLE","simulation second","100%","deviceQueueFull","commandId","completionReason","detections[0]","timestamp","wait_for","ascending thread order","0.2","one tank","best_effort","150 studs","Ctrl+A / Ctrl+C"} do
 check(all:lower():find(text:lower(),1,true)~=nil,"required handbook concept: "..text)
end
check(ids.cpu and ids.buses and ids.movement and ids.turret and ids.weapon and ids.radar and ids.clock and ids.queues and ids.language and ids.examples and ids.loops,"all topics accessible")
local original=Hardware.Costs.forward
Hardware.Costs.forward=2.75
local current
for _,command in Handbook.commands() do if command.name=="forward" then current=command end end
check(current.cost==2.75,"cost uses actual runtime config")
check(Handbook.sections()[3].body:find("2.75 ticks",1,true),"rendered reference updates cost")
Hardware.Costs.forward=original
local runCount,stopCount,configured=0,0,0
local ui=IDE.new(Instance.new("PlayerGui"),function() runCount+=1; return runCount end,function() stopCount+=1; return stopCount end,function() configured+=1 end)
ui:bind("Boomer")
local source=ui.editor.Text
check(not ui.handbook.frame.Visible,"popup starts closed")
ui.toggle.Activated:Fire(); ui.handbookButton.Activated:Fire()
check(ui.frame.Visible and ui.handbook.frame.Visible and ui.handbook.selected==1,"IDE button opens intro popup")
check(runCount==0 and stopCount==0 and configured==0 and ui.editor.Text==source,"opening reference changes no program, configuration or source")
check(ui.editor.releasedFocus and ui.output.releasedFocus and ui.configEditor.releasedFocus,"opening releases previous text focus")
check(ui.handbook.body.ClassName=="TextBox" and not ui.handbook.body.TextEditable and ui.handbook.body.MultiLine and not ui.handbook.body.ClearTextOnFocus,"handbook is selectable read-only multiline text")
check(ui.handbook.scroll.AutomaticCanvasSize==Enum.AutomaticSize.None and ui.handbook.body.AutomaticSize==Enum.AutomaticSize.None and ui.handbook.body.TextWrapped,"explicit measurement avoids automatic canvas feedback")
check(ui.handbook.scroll.CanvasSize.Y.Offset>ui.handbook.scroll.AbsoluteSize.Y and ui.handbook.body.Size.Y.Offset>0,"long reference has a scrollable measured canvas")
check(ui.handbook.scroll.ScrollBarThickness>=10 and ui.handbook.scroll.ScrollBarImageTransparency==0 and ui.handbook.scroll.ScrollingEnabled,"visible enabled vertical scrollbar")
check(ui.handbook.navigation.CanvasSize.X.Offset>ui.handbook.navigation.Size.X.Offset,"all tabs fit horizontal scroll canvas")
for index,section in ui.handbook.sections do
 ui.handbook.scroll.CanvasPosition=Vector2.new(0,100)
 ui.handbook.tabs[index].Activated:Fire()
 check(ui.handbook.selected==index and ui.handbook.body.Text==section.body and ui.handbook.title.Text:find(section.title,1,true),"topic navigation "..section.id)
 check(ui.handbook.scroll.CanvasPosition.Y==0,"topic change resets scrolling")
 check(ui.handbook.scroll.CanvasSize.Y.Offset>=ui.handbook.body.Size.Y.Offset+ui.handbook.body.Position.Y.Offset,"canvas includes whole document and bottom padding")
end
ui.handbook:showSection(3)
local originalHeight=ui.handbook.scroll.CanvasSize.Y.Offset
ui.handbook.scroll.AbsoluteSize=Vector2.new(320,180)
ui.handbook.scroll:GetPropertyChangedSignal("AbsoluteSize"):Fire()
check(ui.handbook.scroll.CanvasSize.Y.Offset>originalHeight and ui.handbook.body.Size.X.Offset==280,"narrowing popup remeasures wrapped text")
check(ui.handbook.body.Text:find("COMMAND: back",1,true) and ui.handbook.body.Text:find("COMMAND: turn_right",1,true),"lower movement entries are retained in scrollable body")
ui:update({tankType="Boomer",bwRunning=true,bwStatus="running",bwLine=4,bwIndex=2,bwCount=5})
check(ui.running and ui.handbook.frame.Visible and runCount==0 and stopCount==0,"live runtime update does not pause or close reference")
ui.handbook.closeButton.Activated:Fire()
check(not ui.handbook.frame.Visible and ui.frame.Visible and ui.handbook.body.releasedFocus,"Close returns to existing IDE")
ui.handbookButton.Activated:Fire(); ui:bind("Rattler")
check(not ui.handbook.frame.Visible,"tank switch closes popup")
ui.handbookButton.Activated:Fire(); ui:close()
check(not ui.handbook.frame.Visible and not ui.frame.Visible,"IDE close also closes popup")
ui.toggle.Activated:Fire(); ui.handbookButton.Activated:Fire(); ui.running=false; ui.pendingRequest=nil; ui.run.Activated:Fire()
check(runCount==1 and not ui.handbook.frame.Visible and not ui.frame.Visible,"existing Run still closes reference/IDE")
-- Clicking the log must not make continuous scanner output appear frozen.
UIS.focusedTextBox=ui.output; ui.output.SelectionStart=-1; ui.output.CursorPosition=1
ui:setOutput("live scan output")
check(ui.output.Text=="live scan output","focused log without selection keeps updating")
ui.output.SelectionStart=1; ui.output.CursorPosition=5
ui:setOutput("new scan output")
check(ui.output.Text=="live scan output","actual selection remains stable for copying")
ui.output.SelectionStart=-1; ui:setOutput("new scan output")
check(ui.output.Text=="new scan output","clearing selection resumes live output")
UIS.focusedTextBox=nil
local popup=ui.handbook.frame
ui:destroy()
check(popup.destroyed and ui.gui.destroyed,"popup cleaned on IDE destruction")
ui.handbook.closeButton.Activated:Fire()
check(runCount==1 and stopCount==0,"disconnected handbook handlers never issue controls")
print("BW handbook suite passed: "..count.." assertions")
