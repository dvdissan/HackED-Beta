-- The airplane and dinner scenarios.
-- LingoClient runs the intro and the fast food scenario itself; for these two it
-- hands over to Scenes.run(scenarioId, ctx), passing the helpers it already has
-- (create, tween, sounds, NPC walking and body animation, the remote, and so on).
--
-- Every character here is its own object: its own voice box, its own "busy"
-- flag and its own queue. The rules are the same as in the fast food place:
--   * the microphone is always open, and speaking over someone interrupts them
--   * whoever the player is close to AND looking at is the one who hears them
--   * characters only look back at the player on eye contact

local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RealRunService = game:GetService("RunService")
local TextChatService = game:GetService("TextChatService")
local TweenService = game:GetService("TweenService")
local RealUserInputService = game:GetService("UserInputService")
local VRService = game:GetService("VRService")

local Scenes = {}

-- Every connection made here is remembered, so that going back to the main menu
-- can end them all (Scenes.stop). These two stand-ins look like the real services
-- for the one thing this module uses them for: connecting to an event.
local connections = {}
local function tracked(signal)
	return {
		Connect = function(_, callback)
			local connection = signal:Connect(callback)
			table.insert(connections, connection)
			return connection
		end,
	}
end
local RunService = { Heartbeat = tracked(RealRunService.Heartbeat) }
local UserInputService = { InputBegan = tracked(RealUserInputService.InputBegan) }

function Scenes.stop()
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
end

local WHITE = Color3.new(1, 1, 1)
local UPRIGHT = CFrame.Angles(0, 0, math.rad(90)) -- stands a cylinder on its end

---------------------------------------------------------------------
-- The kit: everything a scenario needs to have characters who talk
---------------------------------------------------------------------

