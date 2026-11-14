local View=require(script.Parent.ShellView)
local Screen={}
function Screen.new(context)
 local view=View.new(context,"Store","More ways to make BattleWorks yours.")
 view:paragraph("ComingSoon","The store is coming soon. There are no purchases or items to claim in this preview.")
 view:back()
 return view
end
return Screen
