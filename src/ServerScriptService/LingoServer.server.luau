-- Server side of the language-practice game. Only two jobs live here, because
-- Roblox does not allow them on the client:
--   1. Spawning the player's character once they finish the intro screen.
--   2. Asking the Claude API for an NPC's next line (web requests and secrets
--      are server-only).
-- Everything else (intro screen, building, NPC movement and animation, microphone,
-- voices, music and effects) runs in StarterPlayerScripts.LingoClient.
--
-- Setup needed once:
--   Creator Hub > your game > Secrets: name ANTHROPIC_API_KEY, domain api.anthropic.com
--   Studio tests: Experience Settings > Security > Local Secrets (same name)

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Data = require(ReplicatedStorage:WaitForChild("LingoData"))
local Remotes = ReplicatedStorage:WaitForChild("LingoRemotes")
local startScenario = Remotes:WaitForChild("StartScenario")
local npcGenerate = Remotes:WaitForChild("NpcGenerate")
local returnToMenu = Remotes:WaitForChild("ReturnToMenu")

local CLAUDE = {
	Model = "claude-opus-5-5",
	Effort = "low", -- keeps replies quick for a spoken conversation
	MaxTokens = 4000,
	SecretName = "ANTHROPIC_API_KEY",
	MaxHistoryMessages = 40,
}

local API_URL = "https://api.anthropic.com/v1/messages"
local API_VERSION = "2026-10-21"
-- Lets the API hand a declined request to a fallback model instead of failing
local FALLBACK_BETA = "server-side-fallback-2026-07-01"

local MAX_SPEECH_LENGTH = 500
local MIN_SECONDS_BETWEEN_REQUESTS = 0.5
local RESPAWN_DELAY = 3

local SCENARIOS = { fastfood = true, airplane = true, dinner = true }

-- [player] = { main = languageTable, learn = languageTable, scenario = string, histories = { [npcId] = {...} } }
local sessions = {}
local lastRequest = {}

---------------------------------------------------------------------
-- Character spawning (CharacterAutoLoads is off so the intro shows first)
---------------------------------------------------------------------

Players.CharacterAutoLoads = false

local function onCharacterAdded(player, character)
	local humanoid = character:WaitForChild("Humanoid", 10)
	if not humanoid then
		return
	end
	humanoid.Died:Once(function()
		task.wait(RESPAWN_DELAY)
		if player.Parent and sessions[player] then
			player:LoadCharacter()
		end
	end)
end

Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(function(character)
		onCharacterAdded(player, character)
	end)
end)

Players.PlayerRemoving:Connect(function(player)
	sessions[player] = nil
	lastRequest[player] = nil
end)

startScenario.OnServerEvent:Connect(function(player, mainCode, learnCode, scenarioId)
	local main = type(mainCode) == "string" and Data.LanguageByCode[mainCode]
	local learn = type(learnCode) == "string" and Data.LanguageByCode[learnCode]
	if not main or not learn or main == learn or not SCENARIOS[scenarioId] then
		warn("[LingoServer] bad StartScenario request from", player.Name)
		return
	end

	sessions[player] = { main = main, learn = learn, scenario = scenarioId, histories = {} }
	player:SetAttribute("MainLanguage", main.code)
	player:SetAttribute("LearnLanguage", learn.code)
	player:SetAttribute("Scenario", scenarioId)
	player:LoadCharacter()
end)

-- Back to the main menu: forget the scenario and take the character away,
-- so the player is on the intro screen with no character, as when they joined.
returnToMenu.OnServerEvent:Connect(function(player)
	sessions[player] = nil
	lastRequest[player] = nil
	player:SetAttribute("Scenario", nil)
	local character = player.Character
	if character then
		player.Character = nil
		character:Destroy()
	end
end)

---------------------------------------------------------------------
-- Reply formats (Claude answers in JSON that matches one of these)
---------------------------------------------------------------------

local function objectSchema(properties, required)
	return { type = "object", properties = properties, required = required, additionalProperties = false }
end

local MENU_IDS = {}
for _, item in Data.FastFood.Menu do
	table.insert(MENU_IDS, item.id)
end

-- Things a character can physically do when the player asks (LingoClient acts them out)
local ACTIONS = { "none", "follow", "come", "stop", "go_away", "dance", "wave", "point" }
-- Places a character can point at
local POINT_TARGETS = { "none", "counter", "menu", "pickup", "kitchen", "door", "tables", "guide" }
local ACTION_FIELD = { type = "string", enum = ACTIONS }
local POINT_FIELD = { type = "string", enum = POINT_TARGETS }

-- Cashier: a line, and the order once it is confirmed
local ORDER_SCHEMA = objectSchema({
	say = { type = "string" },
	action = ACTION_FIELD,
	point_at = POINT_FIELD,
	order_complete = { type = "boolean" },
	items = {
		type = "array",
		items = objectSchema({ id = { type = "string", enum = MENU_IDS }, quantity = { type = "integer" } }, { "id", "quantity" }),
	},
}, { "say", "action", "point_at", "order_complete", "items" })

-- Cook, cleaner and the regular customer: a line, and maybe something to do
local STAFF_SCHEMA = objectSchema({ say = { type = "string" }, action = ACTION_FIELD, point_at = POINT_FIELD }, { "say", "action", "point_at" })

-- Staff talking to each other: two or three short lines
local EXCHANGE_SCHEMA = objectSchema({
	lines = {
		type = "array",
		items = objectSchema({
			speaker = { type = "string", enum = { "cashier", "cook", "cleaner", "customer" } },
			say = { type = "string" },
		}, { "speaker", "say" }),
	},
}, { "lines" })

