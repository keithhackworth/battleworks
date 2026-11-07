-- Data-only parser. Never evaluates Luau, expressions, or user-supplied functions.
local Limits=require(script.Parent.BWConfig)
local Parser={}
local moves={forward=true,back=true}
local turns={turn_left=true,turn_right=true,turret_left=true,turret_right=true}
local function trim(s) return s:match("^%s*(.-)%s*$") end
local function failure(line,message) return nil,{line=line,message=string.format("Line %d: %s",line,message)} end
local function number(s)
	if not s:match("^[+-]?%d+%.?%d*$") and not s:match("^[+-]?%.%d+$") then return nil end
	local value=tonumber(s)
	return if value and value==value and math.abs(value)<math.huge then value else nil
end
function Parser.parse(source)
	if type(source)~="string" then return failure(1,"Source must be text.") end
	if #source>Limits.MaxSourceBytes then return failure(1,"Program exceeds 16,384 bytes.") end
	local instructions={}
	local line=0
	local lines=if source:sub(-1)=="\n" then source else source.."\n"
	for raw in lines:gmatch("([^\n]*)\n") do
		line+=1
		if line>Limits.MaxLines then return failure(line,"Too many source lines (maximum 400).") end
		local text=trim((raw:gsub("#.*$","")))
		if text=="" then continue end
		local op,argument=text:match("^([%a_][%w_]*)%s*%((.-)%)%s*$")
		if not op then return failure(line,"Expected one command, for example forward(10).") end
		if not moves[op] and not turns[op] and op~="fire" then return failure(line,"Unknown command '"..op.."' (names are case-sensitive).") end
		argument=trim(argument)
		local absolute,bestEffort,hasValue,seenBest,sawKeyword=false,true,false,false,false
		local valueText
		if argument~="" then
			for rawArgument in (argument..","):gmatch("([^,]*),") do
				local token=trim(rawArgument)
				if token=="" then return failure(line,"Empty argument or trailing comma.") end
				local key,literal=token:match("^([%a_][%w_]*)%s*=%s*(.-)%s*$")
				if key then
					sawKeyword=true
					if key=="best_effort" then
						if seenBest then return failure(line,"Duplicate best_effort argument.") end
						if literal~="true" and literal~="false" then return failure(line,"best_effort must be true or false (lowercase).") end
						seenBest=true; bestEffort=literal=="true"
					elseif key=="to" then
						if not turns[op] then return failure(line,"Only chassis/turret turns support to=heading.") end
						if hasValue then return failure(line,"Use one angle: either degrees or to=heading.") end
						absolute=true; hasValue=true; valueText=literal
					else return failure(line,"Unknown argument '"..key.."'.") end
				else
					if sawKeyword then return failure(line,"Put the distance/angle/duration before named arguments.") end
					if hasValue then return failure(line,"Only one positional argument is allowed.") end
					hasValue=true; valueText=token
				end
			end
		end
		local value
		if not hasValue and op=="fire" then value=nil
		else
			value=if valueText then number(valueText) else nil
			if value==nil then return failure(line,"Expected a finite decimal number"..(if turns[op] then " or to=heading." else ".")) end
			local limit=if absolute then Limits.MaxAbsoluteAngle elseif moves[op] then Limits.MaxDistance elseif turns[op] then Limits.MaxRelativeAngle else Limits.MaxFireSeconds
			if (not absolute and value<0) or math.abs(value)>limit then
				return failure(line,string.format("Argument must be %s to %g.",if absolute then tostring(-limit) else "0",limit))
			end
			if absolute then value=value%360 end
		end
		table.insert(instructions,{op=op,value=value,absolute=absolute,bestEffort=bestEffort,line=line,text=text:sub(1,200)})
		if #instructions>Limits.MaxInstructions then return failure(line,"Too many commands (maximum 128).") end
	end
	return instructions
end
return Parser
