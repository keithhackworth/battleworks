-- Read-only measurements from resolved server positions, including recoil/collision.
local Telemetry = {}
function Telemetry.update(state,previous,dt)
	local kind,generation=state.tankType or "Boomer",state.generation or 0
	if state.telemetryType~=kind or state.telemetryGeneration~=generation then
		state.movementPeakXZ=0; state.telemetryType=kind; state.telemetryGeneration=generation
	end
	local correction=state.motionCorrection or Vector3.zero
 local delta=state.position-previous-(correction-(state.motionCorrectionAtStepStart or state.telemetryCorrection or Vector3.zero))
 state.telemetryCorrection=correction
	local scale=if dt>0 then 1/dt else 0
	state.movementSpeedXZ=math.sqrt(delta.X^2+delta.Z^2)*scale
	state.movementSpeedY=delta.Y*scale
	state.movementSpeed3D=delta.Magnitude*scale
	state.movementPeakXZ=math.max(state.movementPeakXZ or 0,state.movementSpeedXZ)
end
return Telemetry
