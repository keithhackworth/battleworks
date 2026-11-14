-- Screens are lazy modules: new(context), enter(params), exit(), destroy().
local Manager={}; Manager.__index=Manager
function Manager.new(context,definitions,onChanged)
 local self=setmetatable({context=context,definitions=definitions,screens={},onChanged=onChanged or function() end},Manager)
 context.navigate=function(name,params) return self:show(name,params) end
 return self
end
function Manager:get(name)
 assert(self.definitions[name],"Unknown screen: "..tostring(name))
 if not self.screens[name] then self.screens[name]=self.definitions[name].new(self.context) end
 return self.screens[name]
end
function Manager:show(name,params)
 assert(self.definitions[name],"Unknown screen: "..tostring(name))
 if name==self.current then return false end
 local nextScreen=self:get(name)
 if self.current then self.screens[self.current]:exit() end
 self.current=name
 nextScreen:enter(params)
 self.onChanged(name)
 return true
end
function Manager:destroy()
 if self.current then self.screens[self.current]:exit() end
 for _,screen in self.screens do screen:destroy() end
 self.screens={}; self.current=nil
end
return Manager
