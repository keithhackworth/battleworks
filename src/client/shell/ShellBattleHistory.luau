local View=require(script.Parent.ShellView)
local Screen={}
function Screen.new(context)
 local view=View.new(context,"Battle History","Every battle will have a story.")
 view:paragraph("ComingSoon","Battle history and replays are coming soon. No battles are being recorded or saved yet.")
 view:back()
 return view
end
return Screen
