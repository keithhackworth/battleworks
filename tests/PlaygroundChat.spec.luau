-- Native renderer/input boundaries are mocked; text filtering is Roblox-owned
-- and must be validated with eligible real users in Studio/published play.
local count=0
local function check(ok,message)assert(ok,message);count+=1 end
local originalService=game.GetService
local actions={bindings={}}
function actions:BindActionAtPriority(name,callback)self.bindings[name]=callback end
function actions:UnbindAction(name)self.bindings[name]=nil end
local prompts={Enabled=true}
Players.PlayerRemoving=signal();player.UserId=201
local service=Instance.new("TextChatService");service.ChatVersion=Enum.ChatVersion.TextChatService;service.MessageReceived=signal()
local bar=Instance.new("ChatInputBarConfiguration");bar.Enabled=true;bar.KeyboardKeyCode=Enum.KeyCode.Slash;bar.IsFocused=false
local history=Instance.new("ChatWindowConfiguration");history.Enabled=true
local channels=Instance.new("Folder");channels.Name="TextChannels";channels.ChildAdded=signal()
local general=Instance.new("TextChannel");general.Name="RBXGeneral";general.ChildRemoved=signal()
local source=Instance.new("TextSource");source.UserId=201;source.CanSend=true
source.Parent=general;general.children={source};general.Parent=channels;channels.children={general};service.children={bar,history,channels}
local nativePermission=true;local permissionError=false
function service:CanUserChatAsync(id)check(id==201,"permission query uses only the local player");if permissionError then error("offline")end;return nativePermission end
function service:FindFirstChildOfClass(kind)for _,item in self.children do if item.ClassName==kind then return item end end end
function service:FindFirstChild(name)if name=="TextChannels"then return channels end end
function channels:FindFirstChild(name)if name=="RBXGeneral"then return general end end
local rawSendCalls=0
function general:SendAsync()rawSendCalls+=1;error("Only native input may send")end
function game:GetService(name)
 if name=="TextChatService"then return service elseif name=="ContextActionService"then return actions elseif name=="ProximityPromptService"then return prompts end
 return originalService(self,name)
end
local Controller=require("InputController")
local Chat=require("PlaygroundChat")
local State=require("PlaygroundChatState")
local gui=Instance.new("ScreenGui");local releases=0
local input=Controller.new(gui,function()releases+=1 end)
input:setCharacterControl(true)
check(Chat.new(playerGui,input,"Classic")==nil and history.Enabled,"Classic is not configured or given a Playground chat HUD")
local chat=Chat.new(playerGui,input,"BattleRoyale")
check(chat.ready and chat.allowed and chat.window.ClassName=="TextChannelWindow"and chat.window.Target==general,"chat binds native renderer to Roblox global channel")
check(bar.TextBox==chat.box and bar.TargetTextChannel==general and bar.KeyboardKeyCode==Enum.KeyCode.Return,"Roblox owns managed input, Return hotkey and channel routing")
check(not history.Enabled and not bar.Enabled,"no duplicate default history or collapsed input bar")
check(not chat.gui.Enabled,"Playground shell can construct chat without enabling menu UI")
chat:setActive(true)
check(chat.gui.Enabled and not chat.panel.Visible,"chat is available on foot, initially collapsed")
local binding=actions.bindings.BattleWorksTextEntry_PlaygroundChat
local result=binding(nil,Enum.UserInputState.Begin,{KeyCode=Enum.KeyCode.Return})
check(result==Enum.ContextActionResult.Pass and chat.panel.Visible and bar.Enabled,"Enter expands wrapper and passes through to native focus/send handling")
local function nativeFocus(focused)
 bar.IsFocused=focused;bar:GetPropertyChangedSignal("IsFocused"):Fire()
