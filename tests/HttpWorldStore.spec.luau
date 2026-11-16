local HttpStore=require("HttpWorldStore")
local State=require("WorldEditorState")
local Document=require("WorldEditorDocument")
local count=0
local function check(value,message)assert(value,message);count+=1 end
local wire,serial={},0
local calls={};local response;local fail=false;local keyFail=false
local header={secret=true}
local http={HttpEnabled=true}
function http:JSONEncode(value)serial+=1;local key="json_"..serial;wire[key]=State.copy(value);return key end
function http:JSONDecode(value)return State.copy(assert(wire[value],"bad JSON"))end
function http:GenerateGUID()serial+=1;return "request-guid-000000-"..serial end
function http:GetSecret(name)
 if keyFail then error("missing secret")end
 check(name=="BattleWorksStudioWorlds","uses server-only configured secret name")
 return {AddPrefix=function(_,prefix)check(prefix=="Bearer ","bearer prefix applied without extracting secret");return header end}
end
function http:RequestAsync(request)
 table.insert(calls,request)
 if fail then error("network failure")end
 return response
end
local function reply(status,value)response={StatusCode=status,Success=status>=200 and status<300,Body=http:JSONEncode(value)}end
local store=HttpStore.new(http,"https://groupboard.app/api/battleworks/v1","BattleWorksStudioWorlds")
check(not store.temporary and store.kind=="Http","Studio HTTP saves report durable storage")
reply(200,{ok=true,worlds={}})
check(#store:list(101)==0 and calls[#calls].Url=="https://groupboard.app/api/battleworks/v1/players/101/worlds","list uses authenticated owner in URL")
check(calls[#calls].Headers.Authorization==header and calls[#calls].Headers["Content-Type"]=="application/json","secret object stays in header, never URL/body")
local doc=Document.fresh();doc.id="forest"
reply(200,{ok=true,document=doc,revision=1})
check(store:save(101,doc,0).revision==1,"save acknowledges durable revision")
local saved=http:JSONDecode(calls[#calls].Body)
check(saved.document.id=="forest" and saved.revision==0 and type(saved.request_id)=="string","save envelope preserves document and expected revision")
local savedPath=calls[#calls].Url
check(calls[#calls].Method=="PUT" and savedPath:find("/players/101/worlds/forest",1,true),"save is scoped to server-derived owner")
check(store:load(101,"forest").document.id=="forest","load returns document from selected private slot")
fail=true
check(not pcall(store.save,store,101,doc,1),"network failure never reports save success")
local firstAttempt=http:JSONDecode(calls[#calls].Body).request_id
fail=false;reply(200,{ok=true,document=doc,revision=2})
check(store:save(101,State.copy(doc),1).revision==2,"retry can recover a committed save acknowledgment")
check(http:JSONDecode(calls[#calls].Body).request_id==firstAttempt,"retry reuses idempotency ID for same owner/revision/content")
fail=true;check(not pcall(store.save,store,101,doc,2),"next failed save retains its pending ID")
local original=http:JSONDecode(calls[#calls].Body).request_id
local changed=State.copy(doc);changed.name="New draft"
check(not pcall(store.save,store,101,changed,2),"changed content remains unsaved during outage")
check(http:JSONDecode(calls[#calls].Body).request_id~=original,"changed draft gets a distinct save ID")
store:forget(101);check(next(store.pending)==nil,"disconnect clears retry memory, never durable worlds")
fail=false;reply(409,{ok=false,message="World changed elsewhere"})
local ok,err=pcall(store.save,store,101,doc,2)
check(not ok and tostring(err):find("changed elsewhere",1,true),"revision conflicts surface clearly and never overwrite")
reply(401,{ok=false});check(not pcall(store.list,store,101),"invalid credentials fail closed")
reply(503,{ok=false});check(not pcall(store.list,store,101),"outage cannot masquerade as empty saved worlds")
response={StatusCode=200,Success=true,Body="malformed"};check(not pcall(store.list,store,101),"malformed service response is not success")
reply(200,{ok=true,document=doc,revision=9});check(not pcall(store.save,store,101,doc,2),"wrong acknowledged revision rejected")
local another=State.copy(doc);another.id="someone_else"
reply(200,{ok=true,document=another,revision=3});check(not pcall(store.load,store,101,"forest"),"mismatched response identity rejected")
local before=#calls
check(not pcall(store.load,store,101,"../forest") and not pcall(store.list,store,0),"path traversal and invalid owner rejected before HTTP")
check(#calls==before,"invalid identities never reach the service")
keyFail=true;check(not pcall(store.list,store,101) and #calls==before,"missing local secret leaves draft available and sends no request")
keyFail=false;http.HttpEnabled=false
check(not pcall(store.list,store,101) and #calls==before,"disabled HTTP gives setup error without silent fallback")
http.HttpEnabled=true;reply(200,{ok=true,worlds={}})
store:list(-1);check(calls[#calls].Url:find("/players/-1/worlds",1,true),"Studio test-player IDs remain stable across play sessions")
local config={FindFirstChild=function()return {Value="Http"}end}
local selected=require("PlayerWorldStorage").create(http,config,true)
check(selected.kind=="Http" and selected.secretName=="BattleWorksStudioWorlds","configured Studio provider is durable HTTP")
selected=require("PlayerWorldStorage").create(http,config,false)
check(selected.secretName=="BattleWorksLiveWorlds","published provider uses distinct live credential/namespace")
local logs={};store.logger=function(line)table.insert(logs,line)end
local function failure(code,fn)
 local ok,reason=pcall(fn)
 check(not ok and tostring(reason):find("["..code.."]",1,true),"reports distinct failure: "..code)
 check(logs[#logs] and logs[#logs]:find("event=failure_"..code,1,true),"logs distinct failure: "..code)
end
keyFail=true;before=#calls;failure("secret_missing",function()store:list(101)end)
check(#calls==before and logs[#logs]:find("stage=GetSecret",1,true) and logs[#logs]:find("missing secret",1,true),"lookup failure retains actual Roblox reason and sends no HTTP")
keyFail=false
local getSecret=http.GetSecret
http.GetSecret=function()error("Permission denied by Roblox secret service")end
failure("secret_lookup_failed",function()store:list(101)end)
http.GetSecret=function()return {AddPrefix=function()error("header construction failed")end}end
failure("secret_header_failed",function()store:list(101)end)
check(#calls==before,"lookup/header errors never reach backend")
http.GetSecret=getSecret
fail=true;failure("http_transport",function()store:list(101)end);fail=false
for _,status in {401,403} do reply(status,{ok=false,code="unauthorized",message="Invalid credential"});failure("http_authorization",function()store:list(101)end)end
reply(503,{ok=false,code="storage_unavailable",message="Database unavailable"})
failure("backend_error",function()store:list(101)end)
check(logs[#logs]:find("status=503",1,true) and logs[#logs]:find("backendCode=storage_unavailable",1,true) and logs[#logs]:find("Database unavailable",1,true),"backend status/code/reason logged without response body")
response={StatusCode=200,Success=true,Body="malformed"};failure("response_json",function()store:list(101)end)
local safe=require("WorldStorageDiagnostics").safe("Authorization: Bearer fake-sensitive-value")
check(not safe:find("fake-sensitive-value",1,true),"diagnostics redact authorization values")
check(require("WorldStorageDiagnostics").safe(false)=="false","diagnostics retain false runtime flags explicitly")
-- Compose the actual runtime mode decision with storage selection.
local Context=require("WorldTestContext")
local settings={TeamTestMode={Value=false},TeamTestHostUserId={Value="0"},WorldStorageProvider={Value="Http"}}
local configuration={FindFirstChild=function(_,name)return settings[name]end}
local place={PrivateServerId="cloud-test",PrivateServerOwnerId=0,CreatorType=Enum.CreatorType.User,CreatorId=101}
local context=Context.resolve({IsStudio=function()return false end},place,configuration)
selected=require("PlayerWorldStorage").create(http,configuration,context.studio,context)
check(selected.secretName=="BattleWorksLiveWorlds" and selected.diagnostics.teamTestEnabled==false,"disabled Team Test configuration reproduces live-secret path")
http.GetSecret=function(_,name)error("Can't find secret with given key: "..name)end
selected.logger=function(line)table.insert(logs,line)end
local ok,reason=pcall(selected.list,selected,101)
check(not ok and tostring(reason):find("BattleWorksLiveWorlds",1,true) and tostring(reason):find("secret_missing",1,true),"reproduces reported live lookup warning at the exact failing stage")
http.GetSecret=getSecret;settings.TeamTestMode.Value=true
context=Context.resolve({IsStudio=function()return false end},place,configuration)
selected=require("PlayerWorldStorage").create(http,configuration,context.studio,context)
selected.logger=function(line)table.insert(logs,line)end
check(selected.secretName=="BattleWorksStudioWorlds" and selected.diagnostics.mode=="TeamTest" and selected.diagnostics.secretStore=="CreatorDashboard","enabled Team Test selects Studio namespace and cloud secret store")
local originalRequest=http.RequestAsync;local backendNamespace="live"
function http:RequestAsync(request)
 local prior=response
 if request.Url:sub(-7)=="/health" then response={StatusCode=200,Success=true,Body=self:JSONEncode({ok=true,namespace=backendNamespace})}end
 local result=originalRequest(self,request);response=prior;return result
end
reply(200,{ok=true,worlds={}});before=#calls
local ok,reason=pcall(selected.list,selected,101)
check(not ok and tostring(reason):find("namespace_mismatch",1,true) and #calls==before+1 and calls[#calls].Url:sub(-7)=="/health","wrong credential namespace is rejected using read-only health before any world operation")
backendNamespace="studio";check(#selected:list(101)==0 and selected.actualNamespace=="studio","correct Team Test credential verifies Studio backend namespace")
before=#calls;selected:list(101);check(#calls==before+1,"verified namespace is cached without repeated health requests")
http.RequestAsync=originalRequest
print(string.format("HTTP world storage adapter passed: %d assertions",count))
