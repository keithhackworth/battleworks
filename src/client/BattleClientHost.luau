-- The menu needs only this interface, not the simulator's UI/input/camera objects.
-- Retain one client so leaving/re-entering preserves BW source buffers.
local Host={};Host.__index=Host
function Host.new(create,network)
 local self=setmetatable({create=create,desired=false,receivers={}},Host)
 -- Broadcasts can arrive while players are editing or in the menu, long before
 -- the lazy gameplay client exists. Consume without retaining/replaying them.
 if network then
  for _,name in {"Snapshot","Shot","PrepareShot"} do
   table.insert(self.receivers,network:WaitForChild(name).OnClientEvent:Connect(function()end))
  end
 end
 return self
end
function Host:setActive(enabled)
 self.desired=enabled==true
 if self.client then self.client:setActive(self.desired);return end
 if not self.desired or self.loading then return end
 self.loading=true
 local ok,client=pcall(self.create)
 self.loading=false
 if not ok then error(client,0) end
 self.client=client
 for _,receiver in self.receivers do receiver:Disconnect() end
 table.clear(self.receivers)
 -- The user may have returned to the menu while a dependency was loading.
 self.client:setActive(self.desired)
end
return Host
