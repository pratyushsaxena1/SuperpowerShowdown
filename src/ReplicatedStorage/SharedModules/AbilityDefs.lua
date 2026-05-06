local AbilityDefs = {}

AbilityDefs.List = {
	"Flying",
	"Teleportation",
	"SuperStrength",
	"SuperSpeed",
	"Invisibility",
	"Shockwave",
	"Healing",
	"Duplication",
	"SizeShift",
	"LightningStrike",
	"Magnetism",
	"Mirror",
}

-- cooldown = downtime AFTER the ability's active effect ends.
-- activeDuration = how long the effect persists before cooldown starts (0 = instant).
AbilityDefs.Display = {
	Flying        = { name = "Flying",       color = Color3.fromRGB(120, 200, 255), desc = "Fly freely; attack in the air.",       cooldown = 0.3, activeDuration = 0   },
	Teleportation = { name = "Teleportation",color = Color3.fromRGB(200, 120, 255), desc = "Blink forward to dodge.",              cooldown = 2.5, activeDuration = 0   },
	SuperStrength = { name = "Super Strength",color = Color3.fromRGB(255, 120, 120),desc = "Throw heavy crates; huge slam.",       cooldown = 3,   activeDuration = 0   },
	SuperSpeed    = { name = "Super Speed",  color = Color3.fromRGB(255, 220, 100), desc = "Burst of speed and faster hits.",      cooldown = 3.5, activeDuration = 3   },
	Invisibility  = { name = "Invisibility", color = Color3.fromRGB(200, 200, 200), desc = "Vanish for 3s; hits break it.",        cooldown = 5,   activeDuration = 3   },
	Shockwave     = { name = "Shockwave",    color = Color3.fromRGB(255, 180, 80),  desc = "360° blast; cover blocks it, crates fly.", cooldown = 6, activeDuration = 0 },
	Healing       = { name = "Healing",      color = Color3.fromRGB(120, 255, 180), desc = "Restore 35 HP instantly.",             cooldown = 7,   activeDuration = 0   },
	Duplication   = { name = "Duplication",  color = Color3.fromRGB(140, 220, 255), desc = "Spawn 4 decoys that die in 1 hit.",    cooldown = 4,   activeDuration = 9   },
	SizeShift     = { name = "Size Shift",   color = Color3.fromRGB(200, 170, 255), desc = "Cycle Big (slow, +dmg) / Small (fast, -dmg).", cooldown = 0.8, activeDuration = 0 },
	LightningStrike = { name = "Lightning",  color = Color3.fromRGB(255, 230, 120), desc = "Telegraphed bolt - dodge the zone!",   cooldown = 8,   activeDuration = 0.6 },
	Magnetism     = { name = "Magnetism",    color = Color3.fromRGB(255, 200,  80), desc = "Yank your opponent in for a 14 dmg slam.", cooldown = 6, activeDuration = 0.5 },
	Mirror        = { name = "Mirror",       color = Color3.fromRGB(180, 230, 255), desc = "Reflect 100% damage taken for 2.5s.",     cooldown = 9, activeDuration = 2.5 },
}

function AbilityDefs.isValid(name)
	for _, n in ipairs(AbilityDefs.List) do
		if n == name then return true end
	end
	return false
end

function AbilityDefs.randomAbility()
	return AbilityDefs.List[math.random(1, #AbilityDefs.List)]
end

function AbilityDefs.randomBotAbility()
	local pool = {}
	local Abilities = game:GetService("ReplicatedStorage"):FindFirstChild("Abilities")
	for _, n in ipairs(AbilityDefs.List) do
		local mod = Abilities and Abilities:FindFirstChild(n)
		local data = mod and require(mod)
		if not (data and data.clientOnly) then
			table.insert(pool, n)
		end
	end
	if #pool == 0 then return AbilityDefs.List[1] end
	return pool[math.random(1, #pool)]
end

return AbilityDefs
