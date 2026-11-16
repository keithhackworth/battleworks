-- Never log Secret objects, authorization headers, request bodies or response bodies.
local D={}
function D.safe(value)
 local s=(if value==nil then "" else tostring(value)):gsub("[\r\n]"," ")
 s=s:gsub("[Aa]uthorization%s*[:=]%s*[^,;}]+","Authorization=[redacted]")
 s=s:gsub("[Bb]earer%s+[^%s,;}]+","Bearer [redacted]")
 return s:sub(1,600)
end
function D.log(logger,event,fields)
 local out={"[BattleWorks worlds] event="..event}
 for _,key in {"mode","provider","expectedNamespace","actualNamespace","secretName","secretStore","rawIsStudio","teamTestEnabled","privateServer","stage","method","status","backendCode","reason"} do
  if fields[key]~=nil then table.insert(out,key.."="..D.safe(fields[key])) end
 end
 (logger or warn)(table.concat(out," "))
end
return D