-- Lumi the guide: an explanation, the phrase being taught, and whether the learner
-- asked for translations to be switched on or off
local TUTOR_SCHEMA = objectSchema({
	say = { type = "string" },
	phrase = { type = "string" },
	translations = { type = "string", enum = { "unchanged", "on", "off" } },
	menu = { type = "boolean" },
}, { "say", "phrase", "translations", "menu" })

-- Copies of the staff formats with a `translation` of each line added. Used only
-- while the learner has asked Lumi to switch translations on.
local function withTranslation(schema)
	local properties = table.clone(schema.properties)
	properties.translation = { type = "string" }
	local required = table.clone(schema.required)
	table.insert(required, "translation")
	return objectSchema(properties, required)
end

local ORDER_SCHEMA_TRANSLATED = withTranslation(ORDER_SCHEMA)
local STAFF_SCHEMA_TRANSLATED = withTranslation(STAFF_SCHEMA)
local EXCHANGE_SCHEMA_TRANSLATED = objectSchema({
	lines = {
		type = "array",
		items = objectSchema({
			speaker = { type = "string", enum = { "cashier", "cook", "cleaner", "customer" } },
			say = { type = "string" },
			translation = { type = "string" },
		}, { "speaker", "say", "translation" }),
	},
}, { "lines" })

local TRANSLATED = {
	[ORDER_SCHEMA] = ORDER_SCHEMA_TRANSLATED,
	[STAFF_SCHEMA] = STAFF_SCHEMA_TRANSLATED,
	[EXCHANGE_SCHEMA] = EXCHANGE_SCHEMA_TRANSLATED,
}

-- Added to a prompt while translations are on
local function translationRule(session)
	return string.format("\nTranslation (`translation`): a faithful translation of `say` into %s. The game shows it underneath your words as a caption. It is never spoken, and it does not mean you speak or understand %s.\n",
		session.main.english, session.main.english)
end

---------------------------------------------------------------------
-- Prompts
---------------------------------------------------------------------

local function menuText(session, withIds)
	local fastFood = Data.FastFood
	local lines = {}
	for _, item in fastFood.Menu do
		local name = string.format("%s (%s), %d dollars", fastFood.ItemName(session.learn.code, item.id), fastFood.ItemName("en", item.id), item.price)
		table.insert(lines, withIds and ("- id " .. item.id .. ": " .. name) or ("- " .. name))
	end
	return table.concat(lines, "\n")
end

-- Rules shared by everyone who works inside the restaurant
local function staffRules(session)
	local learn, main = session.learn.english, session.main.english
	return string.format([[
The customer is here to practise %s. Their main language is %s.

What you say (`say`): always in %s, in simple, natural, everyday sentences a learner can follow. It is read aloud by a text-to-speech voice, so no emojis, stage directions, lists or quotation marks, and write numbers and prices as words.

Keep it short, the way people really talk. This is a quick back-and-forth, not a speech: say one thing and let the customer answer. Most turns are a single short sentence or just a few words, under 80 characters, like a real reply across a counter. Answer what was asked and stop; do not add extra facts, explanations, or a second topic. Do not end every turn with a question, only ask when you actually need an answer. Go up to two sentences only when you truly have to, such as reading an order back with its total.

You do not speak or understand %s at all, so never use a single word of it in `say`. If the customer says something in it, tell them kindly, in %s, that you only speak %s, and encourage them to try again.

Messages in parentheses are scene directions telling you what is happening in the restaurant; they are not something the customer said. The customer's words reach you through speech recognition that guesses the language of every utterance, and for short answers it often guesses wrong: a %s word can arrive written as a similar-sounding word, letter or number from another language. A Spanish yes, for example, often arrives as the letter C or as the word see. So before reacting, sound out what arrived and ask yourself whether it sounds like something a %s speaker would say at this point in the conversation. If it does, that is what they said: answer it normally, and do not treat it as another language. Only ask them to repeat when nothing fits.

What you do (`action`): you have a body, and the customer may ask you to do something with it. Your character really does whatever you put here, so make `say` match it. On ordinary turns use none.
- follow: walk along behind the customer until told to stop.
- come: walk over to where the customer is standing.
- stop: stop following and go back to what you were doing.
- go_away: walk off and leave the customer alone, when they tell you to go away or to leave them alone.
- dance: do a little dance on the spot.
- wave: wave at them.
- point: point at a place so they can see where it is. Set `point_at` to the place: counter (where orders are taken), menu (the menu board), pickup (where finished orders are handed over), kitchen, door (the entrance), tables (the dining tables) or guide (the floating guide outside). On every other action `point_at` is none.
Decide the way your character would in that moment. A playful request such as a dance is usually fine. If you are in the middle of something you cannot walk away from (an order being taken or prepared, food on the grill, sitting at a table with them), politely say you cannot right now and use none. When you are giving directions to somewhere in the restaurant, point at it.

Stay in character and keep it friendly and family-appropriate.
]], learn, main, learn, main, learn, learn, learn, learn)
end

local function cashierPrompt(session)
	local fastFood = Data.FastFood
	return string.format([[
You are %s, a friendly cashier at %s, a fast food restaurant. You are speaking out loud with one customer at the counter. %s the cook is in the kitchen behind you.

%s
The menu (the only things you sell):
%s

How the visit goes: greet the customer, ask what they would like, answer questions about the menu, take the order, repeat it back with the total price and ask them to confirm.

Orders (`order_complete`, `items`): on the one turn where the customer confirms their whole order, set `order_complete` to true and list every item with its quantity in `items`, and tell them it will be ready in a moment. On every other turn `order_complete` is false and `items` is empty. An order can have at most %d items in total; if they ask for more, explain the limit.
]], fastFood.CashierName, fastFood.RestaurantName, fastFood.CookName, staffRules(session), menuText(session, true), fastFood.MaxItemsPerOrder)
end

