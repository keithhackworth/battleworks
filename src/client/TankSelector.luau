-- Lightweight development selector; snapshots, not buttons, choose the active model.
local Selector = {}
Selector.__index = Selector
function Selector.new(gui,onSelect)
	local self=setmetatable({buttons={},connections={},selected="Boomer"},Selector)
	local frame=Instance.new("Frame")
	frame.Name="TankSelector"; frame.BackgroundTransparency=1
	frame.AnchorPoint=Vector2.new(1,0); frame.Position=UDim2.new(1,-8,0,50); frame.Size=UDim2.fromOffset(194,32)
	frame.Parent=gui; self.frame=frame
	for index,id in {"Boomer","Rattler"} do
		local button=Instance.new("TextButton")
		button.Name=id; button.Text=id; button.Size=UDim2.fromOffset(94,32)
		button.Position=UDim2.fromOffset((index-1)*100,0); button.TextSize=14
		button.Font=Enum.Font.GothamMedium; button.TextColor3=Color3.fromRGB(255,249,222)
		button.Selectable=true; button.Parent=frame; self.buttons[id]=button
		table.insert(self.connections,button.Activated:Connect(function()
			if id~=self.selected then onSelect(id) end
		end))
	end
	self:update({tankType="Boomer"})
	return self
end
function Selector:update(state)
	self.selected=state.tankType or "Boomer"
	for id,button in self.buttons do
		button.BackgroundColor3=if id==self.selected then (if id=="Boomer" then Color3.fromRGB(184,89,18) else Color3.fromRGB(37,134,61)) else Color3.fromRGB(47,56,63)
		button.Text=if id==self.selected then "• "..id else id
	end
end
function Selector:destroy()
	for _,connection in self.connections do connection:Disconnect() end
	self.frame:Destroy()
end
return Selector
