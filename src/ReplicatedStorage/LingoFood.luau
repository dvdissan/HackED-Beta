-- Food as real Roblox Tools (client side only).
-- The Tools in ReplicatedStorage.FoodTools came from the Creator Store; their own
-- scripts were removed, so everything they do is in this module.
--   * The cook puts them on the tray (addToTray).
--   * Once the player has the tray (trayTaken) each item can be picked up:
--       desktop: "take" prompt -> the Tool is equipped; click to take a bite
--       VR: reach for it with your free hand -> it rides on that hand;
--           bring it to your mouth to take a bite
--   * A few bites and it is gone.
-- Used by StarterPlayerScripts.LingoClient. Never touches the camera or the controls.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local VRService = game:GetService("VRService")

local player = Players.LocalPlayer
local templates = ReplicatedStorage:WaitForChild("FoodTools")

local BITES = 3 -- bites to finish an item
local BITE_COOLDOWN = 0.7 -- seconds between bites
local VR_GRAB_RANGE = 0.9 -- studs between hand and food to pick it up
local VR_MOUTH_RANGE = 1.0 -- studs between food and mouth to take a bite
local VR_TRAY_HAND = "Left" -- the tray rides on this hand, the other one grabs
local FALLBACK_BITE_SOUND = "rbxassetid://9119717523" -- used when a Tool has no sound of its own

local Food = {}

local context = nil -- set by Food.start
local records = {} -- every food item that still exists
local activeTray = nil -- the tray the player is carrying
local trayTakenAt = 0
local vrHeld = nil -- the item riding on a VR hand

---------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------

local function partsOf(tool)
	local parts = {}
	for _, item in tool:GetDescendants() do
		if item:IsA("BasePart") then
			table.insert(parts, item)
		end
	end
	return parts
end

-- Moves the whole Tool so that its Handle ends up at handleCFrame
local function moveTool(record, handleCFrame)
	local delta = handleCFrame * record.handle.CFrame:Inverse()
	for _, part in record.parts do
		part.CFrame = delta * part.CFrame
	end
end

local function setAnchored(record, anchored)
	for _, part in record.parts do
		part.Anchored = anchored
	end
end

-- How a Tool stands when it is upright: the direction its Grip calls "up" points up
local function uprightRotation(tool)
	return tool.Grip.Rotation:Inverse()
end

-- Lowest point of the upright Tool, measured from its Handle
local function uprightBottom(record)
	local upright = uprightRotation(record.tool)
	local lowest = math.huge
	for _, part in record.parts do
		local relative = upright * record.handle.CFrame:ToObjectSpace(part.CFrame)
		local half = part.Size / 2
		for _, x in { -1, 1 } do
			for _, y in { -1, 1 } do
				for _, z in { -1, 1 } do
					lowest = math.min(lowest, (relative * Vector3.new(half.X * x, half.Y * y, half.Z * z)).Y)
				end
			end
		end
	end
	return lowest
end

local function inVR()
	return VRService.VREnabled
end

-- World CFrame of a VR controller ("Right" / "Left"), or of the character's hand
-- when the controller is not tracked. nil when there is neither.
local function handCFrame(side)
	local camera = workspace.CurrentCamera
	local userCFrame = side == "Left" and Enum.UserCFrame.LeftHand or Enum.UserCFrame.RightHand
	if camera and inVR() and VRService:GetUserCFrameEnabled(userCFrame) then
		local tracked = VRService:GetUserCFrame(userCFrame)
		return camera.CFrame * (CFrame.new(tracked.Position * camera.HeadScale) * tracked.Rotation)
	end
	local character = player.Character
	local hand = character and character:FindFirstChild(side .. "Hand")
	return hand and hand.CFrame or nil
end

-- Where the player's mouth is (just below and in front of their eyes)
local function mouthPosition()
	local camera = workspace.CurrentCamera
	if not camera then
		return nil
	end
	local scale = inVR() and camera.HeadScale or 1
	return (camera:GetRenderCFrame() * CFrame.new(0, -0.45 * scale, -0.25 * scale)).Position
end

local function log(message)
	if context and context.debugLog then
		context.debugLog(message)
	end
end

local function sparkle(position, count)
	if context and context.burst then
		context.burst(position, "Sparkles", count)
	end
end

local function forget(record)
	local index = table.find(records, record)
	if index then
		table.remove(records, index)
	end
	if vrHeld == record then
		vrHeld = nil
	end
end

---------------------------------------------------------------------
-- Eating
---------------------------------------------------------------------

-- Desktop only: the food swings up towards the face and back (the Tool's Grip moves,
-- so no animation or camera is involved)
local function swingToMouth(record)
	local tool = record.tool
	local restGrip = record.restGrip
	task.spawn(function()
		local started = os.clock()
		while tool.Parent and os.clock() - started < 0.45 do
			local amount = math.sin((os.clock() - started) / 0.45 * math.pi)
			tool.Grip = restGrip * CFrame.new(0, 0.6 * amount, 0.8 * amount):Inverse()
			RunService.RenderStepped:Wait()
		end
		if tool.Parent then
			tool.Grip = restGrip
		end
	end)
end

