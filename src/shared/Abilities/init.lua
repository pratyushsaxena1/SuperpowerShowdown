local Abilities = {}

Abilities.Flying         = require(script:WaitForChild("Flying"))
Abilities.Teleportation  = require(script:WaitForChild("Teleportation"))
Abilities.SuperStrength  = require(script:WaitForChild("SuperStrength"))
Abilities.SuperSpeed     = require(script:WaitForChild("SuperSpeed"))
Abilities.Invisibility   = require(script:WaitForChild("Invisibility"))
Abilities.Fire           = require(script:WaitForChild("Fire"))
Abilities.Ice            = require(script:WaitForChild("Ice"))
Abilities.Lightning      = require(script:WaitForChild("Lightning"))
Abilities.Telekinesis    = require(script:WaitForChild("Telekinesis"))
Abilities.Shadow         = require(script:WaitForChild("Shadow"))

function Abilities.get(name)
	return Abilities[name]
end

return Abilities
