-- Indentation/block AST with bounded source size and scheduler-controlled loops.
local Limits=require(script.Parent.BWConfig)
local Lexer=require(script.Parent.BWLexer)
local Expression=require(script.Parent.BWExpression)
local Commands=require(script.Parent.BWCommands)
local Value=require(script.Parent.BWValue)
local Analysis=require(script.Parent.BWFunctionAnalysis)
local Parser={}
local reserved={CONST=true,const=true,["function"]=true,['with']=true,['thread']=true,['if']=true,['elif']=true,['else']=true,['switch']=true,['case']=true,['default']=true,['and']=true,['or']=true,['not']=true,['true']=true,['false']=true,['null']=true,['while']=true,['for']=true,['def']=true,['break']=true,['return']=true}
local function parse(source)
	if type(source)~="string" then Commands.error(1,"Source must be text.") end
	if #source>Limits.MaxSourceBytes then Commands.error(1,"Program exceeds 16,384 bytes.") end
	local lines,line={},0
	for raw in ((if source:sub(-1)=="\n" then source else source.."\n")):gmatch("([^\n]*)\n") do
		line+=1
		if line>Limits.MaxLines then Commands.error(line,"Too many source lines (maximum 400).") end
		local tokens=Lexer.line(raw,line)
		if tokens[1].kind=="eof" then continue end
		local leading=raw:match("^[ \t]*")
		if leading:find("\t",1,true) then Commands.error(line,"Indent with four spaces; tabs are not allowed.") end
		if #leading%Limits.IndentWidth~=0 then Commands.error(line,"Indentation must use multiples of four spaces.") end
		table.insert(lines,{tokens=tokens,indent=#leading,line=line,text=raw:match("^%s*(.-)%s*$"):sub(1,200)})
	end
 -- Register headers before bodies, so forward and mutually recursive calls validate.
 local functions={}
 for _,row in lines do
  local ts=row.tokens
  if ts[1].value=="function" then
   if row.indent~=0 then Commands.error(row.line,"Function definitions must be at top level.") end
   local name=ts[2]
   if name.kind~="id" or reserved[name.value] or Commands.known(name.value) or ts[3].kind~="(" then Commands.error(row.line,"Expected function name(parameters):") end
   if functions[name.value] then Commands.error(row.line,"Duplicate function '"..name.value.."'.") end
   local params,seen={},{}; local pos=4
   if ts[pos].kind~=")" then repeat
    local immutable=ts[pos].value=="const"; if immutable then pos+=1 end
    local param=ts[pos]; pos+=1
    if param.kind~="id" or reserved[param.value] or Commands.known(param.value) or seen[param.value] then Commands.error(row.line,"Invalid or duplicate parameter name.") end
    seen[param.value]=true; table.insert(params,{name=param.value,const=immutable})
    if #params>Limits.MaxVariables then Commands.error(row.line,"Too many function parameters.") end
    if ts[pos].kind~="," then break end; pos+=1
   until false end
   if ts[pos].kind~=")" or ts[pos+1].kind~=":" or ts[pos+2].kind~="eof" then Commands.error(row.line,"Expected function name(parameters):") end
   functions[name.value]={name=name.value,parameters=params,line=row.line,locals={}}
  end
 end
 local activeFunction
	local cursor,count=1,0
    -- Like mutable BW names, constants have program-wide scope. Resolve in
    -- textual declaration order, including inside thread/branch blocks.
    local constants,mutableNames={},{}
    local function resolveConstants(n,required)
        if n.kind=="variable" then
            local value=constants[n.name]
            if value~=nil and not (activeFunction and activeFunction.locals[n.name]) then return {kind="literal",value=value,line=n.line} end
            if required then Commands.error(n.line,"CONST requires a previously declared constant; '"..n.name.."' is undefined, self-referential or runtime-dependent.") end
        elseif n.kind=="call" then
            if required then Commands.error(n.line,"Function calls are not allowed in CONST expressions.") end
            for _,arg in n.args do
                arg.expression=resolveConstants(arg.expression,false)
                local known,value=Expression.constant(arg.expression)
                if known and not n.userFunction then Commands.validate(n.name,arg.key or "value",value,n.line) end
            end
            Commands.signature(n,functions)
        elseif n.kind=="binary" then
            n.left=resolveConstants(n.left,required); n.right=resolveConstants(n.right,required)
        elseif n.kind=="unary" then n.operand=resolveConstants(n.operand,required)
        elseif n.kind=="group" then n.expression=resolveConstants(n.expression,required)
        elseif n.kind=="index" then
            if required then Commands.error(n.line,"CONST supports scalar expressions only; indexing is not allowed.") end
            n.array=resolveConstants(n.array,false); n.index=resolveConstants(n.index,false)
        elseif n.kind=="array" or n.kind=="dictionary" then
            if required then Commands.error(n.line,"CONST supports scalar values only; arrays and dictionaries are not allowed.") end
            if n.kind=="array" then for i,item in n.items do n.items[i]=resolveConstants(item,false) end
            else for _,entry in n.entries do entry.expression=resolveConstants(entry.expression,false) end end
        end
        return n
    end
    local function writable(name,line)
        if constants[name]~=nil and not (activeFunction and activeFunction.locals[name]) then Commands.error(line,"Cannot assign to CONST '"..name.."'.") end
        if functions[name] and not (activeFunction and activeFunction.locals[name]) then Commands.error(line,"Cannot assign to function '"..name.."'.") end
        if not activeFunction then mutableNames[name]=true end
    end
	local function expression(row,start,last,required)
		local node,pos=Expression.parse(row.tokens,start,functions)
		if row.tokens[pos].kind~=(last or "eof") or (last and row.tokens[pos+1].kind~="eof") then Commands.error(row.line,"Unexpected token after expression; expected "..(last or "end of line")..".") end
		return resolveConstants(node,required)
	end
	local function constant(node) return Expression.constant(node) end
	local function numericCall(row,call)
		call.text=row.text
		local all=true
		for _,arg in call.args do
			local known,value=constant(arg.expression)
			if known then Commands.validate(call.name,arg.key or "value",value,row.line) else all=false end
		end
		if all then
			local instruction=Commands.resolve(call,function(n) local _,value=constant(n); return value end)
			for _,arg in call.args do
				local expr=arg.expression
				if expr.kind~="literal" and not (expr.kind=="unary" and expr.operand.kind=="literal") then instruction.call=call end
			end
			return instruction
		end
		return {op=call.name,call=call,line=row.line,text=row.text,bestEffort=true}
	end
	local block
	local function suite(row,indent,depth)
		if not lines[cursor] or lines[cursor].indent~=indent+Limits.IndentWidth then Commands.error(row.line,"Expected an indented block of four spaces.") end
		return block(indent+Limits.IndentWidth,depth+1)
	end
	block=function(indent,depth)
		if depth>Limits.MaxBlockDepth then Commands.error(lines[cursor].line,"Block nesting exceeds limit.") end
		local result={}
		while lines[cursor] and lines[cursor].indent>=indent do
			local row=lines[cursor]
			if row.indent~=indent then Commands.error(row.line,"Unexpected indentation.") end
			count+=1; if count>Limits.MaxInstructions then Commands.error(row.line,"Too many statements (maximum 128).") end
			local token=row.tokens[1]; local word=token.value
			cursor+=1
			local node={line=row.line,text=row.text}
			if word=="function" then
                node.kind="function"; node.name=row.tokens[2].value
                local fn=functions[node.name]; activeFunction=fn
                for _,param in fn.parameters do fn.locals[param.name]=true end
                -- Assignments anywhere in a function are local, including before their first write.
                local scan=cursor
                while lines[scan] and lines[scan].indent>indent do
                 local ts=lines[scan].tokens
                 if ts[1].kind=="id" and ts[2].kind=="=" then fn.locals[ts[1].value]=true end
                 scan+=1
                end
                local localsCount=0; for _ in fn.locals do localsCount+=1 end
                if localsCount>Limits.MaxVariables then Commands.error(row.line,"Too many function-local bindings.") end
                node.body=suite(row,indent,depth); fn.body=node.body; activeFunction=nil
            elseif word=="return" then
                if not activeFunction then Commands.error(row.line,"return is only valid inside a function.") end
                node.kind="return"; node.expression=if row.tokens[2].kind=="eof" then {kind="literal",value=Value.Null,line=row.line} else expression(row,2)
                constant(node.expression)
            elseif word=="CONST" or word=="const" then
                local name=row.tokens[2]
                if name.kind~="id" or reserved[name.value] or Commands.known(name.value) or row.tokens[3].kind~="=" then Commands.error(row.line,"Expected CONST name = scalar expression; name must not be reserved.") end
                if functions[name.value] then Commands.error(row.line,"Constant conflicts with function name.") end
                if activeFunction then Commands.error(row.line,"Declare compile-time constants at top level, outside functions.") end
                if constants[name.value]~=nil or mutableNames[name.value] then Commands.error(row.line,"Duplicate or conflicting CONST name '"..name.value.."'.") end
                local initializer=expression(row,4,nil,true)
                local known,value=constant(initializer)
                if not known or Value.isArray(value) or Value.isDictionary(value) then Commands.error(row.line,"CONST requires a compile-time scalar expression.") end
                constants[name.value]=value
                node.kind="const" -- retained for source diagnostics; emits nothing
                node.name=name.value; node.value=value
            elseif word=="with" then
                if indent~=0 then Commands.error(row.line,"Thread entry blocks must be at the top level.") end
                local t=row.tokens
                if t[2].value~="thread" or t[3].kind~="(" or t[4].kind~="number" or t[5].kind~=")" or t[6].kind~=":" or t[7].kind~="eof" or t[4].value%1~=0 or t[4].value<1 or t[4].value>16 then Commands.error(row.line,"Expected with thread(1..16):") end
                node.kind="thread"; node.id=t[4].value; node.body=suite(row,indent,depth)
            elseif word=="if" then
				node.kind="if"; node.branches={}
				local condition=expression(row,2,":"); local known,value=constant(condition)
				if known then Expression.boolean(value,row.line) end
				table.insert(node.branches,{condition=condition,body=suite(row,indent,depth),line=row.line,text=row.text})
				while lines[cursor] and lines[cursor].indent==indent and lines[cursor].tokens[1].value=="elif" do
					local branch=lines[cursor]; cursor+=1
					local test=expression(branch,2,":"); local static,v=constant(test); if static then Expression.boolean(v,branch.line) end
					table.insert(node.branches,{condition=test,body=suite(branch,indent,depth),line=branch.line,text=branch.text})
				end
				if lines[cursor] and lines[cursor].indent==indent and lines[cursor].tokens[1].value=="else" then
					local otherwise=lines[cursor]; cursor+=1
					if otherwise.tokens[2].kind~=":" or otherwise.tokens[3].kind~="eof" then Commands.error(otherwise.line,"Expected else: with no condition.") end
					node.otherwise=suite(otherwise,indent,depth)
				end
			elseif word=="while" then
                node.kind="while"; node.condition=expression(row,2,":"); constant(node.condition)
                node.body=suite(row,indent,depth)
            elseif word=="switch" then
				node.kind="switch"; node.expression=expression(row,2,":"); constant(node.expression); node.cases={}
				if not lines[cursor] or lines[cursor].indent~=indent+Limits.IndentWidth then Commands.error(row.line,"Expected indented case/default branches.") end
				local labels={}
				while lines[cursor] and lines[cursor].indent==indent+Limits.IndentWidth do
					local branch=lines[cursor]; cursor+=1
					if branch.tokens[1].value=="case" then
						local label=expression(branch,2,":"); local known,value=constant(label)
						if not known or Value.isArray(value) or Value.isDictionary(value) then Commands.error(branch.line,"Case labels must be constant numbers, strings, booleans or null.") end
						for _,old in labels do if Value.equal(old,value) then Commands.error(branch.line,"Duplicate case value.") end end
						table.insert(labels,value)
						table.insert(node.cases,{value=value,body=suite(branch,indent+Limits.IndentWidth,depth+1),line=branch.line})
					elseif branch.tokens[1].value=="default" then
						if node.otherwise then Commands.error(branch.line,"Duplicate default branch.") end
						if branch.tokens[2].kind~=":" or branch.tokens[3].kind~="eof" then Commands.error(branch.line,"Expected default:.") end
						node.otherwise=suite(branch,indent+Limits.IndentWidth,depth+1)
					else Commands.error(branch.line,"A switch block may contain only case/default branches.") end
				end
			elseif reserved[word] then Commands.error(row.line,"Unexpected or unsupported statement '"..word.."'.")
			elseif token.kind=="id" and (row.tokens[2].kind=="." or row.tokens[2].kind=="[") then
                local target,pos=Expression.parse(row.tokens,1,functions)
                if row.tokens[pos].kind~="=" or target.kind~="index" then Commands.error(row.line,"Expected dictionary assignment.") end
                local root=target; while root.kind=="index" do root=root.array end
                if root.kind=="variable" then writable(root.name,row.line) end
                target=resolveConstants(target,false)
                node.kind="set"; node.target=target; node.expression=expression(row,pos+1); constant(node.expression)
            elseif token.kind=="id" and row.tokens[2].kind=="=" then
				if Commands.known(word) then Commands.error(row.line,"Cannot assign to built-in function '"..word.."'.") end
				writable(word,row.line)
				node.kind="assign"; node.name=word; node.expression=expression(row,3); constant(node.expression)
			else
				local call=expression(row,1)
				if call.kind~="call" then Commands.error(row.line,"Expected an assignment or function-style command.") end
				if call.name=="print" then node.kind="print"; node.expression=call.args[1].expression; constant(node.expression)
				elseif call.userFunction or Commands.special[call.name] then node.kind="call"; node.expression=call
                else node.kind="action"; node.instruction=numericCall(row,call) end
			end
			table.insert(result,node)
		end
		return result
	end
	local ast=block(0,0)
	local tips=Analysis.validate(ast,functions)
	local instructions={}
    local streams={[1]=instructions}; local declared={}
	local function emit(op,node,fields)
		local item=fields or {}; item.op=op; item.line=node.line; item.text=node.text; item.bestEffort=if item.bestEffort==nil then false else item.bestEffort
		table.insert(instructions,item)
		if #instructions>Limits.MaxCompiledInstructions then Commands.error(node.line,"Compiled program is too large.") end
		return item
	end
	local compile
	compile=function(body)
		for _,node in body do
			if node.kind=="function" then
                local previous=instructions; instructions={}
                compile(node.body); emit("$return",node,{expression={kind="literal",value=Value.Null,line=node.line}})
                functions[node.name].instructions=instructions; instructions=previous
            elseif node.kind=="return" then emit("$return",node,{expression=node.expression})
            elseif node.kind=="thread" then
                if declared[node.id] then Commands.error(node.line,"Duplicate thread entry block.") end
                declared[node.id]=true
                local previous=instructions; instructions=streams[node.id] or {}; streams[node.id]=instructions
                compile(node.body); instructions=previous
            elseif node.kind=="set" then emit("$set",node,{targetExpression=node.target,expression=node.expression})
            elseif node.kind=="call" then emit("$call",node,{expression=node.expression})
            elseif node.kind=="action" then table.insert(instructions,node.instruction)
			elseif node.kind=="assign" then emit("$assign",node,{name=node.name,expression=node.expression})
			elseif node.kind=="print" then emit("$print",node,{expression=node.expression})
			elseif node.kind=="if" then
				local exits={}
				for _,branch in node.branches do
					local test=emit("$branch",branch,{condition=branch.condition})
					compile(branch.body); table.insert(exits,emit("$jump",node))
					test.target=#instructions+1
				end
				if node.otherwise then compile(node.otherwise) end
				for _,exit in exits do exit.target=#instructions+1 end
			elseif node.kind=="while" then
                local start=#instructions+1
                local test=emit("$while",node,{condition=node.condition})
                compile(node.body); emit("$jump",node,{target=start})
                test.target=#instructions+1
            elseif node.kind=="switch" then
				local switch=emit("$switch",node,{expression=node.expression,choices={}}); local exits={}
				for _,case in node.cases do
					table.insert(switch.choices,{value=case.value,target=#instructions+1})
					compile(case.body); table.insert(exits,emit("$jump",node))
				end
				switch.target=#instructions+1
				if node.otherwise then compile(node.otherwise) end
				for _,exit in exits do exit.target=#instructions+1 end
			end
			if #instructions>Limits.MaxCompiledInstructions then Commands.error(node.line,"Compiled program is too large.") end
		end
	end
	compile(ast)
	instructions.streams=streams
 instructions.functions=functions
 instructions.tips=tips or {}
    return instructions,ast
end
function Parser.parse(source)
	local ok,instructions,ast=pcall(parse,source)
	if ok then return instructions,nil,ast end
	local err=instructions
	if type(err)~="table" or not err.bwError then return nil,{line=1,message="Line 1: Invalid BW syntax."} end
	return nil,{line=err.line or 1,message=string.format("Line %d: %s",err.line or 1,err.message)}
end
return Parser
