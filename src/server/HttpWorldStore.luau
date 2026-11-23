-- Server-only REST adapter. Credentials stay in Roblox Secrets, never replicas.
local Store={};Store.__index=Store
local Diagnostics=require(script.Parent.WorldStorageDiagnostics)
local function same(a,b)
 if type(a)~=type(b) then return false end
 if type(a)~="table" then return a==b end
 for k,v in a do if not same(v,b[k]) then return false end end
 for k in b do if a[k]==nil then return false end end
 return true
end
function Store.new(http,url,secretName,diagnostics)
 assert(type(url)=="string" and url:match("^https://[%w%.%-]+/[%w%/%-]+$") and type(secretName)=="string","Invalid world service configuration")
 return setmetatable({http=http,url=url,secretName=secretName,diagnostics=diagnostics or {},temporary=false,kind="Http",pending={}},Store)
end
local function ownerPath(owner)
 assert(type(owner)=="number" and owner==owner and owner%1==0 and owner~=0 and math.abs(owner)<=9007199254740991,"Invalid player identity")
 return "/players/"..string.format("%.0f",owner).."/worlds"
end
local function validId(id)
 assert(type(id)=="string" and #id<=64 and id:match("^[a-zA-Z][a-zA-Z0-9_-]*$") and id~="default","Invalid saved world ID")
 return id
end
function Store:failure(code,stage,reason,message,extra)
 local fields=table.clone(self.diagnostics);fields.secretName=self.secretName;fields.stage=stage;fields.reason=reason
 for key,value in extra or {} do fields[key]=value end
 Diagnostics.log(self.logger,"failure_"..code,fields)
 error("["..code.."] "..message,0)
end
function Store:request(method,path,payload,skipNamespaceCheck)
 if self.http.HttpEnabled==false then self:failure("http_disabled","HttpEnabled","HttpEnabled=false","HTTP requests are disabled in this server. Enable Allow HTTP Requests in the experience's Security settings.") end
 if self.diagnostics.expectedNamespace and not self.namespaceVerified and not skipNamespaceCheck then
  local health=self:request("GET","/health",nil,true)
  if health.namespace~="studio" and health.namespace~="live" then self:failure("response_contract","Namespace","Health response omitted a supported namespace","World service did not identify its save namespace. No world list/load/save request was sent.") end
  if health.namespace~=self.diagnostics.expectedNamespace then
   self:failure("namespace_mismatch","Namespace",tostring(health.namespace),"The selected "..self.secretName.." credential authenticated to "..tostring(health.namespace).." storage, but this mode requires "..self.diagnostics.expectedNamespace..". No world list/load/save request was sent.",{actualNamespace=health.namespace})
  end
  self.namespaceVerified=true;self.actualNamespace=health.namespace
  local fields=table.clone(self.diagnostics);fields.actualNamespace=health.namespace;fields.secretName=self.secretName
  Diagnostics.log(self.logger,"namespace_verified",fields)
 end
 local retrieved,secret=pcall(function() return self.http:GetSecret(self.secretName) end)
 if not retrieved then
  local reason=Diagnostics.safe(secret)
  local missing=reason:lower():find("can't find secret",1,true) or reason:lower():find("missing secret",1,true)
  self:failure(if missing then "secret_missing" else "secret_lookup_failed","GetSecret",reason,
   "Roblox GetSecret("..self.secretName..") failed in "..(self.diagnostics.secretStore or "this server's secret store")..": "..reason..". No HTTP request was sent.")
 end
 local prefixed,authorization=pcall(function() return secret:AddPrefix("Bearer ") end)
 if not prefixed then self:failure("secret_header_failed","AddPrefix",Diagnostics.safe(authorization),"The secret lookup succeeded, but Roblox could not build its authorization header: "..Diagnostics.safe(authorization)..". No HTTP request was sent.") end
 local request={Url=self.url..path,Method=method,Headers={Authorization=authorization,["Content-Type"]="application/json"}}
 if payload then request.Body=self.http:JSONEncode(payload) end
 local ok,response=pcall(function()return self.http:RequestAsync(request)end)
 if not ok then self:failure("http_transport","RequestAsync",Diagnostics.safe(response),"HTTP request failed before a response was received: "..Diagnostics.safe(response)..". Your save is not confirmed.",{method=method}) end
 if type(response)~="table" or type(response.StatusCode)~="number" then self:failure("response_contract","RequestAsync","HTTP response omitted its status code","World service returned an invalid HTTP response. Your save is not confirmed.",{method=method}) end
 local decoded,value=pcall(function()return self.http:JSONDecode(response.Body)end)
 local status=response.StatusCode
 local backend=if decoded and type(value)=="table" then value else {}
 local details={method=method,status=status,backendCode=backend.code}
 local message=if type(backend.message)=="string" then Diagnostics.safe(backend.message) else "No structured backend error message"
 if status==401 or status==403 then self:failure("http_authorization","Response",message,"Secret retrieval succeeded, but the world service rejected "..self.secretName.." (HTTP "..status.."): "..message,details) end
 if status==409 then self:failure("revision_conflict","Response",message,if type(backend.message)=="string" then message else "World changed elsewhere. Open it again, or choose a new World ID.",details) end
 if status==400 or status==413 then self:failure("world_validation","Response",message,"World service rejected the request (HTTP "..status.."): "..message,details) end
 if status==404 then self:failure("http_not_found","Response",message,"World service endpoint or saved world was not found (HTTP 404).",details) end
 if status==429 then self:failure("http_rate_limited","Response",message,"World service rate limit reached (HTTP 429). Try again shortly.",details) end
 if not response.Success or (type(status)=="number" and status>=500) then self:failure("backend_error","Response",message,"World service failed (HTTP "..tostring(status).."): "..message..". Your save is not confirmed.",details) end
 if not decoded then self:failure("response_json","JSONDecode","Success response was not valid JSON","World service returned an invalid JSON response (HTTP "..tostring(status).."). Your save is not confirmed.",details) end
 if backend.ok==false then self:failure("backend_error","Response",message,"World service reported a failure (HTTP "..status.."): "..message,details) end
 if type(value)~="table" or value.ok~=true then self:failure("response_contract","Response","JSON response did not confirm ok=true","World service returned an unexpected response (HTTP "..tostring(status).."). Your save is not confirmed.",details) end
 return value
end
function Store:list(owner)
 local result=self:request("GET",ownerPath(owner))
 if type(result.worlds)~="table" then self:failure("response_contract","List","Response omitted worlds array","Invalid world list response") end
 return result.worlds
end
function Store:load(owner,id)
 local result=self:request("GET",ownerPath(owner).."/"..validId(id))
 if not (type(result.document)=="table" and result.document.id==id and type(result.revision)=="number" and result.revision%1==0 and result.revision>0) then self:failure("response_contract","Load","Response identity or revision did not match request","Invalid saved world response") end
 return {document=result.document,revision=result.revision}
end
function Store:save(owner,document,expected)
 local path=ownerPath(owner).."/"..validId(document.id)
 assert(type(expected)=="number" and expected%1==0 and expected>=0,"Invalid save revision")
 local serialized=self.http:JSONEncode(document)
 local pending=self.pending[path]
 if not pending or pending.expected~=expected or not same(pending.document,document) then
  pending={expected=expected,document=self.http:JSONDecode(serialized),id=self.http:GenerateGUID(false)};self.pending[path]=pending
 end
 local result=self:request("PUT",path,{document=document,revision=expected,request_id=pending.id})
 if not (result.revision==expected+1 and type(result.document)=="table" and result.document.id==document.id) then self:failure("response_contract","Save","Acknowledgment identity or revision did not match request","Invalid save acknowledgment; your save is not confirmed") end
 self.pending[path]=nil
 return {document=result.document,revision=result.revision}
end
function Store:delete(owner,id,expected)
 local path=ownerPath(owner).."/"..validId(id)
 assert(type(expected)=="number" and expected%1==0 and expected>0 and expected<=1000000000,"Invalid delete revision")
 local result=self:request("DELETE",path.."?revision="..string.format("%.0f",expected))
 if result.deleted~=true then self:failure("response_contract","Delete","Response did not confirm deletion","World deletion is not confirmed") end
 self.pending[path]=nil
 return {deleted=true}
end
function Store:forget(owner)
 local prefix=ownerPath(owner).."/"
 for path in self.pending do if path:sub(1,#prefix)==prefix then self.pending[path]=nil end end
end
return Store
