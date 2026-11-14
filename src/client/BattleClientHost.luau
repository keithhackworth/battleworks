-- The menu needs only this interface, not the simulator's UI/input/camera objects.
-- Retain one client so leaving/re-entering preserves BW source buffers.
local Host={};Host.__index=Host
function Host.new(create)
 return setmetatable({create=create,desired=false},Host)
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
 -- The user may have returned to the menu while a dependency was loading.
 self.client:setActive(self.desired)
end
return Host
