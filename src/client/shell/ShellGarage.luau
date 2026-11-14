local View=require(script.Parent.ShellView)
local Screen={}
function Screen.new(context)
 local view=View.new(context,"Garage","Build your battlefield identity.")
 view:paragraph("ComingSoon","Vehicle loadouts and customization are coming soon. Your current tanks are ready in Play BattleWorks.")
 view:back()
 return view
end
return Screen
