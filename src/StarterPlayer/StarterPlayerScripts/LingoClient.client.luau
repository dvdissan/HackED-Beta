-- Language-practice game, client side.
--   1. Intro screen (no character yet): pick your language, the language to practise, a scenario.
--   2. The character spawns and the fast food restaurant pops into the field.
--   3. Talk to anyone inside with your voice; the cook makes the food and brings a tray,
--      and you pick the food up, hold it and eat it.
-- The server (ServerScriptService.LingoServer) only spawns the character and calls the AI.
-- The only camera work is the slow sweep behind the intro menu; once the character
-- spawns the default camera is back in charge. The controls are never touched.

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TextChatService = game:GetService("TextChatService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local VRService = game:GetService("VRService")

local Data = require(ReplicatedStorage:WaitForChild("LingoData"))
local LingoFood = require(ReplicatedStorage:WaitForChild("LingoFood")) -- food as real Tools: pick up and eat
local Remotes = ReplicatedStorage:WaitForChild("LingoRemotes")
local startScenario = Remotes:WaitForChild("StartScenario")
local npcGenerate = Remotes:WaitForChild("NpcGenerate")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local SHOW_DEBUG = false -- set to true for a small log in the bottom-left corner (it always prints to the Output window)

local WHITE = Color3.new(1, 1, 1)
local INK = Color3.fromRGB(30, 34, 48)

---------------------------------------------------------------------
-- Small helpers
---------------------------------------------------------------------

local function create(className, props, parent)
	local instance = Instance.new(className)
	for key, value in props do
		instance[key] = value
	end
	instance.Parent = parent
	return instance
end

local function tween(instance, seconds, goal, style, direction)
	local info = TweenInfo.new(seconds, style or Enum.EasingStyle.Quad, direction or Enum.EasingDirection.Out)
	local t = TweenService:Create(instance, info, goal)
	t:Play()
	return t
end

---------------------------------------------------------------------
-- Sound
---------------------------------------------------------------------

local sounds = {}
for name, info in Data.Sounds do
	sounds[name] = create("Sound", {
		Name = name,
		SoundId = info.id,
		Volume = info.volume,
		Looped = info.looped == true,
	}, SoundService)
end

local function playSound(name)
	local sound = sounds[name]
	if sound then
		sound.TimePosition = 0
		sound:Play()
	end
end

---------------------------------------------------------------------
-- Particle effects
---------------------------------------------------------------------

local TEXTURE = {
	Sparkle = "rbxasset://textures/particles/sparkles_main.dds",
	Smoke = "rbxasset://textures/particles/smoke_main.dds",
	Fire = "rbxasset://textures/particles/fire_main.dds",
}

local function numberSequence(...)
	local points = {}
	local values = { ... }
	for i, value in values do
		table.insert(points, NumberSequenceKeypoint.new((i - 1) / (#values - 1), value))
	end
	return NumberSequence.new(points)
end

local EFFECT = {
	Sparkles = {
		Texture = TEXTURE.Sparkle, LightEmission = 1, Color = ColorSequence.new(Color3.fromRGB(255, 232, 130)),
		Lifetime = NumberRange.new(0.5, 1.1), Speed = NumberRange.new(4, 10), SpreadAngle = Vector2.new(180, 180),
		Size = numberSequence(0.6, 0.3, 0), Drag = 3,
	},
	Dust = {
		Texture = TEXTURE.Smoke, Color = ColorSequence.new(Color3.fromRGB(215, 205, 180)),
		Lifetime = NumberRange.new(1.2, 2.2), Speed = NumberRange.new(14, 30), SpreadAngle = Vector2.new(90, 90),
		Size = numberSequence(3, 7, 9), Transparency = numberSequence(0.4, 0.7, 1), Drag = 2,
		Rotation = NumberRange.new(0, 360), EmissionDirection = Enum.NormalId.Top,
	},
	Poof = {
		Texture = TEXTURE.Smoke, Color = ColorSequence.new(WHITE),
		Lifetime = NumberRange.new(0.5, 0.9), Speed = NumberRange.new(3, 7), SpreadAngle = Vector2.new(180, 180),
		Size = numberSequence(1.5, 3, 3.5), Transparency = numberSequence(0.3, 0.6, 1), Rotation = NumberRange.new(0, 360),
	},
	Fire = {
		Texture = TEXTURE.Fire, LightEmission = 1, Color = ColorSequence.new(Color3.fromRGB(255, 170, 60)),
		Lifetime = NumberRange.new(0.35, 0.7), Speed = NumberRange.new(2, 3.5), SpreadAngle = Vector2.new(20, 20),
		Size = numberSequence(0.9, 0.6, 0), Rate = 35,
	},
	Smoke = {
		Texture = TEXTURE.Smoke, Color = ColorSequence.new(Color3.fromRGB(190, 190, 190)),
		Lifetime = NumberRange.new(1.5, 2.5), Speed = NumberRange.new(1.5, 2.5), SpreadAngle = Vector2.new(15, 15),
		Size = numberSequence(0.8, 1.8, 2.6), Transparency = numberSequence(0.6, 0.8, 1), Rate = 9, Rotation = NumberRange.new(0, 360),
	},
	Bubbles = {
		Texture = TEXTURE.Sparkle, LightEmission = 0.8, Color = ColorSequence.new(Color3.fromRGB(255, 215, 90)),
		Lifetime = NumberRange.new(0.3, 0.6), Speed = NumberRange.new(1.5, 3), SpreadAngle = Vector2.new(35, 35),
		Size = numberSequence(0.25, 0.35, 0), Rate = 30,
	},
	Drops = {
		Texture = TEXTURE.Sparkle, LightEmission = 0.6, Color = ColorSequence.new(Color3.fromRGB(110, 190, 255)),
		Lifetime = NumberRange.new(0.3, 0.5), Speed = NumberRange.new(0.5, 1), SpreadAngle = Vector2.new(8, 8),
		Size = numberSequence(0.2, 0.2, 0), Rate = 35, Acceleration = Vector3.new(0, -18, 0), EmissionDirection = Enum.NormalId.Bottom,
	},
	Mist = {
		Texture = TEXTURE.Smoke, Color = ColorSequence.new(Color3.fromRGB(205, 235, 255)),
		Lifetime = NumberRange.new(1, 1.8), Speed = NumberRange.new(0.6, 1.4), SpreadAngle = Vector2.new(60, 60),
		Size = numberSequence(0.8, 1.6, 2.2), Transparency = numberSequence(0.5, 0.8, 1), Rate = 12, Acceleration = Vector3.new(0, -1.5, 0),
	},
}

local function effectAnchor(position)
	return create("Part", {
		Name = "EffectAnchor", Anchored = true, CanCollide = false, CanQuery = false, CanTouch = false,
		Transparency = 1, Size = Vector3.new(0.4, 0.4, 0.4), Position = position,
	}, workspace)
end

local function addEmitter(parent, effectName, enabled)
	local emitter = Instance.new("ParticleEmitter")
	for key, value in EFFECT[effectName] do
		emitter[key] = value
	end
	emitter.Enabled = enabled == true
	emitter.Parent = parent
	return emitter
end

-- One-off puff of particles at a point
local function burst(position, effectName, count, anchorSize)
	local anchor = effectAnchor(position)
	if anchorSize then
		anchor.Size = anchorSize
	end
	local emitter = addEmitter(anchor, effectName, false)
	task.defer(function()
		emitter:Emit(count)
	end)
	Debris:AddItem(anchor, 5)
end

---------------------------------------------------------------------
-- Debug overlay
---------------------------------------------------------------------

local debugLines = {}
local debugLabel

do
	local gui = create("ScreenGui", { Name = "LingoDebug", ResetOnSpawn = false, DisplayOrder = 50, Enabled = SHOW_DEBUG }, playerGui)
	local frame = create("Frame", {
		AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 12, 1, -12), Size = UDim2.new(0, 460, 0, 170),
		BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.45, BorderSizePixel = 0,
	}, gui)
	debugLabel = create("TextLabel", {
		Position = UDim2.new(0, 8, 0, 6), Size = UDim2.new(1, -16, 1, -12), BackgroundTransparency = 1,
		TextColor3 = WHITE, Font = Enum.Font.Code, TextSize = 13, TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Bottom, Text = "",
	}, frame)
end

local function debugLog(message)
	print("[Lingo]", message)
	table.insert(debugLines, os.date("%H:%M:%S ") .. message)
	while #debugLines > 8 do
		table.remove(debugLines, 1)
	end
	debugLabel.Text = table.concat(debugLines, "\n")
end

---------------------------------------------------------------------
-- Back to the main menu (Lumi does this when asked)
---------------------------------------------------------------------

-- Clears away everything this script built, has the server take the character
-- away, then starts a fresh copy of this script (which opens the intro again)
-- and stops this one.
local function returnToMenu()
	debugLog("back to the main menu")
	Remotes:WaitForChild("ReturnToMenu"):FireServer()

	-- the airplane / dinner module keeps its own loops; stop them
	local scenesModule = ReplicatedStorage:FindFirstChild("LingoScenes")
	if scenesModule then
		pcall(function()
			require(scenesModule).stop()
		end)
	end

	-- the scenario in the world
	for _, name in { "FastFood", "Airplane", "Dinner" } do
		local scene = workspace:FindFirstChild(name)
		if scene then
			scene:Destroy()
		end
	end
	for _, child in workspace:GetChildren() do
		if child.Name == "EffectAnchor" then
			child:Destroy()
		end
	end
	-- sounds, interface and microphone objects
	for _, sound in sounds do
		sound:Destroy()
	end
	for _, name in { "LingoDebug", "LingoHud", "IntroGui" } do
		local gui = playerGui:FindFirstChild(name)
		if gui then
			gui:Destroy()
		end
	end
	for _, name in { "LingoMic", "LingoSTT" } do
		local object = player:FindFirstChild(name)
		if object then
			object:Destroy()
		end
	end
	local camera = workspace.CurrentCamera
	if camera then
		camera.CameraType = Enum.CameraType.Custom
	end

	-- a fresh copy of this script takes over; destroying this one ends its loops
	local template = game:GetService("StarterPlayer"):WaitForChild("StarterPlayerScripts"):FindFirstChild(script.Name)
	if template then
		local fresh = template:Clone()
		fresh.Parent = script.Parent
	end
	script:Destroy()
end

---------------------------------------------------------------------
-- Intro screen
---------------------------------------------------------------------

-- Friends: the people in the restaurant look like the player's friends.
-- Their avatars start loading straight away, while the intro screen is up.

local FRIEND_ROLES = { "Cashier", "Cook", "Cleaner", "Customer" } -- the fast food roles; the other scenarios share these avatars
local FRIEND_WAIT = 6 -- seconds the scenario waits for avatars that are still loading

local friendRigs = {} -- [role name] = character model of one of the player's friends
local friendsLoading = #FRIEND_ROLES

task.spawn(function()
	-- everyone on the friends list, shuffled so each visit has different faces
	local ids = {}
	local ok, err = pcall(function()
		local pages = Players:GetFriendsAsync(player.UserId)
		while true do
			for _, friend in pages:GetCurrentPage() do
				table.insert(ids, friend.Id)
			end
			if pages.IsFinished or #ids >= 200 then
				break
			end
			pages:AdvanceToNextPageAsync()
		end
	end)
	if not ok then
		debugLog("friends list FAILED: " .. tostring(err))
	end
	for index = #ids, 2, -1 do
		local other = math.random(index)
		ids[index], ids[other] = ids[other], ids[index]
	end
	debugLog(#ids .. " friends found")

	-- one loader per role; each takes the next friend until an avatar loads.
	-- With fewer friends than roles, the rest keep their usual look.
	for _, role in FRIEND_ROLES do
		task.spawn(function()
			while #ids > 0 do
				local id = table.remove(ids)
				local okRig, rig = pcall(function()
					local description = Players:GetHumanoidDescriptionFromUserId(id)
					return Players:CreateHumanoidModelFromDescription(description, Enum.HumanoidRigType.R15)
				end)
				if okRig and rig then
					friendRigs[role] = rig
					break
				end
				debugLog("friend avatar FAILED: " .. tostring(rig))
			end
			friendsLoading -= 1
		end)
	end
end)

-- Puts a friend's avatar where one of the scene's characters stands, and removes the original.
local function swapInFriend(original, friendRig)
	local oldRoot = original:WaitForChild("HumanoidRootPart")
	local oldHumanoid = original:WaitForChild("Humanoid")
	local root = friendRig:WaitForChild("HumanoidRootPart")
	local humanoid = friendRig:WaitForChild("Humanoid")

	for _, item in friendRig:GetDescendants() do
		if item:IsA("LuaSourceContainer") then
			item:Destroy() -- the avatar's own Animate / Health scripts; setupNpc animates it instead
		elseif item:IsA("BasePart") then
			item.Anchored = false
		end
	end
	root.Anchored = true -- like the originals: the scripts move the root, the body follows
	humanoid.DisplayDistanceType = oldHumanoid.DisplayDistanceType
	humanoid.HealthDisplayType = oldHumanoid.HealthDisplayType

	-- same spot and facing, with the feet on the floor whatever the avatar's height
	local floorY = oldRoot.Position.Y - oldHumanoid.HipHeight - oldRoot.Size.Y / 2
	local position = Vector3.new(oldRoot.Position.X, floorY + humanoid.HipHeight + root.Size.Y / 2, oldRoot.Position.Z)
	friendRig.PrimaryPart = root
	friendRig:PivotTo(CFrame.new(position) * oldRoot.CFrame.Rotation)

	friendRig.Name = original.Name
	friendRig.Parent = original.Parent
	original:Destroy()
end

-- For the airplane and dinner scenarios: waits (briefly) for the avatars that are
-- still loading, then hands over every friend avatar that loaded, as a list.
local function takeFriendRigs()
	local deadline = os.clock() + FRIEND_WAIT
	while friendsLoading > 0 and os.clock() < deadline do
		task.wait(0.1)
	end
	local rigs = {}
	for role, rig in friendRigs do
		table.insert(rigs, rig)
		friendRigs[role] = nil
	end
	return rigs
end

local CHOOSE_LANGUAGE = "Choose your language · Elige tu idioma · Choisis ta langue · 选择你的语言 · 言語を選択"
local GREETINGS = "Hello · Hola · Bonjour · Hallo · Ciao · Olá · こんにちは · 안녕하세요 · 你好 · Привет"

-- Shows the intro and yields until a scenario is picked.
-- Returns mainLanguage, learnLanguage, scenarioId, closeIntro()
local function runIntro()
	local picked = Instance.new("BindableEvent")
	local mainLanguage, learnLanguage

	local gui = create("ScreenGui", {
		Name = "IntroGui", IgnoreGuiInset = true, ResetOnSpawn = false, DisplayOrder = 100,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	}, playerGui)

	local root = create("CanvasGroup", {
		Name = "Root", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, BorderSizePixel = 0,
	}, gui)
	-- The gradient sits on its own frame: on the CanvasGroup it would tint every label too
	-- A soft dark tint, heavier at the top and bottom, so the text stays readable
	-- while the grass field shows through behind the menu.
	local background = create("Frame", {
		Name = "Background", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(10, 22, 40), BorderSizePixel = 0, ZIndex = 0,
	}, root)
	create("UIGradient", {
		Rotation = 90,
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(0.4, 0.88), NumberSequenceKeypoint.new(1, 0.8), -- light over the grass
		}),
	}, background)

	-- Cinematic camera: a slow sweep over the grass field behind the menu.
	-- It only runs while the intro is open (there is no character yet); the normal
	-- first-person camera takes over the moment the intro closes.
	local FIELD_FOCUS = Vector3.new(0, 3, -20)
	local cinematicStart = os.clock()
	local cinematic = RunService.RenderStepped:Connect(function()
		local camera = workspace.CurrentCamera
		camera.CameraType = Enum.CameraType.Scriptable
		if VRService.VREnabled then
			-- no camera motion in a headset (comfort): a fixed viewpoint over the field
			camera.CFrame = CFrame.lookAt(Vector3.new(0, 12, 40), FIELD_FOCUS)
			return
		end
		local t = os.clock() - cinematicStart
		local angle = math.rad(20) + t * math.rad(4) -- one lap every 90 seconds
		-- high enough, and tilted down enough, that the green field fills the lower part of the view
		local height = 24 + math.sin(t * 0.25) * 4
		local position = FIELD_FOCUS + Vector3.new(math.sin(angle) * 70, height, math.cos(angle) * 70)
		camera.CFrame = CFrame.lookAt(position, FIELD_FOCUS)
	end)
	local function stopCinematic()
		if cinematic then
			cinematic:Disconnect()
			cinematic = nil
			workspace.CurrentCamera.CameraType = Enum.CameraType.Custom
		end
	end

	-- Keeps the mouse free on desktop while the game is locked to first person
	create("TextButton", { Size = UDim2.fromOffset(2, 2), BackgroundTransparency = 1, Text = "", Modal = true }, root)

	-- Food and travel icons drifting up the screen
	local icons = { "🍔", "🍟", "🍕", "🥤", "🍦", "🌍", "💬", "🎧" }
	for i, icon in icons do
		local x = (i - 0.5) / #icons
		local label = create("TextLabel", {
			Text = icon, BackgroundTransparency = 1, TextTransparency = 0.55, TextScaled = true, ZIndex = 1, -- behind all text and buttons
			AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromScale(0.06, 0.09), Position = UDim2.fromScale(x, 1.1),
		}, root)
		task.spawn(function()
			task.wait(i * 1.1)
			while label.Parent do
				label.Position = UDim2.fromScale(x, 1.1)
				label.Rotation = math.random(-20, 20)
				local drift = TweenService:Create(label, TweenInfo.new(math.random(10, 15), Enum.EasingStyle.Linear), {
					Position = UDim2.fromScale(x + (math.random() - 0.5) * 0.08, -0.1), Rotation = math.random(-50, 50),
				})
				drift:Play()
				drift.Completed:Wait()
			end
		end)
	end

	local title = create("TextLabel", {
		Text = "HelloWorld", Font = Enum.Font.FredokaOne, TextColor3 = WHITE, TextScaled = true, BackgroundTransparency = 1, ZIndex = 3,
		AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0.04), Size = UDim2.fromScale(0.7, 0.13),
	}, root)
	local titleScale = create("UIScale", { Scale = 0.6 }, title)
	tween(titleScale, 0.7, { Scale = 1 }, Enum.EasingStyle.Back)

	create("TextLabel", {
		Text = GREETINGS, Font = Enum.Font.GothamMedium, TextColor3 = WHITE, TextTransparency = 0.2, TextScaled = true, ZIndex = 3,
		BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0.175), Size = UDim2.fromScale(0.8, 0.035),
	}, root)

	local header = create("TextLabel", {
		Text = "", Font = Enum.Font.GothamBold, TextColor3 = WHITE, TextScaled = true, BackgroundTransparency = 1, ZIndex = 3,
		AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0.235), Size = UDim2.fromScale(0.9, 0.06),
	}, root)

	-- outlines keep the white headings readable over the sky and grass
	for _, label in { title, header } do
		create("UIStroke", { Color = Color3.fromRGB(12, 24, 44), Thickness = 2, Transparency = 0.35 }, label)
	end

	local pageHolder = create("Frame", {
		Name = "Pages", BackgroundTransparency = 1, ZIndex = 3, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0.315), Size = UDim2.fromScale(0.8, 0.58),
	}, root)

	local backAction
	local backButton = create("TextButton", {
		Text = "", Font = Enum.Font.GothamBold, TextColor3 = WHITE, TextScaled = true, Visible = false, ZIndex = 3,
		BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.7, AutoButtonColor = true,
		AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0.02, 0.985), Size = UDim2.fromScale(0.2, 0.085),
	}, root)
	create("UICorner", { CornerRadius = UDim.new(0.3, 0) }, backButton)
	create("UIPadding", { PaddingTop = UDim.new(0.18, 0), PaddingBottom = UDim.new(0.18, 0) }, backButton)
	backButton.Activated:Connect(function()
		playSound("Click")
		if backAction then
			backAction()
		end
	end)

	local currentPage
	local function newPage()
		if currentPage then
			local old = currentPage
			old.Name = "OldPage"
			old.Interactable = false
			tween(old, 0.2, { GroupTransparency = 1 })
			Debris:AddItem(old, 0.3)
		end
		playSound("Whoosh")
		local page = create("CanvasGroup", {
			Name = "Page", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Position = UDim2.fromScale(0, 0.08), GroupTransparency = 1,
		}, pageHolder)
		tween(page, 0.35, { GroupTransparency = 0, Position = UDim2.fromScale(0, 0) })
		currentPage = page
		return page
	end

	-- Hover / press feel shared by every button
	local function addButtonFeel(button, index)
		local scale = create("UIScale", { Scale = 0.5 }, button)
		task.delay((index or 0) * 0.025, function()
			tween(scale, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)
		end)
		button.MouseEnter:Connect(function()
			tween(scale, 0.12, { Scale = 1.06 })
		end)
		button.MouseLeave:Connect(function()
			tween(scale, 0.12, { Scale = 1 })
		end)
	end

	local showLanguages, showScenarios

	local PANEL = Color3.fromRGB(14, 22, 38) -- dark glass behind lists and cards
	local SOFT = Color3.fromRGB(190, 200, 222) -- secondary text on the dark glass

	-- A dark, rounded, slightly see-through panel that fills a page
	local function glassPanel(page)
		local panel = create("Frame", {
			Name = "Panel", Size = UDim2.fromScale(1, 1), BackgroundColor3 = PANEL, BackgroundTransparency = 0.25, BorderSizePixel = 0,
		}, page)
		create("UICorner", { CornerRadius = UDim.new(0.05, 0) }, panel)
		create("UIStroke", { Color = WHITE, Transparency = 0.8, Thickness = 1.5 }, panel)
		return panel
	end

	-- One row of the language list: flag, the language's own name, a note, and a chevron
	local function languageRow(list, index, language, note, onPick)
		local row = create("TextButton", {
			Name = language.code, Text = "", BackgroundColor3 = WHITE, BackgroundTransparency = 0.92, AutoButtonColor = false,
			LayoutOrder = index, Size = UDim2.new(1, -6, 0, list:GetAttribute("RowHeight") or 64),
		}, list)
		create("UICorner", { CornerRadius = UDim.new(0.3, 0) }, row)
		local stroke = create("UIStroke", { Color = WHITE, Transparency = 0.86, Thickness = 1 }, row)

		create("TextLabel", {
			Name = "Flag", Text = language.flag or "", BackgroundTransparency = 1, TextScaled = true,
			AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.fromScale(0.035, 0.5), Size = UDim2.fromScale(0.11, 0.7),
		}, row)
		local native = create("TextLabel", {
			Text = language.native, Font = Enum.Font.GothamBold, TextColor3 = WHITE, TextScaled = true, BackgroundTransparency = 1,
			TextXAlignment = Enum.TextXAlignment.Left, AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.fromScale(0.18, 0.5), Size = UDim2.fromScale(0.4, 0.54),
		}, row)
		create("UITextSizeConstraint", { MaxTextSize = 48 }, native)
		local sub = create("TextLabel", {
			Text = note, Font = Enum.Font.Gotham, TextColor3 = SOFT, TextScaled = true, BackgroundTransparency = 1,
			TextXAlignment = Enum.TextXAlignment.Right, AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.fromScale(0.9, 0.5), Size = UDim2.fromScale(0.3, 0.38),
		}, row)
		create("UITextSizeConstraint", { MaxTextSize = 28 }, sub)
		create("TextLabel", {
			Text = "\u{203A}", Font = Enum.Font.GothamBold, TextColor3 = SOFT, TextScaled = true, BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.fromScale(0.975, 0.5), Size = UDim2.fromScale(0.045, 0.6),
		}, row)

		-- rows pop in one after another, and light up under the pointer
		local scale = create("UIScale", { Scale = 0.8 }, row)
		task.delay(index * 0.02, function()
			tween(scale, 0.3, { Scale = 1 }, Enum.EasingStyle.Back)
		end)
		row.MouseEnter:Connect(function()
			tween(row, 0.12, { BackgroundTransparency = 0.76 })
			tween(stroke, 0.12, { Transparency = 0.35 })
		end)
		row.MouseLeave:Connect(function()
			tween(row, 0.15, { BackgroundTransparency = 0.92 })
			tween(stroke, 0.15, { Transparency = 0.86 })
		end)
		row.Activated:Connect(function()
			playSound("Click")
			onPick(language)
		end)
	end

	function showLanguages(mode)
		local page = newPage()
		local panel = glassPanel(page)

		-- A scrolling list, one language per row. Rows are tall so they are easy to
		-- hit with a VR pointer; about five fit on screen and the rest scroll.
		local rowHeight = math.max(60, math.floor(pageHolder.AbsoluteSize.Y * 0.17))
		local rowGap = math.max(6, math.floor(rowHeight * 0.12))
		local list = create("ScrollingFrame", {
			Name = "List", BackgroundTransparency = 1, BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.fromScale(0.025, 0.5), Size = UDim2.fromScale(0.86, 0.92),
			ScrollingDirection = Enum.ScrollingDirection.Y, ScrollBarThickness = 10, ScrollBarImageColor3 = WHITE,
			ScrollBarImageTransparency = 0.3, CanvasSize = UDim2.new(0, 0, 0, 0),
		}, panel)
		list:SetAttribute("RowHeight", rowHeight)
		create("UIListLayout", { Padding = UDim.new(0, rowGap), SortOrder = Enum.SortOrder.LayoutOrder }, list)

		if mode == "main" then
			header.Text = CHOOSE_LANGUAGE
			backButton.Visible = false
		else
			header.Text = (mainLanguage.flag and (mainLanguage.flag .. "  ") or "") .. Data.Text(mainLanguage.code, "learn")
			backButton.Text = "\u{2190}  " .. Data.Text(mainLanguage.code, "back")
			backButton.Visible = true
			backAction = function()
				showLanguages("main")
			end
		end

		local rows = 0
		for index, language in Data.Languages do
			if mode == "learn" and language == mainLanguage then
				continue
			end
			local note = language.english
			if mode == "learn" and not language.voice then
				note = Data.Text(mainLanguage.code, "noVoice")
			end
			rows += 1
			languageRow(list, index, language, note, function(choice)
				if mode == "main" then
					mainLanguage = choice
					showLanguages("learn")
				else
					learnLanguage = choice
					showScenarios()
				end
			end)
		end
		list.CanvasSize = UDim2.new(0, 0, 0, rows * (rowHeight + rowGap))

		-- Big up / down buttons beside the list: one press scrolls most of a screenful.
		-- (The list also scrolls with the mouse wheel, a drag, or the thumbstick.)
		local function scrollButton(symbol, y, direction)
			local button = create("TextButton", {
				Name = direction > 0 and "ScrollDown" or "ScrollUp", Text = symbol, Font = Enum.Font.GothamBold, TextColor3 = WHITE, TextScaled = true,
				BackgroundColor3 = WHITE, BackgroundTransparency = 0.88, AutoButtonColor = true,
				AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.fromScale(0.98, y), Size = UDim2.fromScale(0.075, 0.4),
			}, panel)
			create("UICorner", { CornerRadius = UDim.new(0.2, 0) }, button)
			create("UIPadding", { PaddingTop = UDim.new(0.3, 0), PaddingBottom = UDim.new(0.3, 0) }, button)
			button.Activated:Connect(function()
				playSound("Click")
				local step = list.AbsoluteWindowSize.Y * 0.8
				local limit = math.max(0, list.AbsoluteCanvasSize.Y - list.AbsoluteWindowSize.Y)
				local target = math.clamp(list.CanvasPosition.Y + direction * step, 0, limit)
				tween(list, 0.25, { CanvasPosition = Vector2.new(0, target) })
			end)
		end
		scrollButton("\u{25B2}", 0.27, -1)
		scrollButton("\u{25BC}", 0.73, 1)
	end

	local function scenarioCard(page, index, icon, titleText, descText, enabled, onPick)
		local card = create("TextButton", {
			Name = "Scenario" .. index, Text = "", BackgroundColor3 = PANEL, BackgroundTransparency = enabled and 0.2 or 0.55,
			AutoButtonColor = enabled, Active = enabled, Size = UDim2.fromScale(0.31, 0.92), LayoutOrder = index,
		}, page)
		create("UICorner", { CornerRadius = UDim.new(0.08, 0) }, card)
		create("UIStroke", { Color = WHITE, Transparency = enabled and 0.7 or 0.88, Thickness = 1.5 }, card)
		create("TextLabel", {
			Text = icon, TextScaled = true, BackgroundTransparency = 1, TextTransparency = enabled and 0 or 0.4,
			Position = UDim2.fromScale(0.25, 0.08), Size = UDim2.fromScale(0.5, 0.42),
		}, card)
		local cardTitle = create("TextLabel", {
			Text = titleText, Font = Enum.Font.GothamBold, TextColor3 = WHITE, TextScaled = true, BackgroundTransparency = 1,
			TextTransparency = enabled and 0 or 0.4, Position = UDim2.fromScale(0.06, 0.55), Size = UDim2.fromScale(0.88, 0.17),
		}, card)
		create("UITextSizeConstraint", { MaxTextSize = 40 }, cardTitle)
		local cardDesc = create("TextLabel", {
			Text = descText, Font = Enum.Font.Gotham, TextColor3 = SOFT, TextScaled = true,
			BackgroundTransparency = 1, Position = UDim2.fromScale(0.06, 0.74), Size = UDim2.fromScale(0.88, 0.16),
		}, card)
		create("UITextSizeConstraint", { MaxTextSize = 24 }, cardDesc)
		if enabled then
			addButtonFeel(card, index * 4)
			card.Activated:Connect(function()
				playSound("Click")
				onPick()
			end)
		end
	end

	local function showLoading()
		local page = newPage()
		header.Text = Data.Text(mainLanguage.code, "loading")
		backButton.Visible = false
		local spinner = create("TextLabel", {
			Text = "🍔", TextScaled = true, BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.4), Size = UDim2.fromScale(0.2, 0.4),
		}, page)
		TweenService:Create(spinner, TweenInfo.new(1.2, Enum.EasingStyle.Linear, Enum.EasingDirection.Out, -1), { Rotation = 360 }):Play()
	end

	function showScenarios()
		local page = newPage()
		header.Text = Data.Text(mainLanguage.code, "scenario")
		backButton.Text = "←  " .. Data.Text(mainLanguage.code, "back")
		backButton.Visible = true
		backAction = function()
			showLanguages("learn")
		end
		create("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center,
			VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0.03, 0), SortOrder = Enum.SortOrder.LayoutOrder,
		}, page)
		scenarioCard(page, 1, "🍔", Data.Text(mainLanguage.code, "fastfood"),
			Data.Text(mainLanguage.code, "fastfoodDesc") .. "  ·  " .. (learnLanguage.flag and (learnLanguage.flag .. " ") or "") .. learnLanguage.native, true, function()
				showLoading()
				picked:Fire("fastfood")
			end)
		local practising = "  \u{00B7}  " .. (learnLanguage.flag and (learnLanguage.flag .. " ") or "") .. learnLanguage.native
		scenarioCard(page, 2, "\u{2708}\u{FE0F}", Data.Text(mainLanguage.code, "airplane"),
			Data.Text(mainLanguage.code, "airplaneDesc") .. practising, true, function()
				showLoading()
				picked:Fire("airplane")
			end)
		scenarioCard(page, 3, "\u{1F37D}\u{FE0F}", Data.Text(mainLanguage.code, "dinner"),
			Data.Text(mainLanguage.code, "dinnerDesc") .. practising, true, function()
				showLoading()
				picked:Fire("dinner")
			end)
	end

	showLanguages("main")
	local scenarioId = picked.Event:Wait()

	local function closeIntro()
		stopCinematic()
		root.Interactable = false
		tween(root, 0.8, { GroupTransparency = 1 })
		Debris:AddItem(gui, 1)
	end

	return mainLanguage, learnLanguage, scenarioId, closeIntro
