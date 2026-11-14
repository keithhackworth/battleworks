local View=require(script.Parent.ShellView)
local Screen={}
function Screen.new(context)
 local view=View.new(context,"Manuals","Learn the tools. Command the field.")
 view:paragraph("ComingSoon","The manuals library is coming soon. The existing BW Handbook is available from the BW editor during battle.")
 view:back()
 return view
end
return Screen
