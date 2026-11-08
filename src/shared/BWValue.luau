-- Immutable BW values. Explicit null preserves trailing array entries.
local Limits=require(script.Parent.BWConfig)
local Value={}
local arrays=setmetatable({},{__mode="k"})
Value.Null=table.freeze({kind="null"})
function Value.array(items) arrays[items]=true; return table.freeze(items) end
function Value.isArray(value) return type(value)=="table" and arrays[value]==true end
function Value.type(value)
	return if value==Value.Null then "null" elseif Value.isArray(value) then "array" else type(value)
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
	local function format(v)
		if remaining<=0 then truncated=true; return end
		if v==Value.Null then emit("null")
		elseif type(v)=="number" then emit(string.format("%.17g",v))
		elseif type(v)=="boolean" then emit(if v then "true" else "false")
		elseif type(v)=="string" then emit(quote(v))
		elseif Value.isArray(v) then
			emit("[")
			for i,item in v do if remaining<=0 then truncated=true; break end; if i>1 then emit(", ") end; format(item) end
			emit("]")
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