end

---------------------------------------------------------------------
-- NPC movement and body animation
---------------------------------------------------------------------

local IDLE_ANIMATION = "rbxassetid://507766388" -- default R15 idle
local WALK_ANIMATION = "rbxassetid://507777826" -- default R15 walk
local SIT_ANIMATION = "rbxassetid://2506281703" -- default R15 sit
local DANCE_ANIMATION = "rbxassetid://507771019" -- default R15 dance
local NPC_WALK_SPEED = 7

-- Joints that gestures move, on top of the idle / walk animation
local POSE_JOINTS = { "Neck", "Waist", "RightShoulder", "LeftShoulder", "RightElbow", "LeftElbow" }

local function rot(x, y, z)
	return CFrame.Angles(math.rad(x or 0), math.rad(y or 0), math.rad(z or 0))
end

-- Each gesture returns joint rotations for time t. A positive first number
-- swings an arm forward / up; on the neck it looks up.
local GESTURES = {
	idle = function()
		return {}
	end,
	wave = function(t)
		return { RightShoulder = rot(165, 0, -12), RightElbow = rot(15, 0, math.sin(t * 10) * 28) }
	end,
	talk = function(t)
		return {
			RightShoulder = rot(32 + math.sin(t * 5) * 8), RightElbow = rot(45 + math.sin(t * 7) * 14),
			LeftShoulder = rot(14 + math.sin(t * 4 + 1) * 6), LeftElbow = rot(20 + math.sin(t * 6 + 2) * 8),
			Neck = rot(math.sin(t * 6) * 3),
		}
	end,
	type = function(t) -- tapping the order into the register
		return {
			RightShoulder = rot(58, 0, -8), RightElbow = rot(28 + math.sin(t * 18) * 9),
			LeftShoulder = rot(52, 0, 8), LeftElbow = rot(30 + math.sin(t * 18 + 2) * 9), Neck = rot(-12),
		}
	end,
	cook = function(t) -- working at a kitchen station
		return {
			Waist = rot(-8), Neck = rot(-14),
			RightShoulder = rot(62), RightElbow = rot(26 + math.sin(t * 8) * 20),
			LeftShoulder = rot(62), LeftElbow = rot(26 + math.sin(t * 8 + math.pi) * 20),
		}
	end,
	point = function() -- right arm straight out, toward whatever the body is facing
		return { RightShoulder = rot(92), RightElbow = rot(4), LeftShoulder = rot(6) }
	end,
	carry = function() -- holding a tray out in front
		return { RightShoulder = rot(48, 0, -6), RightElbow = rot(48), LeftShoulder = rot(48, 0, 6), LeftElbow = rot(48) }
	end,
	sweep = function(t) -- mopping
		return {
			Waist = rot(-10, math.sin(t * 3) * 22), Neck = rot(-18),
			RightShoulder = rot(50, 0, -10), RightElbow = rot(25), LeftShoulder = rot(40, 0, 10), LeftElbow = rot(35),
		}
	end,
}