end
-- Core chat focus may not appear in GetFocusedTextBox: test the explicit bridge.
UIS.focusedTextBox=nil
local before=releases;nativeFocus(true)
check(input.textEntryActive and releases>before and input.suspended,"native chat focus releases/suspends all input providers even outside PlayerGui")
check(not defaultControls.controlsEnabled and not prompts.Enabled,"on-foot motion and tank-entry prompts yield while typing")
input:setCharacterControl(false)
check(chat.gui.Enabled and input.textEntryActive,"entering tank/control-state changes do not reset chat or its focus lease")
input:setCharacterControl(true)
check(not defaultControls.controlsEnabled,"on-foot re-admission cannot restore movement through active chat focus")
result=binding(nil,Enum.UserInputState.Begin,{KeyCode=Enum.KeyCode.Escape})
check(result==Enum.ContextActionResult.Pass and not chat.state.expanded and not bar.Enabled,"Escape cancels via native handling and closes wrapper without sending")
nativeFocus(false)
check(not input.textEntryActive and defaultControls.controlsEnabled and prompts.Enabled,"native blur restores original on-foot controls and prompt state")
chat:setExpanded(true)
chat.box.Focused:Fire()
check(input.textEntryActive and not defaultControls.controlsEnabled,"promoted PlayerGui TextBox focus also uses the same release bridge")
input:setTextEntryFocus("OtherModal",true)
chat.box.FocusLost:Fire(false)
check(input.textEntryActive,"chat blur cannot release another modal input owner")
input:setTextEntryFocus("OtherModal",false)
check(not input.textEntryActive and defaultControls.controlsEnabled,"only the last modal release restores movement")
nativeFocus(true)
chat:setExpanded(false)
check(bar.IsFocused and not input.textEntryActive and defaultControls.controlsEnabled and chat.box.releasedFocus,
 "collapsing chat releases the text box and input lease even before native blur arrives")
nativeFocus(false)
-- Send only through the native bar. Delivery updates contain no readable text.
local function message(id,status,who,channel)
 return setmetatable({MessageId=id,Status=status,TextSource=if who then {UserId=who}else nil,TextChannel=channel or general},{__index=function(_,key)
  if key=="Text"or key=="PrefixText"or key=="Translation"then error("Player content must stay native")end
 end})
