-- Conservative, whole-program allocation-site points-to analysis. No runtime
-- const traps: unknown reference flows are rejected at compilation. Flow-insensitive
-- unions deliberately retain aliases across branches, loops and recursive calls.
local Commands=require(script.Parent.BWCommands)
local Expression=require(script.Parent.BWExpression)
local A={}
local function value(scalar,unknown,readonly) return {scalar=scalar or false,unknown=unknown or false,readonly=readonly or false,refs={}} end
local function merge(a,b)
 local changed=false
 for _,k in {"scalar","unknown","readonly"} do if b[k] and not a[k] then a[k]=true; changed=true end end
 for id in b.refs do if not a.refs[id] then a.refs[id]=true; changed=true end end
 return changed
end
local function copy(v) local out=value(); merge(out,v); return out end
local function reference(v) return v.unknown or next(v.refs)~=nil end
function A.validate(ast,functions)
 if next(functions)==nil then return end
 local wildcard={}
 local globals,heap,contexts={}, {},{}; local changed=false; local threads={ [1]=true }
 local function slot(env,name) if not env[name] then env[name]=value() end; return env[name] end
 for name,fn in functions do
  local ctx={fn=fn,env={},returns=value(),writes=value(),calls={},rebound={}}; contexts[name]=ctx
  for localName in fn.locals do slot(ctx.env,localName) end
 end
 local function collect(body)
  for _,n in body do
   if n.kind=="thread" then threads[n.id]=true; collect(n.body)
   elseif n.kind=="if" then for _,b in n.branches do collect(b.body) end; if n.otherwise then collect(n.otherwise) end
   elseif n.kind=="while" then collect(n.body)
   elseif n.kind=="switch" then for _,b in n.cases do collect(b.body) end; if n.otherwise then collect(n.otherwise) end end
  end
 end
 collect(ast); local threadCount=0; for _ in threads do threadCount+=1 end
 local function update(a,b) if merge(a,b) then changed=true end end
 local function binding(ctx,name)
  return if ctx and ctx.fn.locals[name] then slot(ctx.env,name) else slot(globals,name)
 end
 local eval
 eval=function(n,ctx)
  if not n then return value(true) end
  if n.kind=="variable" then
   local v=copy(binding(ctx,n.name))
   if ctx then for _,p in ctx.fn.parameters do if p.name==n.name and p.const then v.readonly=true; n.constParameter=true end end end
   return v
  elseif n.kind=="group" then return eval(n.expression,ctx)
  elseif n.kind=="literal" then return value(true)
  elseif n.kind=="unary" then eval(n.operand,ctx); return value(true)
  elseif n.kind=="binary" then eval(n.left,ctx); eval(n.right,ctx); return value(true)
  elseif n.kind=="array" or n.kind=="dictionary" then
   if not heap[n] then heap[n]={} end
   if n.kind=="array" then for i,item in n.items do update(slot(heap[n],i-1),eval(item,ctx)) end
   else for _,e in n.entries do update(slot(heap[n],e.key),eval(e.expression,ctx)) end end
   local v=value(); v.refs[n]=true; return v
  elseif n.kind=="index" then
   local base=eval(n.array,ctx); eval(n.index,ctx)
   local v=value(false,base.unknown,base.readonly)
   local known,key=Expression.constant(n.index)
   for id in base.refs do
    local fields=heap[id] or {}
    if known and key~=nil then if fields[key] then merge(v,fields[key]) else v.unknown=true end; if fields[wildcard] then merge(v,fields[wildcard]) end
    else for _,item in fields do merge(v,item) end; v.unknown=true end
   end
   return v
  elseif n.kind=="call" then
   local fn=functions[n.name]
   if fn then
    local other=contexts[n.name]
    if ctx then ctx.calls[n.name]=true end
    for i,arg in n.args do update(slot(other.env,fn.parameters[i].name),eval(arg.expression,ctx)) end
    -- Readonly authority belongs to the invocation, not the returned object.
    local v=copy(other.returns); v.readonly=false; return v
   end
   for _,arg in n.args do eval(arg.expression,ctx) end
   -- Built-in result records have known scalar metadata. Their public records
   -- are immutable; unknown extension fields remain conservatively unknown.
   heap[n]=heap[n] or {}
   for _,key in {"status","reason","commandId","state","completionReason","device","steeringDegrees","time","world_direction","changed","version","count","timestamp","sensor","range"} do
    update(slot(heap[n],key),value(true))
   end
   local v=value(false,false,true); v.refs[n]=true
   return v
  end
  return value(false,true)
 end
 local walk
 walk=function(body,ctx)
  for _,n in body do
   if n.kind=="function" then continue end
   if n.kind=="assign" then
    if ctx then ctx.rebound[n.name]=true end
    update(binding(ctx,n.name),eval(n.expression,ctx))
   elseif n.kind=="set" then
    local base=eval(n.target.array,ctx); local v=eval(n.expression,ctx); eval(n.target.index,ctx)
    if ctx then update(ctx.writes,base) end
    local key=if n.target.index.kind=="literal" then n.target.index.value else nil
    for id in base.refs do if heap[id] then update(slot(heap[id],if key~=nil then key else wildcard),v) end end
   elseif n.kind=="return" then update(ctx.returns,eval(n.expression,ctx))
   elseif n.kind=="action" then if n.instruction.call then eval(n.instruction.call,ctx) end
   elseif n.kind=="call" or n.kind=="print" then eval(n.expression,ctx)
   elseif n.kind=="thread" or n.kind=="while" then if n.condition then eval(n.condition,ctx) end; walk(n.body,ctx)
   elseif n.kind=="if" then for _,b in n.branches do eval(b.condition,ctx); walk(b.body,ctx) end; if n.otherwise then walk(n.otherwise,ctx) end
   elseif n.kind=="switch" then eval(n.expression,ctx); for _,b in n.cases do walk(b.body,ctx) end; if n.otherwise then walk(n.otherwise,ctx) end end
  end
 end
 local converged=false
 for _=1,256 do
  changed=false; walk(ast,nil)
  for _,ctx in contexts do walk(ctx.fn.body,ctx); for name in ctx.calls do update(ctx.writes,contexts[name].writes) end end
  if not changed then converged=true; break end
 end
 if not converged then Commands.error(1,"Function alias analysis exceeded its complexity limit.") end
 -- Uncalled/unresolved parameters are unknown, never optimistically scalars.
 for _,ctx in contexts do for _,p in ctx.fn.parameters do
  local v=ctx.env[p.name]; if not v.scalar and next(v.refs)==nil then v.unknown=true end
 end end
 -- Propagate unknowns through derived fields/aliases as well as known roots.
 converged=false
 for _=1,256 do
  changed=false; walk(ast,nil)
  for _,ctx in contexts do walk(ctx.fn.body,ctx); for name in ctx.calls do update(ctx.writes,contexts[name].writes) end end
  if not changed then converged=true; break end
 end
 if not converged then Commands.error(1,"Function alias analysis exceeded its complexity limit.") end
 local function reachable(v)
  local out=copy(v); local seen={}
  local function visit(id)
   if seen[id] then return end; seen[id]=true
   for _,field in heap[id] or {} do merge(out,field); for child in field.refs do visit(child) end end
  end
  for id in v.refs do visit(id) end
  return out
 end
 local function overlap(a,b)
  a=reachable(a); b=reachable(b)
  if (a.unknown and reference(b)) or (b.unknown and reference(a)) then return true end
  for id in a.refs do if b.refs[id] then return true end end
  return false
 end
 local shared=value(); for _,v in globals do merge(shared,v) end
 local checkExpression
 checkExpression=function(n,ctx,protected)
  if not n then return end
  if n.kind=="call" then
   local fn=functions[n.name]
   if fn then
    local args={}; for i,arg in n.args do args[i]=eval(arg.expression,ctx) end
    for i,param in fn.parameters do
     local arg=args[i]
     if not param.const and reference(arg) and (arg.readonly or overlap(arg,protected)) then Commands.error(n.line,"Cannot pass const object to mutable parameter '"..param.name.."' of "..fn.name.."().") end
     if param.const and reference(arg) then
      for j,other in fn.parameters do if not other.const and reference(args[j]) and overlap(arg,args[j]) then Commands.error(n.line,"Potential const/mutable alias conflict in "..fn.name.."().") end end
      if threadCount>1 and overlap(arg,shared) then Commands.error(n.line,"Const reference may alias shared state accessed by another BW thread; use function-local independent storage.") end
      if overlap(arg,contexts[fn.name].writes) then Commands.error(n.line,"Function may mutate an alias of its const argument.") end
     end
    end
    if reference(protected) and overlap(protected,contexts[fn.name].writes) then Commands.error(n.line,"Called function may mutate a protected const alias.") end
   end
   for _,arg in n.args do checkExpression(arg.expression,ctx,protected) end
  elseif n.kind=="index" then checkExpression(n.array,ctx,protected); checkExpression(n.index,ctx,protected)
  elseif n.kind=="binary" then checkExpression(n.left,ctx,protected); checkExpression(n.right,ctx,protected)
  elseif n.kind=="unary" then checkExpression(n.operand,ctx,protected)
  elseif n.kind=="group" then checkExpression(n.expression,ctx,protected)
  elseif n.kind=="array" then for _,item in n.items do checkExpression(item,ctx,protected) end
  elseif n.kind=="dictionary" then for _,e in n.entries do checkExpression(e.expression,ctx,protected) end end
 end
 local validate
 validate=function(body,ctx,protected)
  for _,n in body do
   if n.kind=="function" then continue end
   if n.kind=="assign" and ctx then
    for _,p in ctx.fn.parameters do if p.const and p.name==n.name then Commands.error(n.line,"Cannot assign to const parameter '"..p.name.."'.") end end
   elseif n.kind=="set" then
    local target=eval(n.target.array,ctx)
    if target.readonly or (reference(target) and overlap(target,protected)) then Commands.error(n.line,"Cannot mutate a const parameter or a const-derived alias.") end
    checkExpression(n.target,ctx,protected)
   end
   checkExpression(n.expression,ctx,protected); checkExpression(n.condition,ctx,protected)
   if n.kind=="action" then checkExpression(n.instruction.call,ctx,protected) end
   if n.kind=="thread" or n.kind=="while" then validate(n.body,ctx,protected)
   elseif n.kind=="if" then for _,b in n.branches do checkExpression(b.condition,ctx,protected); validate(b.body,ctx,protected) end; if n.otherwise then validate(n.otherwise,ctx,protected) end
   elseif n.kind=="switch" then for _,b in n.cases do validate(b.body,ctx,protected) end; if n.otherwise then validate(n.otherwise,ctx,protected) end end
  end
 end
 validate(ast,nil,value())
 for _,ctx in contexts do
  local protected=value()
  for _,p in ctx.fn.parameters do if p.const then local v=copy(ctx.env[p.name]); if reference(v) then merge(protected,v) end end end
  validate(ctx.fn.body,ctx,protected)
 end
 local tips={}
 for _,ctx in contexts do for _,p in ctx.fn.parameters do
  if not p.const and not ctx.rebound[p.name] and not reference(ctx.env[p.name]) then
   table.insert(tips,{line=ctx.fn.line,message="Tip: Parameter '"..p.name.."' in "..ctx.fn.name.."() is never modified. Consider declaring it const to reduce CPU ticks."})
  end
 end end
 table.sort(tips,function(a,b) return if a.line==b.line then a.message<b.message else a.line<b.line end)
 return tips
end
return A