local function cookPrompt(session)
	local fastFood = Data.FastFood
	return string.format([[
You are %s, the cook at %s, a fast food restaurant. You work in the kitchen behind the counter: the grill, the fryer, the pizza oven, the drinks machine and the ice cream freezer. A customer has come over to chat with you while you work.

You love your job. Talk about what you are cooking, how the food is made, the ingredients, your favourite thing on the menu, how busy the day is. You do not take orders or handle money: if they want to order, send them to %s, the cashier at the counter.

%s
The menu:
%s
]], fastFood.CookName, fastFood.RestaurantName, fastFood.CashierName, staffRules(session), menuText(session, false))
end

local function cleanerPrompt(session)
	local fastFood = Data.FastFood
	return string.format([[
You are %s, who keeps the dining room of %s, a fast food restaurant, clean and tidy, mop in hand. A customer has stopped to chat with you.

You know the place well: the counter and %s the cashier are straight ahead from the door, the menu board hangs above the right side of the counter, finished orders are handed over at the right end of the counter, there are tables on both sides, %s the cook is in the kitchen at the back, and %s the guide floats outside the entrance and teaches useful phrases. Make small talk and help them find things. You do not take orders: send them to %s for that.

%s
The menu:
%s
]], fastFood.CleanerName, fastFood.RestaurantName, fastFood.CashierName, fastFood.CookName, Data.TutorName, fastFood.CashierName,
		staffRules(session), menuText(session, false))
end

local function customerPrompt(session)
	local fastFood = Data.FastFood
	return string.format([[
You are %s, a friendly regular at %s, a fast food restaurant. You are hanging around the dining room, in no hurry. Another customer has come over to talk with you.

Chat like a friendly stranger: what is good on the menu, what you usually order, how your day is going, small talk. If they sit down at a table you happily sit across from them and keep them company. You do not work here: for ordering, point them to %s, the cashier at the counter.

%s
The menu:
%s
]], fastFood.CustomerName, fastFood.RestaurantName, fastFood.CashierName, staffRules(session), menuText(session, false))
end

-- Lumi is the one character who speaks the learner's own language
local function tutorPrompt(session)
	local fastFood = Data.FastFood
	local learn, main = session.learn.english, session.main.english
	return string.format([[
You are %s, a cheerful floating ball of light who helps language learners. You hover outside %s, a fast food restaurant, and talk out loud with one learner before they go in.

The learner's own language is %s. They are about to practise %s by ordering food from the cashier inside. Everyone who works in there speaks only %s.

Your job: teach them the words and phrases they will need in there (greeting, ordering, the menu items, quantities, asking the price, please and thank you, confirming the order, saying goodbye), a little at a time, and answer their questions about how to say things. If they try saying a phrase, tell them how they did and what to fix. Their words reach you through speech recognition that guesses the language of every utterance and often gets short ones wrong, so a phrase they tried may arrive as similar-sounding words, letters or numbers from another language. Judge an attempt by how it sounds, treat a close match as a good try, and put small slips down to the recognition rather than to them.

Your reply has two parts:
- `say`: what you say to the learner, in %s only. Keep it short like real conversation: usually one warm sentence, under 100 characters, two only when an explanation truly needs it. Teach one thing per turn and let the learner respond. It is read aloud by a %s text-to-speech voice, so do not put any %s words in it; refer to "this phrase" instead. No emojis, lists or quotation marks.
- `phrase`: the single %s word or short phrase you are teaching this turn (at most ten words), written exactly as the learner should say it. It is read aloud right after `say` by a %s voice. Use an empty string when there is nothing to teach this turn.
- `translations`: the learner can ask you to show a translation into %s underneath what everyone in the restaurant says, and to take it away again. When they ask for that, set this to on or off and tell them it is done; on every other turn use unchanged. Translations are currently %s.
- `menu`: set this to true only when the learner asks to go back to the main menu (to leave, or to pick another language or scenario), and say a short goodbye in `say`. The game takes them back as soon as you have finished speaking. On every other turn it is false.

The restaurant's menu:
%s

Messages in parentheses are scene directions telling you what just happened; they are not something the learner said. Stay friendly, encouraging and family-appropriate.
]], Data.TutorName, fastFood.RestaurantName, main, learn, learn, main, main, learn, learn, learn, main,
		session.translations and "on" or "off", menuText(session, false))
end

---------------------------------------------------------------------
-- Claude API call
---------------------------------------------------------------------

local SECRET_HELP = "API key secret '" .. CLAUDE.SecretName .. "' not found. Add it in Creator Hub > Secrets "
	.. "(for Studio tests: Experience Settings > Security > Local Secrets)."

