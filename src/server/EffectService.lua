local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))

local EffectService = {}
EffectService.__index = EffectService

function EffectService.new()
	return setmetatable({}, EffectService)
end

-- Broadcast a VFX payload to every client.
-- kind: string. data: table. Clients render based on kind.
function EffectService:Broadcast(kind, data)
	Remotes.Effect:FireAllClients(kind, data or {})
end

-- Targeted hit feedback (camera shake, screen flash, damage number).
function EffectService:HitFeedback(player, kind, data)
	if player and player.Parent then
		Remotes.HitFeedback:FireClient(player, kind, data or {})
	end
end

return EffectService
