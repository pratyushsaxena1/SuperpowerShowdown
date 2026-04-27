local Config = {}

Config.DEFAULT_ELO = 1000
Config.MATCH_DURATION = 60
Config.SELECTION_DURATION = 8
Config.LOBBY_RETURN_DELAY = 4
Config.MAX_HP = 100

Config.ELO_DELTAS = {
	equal = 25,
	favored = 10,
	upset = 40,
	draw = 0,
}
Config.ELO_FAVORED_GAP = 100

Config.ABILITIES = { "Flying", "Teleportation", "SuperStrength", "SuperSpeed", "Invisibility" }

Config.LOBBY_SPAWN = Vector3.new(0, 5, 0)
Config.PAD_A_POS = Vector3.new(-20, 5, 0)
Config.PAD_B_POS = Vector3.new(20, 5, 0)
Config.ARENA_A_POS = Vector3.new(-30, 5, 500)
Config.ARENA_B_POS = Vector3.new(30, 5, 500)
Config.ARENA_CENTER = Vector3.new(0, 5, 500)

Config.PAD_HOLD_TIME = 3

Config.BASE_PUNCH_DAMAGE = 10
Config.PUNCH_RANGE = 6
Config.PUNCH_COOLDOWN = 0.6

return Config
