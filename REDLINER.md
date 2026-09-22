# Redliner Script — Discontinued

**Status:** v1.0 Final Release — No Further Development

---

## Why

Redliner uses a custom packet system built on LZ4 compression and Base64 encoding,
routed through a single RemoteEvent rather than standard Roblox remotes.
This makes the parry system (F key) impossible to reverse engineer without
full module decompilation — which is outside the scope of this project.

The features we could confirm and build work well. The core feature (parry timing)
does not and cannot without significantly more reverse engineering time.
Rather than ship a half-built script indefinitely, we're calling v1.0 the final release.

---

## What Works in v1.0

- Aimlock with 5-frame weighted velocity prediction
- Team check via `is_teammate` character attribute
- Sticky aim and UUID lock (mutually exclusive)
- Nearest-to-death priority targeting
- Anti-aim detection (angular velocity threshold → HRP fallback)
- Hitbox expander (event-driven, resets on death)
- Chams (enemy / locked / teammate colors)
- ESP (box, name, distance, health bar, target circle, tracer)
- FOV circle with 3 color states (idle / acquiring / locked)
- Lock indicator label
- Silent aim (hookmetamethod — effectiveness unconfirmed on Redliner)
- Auto-shoot trigger
- Auto-click
- Kill notification + session counter
- Speed hack, walk speed, jump power sliders
- Infinite jump
- Anti-AFK
- Fullbright
- Remove fog
- Config save/load via Obsidian SaveManager

---

## What Was Attempted

- Parry system (F key) — requires cracking the LZ4/Base64 packet schema
- RakNet packet analysis — packets captured but schema unknown
- Remote hook — PacketEvent and Main remote identified, payload unreadable

---

## Confirmed Recon Data

```
team detection:    char:GetAttribute("is_teammate") == true
weapon detection:  char child Model with GetAttribute("item_id")
confirmed weapons: Castigate, Redliner, Carmine3P, Neo3P
main remote:       ReplicatedStorage.Assets.RemoteEvents.Main
packet remote:     ReplicatedStorage.Assets.ModuleScripts.Packets.Packet.PacketEvent
packet encoding:   LZ4 + Base64 — schema unknown
parry key:         F
```

---

## UI Library

Obsidian by deividcomsono
https://github.com/deividcomsono/Obsidian

---

*This script is open source. Fork it, build on it, crack the packet system if you can.*
*We moved on to better targets.*

# It was a good run, we are ceasing devlopment for our redliner script for good.