local function setupNpc(rig)
	local humanoid = rig:WaitForChild("Humanoid")
	local animator = humanoid:FindFirstChildOfClass("Animator") or create("Animator", {}, humanoid)
	local function loadTrack(id)
		local ok, track = pcall(function()
			local animation = Instance.new("Animation")
			animation.AnimationId = id
			local loaded = animator:LoadAnimation(animation)
			loaded.Looped = true
			return loaded
		end)
		return ok and track or nil
	end
	local npc = {
		rig = rig,
		root = rig:WaitForChild("HumanoidRootPart"),
		idle = loadTrack(IDLE_ANIMATION),
		walk = loadTrack(WALK_ANIMATION),
		sit = loadTrack(SIT_ANIMATION),
		dance = loadTrack(DANCE_ANIMATION),
		lookAtPart = nil, -- set while talking to another NPC; otherwise the head follows the player
		lookAtPoint = nil, -- set while pointing at a place: the body and head turn to it
		ignorePlayer = false, -- true after being told to go away: no turning toward the player
		actionGesture = nil, -- a gesture the player asked for (wave, point); wins over everything
		command = nil, -- { kind = "follow" / "come" / "away" } while doing what the player asked
		joints = {},
		workGesture = "idle", -- what the job calls for (cooking, carrying, mopping)
		talkGesture = nil, -- set while talking; wins over workGesture
		neckLook = CFrame.identity, -- how far the head is turned toward the player
		waistLook = CFrame.identity, -- how far the upper body is twisted toward the player
		moving = false, -- true while a walk / turn tween owns the root
		turning = false, -- true while the whole body is turning toward the player
	}
	npc.restLook = npc.root.CFrame.LookVector -- the way it faces when nobody is around
	npc.y = npc.root.Position.Y
	for _, name in POSE_JOINTS do
		local motor = rig:FindFirstChild(name, true)
		if motor and motor:IsA("Motor6D") then
			npc.joints[name] = { motor = motor, base = motor.C0, current = CFrame.identity }
		end
	end
	if npc.dance then
		npc.dance.Priority = Enum.AnimationPriority.Action -- plays over idle and walking
	end
	if npc.idle then
		npc.idle:Play()
	end
	return npc
end

local LOOK_RANGE = 28 -- staff notice the player within this many studs
local TURN_START = math.rad(75) -- the body only starts turning once the player is further round than the head and shoulders can follow
local TURN_STOP = math.rad(30) -- and stops as soon as the head can comfortably cover the rest
local TURN_SPEED = math.rad(120) -- fastest body turn, per second

