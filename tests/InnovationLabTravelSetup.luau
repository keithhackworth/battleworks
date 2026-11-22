game.PlaceId=55
game.PrivateServerId=if labEntry then "" else "lab-reservation"
game.PrivateServerOwnerId=0
first.GetJoinData=function()
 return {SourcePlaceId=game.PlaceId,TeleportData={mode="InnovationLab",owner=first.UserId}}
end
local departures={}
local travelFailure
local teleport={TeleportInitFailed=signal()}
function teleport:TeleportAsync(place,party,options)
 table.insert(departures,{place=place,party=party,options=options})
end
local previousGetService=game.GetService
game.GetService=function(self,name)
 if name=="TeleportService" then return teleport end
 if name=="HttpService" then return {GenerateGUID=function()return "test-reservation" end} end
 return previousGetService(self,name)
end
local previousNew=Instance.new
Instance.new=function(class)
 local instance=previousNew(class)
 if class=="RemoteEvent" then
  local fire=instance.FireClient
  instance.FireClient=function(self,player,...)
   if self.Name=="InnovationLabTravel" and player==first then travelFailure=(...) end
   return fire(self,player,...)
  end
 elseif class=="TeleportOptions" then
  instance.SetTeleportData=function(self,data)self.teleportData=data end
 end
 return instance
end
