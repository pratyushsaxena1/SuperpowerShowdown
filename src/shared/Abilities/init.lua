local Abilities = {}

Abilities.Flying         = require(script:WaitForChild("Flying"))
Abilities.Teleportation  = require(script:WaitForChild("Teleportation"))
Abilities.SuperStrength  = require(script:WaitForChild("SuperStrength"))
Abilities.SuperSpeed     = require(script:WaitForChild("SuperSpeed"))
Abilities.Invisibility   = require(script:WaitForChild("Invisibility"))

function Abilities.get(name)
	return Abilities[name]
end

return Abilities