-- Returns the raw JSON text of the reply, or nil plus an error message.
local function callClaude(systemPrompt, messages, schema)
	local okSecret, apiKey = pcall(function()
		return HttpService:GetSecret(CLAUDE.SecretName)
	end)
	if not okSecret then
		return nil, SECRET_HELP
	end

	local body = HttpService:JSONEncode({
		model = CLAUDE.Model,
		max_tokens = CLAUDE.MaxTokens,
		system = systemPrompt,
		messages = messages,
		output_config = {
			effort = CLAUDE.Effort,
			format = { type = "json_schema", schema = schema },
		},
		fallbacks = "default",
	})

	local ok, response = pcall(function()
		return HttpService:RequestAsync({
			Url = API_URL,
			Method = "POST",
			Headers = {
				["content-type"] = "application/json",
				["x-api-key"] = apiKey,
				["anthropic-version"] = API_VERSION,
				["anthropic-beta"] = FALLBACK_BETA,
			},
			Body = body,
		})
	end)
	if not ok then
		local message = tostring(response)
		if string.find(string.lower(message), "secret", 1, true) then
			return nil, SECRET_HELP
		end
		return nil, "HTTP request failed: " .. message
	end

	local okJson, data = pcall(function()
		return HttpService:JSONDecode(response.Body)
	end)

	if not response.Success then
		local apiMessage = okJson and type(data) == "table" and type(data.error) == "table" and data.error.message
		return nil, string.format("Claude API error %d: %s", response.StatusCode, tostring(apiMessage or response.StatusMessage))
	end
	if not okJson or type(data) ~= "table" then
		return nil, "could not read Claude's response"
	end
	if data.stop_reason == "refusal" then
		return nil, "Claude declined to answer"
	end
	if data.stop_reason == "max_tokens" then
		return nil, "Claude's reply was cut off"
	end

	local parts = {}
	if type(data.content) == "table" then
		for _, block in data.content do
			if type(block) == "table" and block.type == "text" and type(block.text) == "string" then
				table.insert(parts, block.text)
			end
		end
	end
	local text = table.concat(parts)
	if text == "" then
		return nil, "Claude returned no text (stop_reason: " .. tostring(data.stop_reason) .. ")"
	end
	return text
end

---------------------------------------------------------------------
-- Who can be talked to, and how each request becomes a message
---------------------------------------------------------------------

-- Checks an item list sent by the client or returned by Claude.
local function cleanItems(items)
	local cleaned, total = {}, 0
	if type(items) ~= "table" then
		return cleaned
	end
	for _, entry in items do
		if type(entry) == "table" and Data.FastFood.MenuById[entry.id] and type(entry.quantity) == "number" then
			local quantity = math.clamp(math.floor(entry.quantity), 1, Data.FastFood.MaxItemsPerOrder - total)
			if quantity >= 1 then
				table.insert(cleaned, { id = entry.id, quantity = quantity })
				total += quantity
			end
		end
		if total >= Data.FastFood.MaxItemsPerOrder then
			break
		end
	end
	return cleaned
end

local function describeItems(items)
	local parts = {}
	for _, entry in items do
		table.insert(parts, string.format("%d x %s", entry.quantity, Data.FastFood.ItemName("en", entry.id)))
	end
	return table.concat(parts, ", ")
end

local function spokenText(payload)
	if type(payload) ~= "string" or payload == "" then
		return nil
	end
	return string.sub(payload, 1, MAX_SPEECH_LENGTH)
end

local function plainResult(reply)
	local action = table.find(ACTIONS, reply.action) and reply.action or "none"
	local pointAt = action == "point" and table.find(POINT_TARGETS, reply.point_at) and reply.point_at or "none"
	return { ok = true, say = reply.say, action = action, pointAt = pointAt }
end

local sceneTutorPrompt -- for the airplane and dinner scenarios; defined further down

-- The client only ever names an event; the scene directions are written here.
local NPCS = {
	cashier = {
		prompt = cashierPrompt,
		schema = ORDER_SCHEMA,
		message = function(kind, payload)
			if kind == "start" then
				return "(A customer has just walked up to the counter. Greet them and ask what they would like.)"
			elseif kind == "say" then
				return spokenText(payload)
			elseif kind == "food_ready" then
				local items = cleanItems(payload)
				if #items == 0 then
					return nil
				end
				return "(The cook has just put the customer's tray on the counter: " .. describeItems(items)
					.. ". Tell the customer their order is ready and that they can take their food from the tray.)"
			elseif kind == "tray_taken" then
				return "(The customer has started taking their food from the tray. Wish them a good meal. They may come back to order more.)"
			end
			return nil
		end,
		result = function(reply)
			local items = reply.order_complete == true and cleanItems(reply.items) or {}
			local result = plainResult(reply)
			result.orderComplete = #items > 0
			result.items = items
			return result
		end,
	},

	cook = {
		prompt = cookPrompt,
		schema = STAFF_SCHEMA,
		message = function(kind, payload, context)
			if kind == "start" then
				return "(A customer has just walked over to the kitchen. Say hello.)"
			elseif kind == "say" then
				local said = spokenText(payload)
				if not said then
					return nil
				end
				-- context = the order the cook is making right now, if any
				local cookingNow = cleanItems(context)
				if #cookingNow > 0 then
					return "(You are in the middle of cooking this order: " .. describeItems(cookingNow) .. ".)\n" .. said
				end
				return "(You have no order to cook right now.)\n" .. said
			end
			return nil
		end,
		result = plainResult,
	},

	cleaner = {
		prompt = cleanerPrompt,
		schema = STAFF_SCHEMA,
		message = function(kind, payload)
			if kind == "start" then
				return "(A customer has just walked over to you in the dining room. Say hello.)"
			elseif kind == "say" then
				return spokenText(payload)
			end
			return nil
		end,
		result = plainResult,
	},

	customer = {
		prompt = customerPrompt,
		schema = STAFF_SCHEMA,
		message = function(kind, payload, context)
			if kind == "start" then
				return "(Another customer has just walked over to you in the dining room. Say hello.)"
			elseif kind == "sit" then
				return "(The customer you met has sat down at a table, and you have just sat down across from them to keep them company. Say something friendly about sitting together.)"
			elseif kind == "say" then
				local said = spokenText(payload)
				if not said then
					return nil
				end
				if context == "seated" then
					return "(You are sitting at a table together.)\n" .. said
				end
				return said
			end
			return nil
		end,
		result = plainResult,
	},

	tutor = {
		prompt = function(session)
			return session.scenario == "fastfood" and tutorPrompt(session) or sceneTutorPrompt(session)
		end,
		schema = TUTOR_SCHEMA,
		message = function(kind, payload)
			if kind == "start" then
				return "(The learner has just walked up to you outside the restaurant. Greet them, say who you are in one sentence, and teach them a first useful phrase for ordering.)"
			elseif kind == "say" then
				return spokenText(payload)
			end
			return nil
		end,
		result = function(reply)
			return { ok = true, say = reply.say, phrase = type(reply.phrase) == "string" and reply.phrase or "" }
		end,
	},
}

