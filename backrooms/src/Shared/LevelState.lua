--!strict
-- Server-side registry for the generated level.
-- GameManager fills it right after generation; Entity/Pickups/Lights read it.

export type Level = {
	seed: number,
	folder: Folder,
	spawnCFrame: CFrame,
	exitPosition: Vector3,
	fixtures: { Vector3 }, -- ceiling light fixture positions
	waters: { Part }, -- almond water bottles (alive ones stay valid)
	waterPrompts: { ProximityPrompt },
	exitPrompt: ProximityPrompt,
	tile: number,
	gridW: number,
	gridD: number,
	wallH: number,
}

local LevelState = {
	current = nil :: Level?,
}

return LevelState
