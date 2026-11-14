-- VR hands only: hides the local player's whole body (and everything worn on it)
-- from their own view while in VR, leaving just the two hands, which follow the
-- controllers. Other players still see the full avatar.
-- Uses LocalTransparencyModifier, so the real Transparency is left alone and
-- the camera is not touched.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local VRService = game:GetService("VRService")

local player = Players.LocalPlayer

local hiddenParts: { BasePart } = {}
local dirty = true
local wasHiding = false

local VISIBLE = { LeftHand = true, RightHand = true }

-- Everything in the character except the two hands and any Tool being held
local function collect()
	table.clear(hiddenParts)
	local character = player.Character
	if not character then
		return
	end
	for _, d in character:GetDescendants() do
		if d:IsA("BasePart") and not (d.Parent == character and VISIBLE[d.Name]) and not d:FindFirstAncestorOfClass("Tool") then
			table.insert(hiddenParts, d)
		end
	end
end

local function watchCharacter(character: Model)
	dirty = true
	character.DescendantAdded:Connect(function()
		dirty = true
	end)
	character.DescendantRemoving:Connect(function()
		dirty = true
	end)
end

player.CharacterAdded:Connect(watchCharacter)
if player.Character then
	watchCharacter(player.Character)
end

-- Runs right after the camera scripts, which set LocalTransparencyModifier themselves.
RunService:BindToRenderStep("VRHandsOnly", Enum.RenderPriority.Camera.Value + 1, function()
	local hiding = VRService.VREnabled
	if not hiding then
		if wasHiding then
			wasHiding = false
			for _, part in hiddenParts do
				part.LocalTransparencyModifier = 0
			end
		end
		return
	end
	wasHiding = true

	if dirty then
		dirty = false
		collect()
	end
	for _, part in hiddenParts do
		part.LocalTransparencyModifier = 1
	end
end)
