-- Tokenize data only, with quote-aware comments and bounded literal sizes.
local Limits=require(script.Parent.BWConfig)
local Commands=require(script.Parent.BWCommands)
local Lexer={}
function Lexer.line(source,line)
	local result,i={},1
	local function add(kind,value) table.insert(result,{kind=kind,value=value,line=line}); if #result>Limits.MaxTokensPerLine then Commands.error(line,"Too many tokens on one line.") end end
	while i<=#source do
		local c=source:sub(i,i)
		if c=="#" then break
		elseif c:match("%s") then i+=1
		elseif c=='"' or c=="'" then
			local quote,start,out=c,i,{}; i+=1; local closed=false
			while i<=#source do
				c=source:sub(i,i); i+=1
				if c==quote then closed=true; break end
				if c=="\\" then
					local escape=source:sub(i,i); i+=1
					local escaped=({n="\n",r="\r",t="\t",['"']='"',["'"]="'",["\\"]="\\"})[escape]
					if not escaped then Commands.error(line,"Unsupported string escape.") end
					c=escaped
				end
				table.insert(out,c)
			end
			if not closed then Commands.error(line,"Unterminated string literal.") end
			local value=table.concat(out)
			if #value>Limits.MaxStringBytes then Commands.error(line,"String literal is too long.") end
			add("string",value)
		elseif c:match("[%a_]") then
			local id=source:sub(i):match("^[%a_][%w_]*"); i+=#id
			if #id>64 then Commands.error(line,"Variable/function name is too long.") end
			add("id",id)
		elseif c:match("%d") or (c=="." and source:sub(i+1,i+1):match("%d")) then
			local literal=source:sub(i):match("^%d*%.?%d+")
			if not literal then Commands.error(line,"Invalid number.") end
			i+=#literal
			if source:sub(i,i):match("[eE]") then
				local exponent=source:sub(i):match("^[eE][+-]?%d+")
				if not exponent then Commands.error(line,"Invalid numeric exponent.") end
				literal..=exponent; i+=#exponent
			end
			-- Retain the old acceptance of a trailing decimal point (10.).
			if source:sub(i,i)=="." and not literal:find("%.") and not literal:find("[eE]") then literal..="."; i+=1 end
			local value=tonumber(literal)
			if not value or value~=value or math.abs(value)==math.huge then Commands.error(line,"Expected a finite number.") end
			add("number",value)
		else
			local pair=source:sub(i,i+1)
			if pair=="==" or pair=="!=" or pair=="<=" or pair==">=" then add(pair,pair); i+=2
			elseif c:match("[+%-%*/%(%)%[%],:=<>]") then add(c,c); i+=1
			else Commands.error(line,"Unexpected character '"..c.."'.") end
		end
	end
	add("eof","")
	return result
end
return Lexer
