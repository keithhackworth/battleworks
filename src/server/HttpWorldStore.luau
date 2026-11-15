-- Server-only REST adapter. Credentials stay in Roblox Secrets, never replicas.
local Store={};Store.__index=Store
local function same(a,b)
 if type(a)~=type(b) then return false end
 if type(a)~="table" then return a==b end
 for k,v in a do if not same(v,b[k]) then return false end end
 for k in b do if a[k]==nil then return false end end
 return true
end
function Store.new(http,url,secretName)
 assert(type(url)=="string" and url:match("^https://[%w%.%-]+/[%w%/%-]+$") and type(secretName)=="string","Invalid world service configuration")
 return setmetatable({http=http,url=url,secretName=secretName,temporary=false,kind="Http",pending={}},Store)
end
local function ownerPath(owner)
 assert(type(owner)=="number" and owner==owner and owner%1==0 and owner~=0 and math.abs(owner)<=9007199254740991,"Invalid player identity")
 return "/players/"..string.format("%.0f",owner).."/worlds"
end
local function validId(id)
 assert(type(id)=="string" and #id<=64 and id:match("^[a-zA-Z][a-zA-Z0-9_-]*$") and id~="default","Invalid saved world ID")
 return id
end
function Store:request(method,path,payload)
 assert(self.http.HttpEnabled~=false,"Enable Allow HTTP Requests in Experience Settings → Security to save worlds.")
 local authorized,authorization=pcall(function() return self.http:GetSecret(self.secretName):AddPrefix("Bearer ") end)
 assert(authorized,"Configure the "..self.secretName.." secret in Studio Local Secrets / Creator Dashboard before saving worlds.")
 local request={Url=self.url..path,Method=method,Headers={Authorization=authorization,["Content-Type"]="application/json"}}
 if payload then request.Body=self.http:JSONEncode(payload) end
 local ok,response=pcall(function()return self.http:RequestAsync(request)end)
 assert(ok,"Cannot reach the BattleWorks world service. Your save is not confirmed; retry or export your draft.")
 local decoded,value=pcall(function()return self.http:JSONDecode(response.Body)end)
 if response.StatusCode==401 then error("World service credentials were rejected. Check the configured BattleWorks secret.",0) end
 if response.StatusCode==409 and decoded and type(value)=="table" then error(value.message or "World changed elsewhere. Open it again, or choose a new World ID.",0) end
 if (response.StatusCode==400 or response.StatusCode==413) and decoded and type(value)=="table" and type(value.message)=="string" then error(value.message,0) end
 assert(response.Success and decoded and type(value)=="table" and value.ok==true,
  if response.StatusCode==404 then "Saved world not found." else "World service could not complete the request. Your save is not confirmed; retry or export your draft.")
 return value
end
function Store:list(owner)
 local result=self:request("GET",ownerPath(owner))
 assert(type(result.worlds)=="table","Invalid world list response")
 return result.worlds
end
function Store:load(owner,id)
 local result=self:request("GET",ownerPath(owner).."/"..validId(id))
 assert(type(result.document)=="table" and result.document.id==id and type(result.revision)=="number" and result.revision%1==0 and result.revision>0,"Invalid saved world response")
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
 assert(result.revision==expected+1 and type(result.document)=="table" and result.document.id==document.id,"Invalid save acknowledgment")
 self.pending[path]=nil
 return {document=result.document,revision=result.revision}
end
function Store:forget(owner)
 local prefix=ownerPath(owner).."/"
 for path in self.pending do if path:sub(1,#prefix)==prefix then self.pending[path]=nil end end
end
return Store
