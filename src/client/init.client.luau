-- Application composition only. Gameplay, navigation and presentation own their lifecycles.
local Players=game:GetService("Players")
local Run=game:GetService("RunService")
local function startup(stage) if Run:IsStudio() then print("[BattleWorks startup/client] "..stage) end end
startup("client started (height and tilt v6)")
local network=game.ReplicatedStorage:WaitForChild("TankNetwork")
local remote=network:WaitForChild("BattleSession")
local Session=require(script.shell.GameplaySession)
local Shell=require(script.shell.ApplicationShell)
local shell
local gameplay=require(script.BattleClientHost).new(function()
 startup("initializing battle client")
 local client=require(script.BattleClient).new(function() shell.home() end)
 startup("battle client ready")
 return client
end)
local session=Session.new(function(action,requestId) remote:FireServer(action,requestId) end)
startup("initializing main menu")
local function worldRequest(action,payload)
 local worlds=network:FindFirstChild("PlayerWorlds")
 assert(worlds,"Saved worlds are unavailable in this build")
 return worlds:InvokeServer(action,payload)
end
shell=Shell.new(Players.LocalPlayer:WaitForChild("PlayerGui"),workspace:WaitForChild("Arena"),session,gameplay,nil,function() return game.ReplicatedStorage:FindFirstChild("BattleWorksEditorAssets") end,worldRequest)
startup("main menu ready")
local function worldMessage(message)
 local editor=shell.manager.screens.WorldEditor
 if editor and editor.library then editor.library.status.Text=message end
 shell.manager:get("Lobby"):setStatus(false,message)
end
remote.OnClientEvent:Connect(function(requestId,inBattle,message)
 if requestId==0 then worldMessage(message) else session:receive(requestId,inBattle,message) end
end)
-- Destination server loads only the saved owner/revision referenced by the
-- server-issued teleport. No world geometry travels through teleport data.
task.spawn(function()
 local ok,result=pcall(worldRequest,"Bootstrap")
 if not ok then return end -- older places may omit the optional world service
 if not result.ok then worldMessage(result.message)
 elseif result.launch and session.mode=="Menu" and shell.manager.current=="MainMenu" then session:join() end
end)
