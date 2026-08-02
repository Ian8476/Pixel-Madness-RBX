--!strict
--[[
	Tags: vocabulario unico de CollectionService.

	Nadie escribe un tag como string literal en ningun otro archivo. El error clasico
	documentado del proyecto ("tags con mayusculas inconsistentes que fallan en silencio")
	desaparece porque `Tags.Enemyy` es un error de tipado y `"Enemyy"` no lo seria.

	Este modulo es vocabulario, no servicio: no envuelve a CollectionService ni guarda
	estado. Los sistemas siguen usando CollectionService directamente.
]]

local Tags = table.freeze({
	Player = "Player" :: "Player",
	Enemy = "Enemy" :: "Enemy",
	Boss = "Boss" :: "Boss",
	Bullet = "Bullet" :: "Bullet",
	Room = "Room" :: "Room",
	Coin = "Coin" :: "Coin",
	WeaponPickup = "WeaponPickup" :: "WeaponPickup",
	Breakable = "Breakable" :: "Breakable",
})

export type TagName =
	"Player"
	| "Enemy"
	| "Boss"
	| "Bullet"
	| "Room"
	| "Coin"
	| "WeaponPickup"
	| "Breakable"

return Tags
