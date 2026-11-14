local View=require(script.Parent.ShellView)
local Screen={}
function Screen.new(context)
 local view=View.new(context,"BATTLEWORKS","Outthink. Outmaneuver. Take the field.")
 for _,item in {{"Lobby","Play BattleWorks"},{"Garage","Garage"},{"Store","Store"}} do
  view:button(item[1],item[2],function() context.navigate(item[1]) end,item[1]=="Lobby")
 end
 view:separator()
 for _,item in {{"WorldEditor","World Editor"},{"Preferences","Preferences"},{"Manuals","Manuals"}} do
  view:button(item[1],item[2],function() context.navigate(item[1]) end)
 end
 return view
end
return Screen
