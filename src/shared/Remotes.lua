local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = {}

local FOLDER_NAME = "SPS_Remotes"

local function getOrCreate(name, className)
	local folder = ReplicatedStorage:FindFirstChild(FOLDER_NAME)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = FOLDER_NAME
		folder.Parent = ReplicatedStorage
	end
	local r = folder:FindFirstChild(name)
	if not r then
		r = Instance.new(className)
		r.Name = name
		r.Parent = folder
	end
	return r
end

Remotes.AbilityChosen   = getOrCreate("AbilityChosen",   "RemoteEvent")
Remotes.AbilityActivate = getOrCreate("AbilityActivate", "RemoteEvent")
Remotes.PunchAttack     = getOrCreate("PunchAttack",     "RemoteEvent")
Remotes.MatchState      = getOrCreate("MatchState",      "RemoteEvent")
Remotes.EloUpdated      = getOrCreate("EloUpdated",      "RemoteEvent")
Remotes.HpUpdated       = getOrCreate("HpUpdated",       "RemoteEvent")
Remotes.GetMyElo        = getOrCreate("GetMyElo",        "RemoteFunction")

return Remotes
