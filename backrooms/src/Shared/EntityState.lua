--!strict
-- Server-side registry for the Entity, so LightManager can strobe
-- nearby fixtures and the HUD can react without direct references.

local EntityState = {
	root = nil :: BasePart?, -- entity PrimaryPart (torso)
	hunting = false,
	cooldownUntil = 0,
}

return EntityState