local function newKit(ctx)
	local player = ctx.player
	local create, tween, debugLog = ctx.create, ctx.tween, ctx.debugLog
	local Data = ctx.Data
	local main, learn = ctx.mainLanguage, ctx.learnLanguage
	local npcGenerate = ctx.npcGenerate

	local kit = {
		characters = {}, -- everyone who can be talked to
		byId = {},
		bodies = {}, -- the NPC rigs whose gestures and heads are animated
		showTranslations = false, -- switched on or off by asking Lumi
		active = nil, -- the character the player is close to and looking at
	}

	function kit.text(key)
		return Data.Text(main.code, key)
	end

	function kit.playerRoot()
		local character = player.Character
		return character and character:FindFirstChild("HumanoidRootPart")
	end

	function kit.playerHumanoid()
		local character = player.Character
		return character and character:FindFirstChildOfClass("Humanoid")
	end

	function kit.flatDistance(a, b)
		return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
	end

	-- a simple anchored prop part
	function kit.prop(parent, shape, size, cframe, color, material, transparency)
		return create("Part", {
			Anchored = true, CanCollide = false, CanQuery = false, CanTouch = false, Massless = true,
			Shape = shape, Size = size, Color = color, Material = material or Enum.Material.SmoothPlastic,
			Transparency = transparency or 0, TopSurface = Enum.SurfaceType.Smooth, BottomSurface = Enum.SurfaceType.Smooth,
			CFrame = cframe,
		}, parent)
	end

	------------------------------------------------------------------
	-- Chat: built-in bubbles above heads, plus the chat window
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

	-- A line as it is shown: on its own, or with its translation underneath when
	-- translations are on. Only the line itself is ever spoken.
	local function captioned(line, translation)
		if kit.showTranslations and translation and translation ~= "" then
			return line .. "\n(" .. translation .. ")"
		end
		return line
	end

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
	-- Voice: one microphone for the player, a voice box for every character
	------------------------------------------------------------------

	local function wireUp(source, target)
		return create("Wire", { SourceInstance = source, TargetInstance = target }, target)
	end

	local micInput = create("AudioDeviceInput", { Name = "LingoMic", Player = player }, player)
	local speechToText = create("AudioSpeechToText", { Name = "LingoSTT", Enabled = true }, player)
	wireUp(micInput, speechToText)

	local MAX_TTS_CHARACTERS = 300

	-- Returns speak(line, voiceId, pitch), which yields until the line is said or
	-- cut off, and stop(), which cuts it off. With no voiceId (Roblox has no voice
	-- for that language) speak just waits long enough for the bubble to be read.
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
				return
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

	-- What characters said lately, so an echo of it through the open microphone
	-- is not mistaken for the player talking
	local ECHO_WINDOW = 1.5
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
		local record = { text = normal, words = words, endsAt = math.huge }
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
				if #heardWords == 1 and #normal >= 6 and string.find(record.text, normal, 1, true) then
					return true
				end
			end
		end
		return false
	end

	------------------------------------------------------------------
	-- Eye contact
	------------------------------------------------------------------

	local LOOK_ANGLE = math.rad(35) -- looking at someone = they are within this angle of the centre of the view
	local LOOK_KEEP_ANGLE = math.rad(50) -- a little slack for whoever is already listening
	local EYE_CONTACT_RANGE = 40 -- further than this, nobody notices being looked at
	local LINGER_SECONDS = 8 -- how long someone stays engaged after the player looks away
	local STICKINESS = 2

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
	kit.lookAngleTo = lookAngleTo

	-- can this character be spoken to yet? (some only talk after they have spoken first)
	local function canListen(character)
		return character ~= nil and (not character.mustStartFirst or character.started)
	end

	-- the player is looking at them, they are talking, or either was true a moment ago
	function kit.engaged(character)
		return character == kit.active or character.busy
			or os.clock() - (character.lastEngaged or -math.huge) < LINGER_SECONDS
	end

	local function updateStatus()
		for _, character in kit.characters do
			local isActive = character == kit.active
			local label = character.name
			if character.busy and (isActive or character.addressingPlayer) then
				label = kit.text("thinking")
			elseif isActive and canListen(character) then
				label = kit.text("listening")
			end
			character.pill.Text = label
			character.pill.BackgroundColor3 = (isActive and not character.busy and canListen(character))
				and Color3.fromRGB(40, 150, 80) or Color3.fromRGB(40, 44, 60)
		end
	end

	------------------------------------------------------------------
	-- Talking
	------------------------------------------------------------------

	local function runQueue(character)
		if character.busy or #character.queue == 0 then
			return
		end
		local job = table.remove(character.queue, 1)
		job()
	end

	-- Asks the server for a character's next line, then lets that character present it.
	-- If they are already thinking or talking, the request waits in their own queue.
	function kit.request(character, kind, payload, afterSpeaking, context)
		if character.busy then
			table.insert(character.queue, kind == "say" and 1 or #character.queue + 1, function()
				kit.request(character, kind, payload, afterSpeaking, context)
			end)
			return
		end
		character.busy = true
		character.interrupted = false
		character.addressingPlayer = true
		updateStatus()

		local started = os.clock()
		local ok, result = pcall(function()
			return npcGenerate:InvokeServer(character.id, kind, payload, context)
		end)

		if ok and type(result) == "table" and result.ok then
			debugLog(string.format("%s ok (%.1fs): %s", character.name, os.clock() - started, result.say))
			character.present(result, kind)
			if afterSpeaking then
				afterSpeaking()
			end
		else
			local message = ok and type(result) == "table" and result.err or result
			debugLog(character.name .. " FAILED: " .. tostring(message))
			task.wait(1)
		end

		if character.npc then
			character.npc.talkGesture = nil
		end
		character.addressingPlayer = false
		character.busy = false
		updateStatus()
		task.delay(0.3, runQueue, character)
	end

	-- A character says a line: bubble, chat window, gesture, voice
	function kit.say(character, line, translation, kind)
		local shown = captioned(line, translation)
		chatBubble(character.part, shown)
		chatWindowLine(character.name .. ": " .. (string.gsub(shown, "\n", "  ")))
		if character.npc then
			character.npc.talkGesture = kind == "start" and "wave" or "talk"
		end
		character.speak(line, character.voice, character.pitch)
		if character.npc then
			character.npc.talkGesture = nil
		end
	end
	kit.chatBubble = chatBubble
	kit.chatWindowLine = chatWindowLine

	-- Adds a character. spec: id, name, part (what the bubble sits on), range,
	-- voice, pitch, and optionally npc (the rig), autoGreet, mustStartFirst,
	-- greetWhen(), context(), distance(root), pillOffset.
	function kit.addCharacter(spec)
		local character = spec
		character.busy = false
		character.queue = {}
		character.started = false
		character.interrupted = false
		character.speaking = false
		character.pill = statusPill(character.part, character.pillOffset or Vector3.new(-4.2, 0.2, 0), character.name)
		if character.npc then
			character.pill.Parent.Enabled = false -- no floating name tags on people (Lumi keeps its label)
		end
		if not character.distance then
			character.distance = function(root)
				return kit.flatDistance(root.Position, character.part.Position)
			end
		end
		if not character.present then
			character.present = function(result, kind)
				kit.say(character, result.say, result.translation, kind)
			end
		end

		local rawSpeak, stop = newVoice(character.part, character.id)
		character.speak = function(line, voiceId, pitch)
			if character.interrupted then
				return -- the player cut in: nothing more from them this turn
			end
			local record = rememberSpoken(line)
			character.speaking = true
			rawSpeak(line, voiceId, pitch)
			character.speaking = false
			record.endsAt = os.clock()
		end
		character.interrupt = function()
			character.interrupted = true
			stop()
		end

		table.insert(kit.characters, character)
		kit.byId[character.id] = character
		if character.npc then
			table.insert(kit.bodies, character.npc)
		end
		return character
	end

	-- The microphone is always open. What it hears goes to whoever the player is
	-- looking at (or whoever is in the middle of talking to them), and cuts them
	-- off if they are speaking.
	local function playerSaid(heard, typed)
		local character = kit.active
		if not canListen(character) then
			character = nil
			for _, other in kit.characters do
				if other.speaking and other.addressingPlayer and canListen(other) then
					character = other
					break
				end
			end
		end
		if not character then
			debugLog("HEARD (nobody was listening): " .. heard)
			return
		end
		if character.busy then
			debugLog(character.name .. " was interrupted")
			character.interrupt()
		end
		debugLog("HEARD by " .. character.name .. ": " .. heard)
		if not typed then
			-- a typed line is already in the chat window
			chatWindowLine(player.DisplayName .. ": " .. heard)
		end
		kit.request(character, "say", heard, nil, character.context and character.context() or nil)
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
	-- Sitting and walking helpers
	------------------------------------------------------------------

	-- Drops the player onto a seat facing lookAt, sitting (jump to stand up again)
	function kit.sitPlayer(position, lookAt)
		local root, humanoid = kit.playerRoot(), kit.playerHumanoid()
		if not root or not humanoid then
			return false
		end
		root.CFrame = CFrame.lookAt(position, Vector3.new(lookAt.X, position.Y, lookAt.Z))
		humanoid.Sit = true
		return true
	end

	function kit.playerIsSitting()
		local humanoid = kit.playerHumanoid()
		return humanoid ~= nil and humanoid.Sit
	end

	-- Sits an NPC at a root position, facing a direction
	function kit.seatNpc(npc, position, direction)
		npc.workGesture = "seated" -- not "idle", so the body stays put on the seat
		npc.root.CFrame = CFrame.lookAt(position, position + direction)
		npc.restLook = npc.root.CFrame.LookVector
		if npc.idle then
			npc.idle:Stop(0.2)
		end
		if npc.sit then
			npc.sit:Play(0.2)
		end
	end

	-- Stands a seated NPC back up on a floor where its root should be at standingY
	function kit.standNpc(npc, standingY)
		if npc.sit then
			npc.sit:Stop(0.2)
		end
		if npc.idle then
			npc.idle:Play(0.2)
		end
		local position = npc.root.Position
		npc.y = standingY or npc.y
		npc.root.CFrame = npc.root.CFrame.Rotation + Vector3.new(position.X, npc.y, position.Z)
		npc.workGesture = "idle"
	end

	-- Walks an NPC through a list of points, one straight line after another
	function kit.walkPath(npc, points)
		for _, point in points do
			ctx.walkTo(npc, point.X, point.Z)
		end
	end

	------------------------------------------------------------------
	-- Lumi, the floating guide: speaks the player's own language and teaches
	-- phrases in the language being practised. Y calls it over.
	------------------------------------------------------------------

	function kit.addLumi(spot, parent)
		local ball = create("Part", {
			Name = Data.TutorName, Shape = Enum.PartType.Ball, Size = Vector3.new(2.6, 2.6, 2.6), Anchored = true,
			CanCollide = false, CanQuery = false, Material = Enum.Material.Neon, Color = Color3.fromRGB(120, 215, 255), Position = spot,
		}, parent)
		create("PointLight", { Color = Color3.fromRGB(150, 225, 255), Range = 16, Brightness = 1.3 }, ball)

		-- face: two eyes and a smile on a billboard just in front of the ball
		local face = create("BillboardGui", {
			Name = "Face", Adornee = ball, Size = UDim2.fromScale(2, 1.5), StudsOffset = Vector3.new(0, 0, 1.4), LightInfluence = 0, MaxDistance = 120,
		}, ball)
		local FACE_COLOR = Color3.fromRGB(20, 40, 70)
		for _, x in { 0.3, 0.7 } do
			local eye = create("Frame", {
				AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(x, 0.38), Size = UDim2.fromScale(0.16, 0.26),
				BackgroundColor3 = FACE_COLOR, BorderSizePixel = 0,
			}, face)
			create("UICorner", { CornerRadius = UDim.new(1, 0) }, eye)
		end
		local smileClip = create("Frame", {
			AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0.62), Size = UDim2.fromScale(0.34, 0.2),
			BackgroundTransparency = 1, ClipsDescendants = true,
		}, face)
		local smileRing = create("Frame", {
			Position = UDim2.fromScale(0.06, -1.1), Size = UDim2.fromScale(0.88, 2), BackgroundTransparency = 1,
		}, smileClip)
		create("UICorner", { CornerRadius = UDim.new(1, 0) }, smileRing)
		create("UIStroke", { Color = FACE_COLOR, Thickness = 3 }, smileRing)

		local anchor = Instance.new("Vector3Value")
		anchor.Value = spot
		local talking = false
		local summoned, summonedAt, lookedAwayFor = false, 0, 0

		local character
		character = kit.addCharacter({
			id = "tutor", name = Data.TutorName, part = ball, range = 13, autoGreet = true, mustStartFirst = true,
			pillOffset = Vector3.new(0, -2.3, 0),
		})
		-- the explanation in the player's own language, then the new phrase in the practice language
		character.present = function(result)
			if result.translations ~= nil and result.translations ~= kit.showTranslations then
				kit.showTranslations = result.translations
				debugLog("translations " .. (kit.showTranslations and "ON" or "OFF"))
			end
			local hasPhrase = result.phrase ~= nil and result.phrase ~= ""
			local quoted = hasPhrase and ("\u{201C}" .. result.phrase .. "\u{201D}") or nil
			chatBubble(ball, hasPhrase and (result.say .. "\n" .. quoted) or result.say)
			chatWindowLine(Data.TutorName .. ": " .. result.say .. (hasPhrase and ("  " .. quoted) or ""))
			talking = true
			character.speak(result.say, main.voice, 3)
			if hasPhrase then
				character.speak(result.phrase, learn.voice, 0)
			end
			talking = false
			if result.menu and ctx.returnToMenu then
				ctx.returnToMenu() -- the learner asked to go back to the main menu
			end
		end

		local SUMMON_DISTANCE = 6
		local DISMISS_AFTER = 6 -- seconds of looking away before Lumi floats back
		local startTime = os.clock()

		RunService.Heartbeat:Connect(function(dt)
			local t = os.clock() - startTime
			ball.Position = anchor.Value + Vector3.new(math.sin(t * 0.7) * 0.4, math.sin(t * 1.6) * 0.5, 0)
			local size = 2.6 + (talking and math.sin(t * 14) * 0.12 or 0)
			ball.Size = Vector3.new(size, size, size)

			-- called over: goes home again once the player has looked away for a while
			if summoned and os.clock() - summonedAt > 1.5 then
				if lookAngleTo(ball.Position) > math.rad(60) then
					lookedAwayFor += dt
					if lookedAwayFor >= DISMISS_AFTER then
						summoned = false
						tween(anchor, 1.1, { Value = spot }, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut)
					end
				else
					lookedAwayFor = 0
				end
			end
		end)

		-- Y (left VR controller / gamepad, or the Y key) calls Lumi over
		UserInputService.InputBegan:Connect(function(input, processed)
			if input.KeyCode == Enum.KeyCode.ButtonY or (input.KeyCode == Enum.KeyCode.Y and not processed) then
				local camera = workspace.CurrentCamera
				if not camera then
					return
				end
				local view = camera:GetRenderCFrame()
				local forward = Vector3.new(view.LookVector.X, 0, view.LookVector.Z)
				if forward.Magnitude < 0.05 then
					forward = Vector3.new(0, 0, -1)
				end
				summoned = true
				summonedAt = os.clock()
				lookedAwayFor = 0
				ctx.playSound("Whoosh")
				tween(anchor, 0.7, { Value = view.Position + forward.Unit * SUMMON_DISTANCE })
				debugLog("Lumi called over")
			end
		end)

		return character
	end

	------------------------------------------------------------------
	-- Starts the loops. Call once every character has been added.
	------------------------------------------------------------------

	function kit.start()
		-- every frame: body language, and staring back at the player on eye contact
		RunService.Heartbeat:Connect(function(dt)
			local character = player.Character
			local head = character and character:FindFirstChild("Head")
			local headPosition = head and head.Position or nil
			for _, npc in kit.bodies do
				local npcHead = npc.rig:FindFirstChild("Head")
				local eyeContact = headPosition ~= nil and npcHead ~= nil
					and (npcHead.Position - headPosition).Magnitude < EYE_CONTACT_RANGE
					and lookAngleTo(npcHead.Position) < LOOK_KEEP_ANGLE
				ctx.updateNpcBody(npc, dt, eyeContact and headPosition or nil)
			end
		end)

		-- a few times a second: who is the player close to and looking at
		local elapsed = 0
		RunService.Heartbeat:Connect(function(dt)
			elapsed += dt
			if elapsed < 0.15 then
				return
			end
			elapsed = 0

			local root = kit.playerRoot()
			local best, bestScore
			if root then
				for _, character in kit.characters do
					local distance = character.distance(root)
					local lookLimit = character == kit.active and LOOK_KEEP_ANGLE or LOOK_ANGLE
					if distance and distance < character.range and lookAngleTo(character.part.Position) < lookLimit then
						local score = distance - (character == kit.active and STICKINESS or 0)
						if not bestScore or score < bestScore then
							best, bestScore = character, score
						end
					end
				end
			end
			if best ~= kit.active then
				kit.active = best
				updateStatus()
			end
			for _, character in kit.characters do
				if character == kit.active or character.busy then
					character.lastEngaged = os.clock()
				end
			end

			-- Characters who speak first do so on eye contact. Everyone else just
			-- looks back, and answers once the player says something.
			if best and best.autoGreet and not best.started and not best.busy
				and (not best.greetWhen or best.greetWhen()) then
				best.started = true
				debugLog("eye contact with " .. best.name .. ": they start the conversation")
				task.spawn(kit.request, best, "start")
			end
		end)

		updateStatus()
	end

	return kit