---------------------------------------------------------------------
-- The airplane and dinner scenarios
---------------------------------------------------------------------

local SCENES = Data.Scenes

local function idsOf(scene)
	local ids = {}
	for _, item in scene.Items do
		table.insert(ids, item.id)
	end
	return ids
end

-- Checks an item list against a scene's own items
local function cleanSceneItems(items, scene)
	local cleaned, total = {}, 0
	if type(items) ~= "table" then
		return cleaned
	end
	for _, entry in items do
		if type(entry) == "table" and scene.ItemById[entry.id] and type(entry.quantity) == "number" then
			local quantity = math.clamp(math.floor(entry.quantity), 1, scene.MaxItems - total)
			if quantity >= 1 then
				table.insert(cleaned, { id = entry.id, quantity = quantity })
				total += quantity
			end
		end
		if total >= scene.MaxItems then
			break
		end
	end
	return cleaned
end

local function sceneItemName(scene, id, code)
	if scene.ItemName then
		return scene.ItemName(code, id)
	end
	return scene.ItemById[id].english
end

local function describeSceneItems(items, scene)
	local parts = {}
	for _, entry in items do
		table.insert(parts, string.format("%d x %s", entry.quantity, sceneItemName(scene, entry.id, "en")))
	end
	return table.concat(parts, ", ")
end

local function sceneItemList(session, scene)
	local lines = {}
	for _, item in scene.Items do
		local line = "- id " .. item.id .. ": " .. sceneItemName(scene, item.id, "en")
		if scene.ItemName then
			line ..= " (" .. scene.ItemName(session.learn.code, item.id) .. ")"
		end
		if item.price then
			line ..= ", " .. item.price .. " dollars"
		end
		table.insert(lines, line)
	end
	return table.concat(lines, "\n")
end

-- Rules shared by everyone the learner talks to in these scenarios
local function sceneRules(session)
	local learn, main = session.learn.english, session.main.english
	return string.format([[
The person you are talking to is here to practise %s. Their main language is %s.

What you say (`say`): always in %s, in simple, natural, everyday sentences a learner can follow. It is read aloud by a text-to-speech voice, so no emojis, stage directions, lists or quotation marks, and write numbers and prices as words.

Keep it short, the way people really talk. Say one thing and let them answer. Most turns are a single short sentence or just a few words, under 80 characters. Answer what was asked and stop. Do not end every turn with a question. Go up to two sentences only when you truly have to.

You do not speak or understand %s at all, so never use a single word of it in `say`. If they say something in it, tell them kindly, in %s, that you only speak %s, and encourage them to try again.

Messages in parentheses are scene directions telling you what is happening around you; they are not something the other person said. Their words reach you through speech recognition that guesses the language of every utterance, and for short answers it often guesses wrong: a %s word can arrive written as a similar-sounding word, letter or number from another language. So before reacting, sound out what arrived and ask yourself whether it sounds like something a %s speaker would say at this point. If it does, that is what they said: answer it normally. Only ask them to repeat when nothing fits.

Stay in character and keep it friendly and family-appropriate.
]], learn, main, learn, main, learn, learn, learn, learn)
end

local function itemArraySchema(scene)
	return {
		type = "array",
		items = objectSchema({ id = { type = "string", enum = idsOf(scene) }, quantity = { type = "integer" } }, { "id", "quantity" }),
	}
end

-- Passengers and the friend: just a line
local LINE_SCHEMA = objectSchema({ say = { type = "string" } }, { "say" })
-- Flight attendant: a line, and anything she is about to fetch
local ATTENDANT_SCHEMA = objectSchema({ say = { type = "string" }, serve = itemArraySchema(SCENES.airplane) }, { "say", "serve" })
-- Waitress: a line, the step of the evening it moves on to, and the order when it is taken
local WAITRESS_STEPS = { "none", "lead_to_table", "order_taken", "bring_bill", "paid" }
local WAITRESS_SCHEMA = objectSchema({
	say = { type = "string" },
	step = { type = "string", enum = WAITRESS_STEPS },
	items = itemArraySchema(SCENES.dinner),
}, { "say", "step", "items" })

TRANSLATED[LINE_SCHEMA] = withTranslation(LINE_SCHEMA)
TRANSLATED[ATTENDANT_SCHEMA] = withTranslation(ATTENDANT_SCHEMA)
TRANSLATED[WAITRESS_SCHEMA] = withTranslation(WAITRESS_SCHEMA)

local function lineResult(reply)
	return { ok = true, say = reply.say }
end

-- What part of the evening the dinner is at, as told by the client
local DINNER_STAGES = {
	arrive = "Your guests have just arrived and are by the door.",
	led = "You are showing the guests to their table.",
	seated = "The guests are sitting at their table with the menus.",
	ordered = "The guests have ordered and their food is being prepared.",
	served = "The guests have their food and are eating.",
	bill = "The bill is on the guests' table and has not been paid yet.",
	paid = "The guests have paid and are about to leave.",
}

