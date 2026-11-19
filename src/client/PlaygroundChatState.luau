-- Metadata only. Roblox owns all message text, filtering and presentation.
local State={};State.__index=State
function State.new(localUserId)
 return setmetatable({localUserId=localUserId,expanded=false,active=false,unread=0,seen={},order={}},State)
end
function State:setActive(active)self.active=active end
function State:setExpanded(expanded)
 self.expanded=expanded
 if expanded and self.active then self.unread=0 end
end
function State:receive(message,channel)
 if message.TextChannel~=channel or message.Status~=Enum.TextChatMessageStatus.Success or not message.TextSource then return false end
 local id=message.MessageId
 if type(id)~="string"or id==""or self.seen[id]then return false end
 self.seen[id]=true;table.insert(self.order,id)
 if #self.order>200 then self.seen[table.remove(self.order,1)]=nil end
 if message.TextSource.UserId~=self.localUserId and not(self.active and self.expanded)then self.unread=math.min(99,self.unread+1)end
 return true
end
return State
