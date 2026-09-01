<div align="center">

# Cell - NeRgY Fork

### Continued development of Cell raid frames for World of Warcraft

<img src="https://img.shields.io/github/v/release/NeeRgY/Cell?style=for-the-badge" />
<img src="https://img.shields.io/github/last-commit/NeeRgY/Cell?style=for-the-badge" />
<img src="https://img.shields.io/github/issues/NeeRgY/Cell?style=for-the-badge" />
<img src="https://img.shields.io/github/stars/NeeRgY/Cell?style=for-the-badge" />
<br><br>

[![ko-fi](https://ko-fi.com/img/githubbutton_sm.svg)](https://ko-fi.com/neergy)

**This is a community fork. Donations / tips support my maintenance, not the original Cell authors.**



[![Discord](https://img.shields.io/discord/1122747237546610760?style=for-the-badge&label=Discord&color=5865F2)](https://discord.gg/9PSe3fKQGJ)

For help, feel free to join the official Discord server here. I'm usually very active there.

---
<br>

A maintained fork of **Cell**, continued from **Krysio (krysiolol)** / jdtoppin, originally by **enderneko**.

Focused on Midnight compatibility, healer QoL, Classic/TBC & MoP support, and practical fixes that keep raid frames usable in modern WoW.


**Current version:** `r277.9.8.4`


</div>

---

# About This Fork

This repository is maintained by **NeRgY**.

Lineage:

1. [enderneko/Cell](https://github.com/enderneko/Cell) — original Cell
2. [jdtoppin/Cell](https://github.com/jdtoppin/Cell) — Skyking / intermediate fork
3. [krysiolol/Cell](https://github.com/krysiolol/Cell) — Krysio Midnight fork (`r277.7.5.3-krysio`)
4. **NeRgY** — continued from Krysio and extended further

Goals of this fork:

- Keep Cell working on **Retail Midnight (12.1.0)**
- Improve **Classic Era / Hardcore**, **TBC Classic** and **MoP** usability
- Ship healer-focused QoL (Actions, Raid Debuffs, Import UX, options integration)
- Preserve Krysio's Midnight foundation while fixing regressions and filling gaps
- Stay practical: prefer stable, testable changes over experiments

> This is **NOT** the official Cell repository.

---

# Original Project Credits

Huge credit to everyone this build stands on:

- Original Cell: https://github.com/enderneko/Cell
- Skyking / jdtoppin: https://github.com/jdtoppin/Cell
- Krysio fork: https://github.com/krysiolol/Cell

Without their work, this fork would not exist.

---

# Supported Clients

| Client | Status |
|--------|--------|
| Retail Midnight (`12.1.0`) | Primary focus |
| Classic Era / Hardcore (`1.15.9`) | Supported |
| TBC Classic (Anniversary) (`2.5.6`) | Supported |
| MoP Classic (`5.5.4`) | Supported |
| Wotlk / Cata  | TOC present; not the main focus of this branch |

---

## NeRgY Fork Highlights

### Retail / Midnight

- **Hide Blizzard Party / Raid:** more stable, fewer errors in raids and alongside other addons
- **Solo power bars:** fixed a rare update error
- **Bar Animation → Smooth restored:** health and power bars animate smoothly again (Legacy stays immediate)
- **Out of Range Alpha:** frames correctly fade when out of range again (Retail + Classic)
- Built on Krysio's Midnight foundation (Secret Aura Fingerprint, HandleBuff, Aura Blacklist, Midnight Tools, Locale Override, Comm guards, Private Dispel work)
- Extra aura helpers (`Utils_Auras`) for safer timing/stacks/meta binding
- Party utilities updated for 12.0.7+ (`C_PartyInfo` ready check / role poll)
- **Indicators → Actions:** Midnight potion defaults  
  - Silvermoon Health Potion  
  - Light's Potential  
  - Existing profiles migrated automatically
- **Raid Debuffs:** Season 1 raids verified/updated  
  - The Voidspire  
  - The Dreamrift  
  - March on Quel'Danas  
  - Sporefall (Rotmire)

### Classic Era / TBC

- Clearer profile Import UX (errors, whitespace stripping, chat feedback)
- About Import moved up; Layouts Import warns on full-profile strings
- Fixed Import/About crashes when addon version metadata is missing
- **Out of Range Alpha fixed:** frames correctly fade when out of range again

### Options & UX

- Cell page under **Esc → Options → AddOns** (icon, version, credits, Open Options)
- Minimap button (left-click opens options, drag to move; toggle under General)

### Known limitations (Blizzard API)

- **Targeted Spells** remain internally disabled (same as Krysio)
- **Raid Debuffs** still work for **readable** spell IDs; true Private/Secret auras need the Private Auras indicator

---

# Installation

## Recommended Installation

Download the latest release here:

### Releases
https://github.com/NeeRgY/Cell/releases

and copy the `Cell` folder into:

Retail: `World of Warcraft\_retail_\Interface\AddOns\Cell`

Classic: `World of Warcraft\_classic_era_\Interface\AddOns\Cell`

TBC: `World of Warcraft\_anniversary_\Interface\AddOns\Cell`

Then `/reload` in-game.

---

## Important

Do **NOT** download:

- `Source code (zip)`
- `Source code (tar.gz)`

---


# Philosophy

This fork prioritizes:

- healer usability
- modern WoW compatibility (especially Midnight)
- fixing real pain points (import, range, potions, raid debuffs)
- keeping Classic/TBC playable on the same codebase

Expect:

- behavior differences vs official Cell
- occasional breaking changes after Blizzard API updates
- features that may stay fork-only

---

# Contributing

Bug reports, fixes, ideas and suggestions are welcome.

When reporting an issue, please include:

- WoW version / client (Retail, Classic Era, TBC, MoP)
- Addon version (`r277.8.2` etc.)
- Lua errors (BugSack / `/console scriptErrors 1`)
- Reproduction steps

---

# Known Differences From Upstream / Krysio

This fork may:

- include additional QoL not present upstream
- migrate profile data automatically (e.g. Actions potion IDs)
- diverge further over time as NeRgY continues maintenance

---

# Roadmap

- Keep Midnight raid frames stable across patches
- If everything works well, create a version for Season 2 (Patch 12.1.0).
- Continue Classic / TBC support
- Refresh Raid Debuffs when new encounters/patches land
- More QoL updates
- More bug fixes
- Support for other WoW versions, such as MoP

---

# Support

## GitHub Issues
https://github.com/NeeRgY/Cell/issues

## Repository
https://github.com/NeeRgY/Cell

## Krysio (upstream fork base)
https://github.com/krysiolol/Cell

## Official Cell
https://github.com/enderneko/Cell

---

# Maintainer

<div align="center">

## NeRgY

Continuing Cell for healers across Retail Midnight, Classic Era, TBC and MoP.

</div>

---

# Credits

## Original Authors
- enderneko
- jdtoppin
- Cell contributors

## Previous Fork Maintainer
- krysiolol (Krysio)

## Current Fork Maintainer
- NeRgY

## Community
Thanks to testers, healers and UI nerds who report bugs and share profiles.

---

# Disclaimer

This project is unofficial and is not affiliated with Blizzard Entertainment.

World of Warcraft is a trademark of Blizzard Entertainment.

Use this addon at your own discretion.

---

<div align="center">

</div>