local function withStage(context, said)
	local note = type(context) == "string" and DINNER_STAGES[context]
	return note and ("(" .. note .. ")\n" .. said) or said
end

------------------------------------------------------------------ airplane

NPCS.attendant = {
	prompt = function(session)
		local scene = SCENES.airplane
		return string.format([[
You are %s, a flight attendant on a %s flight, cruising high above the clouds. You are speaking out loud with one passenger, who is in their seat.

Look after them the way cabin crew do: welcome them aboard, offer something to drink or eat, answer questions about the flight (it is a smooth flight, about two hours to go, sunny at the destination, the galley is at the back and the toilets are at the front).

What you can bring, free of charge:
%s

Fetching things (`serve`): on the turn where the passenger has told you what they would like, list it in `serve` with quantities (at most %d things in total) and tell them you will be right back with it. On every other turn `serve` is empty.

%s]], scene.AttendantName, scene.AirlineName, sceneItemList(session, scene), scene.MaxItems, sceneRules(session))
	end,
	schema = ATTENDANT_SCHEMA,
	message = function(kind, payload)
		if kind == "start" then
			return "(A passenger has just sat down in their seat. You have walked up the aisle to them. Welcome them aboard and ask if they would like something to drink or eat.)"
		elseif kind == "say" then
			return spokenText(payload)
		elseif kind == "served" then
			local items = cleanSceneItems(payload, SCENES.airplane)
			if #items == 0 then
				return nil
			end
			return "(You have come back from the galley and put this on the passenger's tray table: "
				.. describeSceneItems(items, SCENES.airplane) .. ". Hand it over with a friendly word.)"
		end
		return nil
	end,
	result = function(reply)
		return { ok = true, say = reply.say, serve = cleanSceneItems(reply.serve, SCENES.airplane) }
	end,
}

local function passenger(nameKey, description)
	return {
		prompt = function(session)
			local scene = SCENES.airplane
			return string.format("You are %s, a passenger on a %s flight. %s\n\nChat like a friendly stranger on a plane: where they are going, where they are from, the flight, the food on board. You do not work for the airline: for drinks or food, point them to %s, the flight attendant.\n\n%s",
				scene[nameKey], scene.AirlineName, description, scene.AttendantName, sceneRules(session))
		end,
		schema = LINE_SCHEMA,
		message = function(kind, payload)
			if kind == "start" then
				return "(The passenger near you has turned to you. Say hello.)"
			elseif kind == "say" then
				return spokenText(payload)
			end
			return nil
		end,
		result = lineResult,
	}
end

NPCS.passenger_a = passenger("PassengerAName", "You are sitting across the aisle from another passenger, who has turned to talk to you. You are flying home to see your family, you love travelling, and you are in a cheerful mood.")
NPCS.passenger_b = passenger("PassengerBName", "You are in the window seat, right next to another passenger, who has turned to talk to you. You are on a work trip and a slightly nervous flyer, so a bit of conversation is welcome.")

------------------------------------------------------------------ dinner

NPCS.waitress = {
	prompt = function(session)
		local scene = SCENES.dinner
		return string.format([[
You are %s, a waitress at %s, a cosy restaurant. Two guests have come for dinner: the one you are talking with, and their friend %s, who leaves the ordering to them. You are speaking out loud with the guest.

The menu (the only things you serve):
%s

The evening moves on step by step, and you move it on with `step`:
- lead_to_table: you have greeted them at the door and they want a table. Tell them to follow you, and use this step on that turn.
- order_taken: at the table, once they have told you everything the two of them want and confirmed it, list it all in `items` with quantities (at most %d things in total), say it will be right out, and use this step.
- bring_bill: they ask for the bill. Say you will bring it, and use this step.
- paid: the bill is on the table and they pay, however they say they are paying. Thank them, wish them a good night, and use this step.
On every other turn `step` is none. `items` is empty except with order_taken.

%s]], scene.WaitressName, scene.RestaurantName, scene.FriendName, sceneItemList(session, scene), scene.MaxItems, sceneRules(session))
	end,
	schema = WAITRESS_SCHEMA,
	message = function(kind, payload, context, session)
		local scene = SCENES.dinner
		if kind == "start" then
			return "(Two guests have just walked in and come up to you by the door. Welcome them and ask if they would like a table for two.)"
		elseif kind == "say" then
			local said = spokenText(payload)
			return said and withStage(context, said) or nil
		elseif kind == "at_table" then
			return "(You have led them to their table and they are sitting down. Hand them the menus and say you will give them a moment to choose.)"
		elseif kind == "ready_to_order" then
			return "(You have come back to their table. Ask if they are ready to order.)"
		elseif kind == "food_served" then
			local items = cleanSceneItems(payload, scene)
			if #items == 0 then
				return nil
			end
			return "(You have just carried their food to the table: " .. describeSceneItems(items, scene) .. ". Serve it and wish them a good meal.)"
		elseif kind == "bill" then
			local total = 0
			for _, entry in session.dinnerOrder or {} do
				total += scene.ItemById[entry.id].price * entry.quantity
			end
			return "(You have put the bill on their table. The total is " .. total .. " dollars. Tell them the total.)"
		end
		return nil
	end,
	result = function(reply)
		local step = table.find(WAITRESS_STEPS, reply.step) and reply.step or "none"
		local items = step == "order_taken" and cleanSceneItems(reply.items, SCENES.dinner) or {}
		if step == "order_taken" and #items == 0 then
			step = "none" -- nothing was actually ordered
		end
		return { ok = true, say = reply.say, step = step, items = items }
	end,
	after = function(session, result)
		if result.step == "order_taken" then
			session.dinnerOrder = result.items -- remembered so the bill can be added up
		end
	end,
}

