-- Food and drink: every item in every scenario is a real Roblox gear Tool (client side only).
-- The templates in ReplicatedStorage.FoodTools are official Roblox gear from the
-- marketplace (attributes GearId / GearName say which). Their own scripts were removed,
-- so everything they do is in this module:
--   * A scenario stands an item on a tray or a table with Food.place.
--   * Once it is takeable the player picks it up and it is equipped like any gear:
--       desktop: its prompt -> equipped; click to take a bite
--       VR: reach for it with either hand -> equipped; bring it to your mouth (or pull the trigger)
--   * Each bite shrinks it, and after the last one it is gone.
-- Used by StarterPlayerScripts.LingoClient and ReplicatedStorage.LingoScenes.
-- Never touches the camera or the controls.

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local VRService = game:GetService("VRService")

local player = Players.LocalPlayer
local templates = ReplicatedStorage:WaitForChild("FoodTools")

local DEFAULT_BITES = 4 -- bites or sips an item lasts unless the scenario says otherwise
local BITE_COOLDOWN = 0.9 -- seconds between bites
local VR_GRAB_RANGE = 1.4 -- studs between a hand and an item to pick it up
local VR_MOUTH_RANGE = 1.3 -- studs between the item and the mouth to take a bite
local FALLBACK_BITE_SOUND = "rbxassetid://9119717523" -- for gear that has no eating sound of its own

local Food = {}

local context = {} -- set by Food.start
local records = {} -- every item that still exists
local started = false

---------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------

local function inVR()
	return VRService.VREnabled
end

local function log(message)
	if context.debugLog then
		context.debugLog(message)
	end
end

local function burst(position, effect, count)
	if context.burst then
		context.burst(position, effect, count)
	end
end

local function tween(instance, seconds, goal)
	TweenService:Create(instance, TweenInfo.new(seconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), goal):Play()
end

-- Where a hand is: the VR controller when it is tracked, otherwise the character's hand
local function handPosition(side)
	local camera = workspace.CurrentCamera
	local userCFrame = side == "Left" and Enum.UserCFrame.LeftHand or Enum.UserCFrame.RightHand
	if camera and inVR() and VRService:GetUserCFrameEnabled(userCFrame) then
		local tracked = VRService:GetUserCFrame(userCFrame)
		return (camera.CFrame * CFrame.new(tracked.Position * camera.HeadScale)).Position
	end
	local character = player.Character
	local hand = character and character:FindFirstChild(side .. "Hand")
	return hand and hand.Position or nil
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

local function forget(record)
	local index = table.find(records, record)
	if index then
		table.remove(records, index)
	end
end

-- The item the player has in their hand right now
local function equippedRecord()
	local character = player.Character
	if not character then
		return nil
	end
	for _, record in records do
		if record.state == "held" and record.tool.Parent == character then
			return record
		end
	end
	return nil
end

---------------------------------------------------------------------
-- Eating
---------------------------------------------------------------------

-- Desktop: the food swings up towards the face and back. Only the Tool's Grip moves,
-- so no animation or camera is involved.
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
	local character = player.Character
	if record.state ~= "held" or not character or record.tool.Parent ~= character then
		return -- only what is in the hand can be eaten
	end
	local now = os.clock()
	if now - record.lastBite < BITE_COOLDOWN then
		return
	end
	if context.canBite and not context.canBite(record) then
		return
	end
	record.lastBite = now
	record.bitesLeft -= 1

	record.sound:Play()
	burst(record.handle.Position, record.drink and "Drops" or "Poof", record.drink and 8 or 5)
	if not inVR() then
		swingToMouth(record)
	end
	if record.mesh then
		tween(record.mesh, 0.25, { Scale = record.baseScale * (0.4 + 0.6 * math.max(record.bitesLeft, 0) / record.bites) })
	end
	if context.onBite then
		context.onBite(record)
	end

	if record.bitesLeft <= 0 then
		log("finished " .. record.id)
		record.state = "eaten"
		forget(record)
		burst(record.handle.Position, "Sparkles", 16)
		if record.mesh then
			tween(record.mesh, 0.3, { Scale = Vector3.zero })
		end
		Debris:AddItem(record.tool, 1.5) -- long enough for the last bite's sound to finish
	end
