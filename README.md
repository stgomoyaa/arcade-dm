# Arcade DM

*One plugin. Your bot match becomes a ranked aim trainer.*

**An all-in-one arcade deathmatch mod for Counter-Strike 1.6 and Condition Zero: 11 ranks, two independent ladders, 22 medals and a five line killfeed, in a single 1,770 line AMX Mod X plugin with no external dependencies.**

![license](https://img.shields.io/badge/license-MIT-green) ![amxx](https://img.shields.io/badge/AMX%20Mod%20X-1.9%2B-blue) ![game](https://img.shields.io/badge/game-CS%201.6%20%2F%20CZ-orange)

[The ladder](#the-ladder) · [What it does](#what-it-does) · [Install](#install) · [Bots](#bots) · [Cvars](#cvars) · [HUD channels](#hud-channels) · [What this does not do](#what-this-does-not-do) · [Credits](#credits)

Built for playing alone against bots, as a warmup before a modern tactical shooter. It turns a local listen server into something with progression, rewards and constant feedback, without a server, an account or a database.

## The ladder

Two ladders run at once and they measure different things. Points measure how dominant you are. Aim measures how well you shoot, and it does not drop when you die.

| Rank | Tag | Points | Aim rating | Bonus per kill |
|---|---|---|---|---|
| Iron | `IRN` | 0 | 0 | 0 |
| Bronze | `BRZ` | 100 | 40 | 0 |
| Silver | `SIL` | 250 | 47 | 1 |
| Gold | `GLD` | 500 | 53 | 2 |
| Platinum | `PLT` | 900 | 58 | 3 |
| Diamond | `DIA` | 1,500 | 63 | 5 |
| Master | `MAS` | 2,300 | 68 | 7 |
| Grandmaster | `GM` | 3,400 | 73 | 10 |
| **CHAMPION** | `CHM` | 5,000 | 78 | 14 |
| **KING** | `KNG` | 15,000 | 84 | 20 |
| **DEITY** | `DTY` | 40,000 | 90 | 30 |

Iron through Grandmaster carry divisions I, II and III. The top three ranks swap divisions for a numbered ladder: CHAMPION places you nationally from #15000 down to #1, KING regionally, DEITY globally.

The aim rating is a moving average of four things, not one:

- **Headshot rate**, calibrated against real competitive CS percentages.
- **Time to kill**, from first contact to the kill.
- **Stopping discipline**, your velocity on the shot that kills, which is the counter-strafe.
- **Shot economy**, hits needed per kill, with a different bar per weapon.

The top three aim ranks are not reachable on headshot rate alone. All four have to be there.

> [!NOTE]
> Every threshold in that table is read from `RANK_MIN`, `AIM_MIN` and `RANK_KILL_BONUS` in the source. Nothing here is rounded for presentation.

## What it does

**Real FFA.** GoldSrc cuts damage between teammates to roughly 35%. The plugin compensates so everyone hits for full, removes teamkill warnings and punishments, fixes the scoreboard and clears friendlies off the radar.

**Its own killfeed.** Five colour coded lines replacing the game's monochrome one: your kills in gold, headshots in orange, your deaths in red, background noise in grey. Every line carries both players' rank tags.

**Synchronised combos.** Double, Triple, Ultra, Monster, Ludicrous, Holy Shit, Wicked Sick, Kill Chain. The sound, the banner, the medal and the buff all come out of one table, so they fire on the same frame with the same name.

**Streak rewards.**

| Trigger | Reward |
|---|---|
| 4 fast kills | Vampire: every kill heals you until you die |
| 5 fast kills (Monster) | Vampire++: also refills the magazine on every kill |
| 9 fast kills (Chain) | Bullet time: bots drop to 40% speed for 5 seconds |
| 15 streak | UAV: wallhack ESP, one sweep every 5 seconds for a minute |
| 30 streak | NUKE: the map goes down and every kill counts for you |

**22 Black Ops II style medals** with point bonuses, a **32 rival leaderboard** that progresses alongside you, a **nemesis** (the bot that kills you most), a **killcam** on death, auto equipment, bunnyhop and floating damage numbers.

## Install

Requires **AMX Mod X 1.9 or newer** with the `fun`, `engine`, `fakemeta`, `hamsandwich`, `cstrike` and `nvault` modules enabled in `configs/modules.ini`.

1. Copy `addons/amxmodx/plugins/arcade_dm.amxx` into `cstrike/addons/amxmodx/plugins/`.
2. Append `arcade_dm.amxx` to `cstrike/addons/amxmodx/configs/plugins.ini`.
3. Copy the contents of `configs/listenserver.cfg` into your `cstrike/listenserver.cfg`.
4. Optional: drop the `.wav` files into `cstrike/sound/AQS/`. Without them the mod runs identically, just silent.

To compile from source:

```bash
amxxpc addons/amxmodx/scripting/arcade_dm.sma -o addons/amxmodx/plugins/arcade_dm.amxx
```

## Bots

The plugin ships no bots. Use whichever you already have.

- **CS 1.6:** [YaPB](https://github.com/yapb/yapb) is the recommended option and is compatible with the current game build. The plugin adjusts `yb_difficulty` to follow your aim rank, capped so the arcade pace survives.
- **Condition Zero:** the native ZBots work with nothing extra.

> [!WARNING]
> On the current CS 1.6 build (post anniversary), old bot packs that replace `mp.dll` with 2006 binaries **crash the game**. Use YaPB or ReGameDLL, not those packs.

## Cvars

| Cvar | Default | What it does |
|---|---|---|
| `adm_ffa` | 1 | Full damage between teams, no teamkill warnings, clean radar |
| `adm_killfeed` | 1 | Custom killfeed (0 leaves the game's own) |
| `adm_equip` | 1 | Automatic weapons on respawn |
| `adm_bhop` | 1 | Automatic bunnyhop |
| `adm_sounds` | 1 | Quake style voice announcements |
| `adm_damage_numbers` | 1 | Floating damage numbers |
| `adm_streaks` | 1 | Vampire, bullet time, UAV and nuke |
| `adm_adaptive_bots` | 1 | Bot difficulty follows your aim rating (capped at 2 of 4) |

Type **`guns`** in chat to change your loadout: 10 primaries, 5 secondaries, remembered for the session.

## HUD channels

GoldSrc has only 16 message channels, and any plugin using automatic channel selection (`-1`) can paint over another. This mod pins them:

```
 1  persistent status        6-9   killfeed
 2  point popups             10    (free)
 3  panels (tables)          11    combo banner
 4  large announcements      12    active buffs
 5  animations               13    damage numbers
                             14-15 (free)
```

If you add another HUD plugin, give it one of the free channels. Two rules learned the hard way:

- **Never use `-1`.** Automatic selection can land on a channel this mod already owns and blank it. Several stock AMX Mod X plugins do this — `timeleft`, `adminchat`, `statsx` — and the symptom is the status block vanishing for a second at a time.
- **Do not re-send the same channel more than a few times per second.** Re-sending restarts the message client side, which reads as flicker. The status block here is only re-sent when its text actually changes, and at most every 0.35 s.

## What this does not do

- **It is built for a listen server against bots.** Nothing in it is designed or tested for a populated dedicated server. Progression is local, held in `nvault`, and the 32 leaderboard rivals are simulated, not real players.
- **It ships no bots and no sounds.** Both are third party, and the sound pack is somebody else's work under its own terms. The mod degrades cleanly without either.
- **It occupies 15 of the 16 GoldSrc HUD channels.** That is most of the budget. Any other HUD plugin has to fit in what is left, and there is no negotiation at runtime.
- **The national, regional and global ladders are flavour, not a network.** CHAMPION through DEITY place you on a numbered ladder computed locally. There is no server aggregating players.
- **Only tested on the current CS 1.6 build and Condition Zero.** No claim is made about ReHLDS variants, older builds, or CS: Online forks.
- **The aim rating is opinionated.** Its thresholds were calibrated against competitive CS headshot percentages, which is a judgement call, not a measurement of you against a population.

## Credits

- **Vampire:** based on the *Vampire* plugin by **Shalfey** (2007), turned into a persistent buff here.
- **Wallhack ESP:** technique from **DarkGL**'s ESP in *AmxX Cheats*. The marker projects onto the wall the trace hits, because beams occlude against geometry.
- **Damage numbers:** adapted from **LyesMC**'s *Rotating DMG 6-dir HUD*.
- **Sounds:** the *AdvancedQuakeSounds* pack by **ClaudiuHKS**, available [here](https://github.com/ClaudiuHKS/AdvancedQuakeSounds). Files used: `doublekill`, `triplekill`, `ultrakill`, `monsterkill`, `ludicrouskill`, `holyshit`, `whickedsick`, `comboking`, `impressive`, `payback`, `shutdown`, `flawlessvictory`.
- Ranks, ladder, medals, combos, killfeed, bullet time and the aim rating system are original to this project.

## License

MIT. See [LICENSE](LICENSE). Third-party attributions are in [NOTICE.md](NOTICE.md).