end

---------------------------------------------------------------------
-- Friends: the people in a scenario take on the look of the player's friends
---------------------------------------------------------------------

-- Swaps a friend's avatar in for each named character in the scene, for as many
-- friends as loaded. Anyone left over keeps their usual look.
local function useFriends(ctx, scene, roles)
	if not ctx.takeFriendRigs or not ctx.swapInFriend then
		return
	end
	local rigs = ctx.takeFriendRigs()
	local swapped = 0
	for _, role in roles do
		local original = scene:FindFirstChild(role)
		local rig = table.remove(rigs)
		if original and rig then
			local ok, err = pcall(ctx.swapInFriend, original, rig)
			if ok then
				swapped += 1
			else
				ctx.debugLog(role .. " friend swap FAILED: " .. tostring(err))
			end
		end
	end
	ctx.debugLog(swapped .. " characters look like friends")
end

---------------------------------------------------------------------
-- Airplane: a spacious cabin high above the clouds. Take your seat and the
-- flight attendant comes to you; the passengers nearby will chat if you talk to them.
---------------------------------------------------------------------

local CUP_COLORS = {
	water = Color3.fromRGB(170, 215, 245),
	juice = Color3.fromRGB(255, 170, 50),
	coffee = Color3.fromRGB(80, 50, 30),
	tea = Color3.fromRGB(190, 120, 60),
}

