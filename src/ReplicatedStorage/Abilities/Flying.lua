local Flying = {}

Flying.cooldown = 0.3
Flying.meleeDamage = 7
Flying.speedMultiplier = 1.0
Flying.clientOnly = true

function Flying.onEquip(character)
	character:SetAttribute("Flying", false)
end

function Flying.onUnequip(character)
	if character then character:SetAttribute("Flying", false) end
end

function Flying.onActivate(character)
	local current = character:GetAttribute("Flying") or false
	character:SetAttribute("Flying", not current)
end

return Flying
