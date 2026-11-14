-- Adapter screen: battle UI/camera/input remain owned by the existing client.
local Screen={}
function Screen.new(context)
 return {
  enter=function() assert(context.session:canControl(),"Battle admission required"); context.gameplay:setActive(true) end,
  exit=function() context.gameplay:setActive(false) end,
  destroy=function() context.gameplay:setActive(false) end,
 }
end
return Screen