-- Builds one thing the flight attendant can bring, standing on `at`
local function buildCabinItem(kit, parent, id, at)
	local parts = {}
	local function add(part)
		table.insert(parts, part)
	end
	if CUP_COLORS[id] then
		add(kit.prop(parent, Enum.PartType.Cylinder, Vector3.new(0.6, 0.42, 0.42), CFrame.new(at + Vector3.new(0, 0.3, 0)) * UPRIGHT, WHITE, nil, 0.45))
		add(kit.prop(parent, Enum.PartType.Cylinder, Vector3.new(0.46, 0.34, 0.34), CFrame.new(at + Vector3.new(0, 0.25, 0)) * UPRIGHT, CUP_COLORS[id]))
	elseif id == "sandwich" then
		local bread = Color3.fromRGB(226, 190, 130)
		add(kit.prop(parent, Enum.PartType.Block, Vector3.new(0.7, 0.12, 0.6), CFrame.new(at + Vector3.new(0, 0.06, 0)), bread))
		add(kit.prop(parent, Enum.PartType.Block, Vector3.new(0.72, 0.1, 0.62), CFrame.new(at + Vector3.new(0, 0.17, 0)), Color3.fromRGB(110, 190, 80)))
		add(kit.prop(parent, Enum.PartType.Block, Vector3.new(0.7, 0.12, 0.6), CFrame.new(at + Vector3.new(0, 0.28, 0)), bread))
	else -- cookies
		add(kit.prop(parent, Enum.PartType.Cylinder, Vector3.new(0.05, 0.7, 0.7), CFrame.new(at + Vector3.new(0, 0.025, 0)) * UPRIGHT, WHITE))
		for _, offset in { Vector3.new(-0.14, 0.08, 0.05), Vector3.new(0.14, 0.08, -0.06), Vector3.new(0, 0.14, 0.1) } do
			add(kit.prop(parent, Enum.PartType.Cylinder, Vector3.new(0.06, 0.26, 0.26), CFrame.new(at + offset) * UPRIGHT, Color3.fromRGB(170, 115, 60)))
		end
	end
	return parts
end

