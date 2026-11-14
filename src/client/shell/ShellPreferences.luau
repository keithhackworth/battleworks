local View=require(script.Parent.ShellView)
local Screen={}
function Screen.new(context)
 local view=View.new(context,"Preferences","Make the battlefield feel like home.")
 view:paragraph("ComingSoon","Application preferences are coming soon. In battle, the existing Input button still selects keyboard and mouse, touch, gamepad or Auto.")
 view:back()
 return view
end
return Screen
