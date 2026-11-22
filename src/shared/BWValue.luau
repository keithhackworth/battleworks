-- Immutable BW values. Explicit null preserves trailing array entries.
local Limits=require(script.Parent.BWConfig)
local Value={}
local dictionaries=setmetatable({},{__mode="k"})
local arrays=setmetatable({},{__mode="k"})
Value.Null=table.freeze({kind="null"})
function Value.mutableArray(items) arrays[items]=true; return items end
function Value.array(items) arrays[items]=true; return table.freeze(items) end
function Value.isArray(value) return type(value)=="table" and arrays[value]==true end
function Value.dictionary(fields,immutable) dictionaries[fields]=true; return if immutable then table.freeze(fields) else fields end
function Value.isDictionary(value) return type(value)=="table" and dictionaries[value]==true end
-- Snapshot a trusted producer's data into the same frozen containers used by
-- scan results. Count each occurrence, so a shared input subtree cannot
-- expand into an unbounded payload. Empty plain tables are dictionaries.
function Value.copyEventPayload(fields)
 if type(fields)~="table" or fields==Value.Null or arrays[fields] then return nil end
 local visiting={}
 local elements,bytes=0,0
 local function copy(source,depth)
  if depth>Limits.MaxEventPayloadDepth or visiting[source] or getmetatable(source)~=nil then return nil end
  local isArray
  if arrays[source] then
   if dictionaries[source] then return nil end
   isArray=true
  elseif depth==1 or dictionaries[source] then
   isArray=false
  end
  visiting[source]=true
  local snapshot={}
  local count,lastIndex=0,0
  for key,item in next,source do
   count+=1;elements+=1
   if count>Limits.MaxArrayItems or elements>Limits.MaxEventPayloadElements then return nil end
   local arrayKey=type(key)=="number"
   if isArray==nil then isArray=arrayKey end
   if arrayKey~=isArray then return nil end
   if isArray then
    if key%1~=0 or key<1 or key>Limits.MaxArrayItems then return nil end
    lastIndex=math.max(lastIndex,key)
   else
    if type(key)~="string" or #key>Limits.MaxStringBytes then return nil end
    bytes+=#key
   end
   local kind=type(item)
   if kind=="string" then
    if #item>Limits.MaxStringBytes then return nil end
    bytes+=#item
   elseif kind=="boolean" or item==Value.Null then
    bytes+=8
   elseif kind=="number" then
    if item~=item or math.abs(item)==math.huge then return nil end
    bytes+=8
   elseif kind=="table" then
    bytes+=8
    item=copy(item,depth+1)
    if not item then return nil end
   else
    return nil
   end
   if bytes>Limits.MaxEventPayloadBytes then return nil end
   snapshot[key]=item
  end
  visiting[source]=nil
  if isArray and lastIndex~=count then return nil end
  return if isArray then Value.array(snapshot) else Value.dictionary(snapshot,true)
 end
 return copy(fields,1)
end
function Value.result(reason,fields)
 local result=fields or {}; result.status=if reason then "fail" else "success"; result.reason=reason or Value.Null
 return Value.dictionary(result,true)
end
function Value.type(value)
	return if value==Value.Null then "null" elseif Value.isArray(value) then "array" elseif Value.isDictionary(value) then "dictionary" else type(value)
end
function Value.scan(kind,distance,bearing,player,affiliation)
	return Value.array({kind or Value.Null,distance or Value.Null,bearing or Value.Null,player or Value.Null,affiliation or Value.Null})
end
function Value.get(array,index) return array[index+1] end
function Value.observation(array,timestamp,origin,yaw)
	return table.freeze({value=array,timestamp=timestamp,origin=origin,chassisYaw=yaw})
end
function Value.equal(a,b)
	local seen,visits={},0
	local function equal(x,y)
		visits+=1; if visits>4096 then error({bwError=true,message="Value comparison is too complex."},0) end
		if x==y then return true end
		if not Value.isArray(x) or not Value.isArray(y) or #x~=#y then return false end
		seen[x]=seen[x] or {}; if seen[x][y] then return true end; seen[x][y]=true
		for i=1,#x do if not equal(x[i],y[i]) then return false end end
		return true
	end
	return equal(a,b)
end
local function quote(s)
	return '"'..s:gsub('\\','\\\\'):gsub('"','\\"'):gsub('\n','\\n'):gsub('\r','\\r'):gsub('\t','\\t')..'"'
end
function Value.format(value)
	local out,remaining,truncated={},Limits.MaxOutputBytes,false
	local function emit(text)
		if #text>remaining then text=text:sub(1,remaining); truncated=true end
		table.insert(out,text); remaining-=#text
	end
	local visiting={}
	local function format(v)
		if remaining<=0 then truncated=true; return end
		if v==Value.Null then emit("null")
		elseif type(v)=="number" then emit(string.format("%.17g",v))
		elseif type(v)=="boolean" then emit(if v then "true" else "false")
		elseif type(v)=="string" then emit(quote(v))
		elseif Value.isDictionary(v) then
            if visiting[v] then emit("<cycle>"); return end
            visiting[v]=true; emit("{"); local keys={}; for key in v do table.insert(keys,key) end; table.sort(keys)
            for i,key in keys do if remaining<=0 then truncated=true; break end; if i>1 then emit(", ") end; emit(quote(key)..": "); format(v[key]) end
            emit("}"); visiting[v]=nil
		elseif Value.isArray(v) then
            if visiting[v] then emit("<cycle>"); return end
            visiting[v]=true
			emit("[")
			for i,item in v do if remaining<=0 then truncated=true; break end; if i>1 then emit(", ") end; format(item) end
			emit("]"); visiting[v]=nil
		else error("Unsupported BW value.",0) end
	end
	format(value)
	return table.concat(out)..(if truncated then "… [truncated]" else "")
end
function Value.display(value)
	if type(value)~="string" then return Value.format(value) end
	return if #value>Limits.MaxOutputBytes then value:sub(1,Limits.MaxOutputBytes).."… [truncated]" else value
end
return table.freeze(Value)
