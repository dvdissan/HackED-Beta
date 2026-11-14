# HackED-Beta
HackED Beta Submission

**HelloWorld** is a Roblox VR game for practising a language out loud. You pick the language you speak, the language you want to practise and a scenario (fast food restaurant, airplane, dinner out), then talk by voice with AI characters who only speak the language you are learning.

## What is in this repo

`src/` holds the game's scripts, exported from the Roblox Studio place. The folders mirror where each script lives in Studio:

| File | What it does |
| --- | --- |
| `src/StarterPlayer/StarterPlayerScripts/LingoClient.client.luau` | Intro menu, fast food scenario, NPC movement, speech-to-text, text-to-speech, music and effects |
| `src/StarterPlayer/StarterPlayerScripts/VRHandsOnly.client.luau` | VR body display |
| `src/ReplicatedStorage/LingoScenes.luau` | Airplane and dinner scenarios |
| `src/ReplicatedStorage/LingoData.luau` | Languages, UI translations, menus, layout coordinates, sound ids |
| `src/ReplicatedStorage/LingoFood.luau` | Food and drink: every item is official Roblox gear, equipped as a real Tool and eaten bite by bite |
| `src/ServerScriptService/LingoServer.server.luau` | Spawns the character and calls the Claude API for the characters' lines |
| `src/Workspace/WindService.luau` | Wind effect |

`place/` holds everything else — the buildings, characters, food models, lighting and the scripts again — as one Roblox model file per service:

| File | Goes into |
| --- | --- |
| `place/Workspace.rbxm` | Workspace (baseplate, spawn, wind) |
| `place/ReplicatedStorage.rbxm` | ReplicatedStorage (scenario builds, food, modules, remotes) |
| `place/ServerScriptService.rbxm` | ServerScriptService |
| `place/StarterPlayer.rbxm` | StarterPlayer (the two script folders) |
| `place/Lighting.rbxm` | Lighting (sky, atmosphere, effects) |
| `place/ServerStorage.rbxm` | ServerStorage (archived earlier builds and imported food tools; not needed to run the game) |

To rebuild the game in a new place: open Roblox Studio, right-click each service in the Explorer, choose **Insert from File…** and pick the matching file. Then turn on **Allow HTTP Requests** in Game Settings > Security, set `Players.CharacterAutoLoads` to off and `Workspace.StreamingEnabled` to off.

## API key

The server reads the Claude API key from a Roblox secret named `ANTHROPIC_API_KEY` (Creator Hub > Secrets). No key is stored in this repo.
