local View=require(script.Parent.ShellView)
local Catalog=require(game.ReplicatedStorage.Shared.InnovationLabCatalog)
local Screen={}
function Screen.new(context)
 local view=View.new(context,"Innovation Lab","Select a card to start or restart an experiment.")
 for _,technology in Catalog do
  local text=technology.name.."  ·  "..(if technology.available then "Available" else "Unavailable").."\n"..technology.description
  if technology.available then
   local card=view:button("Experiment_"..technology.id,text,function()context.selectExperiment(technology.id)end,true)
   card.Size=UDim2.new(1,-4,0,66)
   card.TextWrapped=true
  else
   local card=view:paragraph("Technology_"..technology.id,text)
   card.Size=UDim2.new(1,-4,0,60)
   card.AutomaticSize=Enum.AutomaticSize.None
   card.BackgroundTransparency=0;card.BackgroundColor3=Color3.fromRGB(32,47,52)
  end
 end
 local status=view:paragraph("LabStatus","")
 function view:setStatus(message)status.Text=message or "" end
 view:button("ReturnToPlayground","Return to Playground",function()
  status.Text="Returning to the Playground…"
  context.labTravel("Return")
 end)
 return view
end
return Screen
