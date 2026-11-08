-- Soft camera-facing smoke sprites, emitted throughout the turret volume.
-- Invisible emitters never enter combat queries or affect the server schedule.
local Config=require(game.ReplicatedStorage.Shared.DamageEffectsConfig).SmokePresentation
local Debris=game:GetService("Debris")
local Smoke={}
local function sequence(a,b,c)
	return NumberSequence.new({NumberSequenceKeypoint.new(0,a),NumberSequenceKeypoint.new(0.25,b),NumberSequenceKeypoint.new(1,c)})
end
local function emitter(parent,name)
	local p=Instance.new("ParticleEmitter"); p.Name=name
	p.Texture=Config.Texture; p.Enabled=false; p.Rate=0
	p.Shape=Enum.ParticleEmitterShape.Box; p.ShapeStyle=Enum.ParticleEmitterShapeStyle.Volume
	p.Orientation=Enum.ParticleOrientation.FacingCamera
	p.EmissionDirection=Enum.NormalId.Top; p.SpreadAngle=Vector2.new(45,45)
	p.Rotation=NumberRange.new(0,360); p.RotSpeed=NumberRange.new(-25,25)
	p.Speed=NumberRange.new(0.5,1.5); p.Acceleration=Vector3.new(0,1.8,0); p.Drag=0.6
	p.LightEmission=0; p.LightInfluence=0.25; p.LockedToPart=true
	p.Lifetime=NumberRange.new(0.6,1.1); p.Parent=parent
	return p
end
function Smoke.clear(renderer)
	if renderer.smokeFolder then renderer.smokeFolder:Destroy() end
	renderer.smokeFolder=nil; renderer.smokeVolume=nil; renderer.smokeVent=nil; renderer.smokeEmitters=nil; renderer.smokeWasBurst=false; renderer.smokeStyle=nil
end
function Smoke.update(renderer,state,_time,part)
	local severity=state.smokeSeverity or 0
	if state.health<=0 or severity<=0 then Smoke.clear(renderer); return end
	if not renderer.smokeFolder then
		local folder=Instance.new("Folder"); folder.Name="InjurySmoke"; folder.Parent=renderer.model; renderer.smokeFolder=folder
		local volume=part(folder,"TurretSmokeVolume",Vector3.one,Color3.fromRGB(150,150,150))
		volume.Transparency=1; volume.CastShadow=false; renderer.smokeVolume=volume
		local vent=part(folder,"EngineSmokeVent",Vector3.new(1.2,0.5,1.2),Color3.fromRGB(150,150,150))
		vent.Transparency=1; vent.CastShadow=false; renderer.smokeVent=vent
		local stream=emitter(vent,"EngineSmokeStream")
		stream.LockedToPart=false; stream.Lifetime=NumberRange.new(1.2,1.8)
		stream.Speed=NumberRange.new(1.2,2.4); stream.Acceleration=Vector3.new(0.2,2.8,0.1)
		stream.SpreadAngle=Vector2.new(15,15); stream.VelocityInheritance=0.15
		renderer.smokeEmitters={dense=emitter(volume,"TurretSmokeBlanket"),wisps=stream}
	end
	local volume=renderer.smokeVolume
	-- The molded turret's full bounds, rather than its thin center Part or muzzle.
	volume.Size=((renderer.turret:GetAttribute("ArmorSize") or renderer.turret.Size)+Config.VolumePadding)*Config.BurstScale
	volume.CFrame=renderer.turret.CFrame*CFrame.new(0,-0.25,0)
	renderer.smokeVent.CFrame=renderer.chassis.CFrame*CFrame.new(0,1,1.6)
	local dense,wisps=renderer.smokeEmitters.dense,renderer.smokeEmitters.wisps
	local shade=180-severity*25
	local color=ColorSequence.new(Color3.fromRGB(shade,shade+2,shade+5),Color3.fromRGB(shade+35,shade+37,shade+40))
	if renderer.smokeStyle~=severity then
		dense.Color=color; wisps.Color=color
		dense.Size=sequence((3.8+severity*0.3)*Config.BurstScale,(5.3+severity*0.5)*Config.BurstScale,(7.8+severity*0.5)*Config.BurstScale)
		dense.Transparency=sequence(1,0.38-(state.smokeStrength or 0)*0.16,1)
		wisps.Size=sequence(1.2,2.3+severity*0.4,4.5+severity*0.5)
		wisps.Transparency=sequence(1,0.7,1)
		renderer.smokeStyle=severity
	end
	dense.Enabled=state.smokeBurst==true
	dense.Rate=if dense.Enabled then Config.BurstRate else 0
	if dense.Enabled and not renderer.smokeWasBurst then dense:Emit(Config.InitialBurst) end
	if not dense.Enabled and renderer.smokeWasBurst then dense:Clear() end
	renderer.smokeWasBurst=dense.Enabled
	-- Always-on engine plume leaves a trail; only the larger turret blanket is episodic.
	wisps.Enabled=true
	wisps.Rate=Config.StreamRate+severity
end
function Smoke.puff(parent,position,part,large)
	local scale=if large then 3 else 1
	local anchor=part(parent,if large then "TankDeathSmoke" else "CannonImpactSmoke",Vector3.new(1,0.5,1)*scale,Color3.fromRGB(150,150,150))
	anchor.Transparency=1; anchor.CastShadow=false; anchor.CFrame=CFrame.new(position)
	local p=emitter(anchor,"DriftingSmoke")
	p.LockedToPart=false; p.SpreadAngle=Vector2.new(110,110)
	p.Speed=NumberRange.new(1,2.5); p.Acceleration=Vector3.new(0,2.5,0)
	p.Lifetime=if large then NumberRange.new(1,1.8) else NumberRange.new(0.35,0.7)
	p.Color=ColorSequence.new(Color3.fromRGB(125,128,132),Color3.fromRGB(190,193,197))
	p.Size=sequence(0.9*scale,1.8*scale,3.8*scale); p.Transparency=sequence(1,0.45,1)
	p:Emit(if large then 32 else 10)
	Debris:AddItem(anchor,if large then 2 else 0.8)
	return anchor
end
return Smoke
