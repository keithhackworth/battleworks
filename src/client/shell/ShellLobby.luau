local View=require(script.Parent.ShellView)
local Screen={}
function Screen.new(context)
 local view=View.new(context,"Play BattleWorks","Your next battle starts here.")
 view:paragraph("Description","Enter the running battlefield with your own tanks. Drive, aim and fire, or let your BW programs take command.")
 view.join=view:button("EnterBattle","Enter Battle",context.join,true)
 view.status=view:paragraph("Status","Tanks join the simulation only when you enter.")
 view:button("BattleHistory","Battle History",function() context.navigate("BattleHistory") end)
 view:back()
 function view:setStatus(joining,message)
  self.join.Text=if joining then "Entering battlefield…" else "Enter Battle"
  self.status.Text=message or (if joining then "Connecting to the battle server. You can return to cancel." else "Tanks join the simulation only when you enter.")
 end
 return view
end
return Screen
