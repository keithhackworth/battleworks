-- Four-space indentation assistance; parser remains the authority on block syntax.
local Config=require(script.Parent.BWConfig)
local Lexer=require(script.Parent.BWLexer)
local Text={}
function Text.edit(previous,source,cursor)
	cursor=cursor or -1
	if cursor>1 and #source==#previous+1 and source:sub(cursor-1,cursor-1)=="\n"
		and source:sub(1,cursor-2)..source:sub(cursor)==previous then
		local line=source:sub(1,cursor-2):match("([^\n]*)$") or ""
		local prefix=line:match("^[ \t]*")
		local extra=0
		local ok,tokens=pcall(Lexer.line,line,1)
		if ok and #tokens>1 and tokens[#tokens-1].kind==":" then extra=Config.IndentWidth end
		local indent=prefix..string.rep(" ",extra)
		source=source:sub(1,cursor-1)..indent..source:sub(cursor); cursor+=#indent
	end
	local out,offset,delta={},1,0
	for line,ending in (source.."\n"):gmatch("([^\n]*)(\n)") do
		local originalLength=#line
		local prefix=line:match("^[ \t]*"); local columns=0
		for c in prefix:gmatch(".") do columns=if c=="\t" then (math.floor(columns/Config.IndentWidth)+1)*Config.IndentWidth else columns+1 end
		if prefix:find("\t",1,true) then
			local replacement=string.rep(" ",columns)
			if cursor>=offset+#prefix then delta+=#replacement-#prefix
			elseif cursor>=offset then
				local before=prefix:sub(1,cursor-offset); local width=0
				for c in before:gmatch(".") do width=if c=="\t" then (math.floor(width/Config.IndentWidth)+1)*Config.IndentWidth else width+1 end
				delta+=width-#before
			end
			line=replacement..line:sub(#prefix+1)
		end
		table.insert(out,line); offset+=originalLength+1
	end
	return table.concat(out,"\n"),if cursor<0 then cursor else cursor+delta
end
return Text