end

---------------------------------------------------------------------
-- Picking up
---------------------------------------------------------------------

local function take(record)
	if record.state ~= "placed" or not record.takeable then
		return false
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local backpack = player:FindFirstChildOfClass("Backpack")
	if not humanoid or humanoid.Health <= 0 or not backpack then
		return false
	end
	if inVR() and character:FindFirstChildOfClass("Tool") then
		return false -- one thing in the hand at a time in VR: finish it first
	end

	record.state = "held"
	record.takeable = false
	record.lastBite = os.clock() -- no bite on the way past the face
	if record.prompt then
		record.prompt:Destroy()
		record.prompt = nil
	end
	if record.openSound then
		record.openSound:Play()
	end
	burst(record.handle.Position, "Sparkles", 16)
	log("picked up " .. record.id)

	-- from here on it is an ordinary equipped Tool
	record.handle.Anchored = false
	record.tool.Parent = backpack
	humanoid:EquipTool(record.tool)

	if record.onTaken then
		task.spawn(record.onTaken, record)
	end
	return true
end

---------------------------------------------------------------------
-- Used by the scenarios
---------------------------------------------------------------------

-- Is there gear for this menu item?
function Food.has(itemId)
	return templates:FindFirstChild(itemId) ~= nil
end

-- Stands the gear for itemId on a surface. surfaceCFrame is a point on the surface
-- (its Y axis pointing up out of it). Returns a record, or nil when there is no such gear.
-- options = { name = Tool name (shown on the prompt and the hotbar), bites, fill, onTaken = function(record) }
function Food.place(itemId, parent, surfaceCFrame, options)
	local template = templates:FindFirstChild(itemId)
	if not template or not template:FindFirstChild("Handle") then
		return nil
	end
	options = options or {}

	local tool = template:Clone()
	local handle = tool.Handle
	handle.Anchored = true
	handle.CanCollide = false
	handle.CanTouch = false -- so walking into it does not pick it up
	handle.Massless = true

	-- upright the way it is held: the direction its Grip calls "up" points up
	local upright = tool.Grip.Rotation:Inverse()
	local half = handle.Size / 2
	local lowest = math.huge
	for _, x in { -1, 1 } do
		for _, y in { -1, 1 } do
			for _, z in { -1, 1 } do
				lowest = math.min(lowest, (upright * Vector3.new(half.X * x, half.Y * y, half.Z * z)).Y)
			end
		end
	end
	-- RestLift: how far this gear's mesh sits above (+) or below (-) the bottom of its Handle
	local lift = tool:GetAttribute("RestLift") or 0
	handle.CFrame = surfaceCFrame * CFrame.new(0, lift - lowest, 0) * upright

	local sound = handle:FindFirstChild("EatSound")
	if not sound or sound.SoundId == "" then
		sound = Instance.new("Sound")
		sound.Name = "EatSound"
		sound.SoundId = FALLBACK_BITE_SOUND
		sound.Parent = handle
	end
	sound.Volume = 0.8

	local mesh = handle:FindFirstChildOfClass("SpecialMesh")
	local bites = options.bites or DEFAULT_BITES
	local record = {
		id = itemId, tool = tool, handle = handle, mesh = mesh, baseScale = mesh and mesh.Scale or Vector3.one,
		state = "placed", takeable = false, bites = bites, bitesLeft = bites, fill = options.fill or 0,
		drink = tool:GetAttribute("Kind") == "drink", lastBite = 0, restGrip = tool.Grip,
		sound = sound, openSound = handle:FindFirstChild("OpenSound"), onTaken = options.onTaken,
	}

	tool.Name = options.name or itemId
	tool.ToolTip = ""
	tool.CanBeDropped = false
	tool.Activated:Connect(function()
		bite(record)
	end)
	tool.Destroying:Connect(function()
		forget(record)
	end)

	tool.Parent = parent
	table.insert(records, record)
	return record
