local View=require(script.Parent.ShellView)
local Screen={}
function Screen.new(context)
 local view=View.new(context,"BATTLEWORKS","Outthink. Outmaneuver. Take the field.")
 for _,item in {{"Lobby","Play BattleWorks"},{"Garage","Garage"},{"Store","Store"}} do
  view:button(item[1],if context.royale and item[1]=="Lobby" then "The Playground" else item[2],function() if context.royale and item[1]=="Lobby" then context.join()else context.navigate(item[1])end end,item[1]=="Lobby")
 end
 view:separator()
 for _,item in {{"WorldEditor","World Editor"},{"Preferences","Preferences"},{"Manuals","Manuals"}} do
  view:button(item[1],item[2],function() context.navigate(item[1]) end)
 end
 return view
end
return Screen