NPCS.friend = {
	prompt = function(session)
		local scene = SCENES.dinner
		return string.format([[
You are %s, a close friend of the person you are talking to. The two of you are having dinner together tonight at %s. You are relaxed, warm and a little funny, and you are speaking out loud with your friend.

Talk the way friends do over dinner: what looks good on the menu, how the week went, plans for the weekend. You are a guest too: %s the waitress takes the order, and you let your friend order for both of you, so if they ask what you want, pick something from the menu.

The menu:
%s

%s]], scene.FriendName, scene.RestaurantName, scene.WaitressName, sceneItemList(session, scene), sceneRules(session))
	end,
	schema = LINE_SCHEMA,
	message = function(kind, payload, context)
		if kind == "arrive" then
			return "(You and your friend have just arrived outside the restaurant. Say you are hungry and suggest going in.)"
		elseif kind == "seated" then
			return "(The two of you have just sat down at your table and the menus are in front of you. Say what looks good to you.)"
		elseif kind == "ordered" then
			return "(Your friend has just ordered for both of you and the waitress has gone to the kitchen. Make a little small talk while you wait.)"
		elseif kind == "food_served" then
			return "(The food has just arrived at your table. Say something about how it looks or tastes.)"
		elseif kind == "paid" then
			return "(The bill is paid. Thank your friend for a nice evening and suggest heading off.)"
		elseif kind == "say" then
			local said = spokenText(payload)
			return said and withStage(context, said) or nil
		end
		return nil
	end,
	result = lineResult,
}

------------------------------------------------------------------ Lumi in these scenarios

local TUTOR_SCENES = {
	airplane = function(session)
		local scene = SCENES.airplane
		return string.format("You float at the back of the cabin on a %s flight. The learner is about to take their seat and talk with %s the flight attendant and with the passengers around them.",
			scene.AirlineName, scene.AttendantName),
			"greeting the crew, asking for a drink or a snack, please and thank you, asking how long the flight is, asking where the toilet is, and small talk with another passenger (where are you going, where are you from)",
			"What the flight attendant can bring:\n" .. sceneItemList(session, scene)
	end,
	dinner = function(session)
		local scene = SCENES.dinner
		return string.format("You hover outside %s, a restaurant. The learner is about to have dinner there with their friend %s, and will talk with %s the waitress.",
			scene.RestaurantName, scene.FriendName, scene.WaitressName),
			"asking for a table for two, ordering food and drink, asking what is good, asking for the bill, paying, and chatting with a friend over dinner",
			"The restaurant's menu:\n" .. sceneItemList(session, scene)
	end,
}

function sceneTutorPrompt(session)
	local learn, main = session.learn.english, session.main.english
	local where, topics, extra = TUTOR_SCENES[session.scenario](session)
	return string.format([[
You are %s, a cheerful floating ball of light who helps language learners, and you talk out loud with one learner. %s

The learner's own language is %s. They are here to practise %s, and everyone else they meet speaks only %s.

Your job: teach them the words and phrases they will need (%s), a little at a time, and answer their questions about how to say things. If they try saying a phrase, tell them how they did and what to fix. Their words reach you through speech recognition that guesses the language of every utterance and often gets short ones wrong, so a phrase they tried may arrive as similar-sounding words, letters or numbers from another language. Judge an attempt by how it sounds, treat a close match as a good try, and put small slips down to the recognition rather than to them.

Your reply has three parts:
- `say`: what you say to the learner, in %s only. Keep it short like real conversation: usually one warm sentence, under 100 characters, two only when an explanation truly needs it. Teach one thing per turn and let the learner respond. It is read aloud by a %s text-to-speech voice, so do not put any %s words in it; refer to "this phrase" instead. No emojis, lists or quotation marks.
- `phrase`: the single %s word or short phrase you are teaching this turn (at most ten words), written exactly as the learner should say it. It is read aloud right after `say` by a %s voice. Use an empty string when there is nothing to teach this turn.
- `translations`: the learner can ask you to show a translation into %s underneath what everyone says, and to take it away again. When they ask for that, set this to on or off and tell them it is done; on every other turn use unchanged. Translations are currently %s.
- `menu`: set this to true only when the learner asks to go back to the main menu (to leave, or to pick another language or scenario), and say a short goodbye in `say`. The game takes them back as soon as you have finished speaking. On every other turn it is false.

%s

Messages in parentheses are scene directions telling you what just happened; they are not something the learner said. Stay friendly, encouraging and family-appropriate.
]], Data.TutorName, where, main, learn, learn, topics, main, main, learn, learn, learn, main,
		session.translations and "on" or "off", extra)
end

---------------------------------------------------------------------
-- Staff talking to each other (overheard by the player)
---------------------------------------------------------------------

local MAX_EXCHANGES_PER_SESSION = 25 -- each one is a paid API call

-- kind -> the two speakers and what is going on
local EXCHANGES = {
	order_called = function(payload)
		local items = cleanItems(payload)
		if #items == 0 then
			return nil
		end
		return { "cashier", "cook" }, "The cashier has just taken an order and calls it through to the cook in the kitchen: "
			.. describeItems(items) .. ". The cook answers briefly that it is coming right up."
	end,
	staff_chat = function()
		return { "cashier", "cook" }, "A quiet moment. The cashier and the cook swap a quick friendly remark about the shift, the food or how busy it is."
	end,
	dining_chat = function()
		return { "cleaner", "customer" }, "The cleaner, mopping the dining room, and the regular customer swap a quick friendly remark."
	end,
}

