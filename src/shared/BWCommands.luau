-- Shared argument contracts for static validation and evaluated action inputs.
local Limits=require(script.Parent.BWConfig)
local C={}
C.moves={forward=true,back=true}
C.turns={turn_left=true,turn_right=true,turret_left=true,turret_right=true}
function C.known(name) return C.moves[name] or C.turns[name] or name=="fire" or name=="Scanner" or name=="print" end
function C.error(line,message) error({bwError=true,line=line,message=message},0) end
function C.signature(call)
	if not C.known(call.name) then C.error(call.line,"Unknown function '"..call.name.."' (names are case-sensitive).") end
	local seen,value,keyword={},false,false
	for _,arg in call.args do
		local key=arg.key or "value"
		if arg.key and arg.key~="to" and arg.key~="best_effort" then C.error(call.line,"Unknown argument '"..arg.key.."'.") end
		if seen[key] then C.error(call.line,"Duplicate '"..key.."' argument.") end
		seen[key]=true
		if arg.key then keyword=true elseif keyword then C.error(call.line,"Put positional arguments before named arguments.") end
		if key=="value" or key=="to" then
			if value then C.error(call.line,"Use one value: either degrees or to=heading.") end
			value=true
			if key=="to" and not C.turns[call.name] then C.error(call.line,"Only chassis/turret turns support to=heading.") end
		elseif key~="best_effort" or call.name=="print" then C.error(call.line,"Unknown argument '"..key.."'.") end
	end
	if not value and call.name~="fire" then C.error(call.line,"Expected a value for "..call.name..".") end
end
function C.validate(name,key,value,line)
	if key=="best_effort" then
		if type(value)~="boolean" then C.error(line,"best_effort must be a boolean (true or false).") end
		return value
	end
	if name=="print" then return value end
	if type(value)~="number" or value~=value or math.abs(value)==math.huge then C.error(line,name.." expects a finite number.") end
	if name=="Scanner" then local n=value%360; return if n>=360 then 0 else n end
	local absolute=key=="to"
	local limit=if absolute then Limits.MaxAbsoluteAngle elseif C.moves[name] then Limits.MaxDistance elseif C.turns[name] then Limits.MaxRelativeAngle else Limits.MaxFireSeconds
	if (not absolute and value<0) or math.abs(value)>limit then C.error(line,string.format("Argument must be %s to %g.",if absolute then tostring(-limit) else "0",limit)) end
	if absolute then local n=value%360; return if n>=360 then 0 else n end
	return value
end
function C.resolve(call,evaluate)
	local instruction={op=call.name,value=nil,absolute=false,bestEffort=true,line=call.line,text=call.text}
	for _,arg in call.args do
		local key=arg.key or "value"
		local value=C.validate(call.name,key,evaluate(arg.expression),call.line)
		if key=="best_effort" then instruction.bestEffort=value
		else instruction.value=value; instruction.absolute=key=="to" end
	end
	return instruction
end
return C
