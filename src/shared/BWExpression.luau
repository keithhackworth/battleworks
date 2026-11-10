-- Bounded Pratt AST and strict evaluator. No Luau evaluation or speculative calls.
local Limits=require(script.Parent.BWConfig)
local Commands=require(script.Parent.BWCommands)
local Value=require(script.Parent.BWValue)
local E={}
local dynamic={dynamic=true}
local precedence={['or']=10,['and']=20,['==']=30,['!=']=30,['<']=30,['<=']=30,['>']=30,['>=']=30,['+']=40,['-']=40,['*']=50,['/']=50}
function E.parse(tokens,start,functions)
	local pos,nodes=start or 1,0
	local function node(kind,fields)
		nodes+=1; if nodes>Limits.MaxExpressionNodes then Commands.error(tokens[pos].line,"Expression is too large.") end
		fields.kind=kind; fields.line=fields.line or tokens[pos].line; return fields
	end
	local function take(kind)
		local token=tokens[pos]
		if kind and token.kind~=kind then Commands.error(token.line,"Expected '"..kind.."'.") end
		pos+=1; return token
	end
	local parse
	parse=function(minimum,depth)
		if depth>Limits.MaxExpressionDepth then Commands.error(tokens[pos].line,"Expression nesting exceeds limit.") end
		local token=take(); local left
		if token.kind=="number" or token.kind=="string" then left=node("literal",{value=token.value,line=token.line})
		elseif token.kind=="id" and (token.value=="true" or token.value=="false" or token.value=="null") then
			left=node("literal",{value=if token.value=="null" then Value.Null else token.value=="true",line=token.line})
		elseif token.kind=="-" or token.kind=="+" or (token.kind=="id" and token.value=="not") then
			left=node("unary",{op=token.value,operand=parse(if token.value=="not" then 25 else 60,depth+1),line=token.line})
		elseif token.kind=="(" then left=node("group",{expression=parse(0,depth+1),line=token.line}); take(")")
		elseif token.kind=="{" then
            local entries={}
            if tokens[pos].kind~="}" then repeat
                local token=take(); if token.kind~="string" and token.kind~="id" then Commands.error(token.line,"Expected a dictionary key.") end; local key=token.value; take(":"); table.insert(entries,{key=key,expression=parse(0,depth+1)})
                if #entries>Limits.MaxArrayItems then Commands.error(token.line,"Dictionary is too large.") end
                if tokens[pos].kind~="," then break end; take(",")
            until false end
            take("}"); left=node("dictionary",{entries=entries,line=token.line})
        elseif token.kind=="[" then
			local items={}
			if tokens[pos].kind~="]" then repeat
				table.insert(items,parse(0,depth+1)); if #items>Limits.MaxArrayItems then Commands.error(token.line,"Array is too large.") end
				if tokens[pos].kind~="," then break end; take(",")
				if tokens[pos].kind=="]" then Commands.error(token.line,"Trailing comma is not supported.") end
			until false end
			take("]"); left=node("array",{items=items,line=token.line})
		elseif token.kind=="id" then
			if tokens[pos].kind=="(" then
				take("("); local args={}
				if tokens[pos].kind~=")" then repeat
					local key
					if tokens[pos].kind=="id" and tokens[pos+1] and tokens[pos+1].kind=="=" then key=take().value; take("=") end
					table.insert(args,{key=key,expression=parse(0,depth+1)})
					if tokens[pos].kind~="," then break end; take(",")
					if tokens[pos].kind==")" then Commands.error(token.line,"Trailing comma is not supported.") end
				until false end
				take(")"); left=node("call",{name=token.value,args=args,line=token.line}); Commands.signature(left,functions)
			else left=node("variable",{name=token.value,line=token.line}) end
		else Commands.error(token.line,"Expected an expression.") end
		while true do
			local nextToken=tokens[pos]
			if nextToken.kind=="." then
                take("."); local key=take("id"); left=node("index",{array=left,index=node("literal",{value=key.value,line=key.line}),line=token.line})
            elseif nextToken.kind=="[" then
				take("["); local index=parse(0,depth+1); take("]"); left=node("index",{array=left,index=index,line=token.line})
			else
				local bp=precedence[nextToken.value]
				if not bp or bp<=minimum then break end
				if bp==30 and left.kind=="binary" and precedence[left.op]==30 then Commands.error(token.line,"Use 'and' between comparisons instead of chaining them.") end
				take(); left=node("binary",{op=nextToken.value,left=left,right=parse(bp,depth+1),line=token.line})
			end
		end
		return left
	end
	local expression=parse(0,1)
	-- Left-associative trees also need a depth check (not just parse recursion).
	local function validate(n,depth,root)
		if depth>Limits.MaxExpressionDepth then Commands.error(n.line,"Expression nesting exceeds limit.") end
		if n.kind=="call" then

			for _,arg in n.args do
				validate(arg.expression,depth+1,false)
				local known,value=E.constant(arg.expression)
				if known and not n.userFunction then Commands.validate(n.name,arg.key or "value",value,n.line) end
			end
		elseif n.kind=="binary" then validate(n.left,depth+1,false); validate(n.right,depth+1,false)
		elseif n.kind=="unary" then validate(n.operand,depth+1,false)
		elseif n.kind=="group" then validate(n.expression,depth+1,false)
		elseif n.kind=="index" then validate(n.array,depth+1,false); validate(n.index,depth+1,false)
		elseif n.kind=="array" then for _,item in n.items do validate(item,depth+1,false) end
        elseif n.kind=="dictionary" then for _,entry in n.entries do validate(entry.expression,depth+1,false) end end
	end
	validate(expression,1,true)
	return expression,pos