end

-- Lets the player pick the item up (or not): shows its prompt, and in VR lets a hand grab it
function Food.setTakeable(record, takeable)
	if record.state ~= "placed" then
		return
	end
	record.takeable = takeable
	if takeable and not record.prompt then
		local prompt = Instance.new("ProximityPrompt")
		prompt.ActionText = record.tool.Name
		prompt.ObjectText = ""
		prompt.HoldDuration = 0
		prompt.MaxActivationDistance = 9
		prompt.RequiresLineOfSight = false
		prompt.Triggered:Connect(function()
			take(record)
		end)
		prompt.Parent = record.handle
		record.prompt = prompt
	elseif not takeable and record.prompt then
		record.prompt:Destroy()
		record.prompt = nil
	end
end

-- Takes an item away (one the player is holding or has eaten is left alone)
function Food.remove(record)
	if record.state == "placed" or record.state == "npc" then
		forget(record)
		record.tool:Destroy()
	end
end

-- Someone else eats this item (a friend at the table). Every few seconds it lifts from
-- where it stands to their mouth for a bite and goes back, until it is gone. The player
-- cannot take it. mouth() returns where their mouth is now, or nil to stop eating.
-- Yields until the item is finished, so call it from its own thread.
function Food.npcEat(record, mouth, pause)
	if record.state ~= "placed" then
		return
	end
	Food.setTakeable(record, false)
	record.state = "npc"
	local tool, handle = record.tool, record.handle
	local rest = handle.CFrame
	pause = pause or 4

	while tool.Parent and record.bitesLeft > 0 do
		local target = mouth()
		if not target then
			break
		end
		tween(handle, 0.45, { CFrame = rest.Rotation + target })
		task.wait(0.5)
		if not tool.Parent then
			return
		end
		record.bitesLeft -= 1
		record.sound:Play()
		burst(handle.Position, record.drink and "Drops" or "Poof", record.drink and 8 or 5)
		if record.mesh then
			tween(record.mesh, 0.25, { Scale = record.baseScale * (0.4 + 0.6 * math.max(record.bitesLeft, 0) / record.bites) })
		end
		if record.bitesLeft <= 0 then
			break
		end
		tween(handle, 0.45, { CFrame = rest })
		task.wait(pause * (0.75 + math.random() * 0.5))
	end

	if not tool.Parent then
		return
	end
	if record.bitesLeft <= 0 then
		-- the last bite: it is gone
		record.state = "eaten"
		forget(record)
		if record.mesh then
			tween(record.mesh, 0.3, { Scale = Vector3.zero })
		end
		Debris:AddItem(tool, 1.5)
	else
		tween(handle, 0.45, { CFrame = rest }) -- stopped part way: back on its plate
	end
end

-- context = { burst(position, effect, count), debugLog(message),
--             canBite(record) -> false to refuse a bite, onBite(record) after each bite }
function Food.start(newContext)
	context = newContext or {}
	if started then
		return
	end
	started = true

	RunService.Heartbeat:Connect(function()
		if not inVR() then
			return
		end
		local character = player.Character
		if not character then
			return
		end

		-- food held up to the mouth gets eaten
		local equipped = equippedRecord()
		if equipped then
			local mouth = mouthPosition()
			if mouth and (equipped.handle.Position - mouth).Magnitude < VR_MOUTH_RANGE then
				bite(equipped)
			end
			return
		end
		if character:FindFirstChildOfClass("Tool") then
			return
		end

		-- an empty hand picks up whatever food it reaches
		for _, side in { "Right", "Left" } do
			local hand = handPosition(side)
			if hand then
				local nearest, nearestDistance = nil, VR_GRAB_RANGE
				for _, record in records do
					if record.state == "placed" and record.takeable then
						local distance = (record.handle.Position - hand).Magnitude
						if distance < nearestDistance then
							nearest, nearestDistance = record, distance
						end
					end
				end
				if nearest and take(nearest) then
					return
				end
			end
		end
	end)
end

-- For tests
Food._records = records
Food._take = take
Food._bite = bite

return Food