local function bite(record)
	if record.state ~= "held" and record.state ~= "equipped" then
		return
	end
	local now = os.clock()
	if now - record.lastBite < BITE_COOLDOWN then
		return
	end
	record.lastBite = now
	record.bites += 1

	SoundService:PlayLocalSound(record.sound)
	sparkle(record.handle.Position, 8)
	if record.state == "equipped" then
		swingToMouth(record)
	end

	if record.bites < BITES then
		record.tool:ScaleTo(record.baseScale * (1 - 0.22 * record.bites))
		return
	end

	-- last bite: it shrinks away
	log("ate: " .. record.id)
	record.state = "eaten"
	forget(record)
	local tool = record.tool
	local shrink = Instance.new("NumberValue")
	shrink.Value = tool:GetScale()
	shrink.Changed:Connect(function(value)
		if tool.Parent then
			tool:ScaleTo(math.max(value, 0.02))
		end
	end)
	local tween = TweenService:Create(shrink, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Value = 0.02 })
	tween.Completed:Connect(function()
		shrink:Destroy()
		tool:Destroy()
	end)
	tween:Play()
end

---------------------------------------------------------------------
-- Picking up
---------------------------------------------------------------------

local function take(record, side)
	if record.state ~= "tray" then
		return
	end
	if inVR() and vrHeld then
		return -- one item at a time in VR
	end
	if record.prompt then
		record.prompt:Destroy()
		record.prompt = nil
	end
	sparkle(record.handle.Position, 10)
	log("took: " .. record.id)

	if inVR() then
		-- rides on the hand; stays anchored and is placed every frame
		record.state = "held"
		record.side = side or (VR_TRAY_HAND == "Left" and "Right" or "Left")
		record.lastBite = os.clock() -- no bite on the way past the face
		vrHeld = record
		record.tool.Parent = context.scene
		return
	end

	-- desktop: becomes an ordinary equipped Tool
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local backpack = player:FindFirstChildOfClass("Backpack")
	if not humanoid or not backpack then
		return
	end
	record.state = "equipped"
	setAnchored(record, false)
	record.tool.Parent = backpack
	humanoid:EquipTool(record.tool)
end

---------------------------------------------------------------------
-- Used by LingoClient
---------------------------------------------------------------------

-- Puts a food Tool on the tray at slotCFrame (a point on the tray's surface).
-- Returns false when there is no Tool for that menu item.
function Food.addToTray(tray, itemId, slotCFrame)
	local template = templates:FindFirstChild(itemId)
	if not template or not template:FindFirstChild("Handle") then
		return false
	end

	local tool = template:Clone()
	local record = {
		id = itemId, tool = tool, handle = tool.Handle, parts = partsOf(tool), tray = tray,
		state = "tray", bites = 0, lastBite = 0, baseScale = tool:GetScale(), restGrip = tool.Grip,
	}
	setAnchored(record, true)
	moveTool(record, slotCFrame * CFrame.new(0, -uprightBottom(record), 0) * uprightRotation(tool))
	record.slot = tray.base.CFrame:ToObjectSpace(record.handle.CFrame)

	-- the Tool's own eating sound, if it has one
	local sound = tool:FindFirstChild("DrinkSound", true) or tool:FindFirstChildWhichIsA("Sound", true)
	if not sound or sound.SoundId == "" then
		sound = Instance.new("Sound")
		sound.SoundId = FALLBACK_BITE_SOUND
		sound.Parent = record.handle
	end
	sound.Volume = 0.8
	record.sound = sound

	if context then
		tool.Name = context.itemName(context.learnLanguage.code, itemId)
		tool.ToolTip = context.itemName(context.mainLanguage.code, itemId)
	end
	tool.Activated:Connect(function()
		bite(record)
	end)
	tool.Destroying:Connect(function()
		forget(record)
	end)

	tool.Parent = tray.model
	table.insert(records, record)
	return true
end

-- The player now carries this tray: its food can be picked up.
function Food.trayTaken(tray)
	activeTray = tray
	trayTakenAt = os.clock()
	for _, record in records do
		if record.tray == tray and record.state == "tray" and not record.prompt then
			local prompt = Instance.new("ProximityPrompt")
			prompt.ObjectText = record.tool.Name
			prompt.ActionText = record.tool.ToolTip
			prompt.HoldDuration = 0
			prompt.MaxActivationDistance = 9
			prompt.RequiresLineOfSight = false
			prompt.Triggered:Connect(function()
				take(record)
			end)
			prompt.Parent = record.handle
			record.prompt = prompt
		end
	end
end

-- Which hand the tray should ride on in VR ("Left" / "Right")
Food.VR_TRAY_HAND = VR_TRAY_HAND

-- context = { scene, mainLanguage, learnLanguage, itemName(code, itemId), burst(position, effect, count), debugLog(message) }
function Food.start(newContext)
	context = newContext

	RunService.RenderStepped:Connect(function()
		local record = vrHeld
		if not record then
			return
		end
		local hand = handCFrame(record.side)
		if not hand then
			return
		end
		-- sits just above the hand, upright when the hand is level
		moveTool(record, hand * CFrame.new(0, 0.15, -0.1) * CFrame.new(0, -uprightBottom(record), 0) * uprightRotation(record.tool))

		local mouth = mouthPosition()
		if mouth and (record.handle.Position - mouth).Magnitude < VR_MOUTH_RANGE then
			bite(record)
		end
	end)

	RunService.Heartbeat:Connect(function()
		-- VR: the free hand picks up whatever food it reaches
		if not inVR() or vrHeld or not activeTray or os.clock() - trayTakenAt < 0.8 then
			return
		end
		local side = VR_TRAY_HAND == "Left" and "Right" or "Left"
		local hand = handCFrame(side)
		if not hand then
			return
		end
		local nearest, nearestDistance = nil, VR_GRAB_RANGE
		for _, record in records do
			if record.state == "tray" and record.tray == activeTray then
				local distance = (record.handle.Position - hand.Position).Magnitude
				if distance < nearestDistance then
					nearest, nearestDistance = record, distance
				end
			end
		end
		if nearest then
			take(nearest, side)
		end
	end)
end

-- For tests
Food._records = records
Food._take = take
Food._bite = bite

return Food