local function handleExchange(session, kind, payload)
	local build = EXCHANGES[kind]
	if not build then
		return { ok = false, err = "bad request" }
	end
	local speakers, situation = build(payload)
	if not speakers then
		return { ok = false, err = "bad request" }
	end
	session.exchanges = (session.exchanges or 0) + 1
	if session.exchanges > MAX_EXCHANGES_PER_SESSION then
		return { ok = false, err = "exchange limit reached" }
	end

	local fastFood = Data.FastFood
	local prompt = string.format([[
You write tiny, natural bits of dialogue between people at %s, a fast food restaurant, for a language learner to overhear. The people are %s the cashier (speaker id cashier), %s the cook (cook), %s the cleaner (cleaner) and %s, a regular customer (customer).

Write the exchange in %s only, in simple everyday sentences a learner can follow. Two lines, or three at most, each under 90 characters, alternating between the two speakers named in the situation and starting with the first one. Each line is read aloud by a text-to-speech voice, so no emojis, stage directions or quotation marks, and write numbers as words. Keep it friendly and family-appropriate.

The menu, for the names of the food:
%s
]], fastFood.RestaurantName, fastFood.CashierName, fastFood.CookName, fastFood.CleanerName, fastFood.CustomerName,
		session.learn.english, menuText(session, false))

	local replyJson, err = callClaude(prompt, {
		{ role = "user", content = "Situation: " .. situation .. " The two speakers are " .. speakers[1] .. " and " .. speakers[2] .. "."
			.. (session.translations and (" For each line also give `translation`: a faithful translation of it into " .. session.main.english .. ", shown as a caption and never spoken.") or "") },
	}, session.translations and EXCHANGE_SCHEMA_TRANSLATED or EXCHANGE_SCHEMA)
	if not replyJson then
		warn("[LingoServer] exchange:", err)
		return { ok = false, err = err }
	end

	local okDecode, decoded = pcall(function()
		return HttpService:JSONDecode(replyJson)
	end)
	local lines = {}
	if okDecode and type(decoded) == "table" and type(decoded.lines) == "table" then
		for _, line in decoded.lines do
			if type(line) == "table" and table.find(speakers, line.speaker) and type(line.say) == "string" and line.say ~= "" then
				table.insert(lines, {
					speaker = line.speaker, say = line.say,
					translation = session.translations and type(line.translation) == "string" and line.translation or nil,
				})
			end
			if #lines >= 3 then
				break
			end
		end
	end
	if #lines == 0 then
		return { ok = false, err = "Claude's reply was not in the expected format" }
	end
	return { ok = true, lines = lines }
end

npcGenerate.OnServerInvoke = function(player, npcId, kind, payload, context)
	local session = sessions[player]
	if not session then
		return { ok = false, err = "no scenario started" }
	end
	local npc = type(npcId) == "string" and NPCS[npcId]
	if not npc and npcId ~= "ambient" then
		return { ok = false, err = "unknown character" }
	end

	-- each character has its own rate limit, so talking to one never blocks another
	local now = os.clock()
	local playerRequests = lastRequest[player]
	if not playerRequests then
		playerRequests = {}
		lastRequest[player] = playerRequests
	end
	if playerRequests[npcId] and now - playerRequests[npcId] < MIN_SECONDS_BETWEEN_REQUESTS then
		return { ok = false, err = "too many requests" }
	end
	playerRequests[npcId] = now

	if npcId == "ambient" then
		return handleExchange(session, kind, payload)
	end

	local userMessage = npc.message(kind, payload, context, session)
	if not userMessage then
		return { ok = false, err = "bad request" }
	end

	if kind == "start" or not session.histories[npcId] then
		session.histories[npcId] = {}
	end
	local history = session.histories[npcId]
	table.insert(history, { role = "user", content = userMessage })

	-- while the learner has translations switched on, staff also return a translation of each line
	local translating = session.translations == true and TRANSLATED[npc.schema] ~= nil
	local systemPrompt = npc.prompt(session) .. (translating and translationRule(session) or "")
	local replyJson, err = callClaude(systemPrompt, history, translating and TRANSLATED[npc.schema] or npc.schema)
	local reply
	if replyJson then
		local okDecode, decoded = pcall(function()
			return HttpService:JSONDecode(replyJson)
		end)
		if okDecode and type(decoded) == "table" and type(decoded.say) == "string" and decoded.say ~= "" then
			reply = decoded
		else
			err = "Claude's reply was not in the expected format"
		end
	end

	if not reply then
		table.remove(history) -- keep the history alternating user / assistant
		warn("[LingoServer]", npcId, err)
		return { ok = false, err = err }
	end

	table.insert(history, { role = "assistant", content = replyJson })
	while #history > CLAUDE.MaxHistoryMessages do
		table.remove(history, 1)
		table.remove(history, 1)
	end

	local result = npc.result(reply)
	if npc.after then
		npc.after(session, result) -- lets a character remember something for later turns
	end
	if translating and type(reply.translation) == "string" and reply.translation ~= "" then
		result.translation = reply.translation
	end
	if npcId == "tutor" then
		-- Lumi switches translations on or off when the learner asks
		if reply.translations == "on" then
			session.translations = true
		elseif reply.translations == "off" then
			session.translations = false
		end
		result.translations = session.translations == true
		result.menu = reply.menu == true
	end
	return result
end
