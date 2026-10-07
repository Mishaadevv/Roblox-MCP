--!strict
-- Small pure helpers shared by server and client.

local Util = {}

function Util.shuffle<T>(t: { T }, rng: Random): { T }
	local out = table.clone(t)
	for i = #out, 2, -1 do
		local j = rng:NextInteger(1, i)
		out[i], out[j] = out[j], out[i]
	end
	return out
end

function Util.cellToWorld(cx: number, cz: number, tile: number, y: number): Vector3
	return Vector3.new(cx * tile, y, cz * tile)
end

function Util.gridDistance(ax: number, az: number, bx: number, bz: number): number
	local dx = ax - bx
	local dz = az - bz
	return math.sqrt(dx * dx + dz * dz)
end

function Util.clamp01(x: number): number
	if x < 0 then
		return 0
	end
	if x > 1 then
		return 1
	end
	return x
end

return Util