end
service.MessageReceived:Fire(message("m1",Enum.TextChatMessageStatus.Sending,202))
service.MessageReceived:Fire(message("m1",Enum.TextChatMessageStatus.Success,202))
service.MessageReceived:Fire(message("m1",Enum.TextChatMessageStatus.Success,202))
check(chat.state.unread==1 and string.find(chat.toggle.Text,"(1)",1,true),"only one delivered message counts despite sending echo/delivery duplicates")
service.MessageReceived:Fire(message("local",Enum.TextChatMessageStatus.Success,201))
service.MessageReceived:Fire(message("error",Enum.TextChatMessageStatus.TextFilterFailed,201))
check(chat.state.unread==1 and string.find(chat.status.Text,"could not deliver",1,true),"local sends do not add unread and failed delivery has visible error state")
service.MessageReceived:Fire(message("other",Enum.TextChatMessageStatus.Success,202,{}))
check(chat.state.unread==1,"unrelated channels cannot duplicate global unread")
chat.toggle.Activated:Fire()
check(chat.state.unread==0 and chat.panel.Visible,"touch-friendly toggle expands and clears badge")
service.MessageReceived:Fire(message("m2",Enum.TextChatMessageStatus.Success,202))
check(chat.state.unread==0,"visible global window does not build unread")
chat:setActive(false)
check(not chat.gui.Enabled and not bar.Enabled and not chat.state.expanded,"main menu/world-editor transition hides and defocuses chat UI")
service.MessageReceived:Fire(message("menu",Enum.TextChatMessageStatus.Success,202))
chat:setActive(true)
check(chat.state.unread==1 and chat.window.Target==general,"return/death/tank switching reuses native history and unread state")
local provider=input.providers.KeyboardMouse
input:setCharacterControl(false);input:setExternalControl(false);input:setMouseMode("Mouse Direct")
check(UIS.MouseBehavior==Enum.MouseBehavior.LockCenter,"existing Direct mode begins unchanged")
chat:setExpanded(true);nativeFocus(true)
check(UIS.MouseBehavior==Enum.MouseBehavior.Default and provider.mouseMode=="Mouse Direct","chat yields cursor via existing suspension without changing mouse mode")
UIS.InputBegan:Fire({KeyCode=Enum.KeyCode.W,UserInputType=Enum.UserInputType.Keyboard},false)
UIS.InputBegan:Fire({KeyCode=Enum.KeyCode.C,UserInputType=Enum.UserInputType.Keyboard},false)
UIS.InputBegan:Fire({KeyCode=Enum.KeyCode.LeftAlt,UserInputType=Enum.UserInputType.Keyboard},false)
check(input:sample().throttle==0 and not input:sample().fire and not provider.recenter,"typed movement/aim shortcuts cannot reach providers")
-- Revocation cannot resume gameplay before native text focus ends.
source.CanSend=false;source:GetPropertyChangedSignal("CanSend"):Fire()
check(not chat.allowed and not chat.box.TextEditable and input.textEntryActive,"live chat permission revocation fails closed while retaining input isolation")
nativeFocus(false)
check(not input.textEntryActive and UIS.MouseBehavior==Enum.MouseBehavior.LockCenter and provider.mouseMode=="Mouse Direct","blur restores existing Direct cursor/mode without stale movement")
source.CanSend=true;source:GetPropertyChangedSignal("CanSend"):Fire()
check(chat.allowed,"Roblox channel eligibility can recover without recreating UI")
chat:setExpanded(false);nativePermission=false;chat:checkPermission()
check(not chat.allowed and not bar.Enabled and not chat.box.TextEditable and string.find(chat.reason,"account"),"account denied chat has no game-provided send workaround")
local expanded=chat.state.expanded;binding(nil,Enum.UserInputState.Begin,{KeyCode=Enum.KeyCode.Return})
check(chat.state.expanded==expanded,"denied user cannot focus chat with Enter")
nativePermission=true;permissionError=true;chat:checkPermission()
check(not chat.allowed and string.find(chat.reason,"could not be checked"),"permission service errors fail closed with a distinct reason")
permissionError=false;chat:checkPermission()
-- Other text editors own Enter; do not grab focus from BW or world editing.
chat:setExpanded(false);UIS.focusedTextBox={}
binding(nil,Enum.UserInputState.Begin,{KeyCode=Enum.KeyCode.Return})
check(not chat.state.expanded,"another editor's Enter is not captured by chat")
UIS.focusedTextBox=nil
-- Compact touch panel uses a modal layout, hiding sticks rather than covering them.
UIS.PreferredInput=Enum.PreferredInput.Touch;UIS.preferredSignal:Fire()
chat.gui.AbsoluteSize=Vector2.new(640,360);chat:layout();chat:setExpanded(true)
check(input.textEntryActive and not input.providers.Touch.root.Visible and chat.root.Position.Y.Offset== -12,"short touch screens reserve modal chat without covering live sticks/FIRE")
check(chat.box.Size.Y.Offset==44 and chat.window.Visible,"touch input target remains 44px and native history fits landscape phone")
chat:setExpanded(false);nativeFocus(false)
check(not input.textEntryActive and input.providers.Touch.root.Visible,"collapse restores touch controls via existing provider")
chat.gui.AbsoluteSize=Vector2.new(480,200);chat:setExpanded(true)
check(chat.root.Size.Y.Offset>=80 and not chat.window.Visible and chat.box.Position.Y.Offset==0,"very short screens retain usable input without an overlapping history list")
chat:setExpanded(false)
local state=State.new(201)
for i=1,250 do state:receive(message(tostring(i),Enum.TextChatMessageStatus.Success,202),general)end
check(#state.order==200 and state.unread==99,"metadata/dedup memory and unread badge are bounded")
Players.PlayerRemoving:Fire({UserId=202})
check(not chat.destroyed,"remote departure needs no per-player UI resources or singleton reset")
local nativeBox=bar.TextBox
Players.PlayerRemoving:Fire(player)
check(chat.destroyed and chat.gui.destroyed and bar.TextBox~=nativeBox and history.Enabled and bar.KeyboardKeyCode==Enum.KeyCode.Slash,"local departure disconnects UI and restores native chat configuration")
check(not actions.bindings.BattleWorksTextEntry_PlaygroundChat and not input.textEntryActive,"departure removes keyboard route and focus lease")
local unread=chat.state.unread;service.MessageReceived:Fire(message("late",Enum.TextChatMessageStatus.Success,202))
check(chat.state.unread==unread and rawSendCalls==0,"destroyed listener cannot update or send user text")
chat:destroy() -- idempotent
-- A delayed permission response after destruction cannot re-enable input.
local savedSpawn=task.spawn;local pending={};task.spawn=function(callback)table.insert(pending,callback)end
local delayed=Chat.new(playerGui,input,"BattleRoyale");delayed:setActive(true);delayed:destroy()
for _,callback in pending do callback()end;task.spawn=savedSpawn
check(delayed.destroyed and not delayed.allowed,"late async permission result respects lifecycle generation")
local nativeFactory=Instance.new
Instance.new=function(class)if class=="TextChannelWindow"then error("unsupported native client")end;return nativeFactory(class)end
local unsupported=Chat.new(playerGui,input,"BattleRoyale");unsupported:setActive(true)
check(not unsupported.ready and not unsupported.box.TextEditable and history.Enabled and bar.TextBox==nil,"older clients retain native chat and fail closed rather than implementing a message relay")
unsupported:destroy();Instance.new=nativeFactory
game.GetService=originalService
print(string.format("Playground native chat/input lifecycle passed: %d assertions",count))
