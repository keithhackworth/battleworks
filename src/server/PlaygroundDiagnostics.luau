-- Studio-only state and fixed-memory wall-clock timing buckets.
local Diagnostics = {}
Diagnostics.__index = Diagnostics
local phases = {"BW", "scan", "physics", "contacts", "projectiles", "tick"}

function Diagnostics.new(window, now)
	local self = setmetatable({enabled=true, clock=0, window=window, buckets={}, scan=0}, Diagnostics)
	for i=1,window+1 do
		self.buckets[i]={count=0, second=-math.huge, total=table.create(#phases,0), peak=table.create(#phases,0)}
	end
	self:reset(now)
	return self
end

function Diagnostics:reset(now)
	for _,bucket in self.buckets do bucket.second=-math.huge end
	self.nextReport=math.floor(now)+self.window+1
end

function Diagnostics:bucket(now)
	local second=math.floor(now)
	local bucket=self.buckets[second%#self.buckets+1]
	if bucket.second~=second then
		bucket.second=second
		bucket.count=0
		bucket.callbacks=0;bucket.steps=0;bucket.maxSteps=0
		bucket.buffered=0;bucket.carry=0;bucket.clipped=0
		for i=1,#phases do bucket.total[i]=0; bucket.peak[i]=0 end
	end
	return bucket
end

function Diagnostics:record(now, bw, scan, physics, contacts, projectiles, tick)
	local bucket=self:bucket(now)
	bucket.count+=1
	for i=1,#phases do
		local duration=if i==1 then bw elseif i==2 then scan elseif i==3 then physics elseif i==4 then contacts elseif i==5 then projectiles else tick
		bucket.total[i]+=duration
		bucket.peak[i]=math.max(bucket.peak[i],duration)
	end
end

function Diagnostics:heartbeat(now,steps,buffered,carry,clipped)
	local bucket=self:bucket(now)
	bucket.callbacks+=1;bucket.steps+=steps;bucket.maxSteps=math.max(bucket.maxSteps,steps)
	bucket.buffered=math.max(bucket.buffered,buffered);bucket.carry=math.max(bucket.carry,carry)
	bucket.clipped+=clipped
end

function Diagnostics:report(now, tanks)
	local second=math.floor(now)
	if second<self.nextReport then return end
	self.nextReport=second+math.max(1,math.floor(self.window/2))
	local count, total, peak=0,table.create(#phases,0),table.create(#phases,0)
	local callbacks,steps,maxSteps,buffered,carry,clipped=0,0,0,0,0,0
	for _,bucket in self.buckets do
		if bucket.second>=second-self.window and bucket.second<second then
			count+=bucket.count
			callbacks+=bucket.callbacks;steps+=bucket.steps;maxSteps=math.max(maxSteps,bucket.maxSteps)
			buffered=math.max(buffered,bucket.buffered);carry=math.max(carry,bucket.carry);clipped+=bucket.clipped
			for i=1,#phases do
				total[i]+=bucket.total[i]
				peak[i]=math.max(peak[i],bucket.peak[i])
			end
		end
	end
	if count==0 then return end
	local public,auto=0,0
	for _,tank in tanks do
		if tank.public then public+=1 end
		if tank.state.controlMode=="Auto" then auto+=1 end
	end
	local readings=table.create(#phases)
	for i,name in phases do
		readings[i]=string.format("%s %.3f/%.3f",name,1000*total[i]/count,1000*peak[i])
	end
	print(string.format("[BattleWorks perf] BW=%s public=%d auto=%d window=%ds ticks=%d | avg/max ms per tick | %s",
		if self.enabled then "ON" else "OFF",public,auto,self.window,count,table.concat(readings," | ")))
	if callbacks>0 then
		print(string.format("[BattleWorks accumulator] %.1f Hz | steps/callback avg %.2f max %d | max buffered %.2f ms | max carry %.2f ms | elapsed clipped %.2f ms",
			callbacks/self.window,steps/callbacks,maxSteps,1000*buffered,1000*carry,1000*clipped))
	end
end

return Diagnostics