end
local function charge(context,category) if context and context.charge then context.charge(category) end end
local function boolean(value,line)
	if type(value)~="boolean" then Commands.error(line,"Expected a boolean, got "..Value.type(value)..".") end
	return value
end
E.boolean=boolean
-- While deliberately accepts value truthiness; existing if/logical contracts
-- remain strict booleans. Undefined variable reads still raise normal errors.
function E.truthy(value)
 if value==nil or value==Value.Null or value==false or value==0 or value=="" then return false end
 if Value.isArray(value) then return #value>0 end
 if Value.isDictionary(value) then return next(value)~=nil end
 return true
end
function E.evaluate(n,context)
	local kind=n.kind
	if kind=="literal" then return n.value end
	if kind=="group" then return E.evaluate(n.expression,context) end
	if kind=="variable" then
		if not context or context.constant then error(dynamic,0) end
		if not n.constParameter then charge(context,"read") end
		local value=context.variables[n.name]
		if value==nil then Commands.error(n.line,"Undefined variable '"..n.name.."'.") end
		return value
	end
	if kind=="dictionary" then
        local entries={}; for _,entry in n.entries do entries[entry.key]=E.evaluate(entry.expression,context) end
        return Value.dictionary(entries)
    end
    if kind=="array" then
		local items={}; for _,item in n.items do table.insert(items,E.evaluate(item,context)) end
		return Value.mutableArray(items)
	end
	if kind=="index" then
		local array,index=E.evaluate(n.array,context),E.evaluate(n.index,context)
		charge(context,"access")
        if Value.isDictionary(array) then
            if type(index)~="string" then Commands.error(n.line,"Dictionary keys must be strings.") end
            return array[index] or (if array[index]==false then false else Value.Null)
        end
		if not Value.isArray(array) then Commands.error(n.line,"Cannot index "..Value.type(array).."; expected an array.") end
		if #array==0 then Commands.error(n.line,"Cannot index an empty array.") end
		if type(index)~="number" or index%1~=0 or index<0 or index>=#array then Commands.error(n.line,"Array index must be an integer from 0 to "..tostring(#array-1)..".") end
		return Value.get(array,index)
	end
	if kind=="call" then
		if not context or context.constant then error(dynamic,0) end
        if context.call then return context.call(n,function(arg) return E.evaluate(arg,context) end) end
        if n.name~="Scanner" then Commands.error(n.line,"This runtime does not support this value-returning function.") end
		local instruction=Commands.resolve(n,function(arg) return E.evaluate(arg,context) end)
		return context.scan(instruction.value,instruction.bestEffort,n.line)
	end
	if kind=="unary" then
		local value=E.evaluate(n.operand,context)
		if n.op=="not" then charge(context,"logical"); return not boolean(value,n.line) end
		charge(context,"arithmetic")
		if type(value)~="number" then Commands.error(n.line,"Unary "..n.op.." requires a number.") end
		return if n.op=="-" then -value else value
	end
	local op=n.op
	local a=E.evaluate(n.left,context)
	if op=="and" or op=="or" then
		charge(context,"logical"); boolean(a,n.line)
		if (op=="and" and not a) or (op=="or" and a) then return a end
		return boolean(E.evaluate(n.right,context),n.line)
	end
	local b=E.evaluate(n.right,context)
	if op=="==" or op=="!=" then charge(context,"comparison"); local same=Value.equal(a,b); return if op=="==" then same else not same end
	if op=="<" or op=="<=" or op==">" or op==">=" then
		charge(context,"comparison")
		if type(a)~=type(b) or (type(a)~="number" and type(a)~="string") then Commands.error(n.line,"Ordering requires two numbers or two strings of the same type.") end
		if op=="<" then return a<b elseif op=="<=" then return a<=b elseif op==">" then return a>b else return a>=b end
	end
	charge(context,"arithmetic")
	if type(a)~="number" or type(b)~="number" then Commands.error(n.line,"Arithmetic requires numbers; no automatic type conversion.") end
	if op=="/" and b==0 then Commands.error(n.line,"Division by zero.") end
	local value=if op=="+" then a+b elseif op=="-" then a-b elseif op=="*" then a*b else a/b
	if value~=value or math.abs(value)==math.huge then Commands.error(n.line,"Arithmetic produced a non-finite number.") end
	return value
end
function E.constant(n)
	local ok,value=pcall(E.evaluate,n,{constant=true})
	if ok then return true,value end
	if value==dynamic then return false end
	error(value,0)
end
return E