-- Runs every frame: blends the NPC's joints toward its current gesture and
-- follows lookAt (the player's head) if that is close enough. The head and
-- upper body twist toward the player; when the NPC is just standing around,
-- the whole body turns to face them too, and turns back once they leave.
local function updateNpcBody(npc, dt, lookAt)
	local gesture = GESTURES[npc.actionGesture or npc.talkGesture or npc.workGesture] or GESTURES.idle
	local targets = gesture(os.clock())
	local alpha = 1 - math.exp(-dt * 10)
	local root = npc.root

	-- while two NPCs talk to each other they look at each other, not at the player
	if npc.lookAtPart and npc.lookAtPart.Parent then
		lookAt = npc.lookAtPart.Position
	elseif npc.lookAtPoint then
		lookAt = npc.lookAtPoint -- pointing at a place
	elseif npc.ignorePlayer then
		lookAt = nil -- told to go away: keeps its back turned
	end

	-- The whole body may turn only while standing around: not walking, not
	-- working at a station / carrying / mopping, and not typing at the register.
	local free = not npc.moving and npc.workGesture == "idle" and npc.talkGesture ~= "type"

	local neckTarget, waistTarget = CFrame.identity, CFrame.identity
	local bodyYaw -- how far the body is from where it wants to face
	local direction = lookAt and root.CFrame:PointToObjectSpace(lookAt)
	if direction and direction.Magnitude < LOOK_RANGE then
		local yaw = math.atan2(-direction.X, -direction.Z)
		bodyYaw = yaw
		-- a busy NPC cannot look at someone right behind it, so it looks ahead instead
		if free or math.abs(yaw) < 2.2 then
			local waistYaw = math.clamp(yaw * 0.35, -0.45, 0.45)
			local neckYaw = math.clamp(yaw - waistYaw, -1, 1)
			local flat = math.sqrt(direction.X ^ 2 + direction.Z ^ 2)
			local pitch = math.clamp(math.atan2(direction.Y - 1.6, flat), -0.5, 0.5)
			waistTarget = CFrame.Angles(0, waistYaw, 0)
			neckTarget = CFrame.Angles(0, neckYaw, 0) * CFrame.Angles(pitch, 0, 0)
		end
	else
		local rest = root.CFrame:VectorToObjectSpace(npc.restLook)
		bodyYaw = math.atan2(-rest.X, -rest.Z)
	end
	npc.neckLook = npc.neckLook:Lerp(neckTarget, alpha)
	npc.waistLook = npc.waistLook:Lerp(waistTarget, alpha)

	if free then
		local off = math.abs(bodyYaw)
		if off > TURN_START then
			npc.turning = true
		elseif off < TURN_STOP then
			npc.turning = false
		end
		if npc.turning then
			local limit = TURN_SPEED * dt
			local step = math.clamp(bodyYaw * (1 - math.exp(-dt * 5)), -limit, limit)
			root.CFrame *= CFrame.Angles(0, step, 0)
		end
	else
		npc.turning = false
	end

	for name, joint in npc.joints do
		joint.current = joint.current:Lerp(targets[name] or CFrame.identity, alpha)
		local offset = joint.current
		if name == "Neck" then
			offset = npc.neckLook * offset
		elseif name == "Waist" then
			offset = npc.waistLook * offset
		end
		joint.motor.C0 = joint.base * offset
	end
end

local function faceDirection(npc, direction)
	local position = npc.root.Position
	npc.moving = true
	tween(npc.root, 0.2, { CFrame = CFrame.lookAt(position, position + direction) }).Completed:Wait()
	npc.restLook = npc.root.CFrame.LookVector
	npc.moving = false
end

-- Turns an NPC's whole body toward a point (ignoring height)
local function facePoint(npc, point)
	local position = npc.root.Position
	local flat = Vector3.new(point.X - position.X, 0, point.Z - position.Z)
	if flat.Magnitude > 0.5 then
		faceDirection(npc, flat.Unit)
	end
end

-- Walks an NPC in a straight line to (x, z). Yields until it arrives.
local function walkTo(npc, x, z)
	local from = npc.root.Position
	local target = Vector3.new(x, npc.y, z)
	local distance = (target - from).Magnitude
	if distance < 0.2 then
		return
	end
	local facing = CFrame.lookAt(from, target)
	npc.moving = true
	tween(npc.root, 0.15, { CFrame = facing }).Completed:Wait()
	if npc.walk then
		if npc.idle then
			npc.idle:Stop(0.2)
		end
		npc.walk:Play(0.2)
	end
	tween(npc.root, distance / NPC_WALK_SPEED, { CFrame = facing.Rotation + target }, Enum.EasingStyle.Linear).Completed:Wait()
	if npc.walk then
		npc.walk:Stop(0.2)
		if npc.idle then
			npc.idle:Play(0.2)
		end
	end
	npc.restLook = npc.root.CFrame.LookVector
	npc.moving = false
end

---------------------------------------------------------------------
-- Food props (built from simple parts)
---------------------------------------------------------------------

local UPRIGHT = CFrame.Angles(0, 0, math.rad(90)) -- stands a cylinder on its end

local function propPart(parent, shape, size, cframe, color, material, transparency)
	return create("Part", {
		Anchored = true, CanCollide = false, CanQuery = false, CanTouch = false, Massless = true,
		Shape = shape, Size = size, Color = color, Material = material or Enum.Material.SmoothPlastic,
		Transparency = transparency or 0, TopSurface = Enum.SurfaceType.Smooth, BottomSurface = Enum.SurfaceType.Smooth,
		CFrame = cframe,
	}, parent)
end

-- Upright cylinder: height along Y
local function cylinder(model, height, diameter, x, y, z, color, material)
	return propPart(model, Enum.PartType.Cylinder, Vector3.new(height, diameter, diameter), CFrame.new(x, y, z) * UPRIGHT, color, material)
end

local function block(model, size, x, y, z, color, material)
	return propPart(model, Enum.PartType.Block, size, CFrame.new(x, y, z), color, material)
end

local BUN = Color3.fromRGB(216, 160, 88)

-- The food itself is official Roblox gear: real Tools, placed and handled by LingoFood
-- (templates in ReplicatedStorage.FoodTools).

local TRAY_SLOTS = {
	Vector3.new(-1.1, 0.06, -0.5), Vector3.new(0, 0.06, -0.5), Vector3.new(1.1, 0.06, -0.5),
	Vector3.new(-1.1, 0.06, 0.5), Vector3.new(0, 0.06, 0.5), Vector3.new(1.1, 0.06, 0.5),
}

local function newTray(parent, cframe)
	local model = create("Model", { Name = "Tray" }, parent)
	local base = create("Part", {
		Name = "Base", Anchored = true, CanCollide = false, CanQuery = false, CanTouch = false,
		Size = Vector3.new(3.4, 0.12, 2.2), Color = Color3.fromRGB(125, 130, 140), Material = Enum.Material.SmoothPlastic,
		TopSurface = Enum.SurfaceType.Smooth, BottomSurface = Enum.SurfaceType.Smooth, CFrame = cframe,
	}, model)
	model.PrimaryPart = base
	return { model = model, base = base, count = 0, items = {} }
end

-- Puts one food item (a gear Tool) on the next free tray slot, with a little pop
local function addFoodToTray(tray, itemId, options)
	if tray.count >= #TRAY_SLOTS then
		return nil
	end
	local record = LingoFood.place(itemId, tray.model, tray.base.CFrame * CFrame.new(TRAY_SLOTS[tray.count + 1]), options)
	if not record then
		return nil
	end
	tray.count += 1
	local entry = { id = itemId, record = record }
	table.insert(tray.items, entry)
	burst(record.handle.Position + Vector3.new(0, 0.3, 0), "Sparkles", 14)
	return entry
end

---------------------------------------------------------------------
-- Fast food scenario
---------------------------------------------------------------------

local function runFastFood(mainLanguage, learnLanguage)
	local fastFood = Data.FastFood
	local layout = fastFood.Layout
	local function text(key)
		return Data.Text(mainLanguage.code, key)
	end

	------------------------------------------------------------------
	-- Build: the restaurant pops out of the ground
	------------------------------------------------------------------

	local scene = ReplicatedStorage:WaitForChild("Scenarios"):WaitForChild("FastFood"):Clone()

	-- The staff and the regular take on the look of the player's friends
	local standingRootY = scene.Customer.HumanoidRootPart.Position.Y -- before the swap; seat heights are measured from it
	do
		local deadline = os.clock() + FRIEND_WAIT
		while friendsLoading > 0 and os.clock() < deadline do
			task.wait(0.1)
		end
		local swapped = 0
		for _, role in FRIEND_ROLES do
			local friendRig = friendRigs[role]
			local original = scene:FindFirstChild(role)
			if friendRig and original then
				local ok, err = pcall(swapInFriend, original, friendRig)
				if ok then
					swapped += 1
				else
					debugLog(role .. " friend swap FAILED: " .. tostring(err))
				end
			end
		end
		debugLog(swapped .. " characters look like friends")
	end
	local rigs = { scene.Cashier, scene.Cook, scene.Cleaner, scene.Customer }
	for _, rig in rigs do
		rig.Parent = nil -- staff appear after the building has finished growing
	end

	-- Menu board in the language being practised, with the main language underneath
	do
		local boardGui = scene.MenuBoard.MenuGui
		create("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center,
			SortOrder = Enum.SortOrder.LayoutOrder,
		}, boardGui)
		for index, item in fastFood.Menu do
			local column = create("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1 / #fastFood.Menu, 1), LayoutOrder = index }, boardGui)
			create("TextLabel", {
				Text = fastFood.ItemName(learnLanguage.code, item.id), Font = Enum.Font.GothamBold, TextColor3 = WHITE, TextScaled = true,
				BackgroundTransparency = 1, Position = UDim2.fromScale(0.05, 0.08), Size = UDim2.fromScale(0.9, 0.36),
			}, column)
			create("TextLabel", {
				Text = fastFood.ItemName(mainLanguage.code, item.id), Font = Enum.Font.Gotham, TextColor3 = Color3.fromRGB(170, 175, 190),
				TextScaled = true, BackgroundTransparency = 1, Position = UDim2.fromScale(0.08, 0.46), Size = UDim2.fromScale(0.84, 0.2),
			}, column)
			create("TextLabel", {
				Text = "$" .. item.price, Font = Enum.Font.FredokaOne, TextColor3 = Color3.fromRGB(255, 220, 70), TextScaled = true,
				BackgroundTransparency = 1, Position = UDim2.fromScale(0.2, 0.68), Size = UDim2.fromScale(0.6, 0.26),
			}, column)
		end
	end

	scene:ScaleTo(0.05)
	scene.Parent = workspace
	playSound("Appear")
	burst(layout.Center + Vector3.new(0, 1, 0), "Dust", 60, Vector3.new(40, 1, 32))
	do
		local growth = Instance.new("NumberValue")
		growth.Value = 0.05
		growth.Changed:Connect(function(value)
			scene:ScaleTo(math.max(value, 0.02))
		end)
		tween(growth, 1.1, { Value = 1 }, Enum.EasingStyle.Back).Completed:Wait()
		scene:ScaleTo(1)
		growth:Destroy()
	end
	burst(layout.Center + Vector3.new(0, 16, 18), "Sparkles", 80, Vector3.new(30, 4, 2))

	for _, rig in rigs do
		rig.Parent = scene
		burst(rig.HumanoidRootPart.Position, "Poof", 18)
	end

	local cashier = setupNpc(scene.Cashier)
	local cook = setupNpc(scene.Cook)
	local cleaner = setupNpc(scene.Cleaner)
	local customer = setupNpc(scene.Customer)
	local staff = { cashier, cook, cleaner, customer }

	sounds.Crowd:Play()

	------------------------------------------------------------------
	-- Moving parts of the building: sliding doors, register drawer, bell
	------------------------------------------------------------------

	local DOOR_Y, DOOR_Z = 4.9, layout.DoorZ
	-- The panels slide just inside the front wall, on their own plane: at DOOR_Z itself an
	-- open door sits inside the window glass and the two flicker against each other.
	local DOOR_PANEL_Z = DOOR_Z - 0.25
	local doors = {}
	for _, side in { -1, 1 } do
		local panel = create("Part", {
			Name = "SlidingDoor", Anchored = true, Size = Vector3.new(5, 9.2, 0.3), CFrame = CFrame.new(side * 2.5, DOOR_Y, DOOR_PANEL_Z),
			Material = Enum.Material.Glass, Color = Color3.fromRGB(190, 225, 240), Transparency = 0.45,
			TopSurface = Enum.SurfaceType.Smooth, BottomSurface = Enum.SurfaceType.Smooth,
		}, scene)
		table.insert(doors, { panel = panel, side = side })
	end
	local doorsOpen = false
	local function setDoorsOpen(open)
		if doorsOpen == open then
			return
		end
		doorsOpen = open
		playSound("Whoosh")
		for _, door in doors do
			door.panel.CanCollide = not open
			tween(door.panel, 0.5, { CFrame = CFrame.new(door.side * (open and 7.4 or 2.5), DOOR_Y, DOOR_PANEL_Z) },
				Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
		end
	end

	local drawer = create("Part", {
		Name = "RegisterDrawer", Anchored = true, CanCollide = false, Size = Vector3.new(1.3, 0.25, 0.9), CFrame = CFrame.new(layout.RegisterDrawer),
		Color = Color3.fromRGB(60, 62, 70), Material = Enum.Material.Metal,
	}, scene)
	local function ringRegister()
		playSound("Register")
		tween(drawer, 0.15, { CFrame = CFrame.new(layout.RegisterDrawer + Vector3.new(0, 0, -0.8)) })
		task.delay(1.2, function()
			tween(drawer, 0.25, { CFrame = CFrame.new(layout.RegisterDrawer) })
		end)
	end

	local bell = scene:FindFirstChild("Bell")
	local function ringBell()
		playSound("Bell")
		if bell then
			local size = bell.Size
			tween(bell, 0.07, { Size = Vector3.new(size.X * 0.6, size.Y, size.Z) })
			task.delay(0.09, function()
				tween(bell, 0.25, { Size = size }, Enum.EasingStyle.Elastic)
			end)
		end
	end

	------------------------------------------------------------------
	-- Kitchen stations: particles, sound, and the food being made
	------------------------------------------------------------------

	local stationEffects = {}
	local function stationAnchor(name, yOffset)
		return effectAnchor(Vector3.new(layout.StationX[name], layout.StationTopY[name] + (yOffset or 0), layout.StationZ))
	end
	do
		local grill = stationAnchor("Grill")
		grill.Size = Vector3.new(3.5, 0.2, 1.4)
		stationEffects.Grill = { emitters = { addEmitter(grill, "Fire"), addEmitter(grill, "Smoke") }, sizzle = true }
		local fryer = stationAnchor("Fryer")
		fryer.Size = Vector3.new(2.6, 0.2, 1.2)
		stationEffects.Fryer = { emitters = { addEmitter(fryer, "Bubbles"), addEmitter(fryer, "Smoke") }, sizzle = true }
		local oven = stationAnchor("Oven", 2.4)
		stationEffects.Oven = { emitters = { addEmitter(oven, "Smoke"), addEmitter(stationAnchor("Oven", -0.2), "Fire") }, sizzle = true }
		local drinks = stationAnchor("Drinks", 0.4)
		drinks.Position += Vector3.new(0, 0, 0.9)
		stationEffects.Drinks = { emitters = { addEmitter(drinks, "Drops") } }
		local freezer = stationAnchor("Freezer", 0.2)
		freezer.Size = Vector3.new(3.5, 0.2, 1.6)
		stationEffects.Freezer = { emitters = { addEmitter(freezer, "Mist") } }
	end

	local function setStationActive(name, active)
		local effects = stationEffects[name]
		if not effects then
			return
		end
		for _, emitter in effects.emitters do
			emitter.Enabled = active
		end
		if effects.sizzle then
			if active then
				sounds.Sizzle:Play()
			else
				sounds.Sizzle:Stop()
			end
		elseif active then
			playSound("Click")
		end
	end

	-- What you see happening at each station while an item is made. Each function
	-- yields for about `seconds` and cleans up after itself.
	local STATION_SHOW = {
		Grill = function(x, seconds) -- a patty browns and gets flipped
			local at = CFrame.new(x, layout.StationTopY.Grill + 0.02, layout.StationZ)
			local patty = propPart(scene, Enum.PartType.Cylinder, Vector3.new(0.2, 1.05, 1.05), at * UPRIGHT, Color3.fromRGB(205, 95, 95))
			tween(patty, seconds, { Color = Color3.fromRGB(98, 58, 34) }, Enum.EasingStyle.Linear)
			task.wait(seconds * 0.45)
			tween(patty, 0.22, { CFrame = (at + Vector3.new(0, 0.9, 0)) * CFrame.Angles(math.rad(90), 0, 0) * UPRIGHT }).Completed:Wait()
			tween(patty, 0.22, { CFrame = at * CFrame.Angles(math.rad(180), 0, 0) * UPRIGHT }, Enum.EasingStyle.Quad, Enum.EasingDirection.In).Completed:Wait()
			burst(at.Position + Vector3.new(0, 0.3, 0), "Poof", 6)
			task.wait(math.max(seconds * 0.55 - 0.44, 0.1))
			patty:Destroy()
		end,
		Fryer = function(x, seconds) -- a basket of fries dips into the oil
			local top = layout.StationTopY.Fryer
			local up, down = CFrame.new(x, top + 1.2, layout.StationZ), CFrame.new(x, top + 0.15, layout.StationZ)
			local basket = propPart(scene, Enum.PartType.Block, Vector3.new(1.7, 0.8, 1.0), up, Color3.fromRGB(150, 155, 160), Enum.Material.Metal, 0.35)
			local fries = propPart(scene, Enum.PartType.Block, Vector3.new(1.4, 0.5, 0.8), up, Color3.fromRGB(252, 225, 130))
			tween(basket, 0.4, { CFrame = down })
			tween(fries, 0.4, { CFrame = down })
			tween(fries, seconds, { Color = Color3.fromRGB(240, 180, 60) }, Enum.EasingStyle.Linear)
			task.wait(math.max(seconds - 0.8, 0.2))
			tween(basket, 0.4, { CFrame = up })
			tween(fries, 0.4, { CFrame = up })
			task.wait(0.4)
			basket:Destroy()
			fries:Destroy()
		end,
		Oven = function(x, seconds) -- a pizza slides into the oven and back out
			local level = layout.StationTopY.Oven - 0.4
			local outside, inside = CFrame.new(x, level, layout.StationZ + 1.7), CFrame.new(x, level, layout.StationZ + 0.1)
			local lift = CFrame.new(0, 0.09, 0)
			local crust = propPart(scene, Enum.PartType.Cylinder, Vector3.new(0.12, 1.2, 1.2), outside * UPRIGHT, BUN)
			local topping = propPart(scene, Enum.PartType.Cylinder, Vector3.new(0.06, 1.0, 1.0), outside * lift * UPRIGHT, Color3.fromRGB(246, 225, 150))
			tween(crust, 0.5, { CFrame = inside * UPRIGHT })
			tween(topping, 0.5, { CFrame = inside * lift * UPRIGHT })
			tween(topping, seconds, { Color = Color3.fromRGB(246, 190, 80) }, Enum.EasingStyle.Linear)
			task.wait(math.max(seconds - 1, 0.2))
			tween(crust, 0.5, { CFrame = outside * UPRIGHT })
			tween(topping, 0.5, { CFrame = outside * lift * UPRIGHT })
			task.wait(0.5)
			crust:Destroy()
			topping:Destroy()
		end,
		Drinks = function(x, seconds) -- a cup fills up under the tap
			local base = CFrame.new(x, layout.StationTopY.Drinks - 0.2, layout.StationZ + 0.9)
			local cup = propPart(scene, Enum.PartType.Cylinder, Vector3.new(0.9, 0.6, 0.6), base * UPRIGHT, WHITE, nil, 0.5)
			local cola = propPart(scene, Enum.PartType.Cylinder, Vector3.new(0.05, 0.5, 0.5), (base + Vector3.new(0, -0.4, 0)) * UPRIGHT, Color3.fromRGB(70, 35, 20))
			tween(cola, math.max(seconds - 0.2, 0.2), { Size = Vector3.new(0.8, 0.5, 0.5), CFrame = (base + Vector3.new(0, -0.02, 0)) * UPRIGHT }, Enum.EasingStyle.Linear)
			task.wait(seconds)
			cup:Destroy()
			cola:Destroy()
		end,
		Freezer = function(x, seconds) -- the lid slides open and a cone comes out
			local lid = scene.Stations.Freezer:FindFirstChild("Lid")
			local closed = lid and lid.CFrame
			if lid then
				tween(lid, 0.35, { CFrame = closed + Vector3.new(2.2, 0, 0) })
			end
			local cone = propPart(scene, Enum.PartType.Cylinder, Vector3.new(0.6, 0.36, 0.36), CFrame.new(x, layout.StationTopY.Freezer - 0.4, layout.StationZ) * UPRIGHT, Color3.fromRGB(212, 165, 105))
			local scoop = propPart(scene, Enum.PartType.Ball, Vector3.new(0.6, 0.6, 0.6), CFrame.new(x, layout.StationTopY.Freezer + 0.1, layout.StationZ), Color3.fromRGB(255, 246, 230))
			task.wait(0.35)
			tween(cone, 0.5, { CFrame = CFrame.new(x, layout.StationTopY.Freezer + 0.9, layout.StationZ) * UPRIGHT })
			tween(scoop, 0.5, { CFrame = CFrame.new(x, layout.StationTopY.Freezer + 1.4, layout.StationZ) })
			task.wait(math.max(seconds - 0.9, 0.2))
			if lid then
				tween(lid, 0.35, { CFrame = closed })
			end
			task.wait(0.2)
			cone:Destroy()
			scoop:Destroy()
		end,
	}

	------------------------------------------------------------------
	-- Chat: Roblox's built-in bubbles above heads, plus the chat window
	------------------------------------------------------------------

	local function chatWindowLine(line)
		pcall(function()
			local channels = TextChatService:FindFirstChild("TextChannels")
			local general = channels and channels:FindFirstChild("RBXGeneral")
			if general then
				general:DisplaySystemMessage(line)
			end
		end)
	end

	local function chatBubble(part, line)
		local ok, err = pcall(function()
			TextChatService:DisplayBubble(part, line)
		end)
		if not ok then
			debugLog("bubble failed: " .. tostring(err))
		end
	end

	-- Small name / status pill beside a head or under Lumi. It sits to the side
	-- so it never covers the chat bubble above.
	local function statusPill(adornee, offset, label)
		local gui = create("BillboardGui", {
			Name = "Status", Adornee = adornee, Size = UDim2.fromScale(5.4, 0.9), StudsOffset = offset, LightInfluence = 0, MaxDistance = 60,
		}, adornee)
		local pill = create("TextLabel", {
			Text = label, Font = Enum.Font.GothamMedium, TextColor3 = WHITE, TextScaled = true, BackgroundColor3 = Color3.fromRGB(40, 44, 60),
			BackgroundTransparency = 0.15, BorderSizePixel = 0, Size = UDim2.fromScale(1, 1),
		}, gui)
		create("UICorner", { CornerRadius = UDim.new(0.4, 0) }, pill)
		create("UIPadding", {
			PaddingTop = UDim.new(0.14, 0), PaddingBottom = UDim.new(0.14, 0), PaddingLeft = UDim.new(0.04, 0), PaddingRight = UDim.new(0.04, 0),
		}, pill)
		return pill
	end

	------------------------------------------------------------------
	-- Voice: one microphone for the player, and a voice box for every character
	------------------------------------------------------------------

	local function wireUp(source, target)
		return create("Wire", { SourceInstance = source, TargetInstance = target }, target)
	end

	local micInput = create("AudioDeviceInput", { Name = "LingoMic", Player = player }, player)
	local speechToText = create("AudioSpeechToText", { Name = "LingoSTT", Enabled = false }, player)
	wireUp(micInput, speechToText)

	local MAX_TTS_CHARACTERS = 300

	-- Gives one character its own text-to-speech voice box, so characters never
	-- wait for each other to finish talking. Returns two functions:
	--   speak(line, voiceId, pitch) yields until the line has been said (or cut off).
	--     With no voiceId (Roblox has no voice for that language) it just waits
	--     long enough for the bubble to be read.
	--   stop() cuts the voice off mid-line.
	local function newVoice(parent, name)
		local textToSpeech = create("AudioTextToSpeech", { Name = name .. "Voice", AutoLocalize = false }, parent)
		local deviceOutput = create("AudioDeviceOutput", { Name = name .. "VoiceOutput" }, parent)
		wireUp(textToSpeech, deviceOutput)
		local stopRequested = false

		local function waitUnlessStopped(seconds)
			local deadline = os.clock() + seconds
			while not stopRequested and os.clock() < deadline do
				task.wait(0.1)
			end
		end

		local function speak(line, voiceId, pitch)
			stopRequested = false
			local length = utf8.len(line) or #line
			if not voiceId then
				waitUnlessStopped(math.clamp(length / 12, 2.5, 8))
				return
			end
			if length > MAX_TTS_CHARACTERS then
				line = string.sub(line, 1, utf8.offset(line, MAX_TTS_CHARACTERS + 1) - 1)
			end
			textToSpeech.VoiceId = voiceId
			textToSpeech.Pitch = pitch or 0
			textToSpeech.Text = line
			textToSpeech.TimePosition = 0
			local ok, status = pcall(function()
				return textToSpeech:LoadAsync()
			end)
			if stopRequested then
				return -- cut off before it even started
			end
			if ok and status == Enum.AssetFetchStatus.Success then
				local ended = false
				local connection = textToSpeech.Ended:Once(function()
					ended = true
				end)
				textToSpeech:Play()
				local deadline = os.clock() + textToSpeech.TimeLength + 2
				while not ended and not stopRequested and os.clock() < deadline do
					task.wait(0.05)
				end
				connection:Disconnect()
				if stopRequested then
					textToSpeech:Pause()
				end
			else
				debugLog(name .. " TTS FAILED: " .. tostring(status))
				waitUnlessStopped(math.clamp(length / 12, 2.5, 8))
			end
		end

		local function stop()
			stopRequested = true
			pcall(function()
				textToSpeech:Pause()
			end)
		end

		return speak, stop
	end

	-- The microphone is always open, so it can pick up a character's own voice
	-- from the speakers. Everything characters say is remembered for a moment so
	-- that an echo of it is not mistaken for the player talking.
	local ECHO_WINDOW = 1.5 -- seconds after a line ends in which a matching transcript counts as an echo
	local spokenLines = {}

	local function normalizeSpeech(line)
		line = string.lower(line)
		line = string.gsub(line, "[%p%c]", " ")
		line = string.gsub(line, "%s+", " ")
		return (string.gsub(line, "^%s*(.-)%s*$", "%1"))
	end

	local function rememberSpoken(line)
		local now = os.clock()
		for index = #spokenLines, 1, -1 do
			if spokenLines[index].endsAt + 10 < now then
				table.remove(spokenLines, index)
			end
		end
		local normal = normalizeSpeech(line)
		local words = {}
		for word in string.gmatch(normal, "%S+") do
			words[word] = true
		end
		local record = { text = normal, words = words, endsAt = math.huge } -- endsAt is set when the line finishes
		table.insert(spokenLines, record)
		return record
	end

	local function looksLikeEcho(heard)
		local normal = normalizeSpeech(heard)
		if normal == "" then
			return false
		end
		local heardWords = {}
		for word in string.gmatch(normal, "%S+") do
			table.insert(heardWords, word)
		end
		local now = os.clock()
		for _, record in spokenLines do
			if now <= record.endsAt + ECHO_WINDOW then
				local matches = 0
				for _, word in heardWords do
					if record.words[word] then
						matches += 1
					end
				end
				if matches / #heardWords >= 0.7 then
					return true
				end
				-- languages written without spaces: compare the text as a whole
				if #heardWords == 1 and #normal >= 6 and string.find(record.text, normal, 1, true) then
					return true
				end
			end
		end
		return false
	end

	-- Gives a character its voice. partner.speak says a line; partner.interrupt()
	-- cuts them off and keeps them quiet for the rest of that turn.
	local function giveVoice(partner)
		local rawSpeak, stop = newVoice(partner.part, partner.id)
		partner.interrupted = false
		partner.speaking = false
		partner.speak = function(line, voiceId, pitch)
			if partner.interrupted then
				return -- the player cut in: nothing more from them this turn
			end
			local record = rememberSpoken(line)
			partner.speaking = true
			rawSpeak(line, voiceId, pitch)
			partner.speaking = false
			record.endsAt = os.clock()
		end
		partner.interrupt = function()
			partner.interrupted = true
			stop()
		end
	end

	------------------------------------------------------------------
	-- Conversation: the character the player is standing near AND looking at is
	-- the one who hears them. Look away and nobody is listening.
	------------------------------------------------------------------

	-- Every character is its own object with its own state: `busy` (thinking or
	-- talking), `queue` (things waiting to be said) and `speak` (its voice box).
	-- Nothing here is shared between characters.
	local activePartner = nil -- the character currently listening to the player
	local cooking = false
	local cookingItems = nil -- the order the cook is making right now
	local trayOnCounter = nil -- tray waiting to be picked up
	local trayTakeable = false
	local partnerById = {}
	local showTranslations = false -- switched on or off by asking Lumi

	-- A line as it is shown: on its own, or with its translation underneath when
	-- translations are on. Only the line itself is ever spoken.
	local function captioned(line, translation)
		if showTranslations and translation and translation ~= "" then
			return line .. "\n(" .. translation .. ")"
		end
		return line
	end
	local playerSeat = nil -- { table = Vector3, side = 1 or -1 } while the player sits at a table
	local customerSeated = false -- the regular customer is sitting with the player
	local partners = {}

	local cashierPartner, cookPartner, cleanerPartner, customerPartner, tutorPartner
	local playExchange, queueRun -- defined below
	local cookOrder -- defined below
	local runQueue

	local function playerRoot()
		local character = player.Character
		return character and character:FindFirstChild("HumanoidRootPart")
	end

	local function flatDistance(a, b)
		return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
	end

	local LOOK_ANGLE = math.rad(35) -- looking at someone = they are within this angle of the centre of the view
	local LOOK_KEEP_ANGLE = math.rad(50) -- a little slack for whoever is already listening
	local EYE_CONTACT_RANGE = 40 -- further than this, nobody notices being looked at

	-- Angle between where the player is looking and the direction to a point
	local function lookAngleTo(position)
		local camera = workspace.CurrentCamera
		if not camera then
			return 0
		end
		local view = camera:GetRenderCFrame() -- in VR this follows the headset
		local toTarget = position - view.Position
		if toTarget.Magnitude < 0.01 then
			return 0
		end
		return math.acos(math.clamp(view.LookVector:Dot(toTarget.Unit), -1, 1))
	end

	------------------------------------------------------------------
	-- Commands: things the player can ask a character to do. The AI decides
	-- whether the character agrees (LingoServer returns an `action` with each
	-- line); this is where the body carries it out.
	--   follow / come / go_away take over the character's walking until they
	--   end, so they run inside that character's own routine (runCommand).
	--   dance / wave / point are gestures and start straight away.
	------------------------------------------------------------------

	local FOLLOW_GAP = 4.5 -- studs a follower keeps between itself and the player
	local FOLLOW_SPEED = 13 -- a little slower than the player, so it trails behind
	local FOLLOW_SECONDS = 90 -- a follower goes back to work after this long
	local AWAY_SECONDS = 25 -- how long someone told to go away keeps to themselves
	local DANCE_SECONDS = 6

	-- Where each place the characters can point at is
	local POINT_TARGETS = {
		counter = layout.CounterFront + Vector3.new(0, 3, 0),
		menu = scene.MenuBoard:GetPivot().Position,
		pickup = layout.Pickup,
		kitchen = Vector3.new(0, 4, layout.StationZ),
		door = Vector3.new(0, 4, DOOR_Z),
		tables = layout.CustomerSpots[2] + Vector3.new(0, 3, 0),
		guide = layout.TutorSpot,
	}

	-- True while the character has something it cannot walk away from (set per character below)
	local function mustWork(npc)
		return npc.mustWork ~= nil and npc.mustWork() == true
	end

	-- Walks after the player, stopping a few steps short, until the command ends.
	-- "come" is the same walk but finishes as soon as the character arrives.
	local function followPlayer(npc, command)
		local walking = false
		local function setWalking(on)
			if walking == on then
				return
			end
			walking = on
			npc.moving = on
			if npc.walk and npc.idle then
				if on then
					npc.idle:Stop(0.2)
					npc.walk:Play(0.2)
				else
					npc.walk:Stop(0.2)
					npc.idle:Play(0.2)
				end
			end
		end

		local started = os.clock()
		while npc.command == command and not mustWork(npc) and os.clock() - started < FOLLOW_SECONDS do
			local dt = RunService.Heartbeat:Wait()
			local root = playerRoot()
			if not root then
				break
			end
			local position = npc.root.Position
			local toPlayer = Vector3.new(root.Position.X - position.X, 0, root.Position.Z - position.Z)
			local distance = toPlayer.Magnitude
			-- starts walking once the player is a bit further off, so it does not shuffle on the spot
			if distance > (walking and FOLLOW_GAP or FOLLOW_GAP + 1.5) then
				setWalking(true)
				local direction = toPlayer.Unit
				local step = math.min(FOLLOW_SPEED * dt, distance - FOLLOW_GAP)
				local facing = npc.root.CFrame.Rotation:Lerp(CFrame.lookAt(Vector3.zero, direction), 1 - math.exp(-dt * 10))
				npc.root.CFrame = facing.Rotation + (Vector3.new(position.X, npc.y, position.Z) + direction * step)
			else
				setWalking(false)
				if command.kind == "come" then
					break
				end
			end
		end
		setWalking(false)
		npc.restLook = npc.root.CFrame.LookVector
	end

	-- Walks to whichever of the character's quiet spots is furthest from the player,
	-- turns its back, and stays there for a while.
	local function goAway(npc, command)
		local root = playerRoot()
		local best, bestDistance
		for _, spot in npc.retreats or {} do
			local distance = root and flatDistance(root.Position, spot) or 0
			if not bestDistance or distance > bestDistance then
				best, bestDistance = spot, distance
			end
		end
		npc.ignorePlayer = true
		if best then
			walkTo(npc, best.X, best.Z)
		end
		root = playerRoot()
		if root then
			local position = npc.root.Position
			local away = Vector3.new(position.X - root.Position.X, 0, position.Z - root.Position.Z)
			if away.Magnitude > 0.5 then
				faceDirection(npc, away.Unit)
			end
		end
		local started = os.clock()
		while npc.command == command and not mustWork(npc) and os.clock() - started < AWAY_SECONDS do
			task.wait(0.25)
		end
		npc.ignorePlayer = false
	end

	-- Called from a character's own routine whenever it has a command. Yields until the command is over.
	local function runCommand(npc)
		local command = npc.command
		if not command then
			return
		end
		local ok, err = pcall(function()
			if command.kind == "away" then
				goAway(npc, command)
			else
				followPlayer(npc, command)
			end
		end)
		if not ok then
			debugLog("command FAILED: " .. tostring(err))
			npc.moving = false
			npc.ignorePlayer = false
		end
		if npc.command == command then
			npc.command = nil
		end
	end

	-- A gesture the player asked for, held for a few seconds
	local function timedGesture(npc, gesture, seconds, lookAtPoint)
		local token = {}
		npc.actionToken = token
		npc.actionGesture = gesture
		npc.lookAtPoint = lookAtPoint
		task.delay(seconds, function()
			if npc.actionToken == token then
				npc.actionGesture = nil
				npc.lookAtPoint = nil
			end
		end)
	end

	-- Carries out the `action` that came back with a character's line
	local function performAction(partner, action, pointAt)
		local npc = partner.npc
		if not npc then
			return
		end
		if action == nil or action == "none" then
			-- being spoken to again ends the sulk after "go away"
			if npc.command and npc.command.kind == "away" then
				npc.command = nil
			end
			return
		end
		debugLog(partner.name .. " action: " .. action .. (action == "point" and (" at " .. tostring(pointAt)) or ""))

		if action == "follow" or action == "come" or action == "go_away" then
			if mustWork(npc) then
				debugLog(partner.name .. " is busy and stays put")
				return
			end
			npc.command = { kind = action == "go_away" and "away" or action }
		elseif action == "stop" then
			npc.command = nil
		elseif action == "dance" then
			if npc.dance then
				local token = {}
				npc.danceToken = token
				npc.dance:Play(0.3)
				task.delay(DANCE_SECONDS, function()
					if npc.danceToken == token then
						npc.dance:Stop(0.4)
					end
				end)
			end
		elseif action == "wave" then
			timedGesture(npc, "wave", 2.5)
		elseif action == "point" then
			timedGesture(npc, "point", 3.5, POINT_TARGETS[pointAt])
		end
	end

	local function canListen(partner)
		return partner ~= nil and (not partner.autoGreet or partner.started)
	end

	-- Engaged = the player is looking at them, they are in the middle of talking,
	-- or either of those was true in the last few seconds. Someone who is engaged
	-- stays where they are instead of wandering back to their routine.
	local LINGER_SECONDS = 8
	local function engaged(partner)
		return partner == activePartner or partner.busy
			or os.clock() - (partner.lastEngaged or -math.huge) < LINGER_SECONDS
	end

	local function updateStatus()
		for _, partner in partners do
			local isActive = partner == activePartner
			local label = partner.name
			if isActive and partner.busy then
				label = text("thinking")
			elseif partner == cashierPartner and trayTakeable then
				label = text("take")
			elseif partner == cashierPartner and cooking then
				label = text("cooking")
			elseif isActive and canListen(partner) then
				label = text("listening")
			end
			partner.pill.Text = label
			partner.pill.BackgroundColor3 = (isActive and not partner.busy and canListen(partner))
				and Color3.fromRGB(40, 150, 80) or Color3.fromRGB(40, 44, 60)
		end

		-- the microphone is always open: the player can speak at any moment, including
		-- over someone who is talking (which interrupts them)
		if not speechToText.Enabled then
			speechToText.Enabled = true
		end
	end

	-- Runs the next thing waiting in one character's queue, if that character is free
	function runQueue(partner)
		if partner.busy or #partner.queue == 0 then
			return
		end
		local job = table.remove(partner.queue, 1)
		job()
	end

	-- Asks the server for a character's next line, then lets that character present it.
	-- If that character is already thinking or talking, the request waits in its own
	-- queue; no other character is held up.
	local function request(partner, kind, payload, afterSpeaking, context)
		if partner.busy then
			-- what the player just said goes to the front of their queue; other things wait their turn
			table.insert(partner.queue, kind == "say" and 1 or #partner.queue + 1, function()
				request(partner, kind, payload, afterSpeaking, context)
			end)
			return
		end
		partner.busy = true
		partner.interrupted = false
		partner.addressingPlayer = true
		updateStatus()
		if partner.npc then
			partner.npc.talkGesture = partner.thinkGesture
		end

		local started = os.clock()
		local ok, result = pcall(function()
			return npcGenerate:InvokeServer(partner.id, kind, payload, context)
		end)

		if ok and type(result) == "table" and result.ok then
			debugLog(string.format("%s ok (%.1fs): %s", partner.name, os.clock() - started, result.say))
			partner.present(result, kind)
			if afterSpeaking then
				afterSpeaking()
			end
		else
			local message = ok and type(result) == "table" and result.err or result
			debugLog(partner.name .. " FAILED: " .. tostring(message))
			task.wait(1)
		end

		if partner.npc then
			partner.npc.talkGesture = nil
		end
		partner.addressingPlayer = false
		partner.busy = false
		updateStatus()
		task.delay(0.3, runQueue, partner)
	end

	-- Things that happen in the restaurant which the cashier should react to.
	-- They go through the cashier's own queue, so they wait only for her.
	local function queueEvent(kind, payload, afterSpeaking)
		request(cashierPartner, kind, payload, afterSpeaking)
	end

	-- A member of staff says a line: bubble, chat window, gesture, voice.
	-- Only the practice language is shown; there is no translation.
	local function presentStaffLine(partner, result, kind)
		performAction(partner, result.action, result.pointAt)
		chatBubble(partner.part, captioned(result.say, result.translation))
		chatWindowLine(partner.name .. ": " .. (string.gsub(captioned(result.say, result.translation), "\n", "  ")))
		local npc = partner.npc
		npc.talkGesture = kind == "start" and "wave" or "talk"
		if kind == "start" then
			task.delay(1.6, function()
				if npc.talkGesture == "wave" then
					npc.talkGesture = "talk"
				end
			end)
		end
		partner.speak(result.say, partner.voice, partner.pitch)
	end

	local function addStaffPartner(id, name, npc, range, voice, pitch)
		local head = npc.rig:WaitForChild("Head")
		local partner = {
			id = id, name = name, npc = npc, part = head, range = range, voice = voice, pitch = pitch,
			busy = false, queue = {},
			pill = statusPill(head, Vector3.new(-4.2, 0.2, 0), name),
			-- only reachable from inside the building
			distance = function(root)
				-- (someone following the player can still be talked to outside, e.g. to tell them to stop)
				if root.Position.Z > layout.DoorZ - 0.7 and not npc.command then
					return nil
				end
				return flatDistance(root.Position, npc.root.Position)
			end,
		}
		partner.present = function(result, kind)
			presentStaffLine(partner, result, kind)
		end
		giveVoice(partner)
		partner.pill.Parent.Enabled = false -- no floating name tags on people
		table.insert(partners, partner)
		partnerById[id] = partner
		return partner
	end

	-- Cashier: greets you at the counter and takes the order
	cashierPartner = addStaffPartner("cashier", fastFood.CashierName, cashier, 12, learnLanguage.voice, 0)
	cashierPartner.autoGreet = true
	cashierPartner.thinkGesture = "type"
	cashierPartner.present = function(result, kind)
		if result.orderComplete and not cooking and not trayOnCounter then
			ringRegister()
			task.spawn(cookOrder, result.items)
			-- once the customer has been answered, the cashier calls the order through to the cook
			queueRun(function()
				playExchange("order_called", result.items)
			end)
		end
		presentStaffLine(cashierPartner, result, kind)
	end

	-- Cook and cleaner: answer when you walk up and speak to them
	cookPartner = addStaffPartner("cook", fastFood.CookName, cook, 9, learnLanguage.voiceMale or learnLanguage.voice, 0)
	cleanerPartner = addStaffPartner("cleaner", fastFood.CleanerName, cleaner, 8, learnLanguage.voice, 2.5)
	customerPartner = addStaffPartner("customer", fastFood.CustomerName, customer, 8, learnLanguage.voiceMale or learnLanguage.voice, 3)

	-- What each of them cannot walk away from, whatever the player asks
	cashier.mustWork = function()
		return cooking or trayOnCounter ~= nil -- an order is being made or is waiting on the counter
	end
	cook.mustWork = function()
		return cooking
	end
	customer.mustWork = function()
		return playerSeat ~= nil or customerSeated
	end

	-- Where each of them goes when told to go away (the one furthest from the player is used)
	cashier.retreats = layout.CashierRetreats
	cook.retreats = { Vector3.new(layout.StationX.Grill, 0, layout.KitchenLaneZ), Vector3.new(layout.StationX.Freezer, 0, layout.KitchenLaneZ) }
	cleaner.retreats = layout.CleanerPath
	customer.retreats = layout.CustomerSpots

	-- The cashier has no routine of her own: she leaves the register only when
	-- asked to, and walks back to it afterwards.
	task.spawn(function()
		local home = cashier.root.Position
		local facing = cashier.restLook
		while scene.Parent do
			if cashier.command then
				runCommand(cashier)
				walkTo(cashier, home.X, home.Z)
				faceDirection(cashier, facing)
			else
				task.wait(0.3)
			end
		end
	end)

	-- Something the player said, either out loud or typed into the chat box
	local function playerSaid(heard, typed)
		-- Who is being spoken to: whoever the player is looking at, or failing that
		-- whoever is in the middle of saying something to them.
		local partner = activePartner
		if not canListen(partner) then
			partner = nil
			for _, other in partners do
				if other.speaking and other.addressingPlayer and canListen(other) then
					partner = other
					break
				end
			end
		end
		if not partner then
			debugLog("HEARD (nobody was listening): " .. heard)
			return
		end
		if partner.busy then
			-- the player spoke over them: they stop mid-sentence and deal with what was said
			debugLog(partner.name .. " was interrupted")
			partner.interrupt()
		end
		debugLog("HEARD by " .. partner.name .. ": " .. heard)
		if not typed then
			-- a typed line is already in the chat window
			chatWindowLine(player.DisplayName .. ": " .. heard)
		end
		-- a little context for whoever is listening: what the cook is making,
		-- or that the regular customer is sitting at the table with the player
		local context = nil
		if partner == cookPartner then
			context = cookingItems
		elseif partner == customerPartner and customerSeated then
			context = "seated"
		end
		request(partner, "say", heard, nil, context)
	end

	speechToText:GetPropertyChangedSignal("Text"):Connect(function()
		local heard = speechToText.Text
		if heard == "" then
			return
		end
		speechToText.Text = ""
		if looksLikeEcho(heard) then
			debugLog("HEARD (ignored, a character's own voice): " .. heard)
			return
		end
		playerSaid(heard, false)
	end)

	-- Typing works too: a message sent from the chat box counts as speech
	TextChatService.SendingMessage:Connect(function(message)
		local typedText = string.match(message.Text, "^%s*(.-)%s*$")
		if typedText == "" or string.sub(typedText, 1, 1) == "/" then
			return
		end
		playerSaid(typedText, true)
	end)

	------------------------------------------------------------------
	-- Food: the cook brings a tray to the counter. The tray stays there; the
	-- player takes the items off it, holds them in their hands, and eats them
	-- by bringing them up to their mouth.
	------------------------------------------------------------------

	local carriedByCook = nil
	local fullness = 0 -- 0 = empty stomach, 1 = full; drops slowly as the food is digested
	local DIGEST_SECONDS = 80 -- how long a completely full stomach takes to digest
	local STOMACH_COLOR = Color3.fromRGB(120, 200, 90)

	-- Stomach bar: shows while there is food to digest
	local hud = create("ScreenGui", { Name = "LingoHud", ResetOnSpawn = false, DisplayOrder = 40 }, playerGui)
	local stomach = create("Frame", {
		AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -18), Size = UDim2.new(0, 240, 0, 26),
		BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.45, BorderSizePixel = 0, Visible = false,
	}, hud)
	create("UICorner", { CornerRadius = UDim.new(0.5, 0) }, stomach)
	create("TextLabel", { Text = "\u{1F37D}", BackgroundTransparency = 1, TextScaled = true, Position = UDim2.new(0, 4, 0, 0), Size = UDim2.new(0, 26, 1, 0) }, stomach)
	local stomachTrack = create("Frame", {
		Position = UDim2.new(0, 36, 0.25, 0), Size = UDim2.new(1, -48, 0.5, 0), BackgroundColor3 = Color3.fromRGB(60, 60, 70), BorderSizePixel = 0,
	}, stomach)
	create("UICorner", { CornerRadius = UDim.new(0.5, 0) }, stomachTrack)
	local stomachFill = create("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = STOMACH_COLOR, BorderSizePixel = 0 }, stomachTrack)
	create("UICorner", { CornerRadius = UDim.new(0.5, 0) }, stomachFill)

	RunService.RenderStepped:Connect(function()
		if carriedByCook then
			carriedByCook.model:PivotTo(cook.root.CFrame * CFrame.new(0, 0.35, -1.75))
		end
	end)

	-- Digesting: the stomach empties slowly over time
	RunService.Heartbeat:Connect(function(dt)
		if fullness > 0 then
			fullness = math.max(0, fullness - dt / DIGEST_SECONDS)
		end
		stomach.Visible = fullness > 0.005
		stomachFill.Size = UDim2.fromScale(fullness, 1)
	end)

	-- The food is gear. LingoFood equips it in the player's hand and handles the eating
	-- (click, or in VR bring it to the mouth); every bite fills the stomach.
	local lastFullNotice = 0
	LingoFood.start({
		burst = burst, debugLog = debugLog,
		canBite = function()
			if fullness < 1 then
				return true
			end
			-- too full: wait for some of it to be digested
			local now = os.clock()
			if now - lastFullNotice > 2 then
				lastFullNotice = now
				debugLog("too full to eat: digesting")
				tween(stomachFill, 0.15, { BackgroundColor3 = Color3.fromRGB(230, 80, 70) })
				task.delay(0.5, function()
					tween(stomachFill, 0.3, { BackgroundColor3 = STOMACH_COLOR })
				end)
			end
			return false
		end,
		onBite = function(record)
			fullness = math.min(1, fullness + record.fill)
		end,
	})

	-- An item has left the tray for the player's hand
	local function foodTaken(tray, entry)
		local index = table.find(tray.items, entry)
		if index then
			table.remove(tray.items, index)
		end
		if not tray.announced then
			tray.announced = true
			queueEvent("tray_taken")
		end
		if #tray.items == 0 then
			-- the empty tray is cleared away
			trayOnCounter = nil
			trayTakeable = false
			if tray.highlight then
				tray.highlight:Destroy()
			end
			tween(tray.base, 0.6, { Transparency = 1 })
			Debris:AddItem(tray.model, 0.8)
		end
		updateStatus()
	end

	-- Called once the cashier has said the order is ready
	local function makeTrayTakeable(tray)
		trayTakeable = true
		tray.highlight = create("Highlight", {
			FillColor = Color3.fromRGB(255, 225, 90), FillTransparency = 0.55, OutlineColor = Color3.fromRGB(255, 240, 160),
			DepthMode = Enum.HighlightDepthMode.Occluded,
		}, tray.model)
		TweenService:Create(tray.highlight, TweenInfo.new(0.7, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { FillTransparency = 0.9 }):Play()
		for _, entry in tray.items do
			LingoFood.setTakeable(entry.record, true)
		end
		updateStatus()
	end

	------------------------------------------------------------------
	-- Cook: potters around the kitchen, and makes orders
	------------------------------------------------------------------

	local cookMoving = false
	local stationNames = { "Grill", "Fryer", "Oven", "Drinks", "Freezer" }

	local function cookGoToStation(name)
		walkTo(cook, layout.StationX[name], layout.KitchenLaneZ)
		faceDirection(cook, Vector3.new(0, 0, -1))
	end

	function cookOrder(items)
		cooking = true
		cookingItems = items
		updateStatus()
		while cookMoving do
			task.wait(0.1) -- let him finish the step he is on
		end
		cookMoving = true

		local tray = newTray(scene, cook.root.CFrame * CFrame.new(0, 0.35, -1.75))
		carriedByCook = tray
		cook.workGesture = "carry"
		local made = {}

		for _, entry in items do
			local item = fastFood.MenuById[entry.id]
			if item then
				for _ = 1, entry.quantity do
					if tray.count >= #TRAY_SLOTS then
						break
					end
					cookGoToStation(item.station)
					cook.workGesture = "cook"
					setStationActive(item.station, true)
					local show = STATION_SHOW[item.station]
					local ok = show and pcall(show, layout.StationX[item.station], item.seconds)
					if not ok then
						task.wait(item.seconds)
					end
					setStationActive(item.station, false)
					cook.workGesture = "carry"
					local trayEntry = addFoodToTray(tray, item.id, {
						name = fastFood.ItemName(learnLanguage.code, item.id), bites = item.bites, fill = item.fill,
					})
					if trayEntry then
						trayEntry.record.onTaken = function()
							foodTaken(tray, trayEntry)
						end
					end
					playSound("Click")
				end
				table.insert(made, { id = entry.id, quantity = entry.quantity })
			end
		end

		-- carry the tray to the pickup spot on the counter
		walkTo(cook, layout.CookPickupStand.X, layout.KitchenLaneZ)
		walkTo(cook, layout.CookPickupStand.X, layout.CookPickupStand.Z)
		faceDirection(cook, Vector3.new(0, 0, 1))
		carriedByCook = nil
		cook.workGesture = "idle"
		tray.model:PivotTo(CFrame.new(layout.Pickup))
		trayOnCounter = tray
		ringBell()
		burst(layout.Pickup + Vector3.new(0, 0.8, 0), "Sparkles", 40)
		debugLog("order on the counter")

		cooking = false
		cookingItems = nil
		updateStatus()
		queueEvent("food_ready", made, function()
			if trayOnCounter == tray then
				makeTrayTakeable(tray)
			end
		end)

		-- back to the kitchen
		task.wait(1)
		walkTo(cook, layout.CookPickupStand.X, layout.KitchenLaneZ)
		cookMoving = false
	end

	task.spawn(function()
		while scene.Parent do
			task.wait(math.random(20, 45) / 10)
			if not cooking and not cookMoving then
				cookMoving = true
				local root = playerRoot()
				if cook.command then
					-- doing something the player asked for (follow, come, go away)
					cook.workGesture = "idle"
					runCommand(cook)
				elseif engaged(cookPartner) and root then
					-- someone is (or was just) talking to him: stay put; his head turns to them
					task.wait(0.2)
				else
					cookGoToStation(stationNames[math.random(#stationNames)])
					cook.workGesture = "cook" -- tidy the station for a moment
					task.wait(math.random(10, 20) / 10)
					cook.workGesture = "idle"
				end
				cookMoving = false
			end
		end
	end)

	------------------------------------------------------------------
	-- Cleaner: mops her way around the dining area
	------------------------------------------------------------------

	local mopHandle = propPart(scene, Enum.PartType.Block, Vector3.new(0.18, 4.6, 0.18), cleaner.root.CFrame, Color3.fromRGB(150, 105, 65), Enum.Material.Wood)
	local mopHead = propPart(scene, Enum.PartType.Block, Vector3.new(1.5, 0.25, 0.5), cleaner.root.CFrame, Color3.fromRGB(235, 235, 240), Enum.Material.Fabric)

	task.spawn(function()
		local index = 1
		while scene.Parent do
			local root = playerRoot()
			if cleaner.command then
				-- doing something the player asked for (follow, come, go away)
				cleaner.workGesture = "idle"
				runCommand(cleaner)
			elseif engaged(cleanerPartner) and root then
				-- someone is (or was just) talking to her: stop mopping and stay; her head turns to them
				cleaner.workGesture = "idle"
				task.wait(0.4)
			else
				local point = layout.CleanerPath[index]
				index = index % #layout.CleanerPath + 1
				walkTo(cleaner, point.X, point.Z)
				cleaner.workGesture = "sweep"
				local mopUntil = os.clock() + math.random(25, 50) / 10
				while os.clock() < mopUntil and not engaged(cleanerPartner) and not cleaner.command do
					task.wait(0.2)
				end
				cleaner.workGesture = "idle"
			end
		end
	end)

	------------------------------------------------------------------
	-- Sitting down: every bench has a prompt. When the player sits, the regular
	-- customer comes over and sits across the table from them.
	------------------------------------------------------------------

	for _, tableModel in scene:GetChildren() do
		local top = tableModel.Name == "DiningTable" and tableModel:FindFirstChild("Top")
		if top then
			for _, bench in tableModel:GetChildren() do
				if bench.Name == "Bench" then
					local side = bench.Position.Z > top.Position.Z and 1 or -1
					local prompt = create("ProximityPrompt", {
						ActionText = text("sit"), ObjectText = "", HoldDuration = 0, MaxActivationDistance = 7, RequiresLineOfSight = false,
					}, bench)
					prompt.Triggered:Connect(function()
						local character = player.Character
						local humanoid = character and character:FindFirstChildOfClass("Humanoid")
						local root = character and character:FindFirstChild("HumanoidRootPart")
						if not humanoid or not root then
							return
						end
						-- drop onto the bench facing the table, then sit (jump to stand up again)
						local seatPosition = Vector3.new(bench.Position.X, layout.BenchTopY + 2.4, bench.Position.Z)
						root.CFrame = CFrame.lookAt(seatPosition, Vector3.new(top.Position.X, seatPosition.Y, top.Position.Z))
						humanoid.Sit = true
						playerSeat = { table = top.Position, side = side }
						debugLog("sat down at a table")
					end)
				end
			end
		end
	end

	local function customerSitWithPlayer(seat)
		local tablePosition = seat.table
		local benchZ = tablePosition.Z - seat.side * layout.BenchOffsetZ -- the bench across from the player
		local aisleX = (tablePosition.X > 0 and 1 or -1) * layout.AisleX
		-- along the front of the counter, down the side aisle, then in to the bench
		walkTo(customer, customer.root.Position.X, layout.FrontZ)
		walkTo(customer, aisleX, layout.FrontZ)
		walkTo(customer, aisleX, benchZ)
		if playerSeat ~= seat then
			return -- the player already got up
		end
		walkTo(customer, tablePosition.X, benchZ)
		-- seat height allows for the customer's avatar being taller or shorter than the original
		local seatedY = layout.SeatedRootY + (customer.y - standingRootY)
		local seatPosition = Vector3.new(tablePosition.X, seatedY, benchZ)
		customer.workGesture = "seated" -- not "idle", so his body stays put on the bench
		customer.root.CFrame = CFrame.lookAt(seatPosition, Vector3.new(tablePosition.X, seatedY, tablePosition.Z))
		if customer.idle then
			customer.idle:Stop(0.2)
		end
		if customer.sit then
			customer.sit:Play(0.2)
		end
		customerSeated = true
		debugLog(fastFood.CustomerName .. " sat down with the player")
		-- say something once settled, as soon as nobody else is talking
		task.spawn(function()
			while customerPartner.busy do
				task.wait(0.2)
			end
			if customerSeated then
				request(customerPartner, "sit")
			end
		end)
	end

	local function customerStandUp()
		customerSeated = false
		if customer.sit then
			customer.sit:Stop(0.2)
		end
		if customer.idle then
			customer.idle:Play(0.2)
		end
		local position = customer.root.Position
		customer.root.CFrame = customer.root.CFrame.Rotation + Vector3.new(position.X, customer.y, position.Z)
		customer.workGesture = "idle"
		local aisleX = (position.X > 0 and 1 or -1) * layout.AisleX
		walkTo(customer, aisleX, position.Z)
		walkTo(customer, aisleX, layout.FrontZ)
		walkTo(customer, -layout.AisleX, layout.FrontZ)
	end

	task.spawn(function()
		local spotIndex = 1
		while scene.Parent do
			local seat = playerSeat
			local root = playerRoot()
			if seat and not customerSeated then
				customer.command = nil -- sitting down together comes first
				customerSitWithPlayer(seat)
			elseif customerSeated and not playerSeat then
				task.wait(6) -- stays at the table a little while after the player gets up
				customerStandUp()
			elseif customerSeated then
				task.wait(0.5)
			elseif customer.command then
				-- doing something the player asked for (follow, come, go away)
				runCommand(customer)
			elseif engaged(customerPartner) and root then
				-- someone is (or was just) talking to him: stay; his head turns to them
				task.wait(0.4)
			else
				-- hang around: wander to the next spot and stand there for a while
				local spot = layout.CustomerSpots[spotIndex]
				spotIndex = spotIndex % #layout.CustomerSpots + 1
				walkTo(customer, spot.X, customer.root.Position.Z)
				walkTo(customer, spot.X, spot.Z)
				local waitUntil = os.clock() + math.random(60, 120) / 10
				while os.clock() < waitUntil and not playerSeat and not engaged(customerPartner) and not customer.command do
					task.wait(0.25)
				end
			end
		end
	end)

	------------------------------------------------------------------
	-- Staff talking to each other. This only ever happens because of something the
	-- player did: the cashier calls a confirmed order through to the cook. Nobody
	-- strikes up a conversation on their own.
	------------------------------------------------------------------

	-- Who takes part in each kind of exchange
	local EXCHANGE_SPEAKERS = {
		order_called = { "cashier", "cook" },
		staff_chat = { "cashier", "cook" },
		dining_chat = { "cleaner", "customer" },
	}

	local function exchangePartners(kind)
		local involved = {}
		for _, id in EXCHANGE_SPEAKERS[kind] or {} do
			if partnerById[id] then
				table.insert(involved, partnerById[id])
			end
		end
		return involved
	end

	local function anyBusy(list)
		for _, partner in list do
			if partner.busy then
				return true
			end
		end
		return false
	end

	-- Two characters talk to each other. Only those two are tied up while it
	-- happens; everyone else carries on and can still be talked to.
	function playExchange(kind, payload)
		local involved = exchangePartners(kind)
		local deadline = os.clock() + 8
		while anyBusy(involved) and os.clock() < deadline do
			task.wait(0.2) -- let either of them finish what they are saying first
		end
		if #involved < 2 or anyBusy(involved) then
			debugLog("exchange skipped: someone was still talking")
			return
		end
		for _, partner in involved do
			partner.busy = true
			partner.interrupted = false
		end
		updateStatus()

		local ok, result = pcall(function()
			return npcGenerate:InvokeServer("ambient", kind, payload)
		end)

		if ok and type(result) == "table" and result.ok then
			-- the two of them look at each other while they talk
			involved[1].npc.lookAtPart = involved[2].part
			involved[2].npc.lookAtPart = involved[1].part
			for _, line in result.lines do
				local partner = partnerById[line.speaker]
				if partner and table.find(involved, partner) then
					debugLog(partner.name .. " (overheard): " .. line.say)
					chatBubble(partner.part, captioned(line.say, line.translation))
					chatWindowLine(partner.name .. ": " .. (string.gsub(captioned(line.say, line.translation), "\n", "  ")))
					partner.npc.talkGesture = "talk"
					partner.speak(line.say, partner.voice, partner.pitch)
					partner.npc.talkGesture = nil
					task.wait(0.25)
				end
			end
			for _, partner in involved do
				partner.npc.lookAtPart = nil
			end
		else
			local message = ok and type(result) == "table" and result.err or result
			debugLog("exchange FAILED: " .. tostring(message))
		end

		for _, partner in involved do
			partner.busy = false
		end
		updateStatus()
		for _, partner in involved do
			task.delay(0.6, runQueue, partner)
		end
	end

	-- Adds a job to the cashier's own queue: something that follows one of her lines
	function queueRun(run)
		table.insert(cashierPartner.queue, run)
		runQueue(cashierPartner)
	end

	------------------------------------------------------------------
	-- Lumi: a friendly floating ball outside the building. Talk to it to learn
	-- words and phrases for the scenario. It speaks the player's own language
	-- and says each new phrase in the language being practised.
	------------------------------------------------------------------

	do
		local spot = layout.TutorSpot
		-- Where Lumi floats right now: the spot outside, or in front of the player after
		-- they call it with X. Tweened, so Lumi glides between the two.
		local anchor = Instance.new("Vector3Value")
		anchor.Value = spot
		local summoned = false
		local summonedAt = 0
		local lookedAwayFor = 0
		local SUMMON_DISTANCE = 5 -- studs in front of the player
		local SUMMON_SETTLE = 1.5 -- seconds Lumi gets to arrive before looking away counts
		local DISMISS_ANGLE = math.rad(60)
		local DISMISS_AFTER = 6 -- seconds of looking away before Lumi leaves (glancing around does not count)
		local ball = create("Part", {
			Name = Data.TutorName, Shape = Enum.PartType.Ball, Size = Vector3.new(2.6, 2.6, 2.6), Anchored = true,
			CanCollide = false, CanQuery = false, Material = Enum.Material.Neon, Color = Color3.fromRGB(120, 215, 255), Position = spot,
		}, scene)
		create("PointLight", { Color = Color3.fromRGB(150, 225, 255), Range = 16, Brightness = 1.3 }, ball)

		local twinkle = addEmitter(ball, "Sparkles", true)
		twinkle.Rate = 7
		twinkle.Speed = NumberRange.new(0.5, 1.6)
		twinkle.Lifetime = NumberRange.new(1, 1.8)
		twinkle.Color = ColorSequence.new(Color3.fromRGB(200, 240, 255))

		-- Face: two eyes and a smile, on a billboard just in front of the ball
		local face = create("BillboardGui", {
			Name = "Face", Adornee = ball, Size = UDim2.fromScale(2, 1.5), StudsOffset = Vector3.new(0, 0, 1.4), LightInfluence = 0, MaxDistance = 120,
		}, ball)
		local FACE_COLOR = Color3.fromRGB(20, 40, 70)
		local eyes = {}
		for _, x in { 0.3, 0.7 } do
			local eye = create("Frame", {
				AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(x, 0.38), Size = UDim2.fromScale(0.16, 0.26),
				BackgroundColor3 = FACE_COLOR, BorderSizePixel = 0,
			}, face)
			create("UICorner", { CornerRadius = UDim.new(1, 0) }, eye)
			local shine = create("Frame", {
				Position = UDim2.fromScale(0.55, 0.15), Size = UDim2.fromScale(0.3, 0.3), BackgroundColor3 = WHITE, BorderSizePixel = 0,
			}, eye)
			create("UICorner", { CornerRadius = UDim.new(1, 0) }, shine)
			table.insert(eyes, eye)
		end
		-- smile: the bottom half of a ring
		local smileClip = create("Frame", {
			AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0.62), Size = UDim2.fromScale(0.34, 0.2),
			BackgroundTransparency = 1, ClipsDescendants = true,
		}, face)
		local smileRing = create("Frame", {
			Position = UDim2.fromScale(0.06, -1.1), Size = UDim2.fromScale(0.88, 2), BackgroundTransparency = 1,
		}, smileClip)
		create("UICorner", { CornerRadius = UDim.new(1, 0) }, smileRing)
		create("UIStroke", { Color = FACE_COLOR, Thickness = 3 }, smileRing)

		local talking = false

		tutorPartner = {
			id = "tutor", name = Data.TutorName, part = ball, range = 13, autoGreet = true,
			busy = false, queue = {},
			pill = statusPill(ball, Vector3.new(0, -2.3, 0), Data.TutorName),
			-- Lumi only listens outside the building
			distance = function(root)
				if summoned then
					return flatDistance(root.Position, anchor.Value) -- called over: listens anywhere
				end
				if root.Position.Z <= layout.DoorZ then
					return nil
				end
				return flatDistance(root.Position, spot)
			end,
			-- the explanation in the player's own language, then the new phrase in the practice language
			present = function(result)
				-- asking Lumi switches translations under everyone's words on or off
				if result.translations ~= nil and result.translations ~= showTranslations then
					showTranslations = result.translations
					debugLog("translations " .. (showTranslations and "ON" or "OFF"))
				end
				local hasPhrase = result.phrase ~= nil and result.phrase ~= ""
				local quoted = hasPhrase and ("\u{201C}" .. result.phrase .. "\u{201D}") or nil
				chatBubble(ball, hasPhrase and (result.say .. "\n" .. quoted) or result.say)
				chatWindowLine(Data.TutorName .. ": " .. result.say .. (hasPhrase and ("  " .. quoted) or ""))
				burst(ball.Position, "Sparkles", 12)
				talking = true
				tutorPartner.speak(result.say, mainLanguage.voice, 3)
				if hasPhrase then
					tutorPartner.speak(result.phrase, learnLanguage.voice, 0)
				end
				talking = false
				if result.menu then
					returnToMenu() -- the learner asked to go back to the main menu
				end
			end,
		}
		giveVoice(tutorPartner)
		table.insert(partners, tutorPartner)
		burst(spot, "Poof", 20)

		-- gentle bobbing, a pulse while talking, and a blink every few seconds
		local startTime = os.clock()
		RunService.Heartbeat:Connect(function()
			local t = os.clock() - startTime
			ball.Position = anchor.Value + Vector3.new(math.sin(t * 0.7) * 0.4, math.sin(t * 1.6) * 0.5, 0)
			local size = 2.6 + (talking and math.sin(t * 14) * 0.12 or 0)
			ball.Size = Vector3.new(size, size, size)
		end)
		-- Y (left VR controller / gamepad, or the Y key) calls Lumi over to float in front
		-- of the player, wherever they are, so they can ask it something.
		local function summonLumi()
			local camera = workspace.CurrentCamera
			if not camera then
				return
			end
			local view = camera:GetRenderCFrame()
			local forward = Vector3.new(view.LookVector.X, 0, view.LookVector.Z)
			if forward.Magnitude < 0.05 then
				local root = playerRoot() -- looking straight up or down: use the way the body faces
				forward = root and Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z) or Vector3.new(0, 0, -1)
			end
			summoned = true
			summonedAt = os.clock()
			lookedAwayFor = 0
			playSound("Whoosh")
			burst(ball.Position, "Sparkles", 14)
			tween(anchor, 0.7, { Value = view.Position + forward.Unit * SUMMON_DISTANCE }, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
			debugLog("Lumi called over")
		end

		local function sendLumiHome()
			summoned = false
			playSound("Whoosh")
			tween(anchor, 1.1, { Value = spot }, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut)
			debugLog("Lumi went back to its spot")
		end

		UserInputService.InputBegan:Connect(function(input, processed)
			if input.KeyCode == Enum.KeyCode.ButtonY or (input.KeyCode == Enum.KeyCode.Y and not processed) then
				summonLumi()
			end
		end)

		-- Looking away from Lumi sends it back to its spot outside
		RunService.Heartbeat:Connect(function(dt)
			if not summoned or os.clock() - summonedAt < SUMMON_SETTLE then
				return
			end
			if lookAngleTo(ball.Position) > DISMISS_ANGLE then
				lookedAwayFor += dt
				if lookedAwayFor >= DISMISS_AFTER then
					sendLumiHome()
				end
			else
				lookedAwayFor = 0
			end
		end)

		task.spawn(function()
			while ball.Parent do
				task.wait(math.random(25, 55) / 10)
				for _, eye in eyes do
					tween(eye, 0.08, { Size = UDim2.fromScale(0.16, 0.04) })
				end
				task.wait(0.12)
				for _, eye in eyes do
					tween(eye, 0.1, { Size = UDim2.fromScale(0.16, 0.26) })
				end
			end
		end)
	end

	------------------------------------------------------------------
	-- Every frame: staff body language (gestures, and staring back at the player
	-- on eye contact)
	-- and the mop in the cleaner's hands
	------------------------------------------------------------------

	RunService.Heartbeat:Connect(function(dt)
		local character = player.Character
		local head = character and character:FindFirstChild("Head")
		local headPosition = head and head.Position or nil
		for _, npc in staff do
			-- Eye contact: a character looks at the player only while the player is
			-- looking at them. Otherwise they keep their eyes on what they are doing.
			local npcHead = npc.rig:FindFirstChild("Head")
			local eyeContact = headPosition ~= nil and npcHead ~= nil
				and (npcHead.Position - headPosition).Magnitude < EYE_CONTACT_RANGE
				and lookAngleTo(npcHead.Position) < LOOK_KEEP_ANGLE
			updateNpcBody(npc, dt, eyeContact and headPosition or nil)
		end

		local push = cleaner.workGesture == "sweep" and math.sin(os.clock() * 3) * 0.5 or 0
		local grip = cleaner.root.CFrame * CFrame.new(0.5, -0.9, -1.5 + push) * CFrame.Angles(math.rad(-28), 0, 0)
		mopHandle.CFrame = grip
		mopHead.CFrame = grip * CFrame.new(0, -2.3, 0) * CFrame.Angles(math.rad(28), 0, 0)
	end)

	------------------------------------------------------------------
	-- A few times a second: who is the player standing next to, should the
	-- doors be open, and is a hand reaching for the tray
	------------------------------------------------------------------

	local DOOR_RANGE = 9
	local STICKINESS = 2 -- how much closer someone else must be to take over the conversation
	local elapsed = 0

	local function pickPartner(root)
		local best, bestScore
		for _, partner in partners do
			local distance = partner.distance(root)
			local lookLimit = partner == activePartner and LOOK_KEEP_ANGLE or LOOK_ANGLE
			if distance and distance < partner.range and lookAngleTo(partner.part.Position) < lookLimit then
				local score = distance - (partner == activePartner and STICKINESS or 0)
				if not bestScore or score < bestScore then
					best, bestScore = partner, score
				end
			end
		end
		return best
	end

	RunService.Heartbeat:Connect(function(dt)
		elapsed += dt
		if elapsed < 0.15 then
			return
		end
		elapsed = 0

		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")

		local partner = root and pickPartner(root) or nil
		if partner ~= activePartner then
			activePartner = partner
			updateStatus()
		end
		-- note who is being looked at or is talking, so they linger afterwards
		for _, other in partners do
			if other == activePartner or other.busy then
				other.lastEngaged = os.clock()
			end
		end
		-- How a conversation starts. `partner` is whoever the player is close to AND looking at.
		--   The cashier and Lumi (autoGreet): eye contact is enough; they speak first.
		--   Everyone else: eye contact makes them stare back, and they only speak
		--   once the player has said something to them.
		if partner and partner.autoGreet and not partner.started and not partner.busy then
			partner.started = true
			debugLog("eye contact with " .. partner.name .. ": they start the conversation")
			task.spawn(request, partner, "start")
		end

		setDoorsOpen(root ~= nil and flatDistance(root.Position, Vector3.new(0, 0, DOOR_Z)) < DOOR_RANGE)

		-- (reaching for food and eating it in VR is done by LingoFood)

		-- the player stood up from the table
		if playerSeat then
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			if not humanoid or not humanoid.Sit then
				playerSeat = nil
				debugLog("stood up")
			end
		end
	end)

	updateStatus()
	debugLog(string.format("scenario ready: %s -> %s", mainLanguage.english, learnLanguage.english))
end

---------------------------------------------------------------------
-- Start
---------------------------------------------------------------------

sounds.Music:Play()

local mainLanguage, learnLanguage, scenarioId, closeIntro = runIntro()
debugLog(string.format("picked %s / %s / %s", mainLanguage.code, learnLanguage.code, scenarioId))

-- The server spawns the character now that the intro is done
startScenario:FireServer(mainLanguage.code, learnLanguage.code, scenarioId)
local character = player.Character or player.CharacterAdded:Wait()
character:WaitForChild("HumanoidRootPart")
task.wait(0.6)

closeIntro()

-- The view goes back to the character that has just spawned. After a return to the
-- main menu the standard camera can be left without a subject (the earlier character
-- was taken away), which leaves the view and the VR head hanging where they were.
-- This only re-attaches the standard first-person camera; it does not move or steer it.
task.spawn(function()
	for _ = 1, 8 do
		local camera = workspace.CurrentCamera
		local current = player.Character
		local humanoid = current and current:FindFirstChildOfClass("Humanoid")
		if camera and humanoid then
			if camera.CameraType ~= Enum.CameraType.Custom then
				camera.CameraType = Enum.CameraType.Custom
			end
			if camera.CameraSubject ~= humanoid then
				debugLog("camera was not on the character: re-attached")
				camera.CameraSubject = humanoid
			end
		end
		task.wait(0.25)
	end
end)

tween(sounds.Music, 2.5, { Volume = 0.04 }) -- barely there once the scenario starts, so voices are easy to hear
task.wait(1)

if scenarioId == "fastfood" then
	runFastFood(mainLanguage, learnLanguage)
else
	-- the airplane and the dinner live in their own module; it gets the helpers this script already has
	local Scenes = require(ReplicatedStorage:WaitForChild("LingoScenes"))
	Scenes.run(scenarioId, {
		player = player, playerGui = playerGui, Data = Data,
		mainLanguage = mainLanguage, learnLanguage = learnLanguage,
		npcGenerate = npcGenerate, sounds = sounds,
		create = create, tween = tween, playSound = playSound, burst = burst, debugLog = debugLog,
		setupNpc = setupNpc, walkTo = walkTo, faceDirection = faceDirection, facePoint = facePoint,
		updateNpcBody = updateNpcBody, returnToMenu = returnToMenu,
		takeFriendRigs = takeFriendRigs, swapInFriend = swapInFriend,
	})
end
