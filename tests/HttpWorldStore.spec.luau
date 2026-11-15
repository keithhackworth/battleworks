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
print(string.format("HTTP world storage adapter passed: %d assertions",count))
