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
| `src/ReplicatedStorage/LingoFood.luau` | Food items the player can hold and eat |
| `src/ServerScriptService/LingoServer.server.luau` | Spawns the character and calls the Claude API for the characters' lines |
| `src/Workspace/WindService.luau` | Wind effect |

The buildings, characters and food models are not scripts, so they are not in `src/`; they live in the Roblox place itself.

## API key

The server reads the Claude API key from a Roblox secret named `ANTHROPIC_API_KEY` (Creator Hub > Secrets). No key is stored in this repo.
