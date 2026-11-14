-- The only client-side battle admission state. Server acknowledgments are required.
local Session={}; Session.__index=Session
function Session.new(send,onState)
 return setmetatable({send=send,onState=onState or function() end,mode="Menu",requestId=0},Session)
end
function Session:join()
 if self.mode~="Menu" then return false end
 self.requestId+=1; self.mode="Joining"
 self.onState(self.mode)
 self.send("Enter",self.requestId)
 return true
end
function Session:leave()
 self.requestId+=1; self.mode="Menu"
 self.onState(self.mode)
 self.send("Leave",self.requestId)
end
function Session:receive(requestId,inBattle,message)
 if requestId~=self.requestId or type(inBattle)~="boolean" then return false end
 -- A delayed Enter acknowledgment must never reopen gameplay after Leave.
 if self.mode=="Menu" and inBattle then return false end
 self.mode=if inBattle then "Battle" else "Menu"
 self.onState(self.mode,message)
 return true
end
function Session:canControl() return self.mode=="Battle" end
return Session
