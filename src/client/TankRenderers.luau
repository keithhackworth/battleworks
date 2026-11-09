-- One renderer per persistent tank ID; selection never replaces a model.
local Registry = {}
function Registry.sync(renderers, states, create)
	for id, renderer in renderers do
		local state = states[id]
		if not state or renderer.tankType ~= (state.tankType or "Boomer") or renderer.generation ~= (state.generation or 0) or (state.weaponId and renderer.weaponId and renderer.weaponId~=state.weaponId) then
			renderer:destroy(); renderers[id] = nil
		end
	end
	for id, state in states do
		if not renderers[id] then
			local renderer = create(id,state.tankType or "Boomer",state.weaponId)
			renderer.generation = state.generation or 0
			renderer:resetPose(state); renderers[id] = renderer
		end
	end
end
return Registry
