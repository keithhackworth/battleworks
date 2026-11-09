-- Shared argument contracts for static validation and evaluated action inputs.
local Limits=require(script.Parent.BWConfig)
local C={}
C.special={get_clock=true,get_facing_direction=true,wait_for_clock=true,wait_for=true,variable_has_changed=true,clear_queue=true,abort_command=true,command_status=true}
C.moves={forward=true,back=true}
C.turns={turn_left=true,turn_right=true,turret_left=true,turret_right=true}
function C.known(name) return C.special[name] or C.moves[name] or C.turns[name] or name=="fire" or name=="Scanner" or name=="print" end
function C.error(line,message) error({bwError=true,line=line,message=message},0) end
function C.signature(call)
	if not C.known(call.name) then C.error(call.line,"Unknown function '"..call.name.."' (names are case-sensitive).") end
	if C.special[call.name] then
        local count=if call.name=="get_clock" or call.name=="get_facing_direction" then 0 else 1
        if #call.args~=count or (#call.args>0 and call.args[1].key) then C.error(call.line,call.name.." expects "..count.." positional arguments.") end
        if (call.name=="wait_for" or call.name=="variable_has_changed") and call.args[1].expression.kind~="variable" then C.error(call.line,call.name.." requires a variable name, not its evaluated value.") end
        return
    end
    local seen,value,keyword={},false,false
	for _,arg in call.args do
		local key=arg.key or "value"
		if arg.key and arg.key~="to" and arg.key~="position" and arg.key~="best_effort" then C.error(call.line,"Unknown argument '"..arg.key.."'.") end
		if seen[key] then C.error(call.line,"Duplicate '"..key.."' argument.") end
		seen[key]=true
		if arg.key then keyword=true elseif keyword then C.error(call.line,"Put positional arguments before named arguments.") end
		if key=="value" or key=="to" or key=="position" then
			if value then C.error(call.line,"Use one input: positional value, to=heading, or Scanner position=index.") end
			value=true
			if key=="position" and call.name~="Scanner" then C.error(call.line,"Only Scanner supports position=index.") end
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
	if name=="print" or C.special[name] then return value end
	if type(value)~="number" or value~=value or math.abs(value)==math.huge then C.error(line,name.." expects a finite number.") end
	if name=="Scanner" then
        if key=="position" then
            if value%1~=0 or value<0 or value>7 then C.error(line,"invalidSensor: position must be an integer from 0 to 7.") end
            return value*45
        end
        local n=value%360
        if n%45~=0 then C.error(line,string.format("invalidSensor: use mounted angles at 45 degree increments (nearby %d or %d).",math.floor(n/45)*45,(math.ceil(n/45)*45)%360)) end
        return n
    end
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
