-- Shared rectangular arena dimensions and safe development spawn positions.
local Layout = {}
function Layout.validSize(size)
	if typeof(size) ~= "Vector2" then return false end
	for _, value in {size.X, size.Y} do
		if value ~= value or value < 25 or value > 2000 or value % 1 ~= 0 then return false end
	end
	return true
end
function Layout.spawn(size, index)
	local columns = math.max(1, math.floor((size.X-10)/12)+1)
	local column = (index-1) % columns
	local row = math.floor((index-1)/columns)
	local x = (column-(columns-1)/2)*12
	local z = math.clamp(size.Y*0.25-row*12, -size.Y/2+5, size.Y/2-5)
	return Vector3.new(x,0,z)
end
return Layout