local function runAirplane(ctx, kit)
	local Data = ctx.Data
	local info = Data.Scenes.airplane
	local layout = info.Layout
	local learn = ctx.learnLanguage
	local player = ctx.player
	local NOSE = Vector3.new(0, 0, -1) -- the way every seat faces

	local scene = ReplicatedStorage:WaitForChild("Scenarios"):WaitForChild("Airplane"):Clone()
	scene.Parent = workspace

	-- The character spawns on the grass; move them up into the cabin (and again if they respawn)
	local function boardPlane(character)
		local root = character:WaitForChild("HumanoidRootPart", 10)
		if root then
			root.CFrame = CFrame.lookAt(layout.Spawn, layout.Spawn + NOSE)
		end
	end
	if player.Character then
		boardPlane(player.Character)
	end
	table.insert(connections, player.CharacterAdded:Connect(function(character)
		task.wait(0.3)
		if scene.Parent then
			boardPlane(character)
		end
	end))

	if ctx.sounds.Cabin then
		ctx.sounds.Cabin:Play()
	end

	-- Flying: the cabin stays where it is and clouds stream past the windows
	local CLOUD_SPEED = 70
	local clouds = {}
	local function placeCloud(cloud, z)
		local side = math.random() < 0.5 and -1 or 1
		cloud.Position = Vector3.new(side * math.random(60, 190), layout.FloorY + math.random(-45, 30), z)
	end
	for _ = 1, 18 do
		local cloud = kit.prop(scene, Enum.PartType.Block,
			Vector3.new(math.random(35, 70), math.random(10, 20), math.random(35, 70)), CFrame.new(), WHITE, nil, 0.25)
		cloud.CastShadow = false
		placeCloud(cloud, math.random(-320, 320))
		table.insert(clouds, cloud)
	end
	RunService.Heartbeat:Connect(function(dt)
		for _, cloud in clouds do
			local position = cloud.Position + Vector3.new(0, 0, CLOUD_SPEED * dt)
			if position.Z > 320 then
				placeCloud(cloud, -320)
			else
				cloud.Position = position
			end
		end
	end)

	-- The people on board (looking like the player's friends, where avatars loaded)
	useFriends(ctx, scene, { "PassengerB", "PassengerA", "Attendant" })
	local attendant = ctx.setupNpc(scene.Attendant)
	local passengerA = ctx.setupNpc(scene.PassengerA)
	local passengerB = ctx.setupNpc(scene.PassengerB)
	kit.seatNpc(passengerA, Vector3.new(layout.PassengerASeat.X, layout.SeatedRootY, layout.PassengerASeat.Z), NOSE)
	kit.seatNpc(passengerB, Vector3.new(layout.PassengerBSeat.X, layout.SeatedRootY, layout.PassengerBSeat.Z), NOSE)

	local attendantCharacter = kit.addCharacter({
		id = "attendant", name = info.AttendantName, npc = attendant, part = attendant.rig:WaitForChild("Head"),
		range = 11, voice = learn.voice, pitch = 0,
	})
	kit.addCharacter({
		id = "passenger_a", name = info.PassengerAName, npc = passengerA, part = passengerA.rig:WaitForChild("Head"),
		range = 10, voice = learn.voice, pitch = 2.5,
	})
	kit.addCharacter({
		id = "passenger_b", name = info.PassengerBName, npc = passengerB, part = passengerB.rig:WaitForChild("Head"),
		range = 8, voice = learn.voiceMale or learn.voice, pitch = 0,
	})
	kit.addLumi(layout.TutorSpot, scene)

	-- The player's seat: highlighted, with a prompt to sit down
	local seat = scene.Seats.PlayerSeat
	local seated = false
	local seatHighlight = ctx.create("Highlight", {
		FillColor = Color3.fromRGB(255, 225, 90), FillTransparency = 0.6, OutlineColor = Color3.fromRGB(255, 240, 160),
		DepthMode = Enum.HighlightDepthMode.Occluded,
	}, seat)
	local seatPrompt = ctx.create("ProximityPrompt", {
		ActionText = kit.text("sit"), ObjectText = "", HoldDuration = 0, MaxActivationDistance = 9, RequiresLineOfSight = false,
	}, seat)
	seatPrompt.Triggered:Connect(function()
		local seatPosition = Vector3.new(layout.PlayerSeat.X, layout.PlayerSeat.Y + 2.4, layout.PlayerSeat.Z)
		if kit.sitPlayer(seatPosition, seatPosition + NOSE) then
			seated = true
			seatHighlight.Enabled = false
			ctx.debugLog("sat down in the seat")
		end
	end)

	-- She stands ahead of the player's row and turns to face their seat
	local towardSeat = Vector3.new(layout.PlayerSeat.X - layout.AttendantStand.X, 0, layout.PlayerSeat.Z - layout.AttendantStand.Z).Unit

	-- Fetching what the passenger asked for from the galley
	local serving = false
	local onTray = {}
	local function serve(items)
		if serving then
			return
		end
		serving = true
		ctx.walkTo(attendant, layout.Galley.X, layout.Galley.Z)
		ctx.faceDirection(attendant, Vector3.new(0, 0, 1))
		attendant.workGesture = "cook" -- busy at the galley counter
		task.wait(3.5)
		attendant.workGesture = "carry"
		ctx.walkTo(attendant, layout.AttendantStand.X, layout.AttendantStand.Z)
		ctx.faceDirection(attendant, Vector3.new(1, 0, 0))
		attendant.workGesture = "idle"

		for _, part in onTray do
			part:Destroy()
		end
		table.clear(onTray)
		local slot = 0
		for _, entry in items do
			for _ = 1, entry.quantity do
				local at = layout.TrayTable + Vector3.new(-0.8 + slot * 0.8, 0, 0)
				for _, part in buildCabinItem(kit, scene, entry.id, at) do
					table.insert(onTray, part)
				end
				slot += 1
			end
		end
		ctx.playSound("Click")
		ctx.burst(layout.TrayTable + Vector3.new(0, 0.4, 0), "Sparkles", 14)
		ctx.debugLog("served at the seat")
		kit.request(attendantCharacter, "served", items)
		serving = false
	end

	attendantCharacter.present = function(result, kind)
		kit.say(attendantCharacter, result.say, result.translation, kind)
		if result.serve and #result.serve > 0 then
			task.spawn(serve, result.serve) -- she goes once she has said she will be right back
		end
	end

	-- Once the player is in their seat, the flight attendant walks up the aisle to them
	task.spawn(function()
		while not seated and scene.Parent do
			task.wait(0.3)
		end
		if not scene.Parent then
			return -- the scenario was closed
		end
		task.wait(2)
		ctx.walkTo(attendant, layout.AttendantStand.X, layout.AttendantStand.Z)
		ctx.faceDirection(attendant, Vector3.new(1, 0, 0))
		attendantCharacter.started = true
		kit.request(attendantCharacter, "start")
	end)

	kit.start()
	ctx.debugLog("airplane ready")
end

---------------------------------------------------------------------
-- Dinner: arrive with a friend, get shown to a table, order, eat, pay, leave
---------------------------------------------------------------------

-- Builds one dish on a plate, standing on `at`
local function buildDish(kit, parent, id, at)
	local parts = {}
	local function add(part)
		table.insert(parts, part)
	end
	local function plate()
		add(kit.prop(parent, Enum.PartType.Cylinder, Vector3.new(0.08, 1.5, 1.5), CFrame.new(at + Vector3.new(0, 0.04, 0)) * UPRIGHT, WHITE))
	end
	if id == "juice" then
		add(kit.prop(parent, Enum.PartType.Cylinder, Vector3.new(0.8, 0.45, 0.45), CFrame.new(at + Vector3.new(0, 0.4, 0)) * UPRIGHT, WHITE, nil, 0.5))
		add(kit.prop(parent, Enum.PartType.Cylinder, Vector3.new(0.62, 0.37, 0.37), CFrame.new(at + Vector3.new(0, 0.33, 0)) * UPRIGHT, Color3.fromRGB(255, 165, 45)))
	elseif id == "soup" then
		plate()
		add(kit.prop(parent, Enum.PartType.Cylinder, Vector3.new(0.3, 1.1, 1.1), CFrame.new(at + Vector3.new(0, 0.22, 0)) * UPRIGHT, Color3.fromRGB(235, 235, 240)))
		add(kit.prop(parent, Enum.PartType.Cylinder, Vector3.new(0.06, 0.95, 0.95), CFrame.new(at + Vector3.new(0, 0.38, 0)) * UPRIGHT, Color3.fromRGB(215, 70, 45)))
	elseif id == "salad" then
		plate()
		for _, offset in { Vector3.new(0, 0.25, 0), Vector3.new(0.25, 0.2, 0.15), Vector3.new(-0.25, 0.2, -0.1) } do
			add(kit.prop(parent, Enum.PartType.Ball, Vector3.new(0.6, 0.6, 0.6), CFrame.new(at + offset), Color3.fromRGB(95, 175, 75)))
		end
		add(kit.prop(parent, Enum.PartType.Ball, Vector3.new(0.25, 0.25, 0.25), CFrame.new(at + Vector3.new(0.1, 0.5, -0.2)), Color3.fromRGB(215, 55, 45)))
	elseif id == "pasta" then
		plate()
		add(kit.prop(parent, Enum.PartType.Ball, Vector3.new(1, 1, 1), CFrame.new(at + Vector3.new(0, 0.3, 0)), Color3.fromRGB(245, 215, 120)))
		add(kit.prop(parent, Enum.PartType.Ball, Vector3.new(0.5, 0.5, 0.5), CFrame.new(at + Vector3.new(0, 0.7, 0)), Color3.fromRGB(200, 55, 40)))
	elseif id == "steak" then
		plate()
		add(kit.prop(parent, Enum.PartType.Block, Vector3.new(0.9, 0.25, 0.6), CFrame.new(at + Vector3.new(-0.15, 0.2, 0)), Color3.fromRGB(105, 60, 40)))
		add(kit.prop(parent, Enum.PartType.Ball, Vector3.new(0.4, 0.4, 0.4), CFrame.new(at + Vector3.new(0.45, 0.25, 0.2)), Color3.fromRGB(95, 175, 75)))
	else -- cake
		plate()
		add(kit.prop(parent, Enum.PartType.Block, Vector3.new(0.7, 0.5, 0.5), CFrame.new(at + Vector3.new(0, 0.33, 0)), Color3.fromRGB(85, 50, 35)))
		add(kit.prop(parent, Enum.PartType.Block, Vector3.new(0.72, 0.08, 0.52), CFrame.new(at + Vector3.new(0, 0.6, 0)), Color3.fromRGB(250, 240, 230)))
	end
	return parts
end

local function runDinner(ctx, kit)
	local Data = ctx.Data
	local info = Data.Scenes.dinner
	local layout = info.Layout
	local learn = ctx.learnLanguage
	local create = ctx.create
	local FLOOR_INSIDE, GROUND = 0.3, 0 -- the restaurant floor is a little higher than the grass

	local scene = ReplicatedStorage:WaitForChild("Scenarios"):WaitForChild("Dinner"):Clone()
	scene.Parent = workspace
	ctx.playSound("Appear")
	ctx.burst(Vector3.new(0, 1, -45), "Dust", 60, Vector3.new(40, 1, 34))
	if ctx.sounds.Crowd then
		ctx.sounds.Crowd:Play()
	end

	-- your dinner companion and the waitress look like friends of yours, where avatars loaded
	useFriends(ctx, scene, { "Friend", "Waitress" })
	local waitress = ctx.setupNpc(scene.Waitress)
	local friend = ctx.setupNpc(scene.Friend)
	local friendStandingOffset = friend.y - GROUND -- how high his root is above whatever he stands on

	-- Where the evening has got to. The server is told with every line, so the
	-- waitress and the friend know what is going on.
	local stage = "arrive" -- arrive, led, seated, ordered, served, bill, paid
	local function context()
		return stage
	end

	local waitressCharacter = kit.addCharacter({
		id = "waitress", name = info.WaitressName, npc = waitress, part = waitress.rig:WaitForChild("Head"),
		range = 22, voice = learn.voice, pitch = 0, context = context,
		-- she speaks first, on eye contact, once the player has come inside
		autoGreet = true, mustStartFirst = true,
		greetWhen = function()
			local root = kit.playerRoot()
			return root ~= nil and root.Position.Z < layout.DoorZ
		end,
	})
	local friendCharacter = kit.addCharacter({
		id = "friend", name = info.FriendName, npc = friend, part = friend.rig:WaitForChild("Head"),
		range = 14, voice = learn.voiceMale or learn.voice, pitch = 1.5, context = context,
	})
	kit.addLumi(layout.TutorSpot, scene)

	------------------------------------------------------------------
	-- The friend tags along behind the player until they sit down
	------------------------------------------------------------------

	local following = true
	local friendSeated = false
	task.spawn(function()
		while scene.Parent do
			local root = kit.playerRoot()
			if following and root then
				local from = friend.root.Position
				local gap = kit.flatDistance(root.Position, from)
				if gap > 6 then
					local direction = Vector3.new(root.Position.X - from.X, 0, root.Position.Z - from.Z).Unit
					local target = from + direction * math.min(gap - 4, 7)
					-- step up onto the restaurant floor when going through the door
					friend.y = (target.Z < layout.DoorZ and FLOOR_INSIDE or GROUND) + friendStandingOffset
					ctx.walkTo(friend, target.X, target.Z)
				else
					task.wait(0.3)
				end
			else
				task.wait(0.3)
			end
		end
	end)

	------------------------------------------------------------------
	-- The table: benches to sit on, the menu, the dishes, the bill
	------------------------------------------------------------------

	local tableModel = scene.MainTable
	local top = tableModel.Top
	local benches = { A = tableModel.BenchA, B = tableModel.BenchB }
	local prompts = {}
	local playerSeated = false
	local onTable = {} -- dishes
	local billPart = nil

	local function showMenu()
		-- a card standing in the middle of the table, readable from both benches
		local card = kit.prop(scene, Enum.PartType.Block, Vector3.new(3, 2.4, 0.1),
			CFrame.new(top.Position.X - 1.2, layout.TableTopY + 1.2, top.Position.Z), Color3.fromRGB(35, 30, 45))
		for _, face in { Enum.NormalId.Front, Enum.NormalId.Back } do
			local gui = create("SurfaceGui", {
				Face = face, SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud, PixelsPerStud = 60, LightInfluence = 0,
			}, card)
			create("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder }, gui)
			create("TextLabel", {
				Text = info.RestaurantName, Font = Enum.Font.FredokaOne, TextColor3 = Color3.fromRGB(255, 225, 150), TextScaled = true,
				BackgroundTransparency = 1, Size = UDim2.fromScale(1, 0.19), LayoutOrder = 0,
			}, gui)
			for index, item in info.Items do
				local row = create("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 0.135), LayoutOrder = index }, gui)
				create("TextLabel", {
					Text = info.ItemName(learn.code, item.id), Font = Enum.Font.GothamMedium, TextColor3 = WHITE, TextScaled = true,
					TextXAlignment = Enum.TextXAlignment.Left, BackgroundTransparency = 1, Position = UDim2.fromScale(0.06, 0.1), Size = UDim2.fromScale(0.66, 0.8),
				}, row)
				create("TextLabel", {
					Text = "$" .. item.price, Font = Enum.Font.GothamBold, TextColor3 = Color3.fromRGB(255, 220, 70), TextScaled = true,
					TextXAlignment = Enum.TextXAlignment.Right, BackgroundTransparency = 1, Position = UDim2.fromScale(0.74, 0.1), Size = UDim2.fromScale(0.2, 0.8),
				}, row)
			end
		end
		ctx.burst(card.Position, "Sparkles", 16)
	end

	local function placeDishes(items)
		for _, part in onTable do
			part:Destroy()
		end
		table.clear(onTable)
		-- three places along each side of the table
		local slots = {}
		for _, side in { 1, -1 } do
			for _, dx in { 1.4, 0.2, 2.5 } do
				table.insert(slots, Vector3.new(top.Position.X + dx - 0.6, layout.TableTopY, top.Position.Z + side * 1.15))
			end
		end
		local slot = 0
		for _, entry in items do
			for _ = 1, entry.quantity do
				slot += 1
				local at = slots[slot]
				if at then
					for _, part in buildDish(kit, scene, entry.id, at) do
						table.insert(onTable, part)
					end
					ctx.burst(at + Vector3.new(0, 0.4, 0), "Sparkles", 8)
				end
			end
		end
	end

	-- Walks the waitress along the centre aisle to somewhere in the room
	local function waitressTo(point, facing)
		ctx.walkTo(waitress, 0, waitress.root.Position.Z) -- out to the aisle
		ctx.walkTo(waitress, 0, point.Z) -- along it
		ctx.walkTo(waitress, point.X, point.Z)
		if facing then
			ctx.faceDirection(waitress, facing)
		end
	end
	local AT_TABLE_FACING = Vector3.new(-1, 0, 0) -- standing at the table, facing the guests
	local AT_DOOR_FACING = Vector3.new(0, 0, 1)

	local function sitDown(key)
		if playerSeated then
			return
		end
		local bench = benches[key]
		local other = benches[key == "A" and "B" or "A"]
		local seatPosition = Vector3.new(bench.Position.X, layout.BenchTopY + 2.4, bench.Position.Z)
		if not kit.sitPlayer(seatPosition, top.Position) then
			return
		end
		playerSeated = true
		stage = "seated"
		for _, prompt in prompts do
			prompt:Destroy()
		end
		ctx.debugLog("sat down at the table")

		task.spawn(function()
			-- the friend takes the bench across the table
			following = false
			while friend.moving do
				task.wait(0.1)
			end
			friend.y = FLOOR_INSIDE + friendStandingOffset
			ctx.walkTo(friend, layout.TableStand.X, other.Position.Z)
			ctx.walkTo(friend, other.Position.X + 1.2, other.Position.Z)
			local friendSeat = Vector3.new(other.Position.X + 1.2, layout.SeatedRootY, other.Position.Z)
			kit.seatNpc(friend, friendSeat, Vector3.new(0, 0, top.Position.Z - other.Position.Z).Unit)
			friendSeated = true

			-- menus, then a moment to choose
			showMenu()
			kit.request(waitressCharacter, "at_table")
			task.wait(1)
			kit.request(friendCharacter, "seated")

			waitressTo(layout.HostSpot, AT_DOOR_FACING)
			task.wait(15)
			if stage == "seated" then
				waitressTo(layout.TableStand, AT_TABLE_FACING)
				if stage == "seated" then
					kit.request(waitressCharacter, "ready_to_order")
				end
			end
		end)
	end

	local function leadToTable()
		stage = "led"
		kit.walkPath(waitress, layout.ToTable)
		ctx.faceDirection(waitress, AT_TABLE_FACING)
		waitress.actionGesture = "point" -- showing them the table
		waitress.lookAtPoint = top.Position
		task.delay(3, function()
			waitress.actionGesture = nil
			waitress.lookAtPoint = nil
		end)
		for key, bench in benches do
			local prompt = create("ProximityPrompt", {
				ActionText = kit.text("sit"), ObjectText = "", HoldDuration = 0, MaxActivationDistance = 8, RequiresLineOfSight = false,
			}, bench)
			prompt.Triggered:Connect(function()
				sitDown(key)
			end)
			table.insert(prompts, prompt)
		end
	end

	local function serveOrder(items)
		stage = "ordered"
		task.spawn(function()
			task.wait(2)
			kit.request(friendCharacter, "ordered")
		end)
		-- to the kitchen and back
		kit.walkPath(waitress, { Vector3.new(0, 0, waitress.root.Position.Z), table.unpack(layout.ToKitchen) })
		ctx.faceDirection(waitress, Vector3.new(0, 0, -1))
		waitress.workGesture = "cook" -- waiting at the kitchen pass
		task.wait(7)
		waitress.workGesture = "carry"
		ctx.walkTo(waitress, 0, waitress.root.Position.Z)
		waitressTo(layout.TableStand, AT_TABLE_FACING)
		waitress.workGesture = "idle"
		placeDishes(items)
		ctx.playSound("Bell")
		kit.request(waitressCharacter, "food_served", items)
		stage = "served"
		task.wait(2)
		kit.request(friendCharacter, "food_served")
		waitressTo(layout.HostSpot, AT_DOOR_FACING)
	end

	local function bringBill()
		waitressTo(layout.TableStand, AT_TABLE_FACING)
		billPart = kit.prop(scene, Enum.PartType.Block, Vector3.new(0.9, 0.08, 1.3),
			CFrame.new(top.Position.X + 2.4, layout.TableTopY + 0.04, top.Position.Z), Color3.fromRGB(25, 25, 30))
		ctx.burst(billPart.Position, "Sparkles", 10)
		stage = "bill"
		kit.request(waitressCharacter, "bill")
	end

	local function finishPayment()
		stage = "paid"
		ctx.playSound("Register")
		if billPart then
			ctx.burst(billPart.Position, "Sparkles", 24)
			billPart:Destroy()
			billPart = nil
		end
		ctx.debugLog("paid")
		task.wait(1.5)
		kit.request(friendCharacter, "paid")
		-- the friend gets up and tags along again on the way out
		if friendSeated then
			friendSeated = false
			kit.standNpc(friend, FLOOR_INSIDE + friendStandingOffset)
			ctx.walkTo(friend, layout.TableStand.X, friend.root.Position.Z)
		end
		following = true
		waitressTo(layout.HostSpot, AT_DOOR_FACING)
	end

	-- The waitress moves the evening on with the `step` that comes with her line.
	-- Each step is only accepted at the point in the evening where it makes sense.
	waitressCharacter.present = function(result, kind)
		kit.say(waitressCharacter, result.say, result.translation, kind)
		local step = result.step
		if step == "lead_to_table" and stage == "arrive" then
			task.spawn(leadToTable)
		elseif step == "order_taken" and stage == "seated" and result.items and #result.items > 0 then
			task.spawn(serveOrder, result.items)
		elseif step == "bring_bill" and stage == "served" then
			task.spawn(bringBill)
		elseif step == "paid" and stage == "bill" then
			task.spawn(finishPayment)
		end
	end

	-- The friend opens the evening, outside
	task.delay(2.5, function()
		kit.request(friendCharacter, "arrive")
	end)

	kit.start()
	ctx.debugLog("dinner ready")
end

---------------------------------------------------------------------

function Scenes.run(scenarioId, ctx)
	local kit = newKit(ctx)
	if scenarioId == "airplane" then
		runAirplane(ctx, kit)
	elseif scenarioId == "dinner" then
		runDinner(ctx, kit)
	else
		ctx.debugLog("unknown scenario: " .. tostring(scenarioId))
	end
end

return Scenes
