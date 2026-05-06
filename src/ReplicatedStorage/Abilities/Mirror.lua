-- Mirror: 2.5s window where damage taken is reflected back to the
-- attacker at 100%. Implemented entirely as a character attribute
-- (`Mirroring` + `MirrorEnds`) so CombatService.applyDamage can read it
-- in one place and redirect the damage. No per-frame work here — once
-- the attribute is set, the combat path does the rest.
--
-- Visual: a rotating glassy halo around the player that vanishes when
-- the window ends.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local VFX = require(ReplicatedStorage.SharedModules.VFX)

local Mirror = {}

Mirror.cooldown = 9
Mirror.meleeDamage = 8
Mirror.speedMultiplier = 1.0
Mirror.duration = 2.5

local HALO_COLOR = Color3.fromRGB(180, 230, 255)
local HALO_BRIGHT = Color3.fromRGB(255, 255, 255)

function Mirror.onEquip() end
function Mirror.onUnequip(character)
	if not character then return end
	character:SetAttribute("Mirroring", false)
	character:SetAttribute("MirrorEnds", 0)
end

function Mirror.onActivate(character, _opponent, _ctx)
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not hrp then return end
	character:SetAttribute("Mirroring", true)
	character:SetAttribute("MirrorEnds", os.clock() + Mirror.duration)

	-- Halo: a thin glass ring orbiting the player horizontally. Tweened
	-- in/out so it doesn't pop on/off jarringly.
	local halo = Instance.new("Part")
	halo.Name = "MirrorHalo"
	halo.Anchored = false
	halo.CanCollide = false
	halo.CanQuery = false
	halo.CanTouch = false
	halo.Massless = true
	halo.Shape = Enum.PartType.Cylinder
	halo.Size = Vector3.new(0.2, 7, 7)
	halo.Material = Enum.Material.Glass
	halo.Color = HALO_COLOR
	halo.Reflectance = 0.4
	halo.Transparency = 1
	halo.CFrame = hrp.CFrame * CFrame.Angles(0, 0, math.rad(90))
	halo.Parent = hrp

	-- Weld so it follows the player's horizontal position; rotate via a
	-- spinner per Heartbeat for the orbital read.
	local weld = Instance.new("Weld")
	weld.Part0 = hrp
	weld.Part1 = halo
	weld.C0 = CFrame.Angles(0, 0, math.rad(90))
	weld.Parent = halo

	TweenService:Create(halo, TweenInfo.new(0.2), { Transparency = 0.3 }):Play()
	Debris:AddItem(halo, Mirror.duration + 0.4)

	VFX.ring(hrp.Position, HALO_BRIGHT, 8, 0.4)

	task.delay(Mirror.duration, function()
		if character and character.Parent then
			character:SetAttribute("Mirroring", false)
			character:SetAttribute("MirrorEnds", 0)
			VFX.sphereBurst(hrp.Position + Vector3.new(0, 1, 0), HALO_COLOR, 5, 0.3)
		end
		if halo and halo.Parent then
			TweenService:Create(halo, TweenInfo.new(0.3), { Transparency = 1 }):Play()
		end
	end)
end

return Mirror
