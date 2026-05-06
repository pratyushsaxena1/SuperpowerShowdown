local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local Services = ServerScriptService:WaitForChild("Services")
local EloDataService = require(Services.EloDataService)
local CurrencyService = require(Services.CurrencyService)
local SkinShopService = require(Services.SkinShopService)
local CosmeticsService = require(Services.CosmeticsService)
local CombatService = require(Services.CombatService)
local ArenaManager = require(Services.ArenaManager)
local MatchmakingService = require(Services.MatchmakingService)
local BotAIController = require(Services.BotAIController)
local AIMatchCoordinator = require(Services.AIMatchCoordinator)
local StoreService = require(Services.StoreService)

local eventBus = Instance.new("BindableEvent")

EloDataService.init()
CurrencyService.init()
SkinShopService.init(CurrencyService)
CosmeticsService.init(CurrencyService)
CombatService.init(eventBus, CosmeticsService)
ArenaManager.init(CombatService)
AIMatchCoordinator.init(CombatService, BotAIController)
MatchmakingService.init(ArenaManager, EloDataService, AIMatchCoordinator)
StoreService.init(SkinShopService, CosmeticsService, CurrencyService)

task.spawn(function()
	local lobby = Workspace:WaitForChild("Lobby", 30)
	if not lobby then
		warn("[Bootstrap] Lobby not found in Workspace")
		return
	end
	local returnPart = lobby:FindFirstChild("ReturnSpawn", true)
	local returnCFrame = returnPart and returnPart.CFrame or CFrame.new(0, 10, 0)
	MatchmakingService.registerLobby(lobby, returnCFrame)
	StoreService.registerLobby(lobby)
end)

-- Lobby spawn guard. Snaps the character to LobbySpawn the instant the
-- HumanoidRootPart is available, then re-checks for one second to catch
-- any post-spawn movement (e.g. Studio "Play Here", a published place
-- that has the camera/spawn saved at a bad position, a transient physics
-- glitch). InMatch players are exempt — arenas teleport them on purpose.
local Players = game:GetService("Players")
task.spawn(function()
	local lobby = Workspace:WaitForChild("Lobby", 30)
	if not lobby then return end
	local lobbySpawn = lobby:WaitForChild("LobbySpawn", 5)
	if not lobbySpawn then return end

	local function inLobby(pos)
		return math.abs(pos.X) <= 100
			and math.abs(pos.Z) <= 100
			and pos.Y > -5 and pos.Y < 60
	end

	local function snapTo(hrp)
		hrp.CFrame = lobbySpawn.CFrame + Vector3.new(0, 4, 0)
		hrp.AssemblyLinearVelocity = Vector3.zero
	end

	local function snapToLobbySpawn(player, char)
		local hrp = char:WaitForChild("HumanoidRootPart", 5)
		if not hrp then return end
		if player:GetAttribute("InMatch") then return end
		-- Only snap if the spawn ended up outside the lobby footprint.
		-- A normal Roblox spawn at the LobbySpawn pad is in-bounds; we
		-- shouldn't teleport that case because doing so on every spawn
		-- can fight with other systems (e.g. skin re-apply on respawn).
		if not inLobby(hrp.Position) then snapTo(hrp) end
		-- Watchdog: re-check for ~1 second to catch any post-spawn
		-- relocation (Studio Play Here, transient physics glitch, etc.).
		local deadline = os.clock() + 1.0
		while os.clock() < deadline do
			task.wait(0.1)
			if not (char.Parent and hrp.Parent) then return end
			if player:GetAttribute("InMatch") then return end
			if not inLobby(hrp.Position) then snapTo(hrp) end
		end
	end

	local function hookPlayer(player)
		player.RespawnLocation = lobbySpawn
		player.CharacterAdded:Connect(function(char)
			snapToLobbySpawn(player, char)
		end)
		if player.Character then
			task.spawn(snapToLobbySpawn, player, player.Character)
		end
	end
	Players.PlayerAdded:Connect(hookPlayer)
	for _, p in ipairs(Players:GetPlayers()) do hookPlayer(p) end
end)

-- Reset the persisted Workspace.Camera CFrame so a new player's initial
-- camera doesn't show the editor camera position (which can be saved high
-- in the sky from a Studio session).
task.spawn(function()
	local cam = Workspace:FindFirstChildOfClass("Camera")
	if cam then
		cam.CFrame = CFrame.lookAt(Vector3.new(0, 8, -50), Vector3.new(0, 4, 5))
	end
end)
