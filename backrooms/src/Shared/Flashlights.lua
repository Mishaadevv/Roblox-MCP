--!strict
-- Server-side registry of player flashlights (SpotLights mounted on heads).
-- GameManager registers them; the Entity flickers them when it hunts you.

local Flashlights = {
	lights = {} :: { [Player]: SpotLight },
	baseOn = {} :: { [Player]: boolean }, -- player's chosen toggle state
}

return Flashlights
