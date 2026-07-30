/*
 *  ============================================================================
 *   ARCADE DM  --  all-in-one arcade deathmatch for Counter-Strike 1.6 / CZ
 *  ============================================================================
 *
 *  A single plugin holding the whole mod: real FFA, custom killfeed, ranked
 *  ladders, medals, killstreak rewards, Quake-style announcer, auto weapons,
 *  bunnyhop and floating damage numbers.
 *
 *  Built for playing alone against bots (YaPB / ZBot) as aim practice with the
 *  dopamine of an arcade. All human-player state is stored in nvault and
 *  survives between sessions.
 *
 *  --------------------------------------------------------------------------
 *  WHAT IT DOES
 *  --------------------------------------------------------------------------
 *   FFA          GoldSrc cuts friendly-fire damage to ~35%; this scales it
 *                back so everyone hits equally. No teamkill warnings, no
 *                punishments, corrected score, clean radar.
 *   KILLFEED     Custom and multicolored (your kills gold, headshots amber,
 *                your deaths red) showing each player's rank.
 *   RANKS        Iron -> ... -> Grandmaster (divisions I/II/III), then
 *                CHAMPION / KING / DEITY with a national / regional / global
 *                ladder running from #15000 down to #1. Top #1 global grants
 *                prestige and restarts the climb with a permanent bonus.
 *   AIM RANK     Separate ladder based on the QUALITY of every kill: headshot,
 *                time-to-kill, stop discipline (counter-strafe) and shot
 *                economy (one tap).
 *   MEDALS       22 Black Ops II style medals with point bonuses.
 *   COMBOS       Double / triple / ultra / monster kill... with sound, banner
 *                and medal fired from ONE table, always in sync.
 *   STREAKS      Vampire (4 fast kills), Vampire++ (5, refills your gun),
 *                bullet time (9), UAV with see-through-walls ESP (streak 15)
 *                and NUKE (streak 30).
 *   EXTRA        Auto loadout, bunnyhop, floating damage numbers, leaderboard
 *                with rivals, nemesis tracking and killcam.
 *
 *  --------------------------------------------------------------------------
 *  REQUIREMENTS
 *  --------------------------------------------------------------------------
 *   AMX Mod X 1.9+ with modules: fun, engine, fakemeta, hamsandwich, cstrike,
 *   nvault.  Optional sounds go in sound/AQS (see README).
 *
 *  --------------------------------------------------------------------------
 *  HUD CHANNELS  (the engine only has 16 -- split so nothing overlaps)
 *  --------------------------------------------------------------------------
 *   1 status   2 toasts   3 panels   4 announcements   5 animation
 *   6-10 killfeed   11 combo banner   12 active buffs   13-15 damage numbers
 *
 *  MIT licensed. Credits in the README.
 */

#include <amxmodx>
#include <amxmisc>
#include <fun>
#include <engine>
#include <fakemeta>
#include <hamsandwich>
#include <cstrike>
#include <xs>
#include <nvault>

#define PLUGIN_NAME    "Arcade DM"
#define PLUGIN_VERSION "1.0.0"
#define PLUGIN_AUTHOR  "Arcade DM contributors"

// ============================================================================
//  TUNING
// ============================================================================

#define GAIN_KILL       5
#define GAIN_HS         8
#define DEATH_LOSS     10

#define VAMP_FAST       4      // ULTRA KILL   -> vampire
#define MONSTER_FAST    5      // MONSTER KILL -> evolved vampire
#define CHAIN_BULLET    9      // KILL CHAIN   -> bullet time
#define VAMP_HEAL      15
#define VAMP_HEAL2     22
#define VAMP_MAX      100
#define UAV_STREAK     15
#define NUKE_STREAK    30
#define BULLET_TIME    5.0
#define BULLET_SLOW    0.40

#define UAV_TICK        0.2
#define UAV_TICKS     300      // 300 x 0.2 s = one minute

#define FEED_LINES      5
#define FEED_HOLD       5.0
#define RIVALS         32

#define TASK_UI      90210
#define TASK_HUD     90211
#define TASK_TIME    90212
#define TASK_FEED    90213
#define TASK_UAV     90214
#define TASK_NUKE    90215
#define TASK_STATUS  90216
#define TASK_BULLET  90217
#define TASK_BULEND  90218

// ============================================================================
//  UI  --  style tokens and animation runtime
// ============================================================================

enum _:UiColors {
    UI_GOLD = 0, UI_AMBER, UI_DANGER, UI_MUTED, UI_TEXT,
    UI_INFO, UI_SUCCESS, UI_LEGEND, UI_DIM
}

new const UI_PALETTE[UiColors][3] = {
    {255,215,  0}, {255,130, 30}, {255, 70, 70}, {140,152,168}, {255,255,255},
    {200,230,255}, { 80,255,120}, {255,235, 90}, { 60, 60, 70}
}

enum _:UiSlots {
    UI_SLOT_HUD = 0, UI_SLOT_TOAST, UI_SLOT_BANNER, UI_SLOT_BOARD,
    UI_SLOT_FEED, UI_SLOT_FEEDBAN, UI_SLOT_STATUS
}

new const Float:UI_POS[UiSlots][2] = {
    { 0.02, 0.18 }, { 0.55, 0.40 }, { -1.0, 0.30 }, { 0.02, 0.50 },
    { 0.60, 0.045 }, { 0.58, 0.010 }, { 0.02, 0.33 }
}

#define UI_CH_HUD      1
#define UI_CH_TOAST    2
#define UI_CH_BOARD    3
#define UI_CH_BANNER   4
#define UI_CH_ANIM     5
#define UI_CH_FEED     6      // 6..10
#define UI_CH_FEEDBAN 11
#define UI_CH_STATUS  12
#define UI_CH_DAMAGE  13      // 13..15

#define UI_TICK        0.1
#define UI_ANIM_PULSE  0
#define UI_ANIM_RISE   1
#define UI_MAX_ANIM    4
#define UI_TEXT_LEN   96

enum _:UiAnimRec {
    UA_ON, UA_ID, UA_CH, UA_TYPE,
    Float:UA_T, Float:UA_DUR, Float:UA_X, Float:UA_Y,
    UA_CA, UA_CB, UA_TXT[UI_TEXT_LEN]
}
new g_anim[UI_MAX_ANIM][UiAnimRec]

// ============================================================================
//  RANKS
// ============================================================================

enum _:ArcRanks {
    RK_IRON = 0, RK_BRONZE, RK_SILVER, RK_GOLD, RK_PLATINUM, RK_DIAMOND,
    RK_MASTER, RK_GRANDMASTER, RK_CHAMPION, RK_KING, RK_DEITY, RK_COUNT
}

new const RANK_NAMES[RK_COUNT][] = {
    "Iron", "Bronze", "Silver", "Gold", "Platinum", "Diamond",
    "Master", "Grandmaster", "CHAMPION", "KING", "DEITY"
}
new const RANK_TAG[RK_COUNT][] = {
    "IRN","BRZ","SIL","GLD","PLT","DIA","MAS","GM","CHM","KNG","DTY"
}
new const RANK_MIN[RK_COUNT]    = { 0, 100, 250, 500, 900, 1500, 2300, 3400, 5000, 15000, 40000 }
new const LADDER_SPAN[RK_COUNT] = { 0,0,0,0,0,0,0,0, 10000, 25000, 60000 }
new const LADDER_SCOPE[RK_COUNT][] = { "","","","","","","","", "national", "regional", "global" }
new const RANK_KILL_BONUS[RK_COUNT] = { 0, 0, 1, 2, 3, 5, 7, 10, 14, 20, 30 }
new const ARC_DIVS[][] = { "I", "II", "III" }

/*
 * AIM RANK scale (0..100), calibrated against real competitive CS headshot
 * rates. With the per-kill base score (head 100 / body 30) a player relying on
 * headshot percentage alone lands around:
 *
 *   35% HS -> ~54  (public server average)
 *   45% HS -> ~61  (tryhard)
 *   55% HS -> ~68  (pro rifler level)
 *   65% HS -> ~75  (aim legend; ScreaM held 68% lifetime)
 *
 * The top three ranks are deliberately NOT reachable on headshots alone: they
 * also demand stop discipline and one-tap economy. Headshot rate in isolation
 * is a misleading metric, so the ceiling here requires all of it.
 */
new const AIM_MIN[RK_COUNT] = { 0, 40, 47, 53, 58, 63, 68, 73, 78, 84, 90 }

#define ARC_LADDER_TOP 15000
#define ARC_AIM_TOP     5000
#define ARC_AIM_KILLS     30   // minimum kills before showing a real aim rank

new const TOP_MILESTONES[] = { 10000, 5000, 2500, 1000, 500, 250, 100, 50, 10, 1 }

// ============================================================================
//  COMBOS  --  one table drives sound, banner, medal and buff
// ============================================================================

#define ARC_FAST_WINDOW 4.0
#define ARC_COMBO_MAX   9

new const COMBO_NAME[][] = {
    "", "", "DOUBLE KILL", "TRIPLE KILL", "ULTRA KILL", "MONSTER KILL",
    "LUDICROUS KILL", "HOLY SHIT", "WICKED SICK", "KILL CHAIN"
}
new const COMBO_SND[][] = {
    "", "", "AQS/doublekill", "AQS/triplekill", "AQS/ultrakill", "AQS/monsterkill",
    "AQS/ludicrouskill", "AQS/holyshit", "AQS/whickedsick", "AQS/comboking"
}

// ============================================================================
//  MEDALS
// ============================================================================

enum {
    MED_FIRSTBLOOD = 0, MED_BACKSTAB, MED_REVENGE, MED_SURVIVOR,
    MED_COMEBACK, MED_BUZZKILL, MED_LONGSHOT,
    MED_BLOODTHIRSTY, MED_MERCILESS, MED_RELENTLESS, MED_UNSTOPPABLE,
    MED_BRUTAL, MED_NUCLEAR, MED_UNTOUCHABLE,
    MED_C2, MED_C3, MED_C4, MED_C5, MED_C6, MED_C7, MED_C8, MED_C9,
    MED_TOTAL
}

new const MEDAL_NAMES[MED_TOTAL][] = {
    "First Blood", "Backstabber", "Revenge", "Survivor", "Comeback",
    "Buzzkill", "Long Shot", "Bloodthirsty", "Merciless", "Relentless",
    "Unstoppable", "Brutal", "NUCLEAR", "Untouchable",
    "DOUBLE KILL", "TRIPLE KILL", "ULTRA KILL", "MONSTER KILL",
    "LUDICROUS KILL", "HOLY SHIT", "WICKED SICK", "KILL CHAIN"
}
new const MEDAL_PTS[MED_TOTAL] = {
    5, 4, 3, 3, 3, 4, 4,
    5, 8, 10, 12, 15, 20, 10,
    2, 4, 6, 8, 10, 12, 15, 15
}

// ============================================================================
//  WEAPONS
// ============================================================================

new const MAXCLIP[] = {
    -1, 13, -1, 10, 1, 7, 1, 30, 30, 1, 30, 20, 25, 30, 35,
    25, 12, 20, 10, 30, 100, 8, 30, 30, 20, 2, 7, 30, 30, 1, 50
}
new const MAXBPAMMO[] = {
    -1, 52, -1, 90, 1, 32, 1, 100, 90, 1, 120, 100, 100, 90, 90,
    90, 100, 120, 30, 120, 200, 32, 90, 120, 90, 2, 35, 90, 90, 0, 100
}

new const PRIMARIES[][]  = { "AK-47","M4A1","AWP","MP5 Navy","Galil","Famas","SG552","AUG","Scout","M249" }
new const PRIM_ENT[][]   = { "weapon_ak47","weapon_m4a1","weapon_awp","weapon_mp5navy","weapon_galil","weapon_famas","weapon_sg552","weapon_aug","weapon_scout","weapon_m249" }
new const PRIM_CSW[]     = { CSW_AK47, CSW_M4A1, CSW_AWP, CSW_MP5NAVY, CSW_GALIL, CSW_FAMAS, CSW_SG552, CSW_AUG, CSW_SCOUT, CSW_M249 }
new const SECONDARIES[][]= { "Deagle","USP","Glock","Elite","Five-Seven" }
new const SEC_ENT[][]    = { "weapon_deagle","weapon_usp","weapon_glock18","weapon_elite","weapon_fiveseven" }
new const SEC_CSW[]      = { CSW_DEAGLE, CSW_USP, CSW_GLOCK18, CSW_ELITE, CSW_FIVESEVEN }

// ============================================================================
//  LEADERBOARD RIVALS  (edit freely: any 32 names work)
// ============================================================================

new const RIVAL_NAMES[RIVALS][24] = {
    "ak_Colo","xFrancoAWP","KrPa-","el_tio_sam","zLukaa","Dieg0x",
    "JuankyDinho","sharkhack","vrfernando750","RedOberyn","Dorinaldo",
    "Ignominious and Pale","RRRickZera","Cintya","AWPSHNIK","miklos",
    "calau","Lcapro ~ Ashaa-A","bling bling","Firestorm","Hyper",
    "Rado","vesslan","Lucchese","Bullseye","Alacakaranlik",
    "fan^^ r0KKKenNn","sOparik","Fantom","Traze se Admini !!!","Next","mouse"
}

// ============================================================================
//  STATE
// ============================================================================

new g_vault = INVALID_HANDLE
new g_human

// progression
new g_points, g_stars, g_rival[RIVALS]
new g_kills, g_deaths, g_hs, g_secs, g_stillKills, g_oneTaps
new g_medals[MED_TOTAL]
new Float:g_aim

// session
new g_streak, g_fastN, g_sessionKills, g_sessionSecs, g_deathRow, g_medalsSession
new Float:g_fastLast
new bool:g_anyKill
new g_deathToggle, g_saveTick, g_lastKiller, g_nemesis, g_killedBy[33]
new g_pStreak[33]

// aim tracking
new Float:g_firstHit[33], g_hits[33], Float:g_shotSpeed
new bool:g_shotGrounded

// weapons
new g_wpnName[20][20], g_wpnKills[20], g_wpnHs[20], g_wpnCount
new g_prim[33], g_sec[33]

// buffs
new g_vampTier, g_uavTick, g_beamSpr
new bool:g_bullet
new Float:g_baseSpeed[33]

// killfeed
new g_line[FEED_LINES][96], Float:g_expire[FEED_LINES], g_lineCol[FEED_LINES]
new bool:g_lineOn[FEED_LINES]

// damage numbers
new g_dmgDir[33]

// cvars
new g_pFFA, g_pFeed, g_pEquip, g_pBhop, g_pSounds, g_pDmgNum, g_pAdaptive, g_pStreaks

#define FL_GROUND (1<<9)

// ============================================================================
//  STARTUP
// ============================================================================

public plugin_init() {
    register_plugin(PLUGIN_NAME, PLUGIN_VERSION, PLUGIN_AUTHOR)

    g_pFFA      = register_cvar("adm_ffa", "1")
    g_pFeed     = register_cvar("adm_killfeed", "1")
    g_pEquip    = register_cvar("adm_equip", "1")
    g_pBhop     = register_cvar("adm_bhop", "1")
    g_pSounds   = register_cvar("adm_sounds", "1")
    g_pDmgNum   = register_cvar("adm_damage_numbers", "1")
    g_pStreaks  = register_cvar("adm_streaks", "1")
    g_pAdaptive = register_cvar("adm_adaptive_bots", "1")
    register_cvar("adm_version", PLUGIN_VERSION, FCVAR_SERVER)

    // a single death hook drives the entire mod
    register_message(get_user_msgid("DeathMsg"), "msg_death")
    register_message(get_user_msgid("TextMsg"), "msg_text")
    register_message(get_user_msgid("Radar"),   "msg_radar")

    RegisterHam(Ham_TakeDamage, "player", "ham_damage_pre",  0)
    RegisterHam(Ham_TakeDamage, "player", "ham_damage_post", 1)
    RegisterHam(Ham_Spawn,      "player", "ham_spawn_post",  1)

    register_clcmd("say",      "cmd_say")
    register_clcmd("say_team", "cmd_say")
    register_clcmd("say guns",  "cmd_guns")
    register_clcmd("say /guns", "cmd_guns")

    g_vault = nvault_open("arcade_dm")
    load_data()

    set_task(UI_TICK, "ui_pump",     TASK_UI,     _, _, "b")
    set_task(3.0,     "hud_tick",    TASK_HUD,    _, _, "b")
    set_task(10.0,    "time_tick",   TASK_TIME,   _, _, "b")
    set_task(0.3,     "feed_tick",   TASK_FEED,   _, _, "b")
    set_task(3.0,     "status_tick", TASK_STATUS, _, _, "b")
}

public plugin_precache() {
    g_beamSpr = precache_model("sprites/laserbeam.spr")
}

public plugin_end() {
    save_data()
    if (g_vault != INVALID_HANDLE)
        nvault_close(g_vault)
}

public client_putinserver(id) {
    g_prim[id] = 0
    g_sec[id]  = 0
    g_pStreak[id] = 0
    g_killedBy[id] = 0
    g_firstHit[id] = 0.0
    g_hits[id] = 0
    if (is_user_bot(id))
        g_prim[id] = random(sizeof(PRIMARIES) - 1)
    else if (!g_human)
        g_human = id
}

public client_disconnected(id) {
    if (id == g_human) {
        save_data()
        g_human = 0
        g_vampTier = 0
        remove_task(TASK_UAV)
    }
}

// ============================================================================
//  CORE: one death, every layer
// ============================================================================

public msg_death(msg_id, msg_dest, msg_entity) {
    new killer   = get_msg_arg_int(1)
    new victim   = get_msg_arg_int(2)
    new headshot = get_msg_arg_int(3)
    new wpn[20]
    get_msg_arg_string(4, wpn, charsmax(wpn))

    new victimStreak = (victim >= 1 && victim <= 32) ? g_pStreak[victim] : 0
    if (killer >= 1 && killer <= 32 && killer != victim)
        g_pStreak[killer]++
    if (victim >= 1 && victim <= 32)
        g_pStreak[victim] = 0

    new bool:wasFirst = !g_anyKill
    if (killer != victim)
        g_anyKill = true

    new Float:ttk = 0.0
    new myHits = 0
    if (victim >= 1 && victim <= 32) {
        if (killer == g_human && g_firstHit[victim] > 0.0)
            ttk = get_gametime() - g_firstHit[victim]
        if (killer == g_human)
            myHits = g_hits[victim]
        g_firstHit[victim] = 0.0
        g_hits[victim] = 0
    }

    if (get_pcvar_num(g_pFeed))
        feed_push(killer, victim, headshot, wpn)

    if (g_human && is_user_connected(g_human)) {
        if (killer == g_human && victim != g_human)
            on_my_kill(victim, headshot, wpn, ttk, myHits, wasFirst, victimStreak)
        else if (victim == g_human)
            on_my_death(killer, wpn)
    }

    // our killfeed replaces the stock one
    return get_pcvar_num(g_pFeed) ? PLUGIN_HANDLED : PLUGIN_CONTINUE
}

on_my_kill(victim, headshot, const wpn[], Float:ttk, hits, bool:wasFirst, victimStreak) {
    new gain = headshot ? GAIN_HS : GAIN_KILL
    new mlist[5], mcount = 0, bonus = 0

    // --- combo ---
    new Float:now = get_gametime()
    if (now - g_fastLast <= ARC_FAST_WINDOW) g_fastN++
    else                                     g_fastN = 1
    g_fastLast = now

    new ci = combo_idx(g_fastN)
    if (ci) {
        give_medal(MED_C2 + (ci - 2), mlist, mcount, bonus)
        if (get_pcvar_num(g_pFeed))
            combo_banner(ci)
        if (get_pcvar_num(g_pSounds))
            client_cmd(g_human, "spk %s", COMBO_SND[ci])
    }

    // --- streak ---
    g_streak++
    switch (g_streak) {
        case 5:  give_medal(MED_BLOODTHIRSTY, mlist, mcount, bonus)
        case 10: give_medal(MED_MERCILESS,    mlist, mcount, bonus)
        case 15: give_medal(MED_RELENTLESS,   mlist, mcount, bonus)
        case 20: give_medal(MED_UNSTOPPABLE,  mlist, mcount, bonus)
        case 25: give_medal(MED_BRUTAL,       mlist, mcount, bonus)
        case 30: give_medal(MED_NUCLEAR,      mlist, mcount, bonus)
        default: { if (g_streak > 30) give_medal(MED_UNTOUCHABLE, mlist, mcount, bonus); }
    }

    // --- situational ---
    if (wasFirst)            give_medal(MED_FIRSTBLOOD, mlist, mcount, bonus)
    if (equal(wpn, "knife")) give_medal(MED_BACKSTAB, mlist, mcount, bonus)
    if (g_lastKiller && victim == g_lastKiller) {
        give_medal(MED_REVENGE, mlist, mcount, bonus)
        g_lastKiller = 0
    }
    if (is_user_alive(g_human) && get_user_health(g_human) < 25)
        give_medal(MED_SURVIVOR, mlist, mcount, bonus)
    if (g_deathRow >= 3) give_medal(MED_COMEBACK, mlist, mcount, bonus)
    g_deathRow = 0
    if (victimStreak >= 5) give_medal(MED_BUZZKILL, mlist, mcount, bonus)
    if (is_user_connected(victim)) {
        new o1[3], o2[3]
        get_user_origin(g_human, o1)
        get_user_origin(victim, o2)
        if (get_distance(o1, o2) > 1800)
            give_medal(MED_LONGSHOT, mlist, mcount, bonus)
    }

    // --- aim rating ---
    aim_register(headshot, ttk, hits, wpn)

    // --- bonus for the victim's rank ---
    new vTier = -1, rankBonus = 0
    if (victim >= 1 && victim <= 32) {
        new vn[32]
        get_user_name(victim, vn, charsmax(vn))
        vTier = bot_tier(vn)
        rankBonus = RANK_KILL_BONUS[vTier]
    }

    // --- nemesis ---
    new nemBonus = 0
    if (g_nemesis && victim == g_nemesis) {
        nemBonus = 15
        ui_banner(g_human, UI_AMBER, 3.5, "^n  REVENGE SERVED  ^nhe had killed you %d times^n+%d pts", g_killedBy[g_nemesis], nemBonus)
        if (get_pcvar_num(g_pSounds)) client_cmd(g_human, "spk AQS/payback")
        g_killedBy[g_nemesis] = 0
        g_nemesis = 0
    }

    new oldRank = rank_idx(g_points), oldDiv = div_idx(g_points, oldRank)
    new oldAbove = rivals_above(), oldTop = ladder_top(g_points)

    gain += bonus + rankBonus + nemBonus
    gain = gain * (100 + 10 * g_stars) / 100        // prestige multiplier
    g_points += gain
    g_sessionKills++
    g_kills++
    if (headshot) g_hs++
    wpn_track(wpn, headshot)

    for (new i = 0; i < RIVALS; i++)
        if (random_num(0, 99) < 30)
            g_rival[i] += random_num(2, 8)

    // --- toast ---
    new pop[192], ln[48]
    formatex(pop, charsmax(pop), "+%d", gain)
    if (rankBonus > 0) {
        formatex(ln, charsmax(ln), "^n%s rival  +%d", RANK_NAMES[vTier], rankBonus)
        add(pop, charsmax(pop), ln)
    }
    for (new i = 0; i < mcount; i++) {
        formatex(ln, charsmax(ln), "^n%s +%d", MEDAL_NAMES[mlist[i]], MEDAL_PTS[mlist[i]])
        add(pop, charsmax(pop), ln)
    }
    if (mcount || rankBonus > 0)
        ui_text(g_human, UI_SLOT_TOAST, UI_GOLD, UI_CH_TOAST, 2.2, "%s", pop)
    else
        ui_toast(g_human, UI_SUCCESS, "%s", pop)

    // --- streak rewards ---
    if (get_pcvar_num(g_pStreaks)) {
        if (g_fastN >= MONSTER_FAST && g_vampTier < 2)     vamp_activate(2)
        else if (g_fastN >= VAMP_FAST && g_vampTier < 1)   vamp_activate(1)
        if (g_vampTier >= 1) vamp_on_kill()
        if (g_fastN >= CHAIN_BULLET) bullet_start()
        if (g_streak == UAV_STREAK)       reward_uav()
        else if (g_streak == NUKE_STREAK) reward_nuke()
    }

    if (g_sessionKills % 12 == 0)     show_weapons()
    else if (g_sessionKills % 5 == 0) show_board()

    announce(oldRank, oldDiv, oldAbove, oldTop, true)
    save_data()
    update_hud()
}

on_my_death(killer, const wpn[]) {
    new oldRank = rank_idx(g_points), oldDiv = div_idx(g_points, oldRank)
    new oldAbove = rivals_above(), oldTop = ladder_top(g_points)

    g_points = clamp_zero(g_points - DEATH_LOSS)
    g_deaths++
    g_streak = 0
    g_fastN  = 0
    g_deathRow++
    if (killer >= 1 && killer <= 32 && killer != g_human)
        g_lastKiller = killer

    ui_toast(g_human, UI_DANGER, "-%d", DEATH_LOSS)

    if (g_vampTier > 0) {
        ui_clear(g_human, UI_CH_STATUS)
        g_vampTier = 0
    }

    // killcam
    if (killer >= 1 && killer <= 32 && killer != g_human) {
        new kname[32], ktag[8], kwpn[20]
        get_user_name(killer, kname, charsmax(kname))
        copy(ktag, charsmax(ktag), RANK_TAG[bot_tier(kname)])
        copy(kwpn, charsmax(kwpn), wpn)
        strtoupper(kwpn)

        g_killedBy[killer]++
        new bool:newNem = false
        if (killer != g_nemesis && (!g_nemesis || g_killedBy[killer] > g_killedBy[g_nemesis])) {
            g_nemesis = killer
            newNem = true
        }
        if (killer == g_nemesis)
            ui_banner(g_human, UI_DANGER, 3.5, "^nKILLED BY^n[%s]  %s   with %s^n^n%s  (%d times)",
                ktag, kname, kwpn, newNem ? "NEW NEMESIS" : "YOUR NEMESIS", g_killedBy[killer])
        else
            ui_banner(g_human, UI_DANGER, 3.0, "^nKILLED BY^n[%s]  %s   with %s", ktag, kname, kwpn)
    }

    // rivals above you push harder when you die
    for (new i = 0; i < RIVALS; i++) {
        if (g_rival[i] > g_points) {
            if (random_num(0, 99) < 40) g_rival[i] += random_num(3, 8)
        } else if (random_num(0, 99) < 15) {
            g_rival[i] += random_num(2, 5)
        }
    }

    g_deathToggle = !g_deathToggle
    if (g_deathToggle) show_board()
    else               show_weapons()

    announce(oldRank, oldDiv, oldAbove, oldTop, false)
    save_data()
    update_hud()
}

// prioritized announcements: one banner per event
announce(oldRank, oldDiv, oldAbove, oldTop, bool:wasKill) {
    new newRank = rank_idx(g_points), newDiv = div_idx(g_points, newRank)
    new newTop  = ladder_top(g_points)
    new rname[48]
    rank_name(g_points, rname, charsmax(rname))

    if (newRank == RK_DEITY && newTop <= 1) {
        do_prestige()
        return
    }

    if (newRank > oldRank) {
        if (newRank >= RK_CHAMPION)
            ui_banner(g_human, UI_GOLD, 6.0, "^n  RANK UP  ^n^n>>  %s  <<^n^nYou enter the %s ranking^nfrom #%d down to #1",
                rname, LADDER_SCOPE[newRank], ARC_LADDER_TOP)
        else
            ui_banner(g_human, UI_GOLD, 4.0, "^n  RANK UP  ^n^n>>  %s  <<", rname)
        if (get_pcvar_num(g_pSounds)) client_cmd(g_human, "spk AQS/holyshit")
    }
    else if (newRank >= RK_CHAMPION && newTop < oldTop && top_milestone(oldTop, newTop)) {
        new th = top_milestone(oldTop, newTop)
        if (th == 1)
            ui_banner(g_human, UI_LEGEND, 5.0, "^n  TOP #1 %s  ", LADDER_SCOPE[newRank])
        else
            ui_banner(g_human, UI_LEGEND, 4.5, "^n  TOP #%d %s  ", th, LADDER_SCOPE[newRank])
        if (get_pcvar_num(g_pSounds)) client_cmd(g_human, "spk AQS/holyshit")
    }
    else if (newRank == oldRank && newDiv > oldDiv) {
        ui_banner(g_human, UI_INFO, 3.0, "Division cleared: %s", rname)
        if (get_pcvar_num(g_pSounds)) client_cmd(g_human, "spk AQS/impressive")
    }
    else if (newRank < oldRank) {
        ui_banner(g_human, UI_MUTED, 2.5, "Demoted to %s", rname)
    }
    else if (wasKill) {
        new nowAbove = rivals_above()
        if (nowAbove < oldAbove) {
            for (new i = 0; i < RIVALS; i++) {
                if (g_rival[i] <= g_points && g_rival[i] > g_points - 10) {
                    ui_banner(g_human, UI_AMBER, 3.0, "You passed %s!", RIVAL_NAMES[i])
                    if (get_pcvar_num(g_pSounds)) client_cmd(g_human, "spk AQS/shutdown")
                    break
                }
            }
        }
    }
}

// start over, but with a permanent star and a bigger payout
do_prestige() {
    g_stars++
    g_points = 0
    g_streak = 0
    for (new i = 0; i < RIVALS; i++)
        g_rival[i] = 50 + random_num(0, 450)
    save_data()
    ui_banner(g_human, UI_LEGEND, 8.0, "^n  * * *  P R E S T I G E   %d  * * *  ^nTop #1 global reached^nBack to Iron with a star^n+%d%% points forever",
        g_stars, g_stars * 10)
    if (get_pcvar_num(g_pSounds)) client_cmd(g_human, "spk AQS/flawlessvictory")
}

give_medal(medal, mlist[], &mcount, &bonus) {
    if (mcount >= 5) return
    mlist[mcount++] = medal
    bonus += MEDAL_PTS[medal]
    g_medals[medal]++
    g_medalsSession++
}

// ============================================================================
//  DAMAGE: FFA, aim tracking and floating numbers
// ============================================================================

public ham_damage_pre(victim, inflictor, attacker, Float:damage, bits) {
    if (attacker < 1 || attacker > 32 || attacker == victim || !is_user_connected(attacker))
        return HAM_IGNORED

    // FFA: the engine cuts friendly damage to ~35%, so scale it back up
    if (get_pcvar_num(g_pFFA) && get_user_team(attacker) == get_user_team(victim))
        SetHamParamFloat(4, damage * 2.857143)

    if (attacker == g_human && victim >= 1 && victim <= 32) {
        if (g_firstHit[victim] <= 0.0)
            g_firstHit[victim] = get_gametime()
        g_hits[victim]++

        // snapshot of your movement on this shot: basis for stop discipline
        new Float:vel[3]
        pev(g_human, pev_velocity, vel)
        g_shotSpeed = floatsqroot(vel[0] * vel[0] + vel[1] * vel[1])
        g_shotGrounded = (pev(g_human, pev_flags) & FL_GROUND) ? true : false
    }
    return HAM_IGNORED
}

public ham_damage_post(victim, inflictor, attacker, Float:damage, bits) {
    if (!get_pcvar_num(g_pDmgNum) || attacker != g_human || attacker == victim)
        return HAM_IGNORED
    if (!is_user_connected(attacker))
        return HAM_IGNORED

    new Float:x, Float:y
    switch (g_dmgDir[attacker]) {
        case 0: { x = 0.492; y = 0.35; }
        case 1: { x = 0.560; y = 0.40; }
        case 2: { x = 0.560; y = 0.55; }
        case 3: { x = 0.492; y = 0.60; }
        case 4: { x = 0.420; y = 0.55; }
        case 5: { x = 0.420; y = 0.40; }
    }

    // reserved channels 13..15: never steal the HUD or killfeed channels
    set_hudmessage(255, 190, 60, x, y, 0, 0.0, 0.5, 0.0, 0.2, UI_CH_DAMAGE + (g_dmgDir[attacker] % 3))
    show_hudmessage(attacker, "%d", floatround(damage))

    if (++g_dmgDir[attacker] > 5)
        g_dmgDir[attacker] = 0

    return HAM_IGNORED
}

// FFA: drop teamkill warnings and hide allies from the radar
public msg_text(msg_id, msg_dest, msg_entity) {
    if (!get_pcvar_num(g_pFFA))
        return PLUGIN_CONTINUE
    new m[32]
    get_msg_arg_string(2, m, charsmax(m))
    if (containi(m, "eammate") != -1 || containi(m, "friendly") != -1)
        return PLUGIN_HANDLED
    return PLUGIN_CONTINUE
}

public msg_radar(msg_id, msg_dest, msg_entity) {
    return get_pcvar_num(g_pFFA) ? PLUGIN_HANDLED : PLUGIN_CONTINUE
}

// ============================================================================
//  AIM RATING
// ============================================================================

/*
 * Hits a kill "should" cost with each weapon. A pistol is not judged like a
 * rifle: two hits with a USP is good economy, two with an AK is already spray.
 * Snipers and the Deagle are held to the single-shot standard.
 */
expected_shots(const wpn[]) {
    if (equal(wpn, "awp") || equal(wpn, "scout") || equal(wpn, "sg550") || equal(wpn, "g3sg1")) return 1
    if (equal(wpn, "deagle") || equal(wpn, "m3") || equal(wpn, "xm1014")) return 2
    if (equal(wpn, "ak47") || equal(wpn, "m4a1") || equal(wpn, "aug")
        || equal(wpn, "sg552") || equal(wpn, "galil") || equal(wpn, "famas")) return 2
    if (equal(wpn, "usp") || equal(wpn, "glock18") || equal(wpn, "p228")
        || equal(wpn, "fiveseven") || equal(wpn, "elite")) return 4
    if (equal(wpn, "mp5navy") || equal(wpn, "tmp") || equal(wpn, "mac10")
        || equal(wpn, "ump45") || equal(wpn, "p90")) return 5
    if (equal(wpn, "m249")) return 6
    return 3
}

/*
 * Quality of a single kill, fed into a slow moving average. Headshot leads;
 * execution speed, stop discipline and shot economy fine-tune it. Dying never
 * lowers it: this measures how you shoot, not how you survive.
 */
aim_register(headshot, Float:ttk, hits, const wpn[]) {
    new Float:q = headshot ? 100.0 : 30.0

    if (ttk > 0.0) {
        if (ttk < 0.7)      q += 8.0      // clean execution
        else if (ttk > 2.5) q -= 12.0     // long duel: poor control
    }

    // stop discipline: in tactical shooters only those who stop first connect
    if (!g_shotGrounded)                    q -= 15.0   // shooting mid-air
    else if (g_shotSpeed < 25.0)          { q += 10.0; g_stillKills++; }
    else if (g_shotSpeed > 90.0)            q -= 12.0   // shooting on the run

    // shot economy: the one tap is the ceiling, spray is the floor
    if (hits > 0 && !equal(wpn, "knife") && !equal(wpn, "grenade")) {
        new exp = expected_shots(wpn)
        if (hits == 1)            { q += 12.0; g_oneTaps++; }
        else if (hits <= exp)       q += 4.0
        else if (hits > exp * 2)    q -= 10.0
    }

    if (q > 100.0) q = 100.0
    if (q < 0.0)   q = 0.0

    g_aim += (q - g_aim) * 0.06
    if (g_aim > 100.0) g_aim = 100.0
    if (g_aim < 0.0)   g_aim = 0.0
}

aim_idx() {
    new v = floatround(g_aim, floatround_floor)
    for (new i = RK_COUNT - 1; i >= 0; i--)
        if (v >= AIM_MIN[i]) return i
    return 0
}

aim_band(ri, &lo, &hi) {
    lo = AIM_MIN[ri]
    hi = (ri < RK_COUNT - 1) ? AIM_MIN[ri + 1] : 100
    if (hi <= lo) hi = lo + 1
}

// "Gold II"  /  "DEITY #412 global"  /  "calibrating 12/30"
aim_name(out[], outlen) {
    if (g_kills < ARC_AIM_KILLS) {
        formatex(out, outlen, "calibrating %d/%d", g_kills, ARC_AIM_KILLS)
        return
    }
    new ri = aim_idx(), lo, hi
    aim_band(ri, lo, hi)
    if (ri >= RK_CHAMPION) {
        new Float:p = (g_aim - float(lo)) / float(hi - lo)
        if (p < 0.0) p = 0.0
        if (p > 1.0) p = 1.0
        new t = ARC_AIM_TOP - floatround(float(ARC_AIM_TOP - 1) * floatsqroot(p), floatround_floor)
        if (t < 1) t = 1
        formatex(out, outlen, "%s #%d %s", RANK_NAMES[ri], t, LADDER_SCOPE[ri])
    } else {
        new d = ((floatround(g_aim, floatround_floor) - lo) * 3) / (hi - lo)
        if (d < 0) d = 0
        if (d > 2) d = 2
        formatex(out, outlen, "%s %s", RANK_NAMES[ri], ARC_DIVS[d])
    }
}

// where your headshot rate sits on the real competitive scale
hs_label(pct, out[], outlen) {
    if (pct >= 65)      copy(out, outlen, "AIM LEGEND  (ScreaM 68%)")
    else if (pct >= 55) copy(out, outlen, "PRO RIFLER  (f0rest)")
    else if (pct >= 45) copy(out, outlen, "TRYHARD")
    else if (pct >= 35) copy(out, outlen, "AVERAGE")
    else                copy(out, outlen, "DEVELOPING")
}

// bot difficulty follows your aim rank, capped low to keep the arcade pace
apply_adaptive() {
    if (!get_pcvar_num(g_pAdaptive)) return
    static lastDiff = -1
    new d = aim_idx() / 4
    if (d > 2) d = 2
    if (d != lastDiff) {
        lastDiff = d
        server_cmd("yb_difficulty %d", d)
    }
}

// ============================================================================
//  RANKS
// ============================================================================

rank_idx(points) {
    for (new i = RK_COUNT - 1; i >= 0; i--)
        if (points >= RANK_MIN[i]) return i
    return 0
}

div_idx(points, ri) {
    if (ri >= RK_CHAMPION) return 2
    new span = RANK_MIN[ri + 1] - RANK_MIN[ri]
    new d = ((points - RANK_MIN[ri]) * 3) / span
    if (d < 0) d = 0
    if (d > 2) d = 2
    return d
}

/*
 * Ladder position inside the current rank (0 = no ladder yet). Square-root
 * curve: thousands of places fall away fast at first, the top 100 is a long
 * grind, and each rank's span is wider than the last.
 */
ladder_top(points) {
    new ri = rank_idx(points)
    if (ri < RK_CHAMPION) return 0
    new Float:p = float(points - RANK_MIN[ri]) / float(LADDER_SPAN[ri])
    if (p < 0.0) p = 0.0
    if (p > 1.0) p = 1.0
    new t = ARC_LADDER_TOP - floatround(float(ARC_LADDER_TOP - 1) * floatsqroot(p), floatround_floor)
    return (t < 1) ? 1 : t
}

pts_for_top(ri, t) {
    if (ri < RK_CHAMPION) return 0
    if (t < 1) t = 1
    new Float:frac = float(ARC_LADDER_TOP - t) / float(ARC_LADDER_TOP - 1)
    return RANK_MIN[ri] + floatround(frac * frac * float(LADDER_SPAN[ri]), floatround_ceil)
}

rank_name(points, out[], outlen) {
    new ri = rank_idx(points)
    if (ri >= RK_CHAMPION)
        formatex(out, outlen, "%s #%d %s", RANK_NAMES[ri], ladder_top(points), LADDER_SCOPE[ri])
    else
        formatex(out, outlen, "%s %s", RANK_NAMES[ri], ARC_DIVS[div_idx(points, ri)])
}

top_milestone(oldTop, newTop) {
    for (new i = 0; i < sizeof(TOP_MILESTONES); i++)
        if (oldTop > TOP_MILESTONES[i] && newTop <= TOP_MILESTONES[i])
            return TOP_MILESTONES[i]
    return 0
}

/*
 * Deterministic rank for a bot derived from its name: the same name always
 * maps to the same rank, so no shared state is needed between subsystems.
 * Distribution is weighted toward the middle, with a couple of KING outliers.
 */
bot_tier(const name[]) {
    new h = 7
    for (new i = 0; name[i]; i++)
        h = (h * 31 + name[i]) & 0x7FFFFFF
    new r = h % 100
    if (r < 8)  return RK_IRON
    if (r < 20) return RK_BRONZE
    if (r < 38) return RK_SILVER
    if (r < 56) return RK_GOLD
    if (r < 71) return RK_PLATINUM
    if (r < 83) return RK_DIAMOND
    if (r < 91) return RK_MASTER
    if (r < 96) return RK_GRANDMASTER
    if (r < 99) return RK_CHAMPION
    return RK_KING
}

rivals_above() {
    new c = 0
    for (new i = 0; i < RIVALS; i++)
        if (g_rival[i] > g_points) c++
    return c
}

clamp_zero(v) { return (v < 0) ? 0 : v; }

combo_idx(fastN) {
    if (fastN < 2) return 0
    return (fastN > ARC_COMBO_MAX) ? ARC_COMBO_MAX : fastN
}

// ============================================================================
//  KILLFEED
// ============================================================================

feed_name(id, out[], outlen) {
    if (id < 1 || id > 32) {
        copy(out, outlen, "WORLD")
        return
    }
    new nm[32]
    get_user_name(id, nm, charsmax(nm))
    if (strlen(nm) > 11) {
        nm[11] = 0
        add(nm, charsmax(nm), ".")
    }
    new tag[8]
    if (id == g_human) copy(tag, charsmax(tag), RANK_TAG[rank_idx(g_points)])
    else               copy(tag, charsmax(tag), RANK_TAG[bot_tier(nm)])
    formatex(out, outlen, "[%s] %s", tag, nm)
}

feed_push(killer, victim, hs, const wpn[]) {
    for (new i = FEED_LINES - 1; i > 0; i--) {
        copy(g_line[i], charsmax(g_line[]), g_line[i - 1])
        g_expire[i]  = g_expire[i - 1]
        g_lineCol[i] = g_lineCol[i - 1]
        g_lineOn[i]  = g_lineOn[i - 1]
    }

    new kn[28], vn[28], wu[16]
    feed_name(killer, kn, charsmax(kn))
    feed_name(victim, vn, charsmax(vn))
    copy(wu, charsmax(wu), wpn)
    strtoupper(wu)

    formatex(g_line[0], charsmax(g_line[]), "%s   [ %s%s ]   %s", kn, wu, hs ? " HS" : "", vn)
    g_expire[0] = get_gametime() + FEED_HOLD
    g_lineOn[0] = true

    if (killer == g_human && victim != g_human) g_lineCol[0] = hs ? UI_AMBER : UI_GOLD
    else if (victim == g_human)                 g_lineCol[0] = UI_DANGER
    else                                        g_lineCol[0] = UI_MUTED

    feed_render()
}

/*
 * No fades here on purpose: every new kill re-sends all lines (they shift one
 * slot down) and any fade would re-animate all of them at once, which reads as
 * lag on screen.
 */
feed_render() {
    if (!g_human || !is_user_connected(g_human)) return
    new Float:now = get_gametime()
    for (new i = 0; i < FEED_LINES; i++) {
        new Float:left = g_expire[i] - now
        if (!g_lineOn[i] || left <= 0.2) {
            if (g_lineOn[i]) {
                g_lineOn[i] = false
                ui_clear(g_human, UI_CH_FEED + i)
            }
            continue
        }
        set_hudmessage(UI_PALETTE[g_lineCol[i]][0], UI_PALETTE[g_lineCol[i]][1], UI_PALETTE[g_lineCol[i]][2],
            UI_POS[UI_SLOT_FEED][0], UI_POS[UI_SLOT_FEED][1] + float(i) * 0.032,
            0, 0.0, left, 0.0, 0.0, UI_CH_FEED + i)
        show_hudmessage(g_human, "%s", g_line[i])
    }
}

public feed_tick() {
    if (!g_human || !is_user_connected(g_human)) return
    new Float:now = get_gametime()
    for (new i = 0; i < FEED_LINES; i++) {
        if (g_lineOn[i] && g_expire[i] - now <= 0.2) {
            feed_render()
            return
        }
    }
}

combo_banner(ci) {
    new txt[48]
    formatex(txt, charsmax(txt), ">>  %s  <<", COMBO_NAME[ci])
    ui_anim(g_human, UI_CH_FEEDBAN, UI_ANIM_PULSE, UI_LEGEND, UI_AMBER, 1.2,
        UI_POS[UI_SLOT_FEEDBAN][0], UI_POS[UI_SLOT_FEEDBAN][1], txt)
}

// ============================================================================
//  STREAK REWARDS
// ============================================================================

// The combo sound (ULTRA / MONSTER KILL) already fires from the same table in
// the same instant, so nothing extra is played here.
vamp_activate(tier) {
    g_vampTier = tier
    if (tier >= 2) {
        screen_fade(g_human, 120, 0, 200, 110, 2)
        ui_banner(g_human, UI_AMBER, 4.5, "^n  %s  ^nEVOLVED VAMPIRE^n+%d HP and a full reload on every kill^nuntil you die",
            COMBO_NAME[MONSTER_FAST], VAMP_HEAL2)
    } else {
        screen_fade(g_human, 0, 0, 200, 90, 2)
        ui_banner(g_human, UI_INFO, 4.0, "^n  %s  ^nVAMPIRE ACTIVE^n+%d HP on every kill until you die",
            COMBO_NAME[VAMP_FAST], VAMP_HEAL)
    }
    show_status()
}

vamp_on_kill() {
    if (!is_user_alive(g_human)) return
    new heal = (g_vampTier >= 2) ? VAMP_HEAL2 : VAMP_HEAL
    new hp = get_user_health(g_human)
    new nhp = hp + heal
    if (nhp > VAMP_MAX) nhp = VAMP_MAX
    if (nhp > hp) {
        set_user_health(g_human, nhp)
        screen_fade(g_human, 0, 40, 200, 45, 1)
    }
    if (g_vampTier >= 2) refill_weapon()
}

refill_weapon() {
    new clip, ammo
    new wid = get_user_weapon(g_human, clip, ammo)
    if (wid <= 0 || wid >= sizeof(MAXCLIP) || MAXCLIP[wid] <= 1) return
    new wname[32]
    get_weaponname(wid, wname, charsmax(wname))
    new went = find_ent_by_owner(-1, wname, g_human)
    if (went > 0) cs_set_weapon_ammo(went, MAXCLIP[wid])
    if (MAXBPAMMO[wid] > 0) cs_set_user_bpammo(g_human, wid, MAXBPAMMO[wid])
}

/*
 * Bullet time: every bot drops to 40% speed while you keep yours. Speed is
 * re-applied every 0.2 s because the game rewrites it on weapon switch, and
 * each bot's original value is restored when it ends.
 */
bullet_start() {
    new bool:renew = g_bullet
    g_bullet = true
    if (!renew) {
        ui_banner(g_human, UI_LEGEND, 3.0, "^n  B U L L E T   T I M E  ^n%s^nthe world slows for %d seconds",
            COMBO_NAME[ARC_COMBO_MAX], floatround(BULLET_TIME))
        screen_fade(g_human, 30, 60, 255, 90, 2)
        remove_task(TASK_BULLET)
        set_task(0.2, "bullet_tick", TASK_BULLET, _, _, "b")
    }
    // every new kill in the chain renews the timer
    remove_task(TASK_BULEND)
    set_task(BULLET_TIME, "bullet_end", TASK_BULEND)
    show_status()
}

public bullet_tick() {
    if (!g_bullet) return
    new players[32], num
    get_players(players, num, "a")
    for (new i = 0; i < num; i++) {
        new id = players[i]
        if (id == g_human || !is_user_bot(id)) continue
        new Float:sp = get_user_maxspeed(id)
        if (sp > 1.0) {
            if (g_baseSpeed[id] <= 0.0 || sp > g_baseSpeed[id] * 0.5)
                g_baseSpeed[id] = sp
            set_user_maxspeed(id, g_baseSpeed[id] * BULLET_SLOW)
        }
    }
}

public bullet_end() {
    g_bullet = false
    remove_task(TASK_BULLET)
    for (new id = 1; id <= 32; id++) {
        if (g_baseSpeed[id] > 0.0 && is_user_alive(id))
            set_user_maxspeed(id, g_baseSpeed[id])
        g_baseSpeed[id] = 0.0
    }
    show_status()
}

reward_uav() {
    g_uavTick = UAV_TICKS
    ui_banner(g_human, UI_LEGEND, 5.5, "^n  UAV ONLINE  ^n%d kill streak^nsee-through-walls ESP^nsweep every 5 s for 60 s", UAV_STREAK)
    remove_task(TASK_UAV)
    set_task(UAV_TICK, "uav_tick", TASK_UAV, _, _, "b")
}

// one tick every 0.2 s; inside each 5 s window it draws for the first 1.6 s,
// so the marker tracks the enemy while the sweep lasts
public uav_tick() {
    if (!g_human || !is_user_connected(g_human) || g_uavTick <= 0) {
        remove_task(TASK_UAV)
        if (g_human) ui_clear(g_human, UI_CH_STATUS)
        g_uavTick = 0
        return
    }
    new phase = (UAV_TICKS - g_uavTick) % 25
    if (phase < 8 && is_user_alive(g_human)) {
        new players[32], num
        get_players(players, num, "a")
        for (new i = 0; i < num; i++)
            if (players[i] != g_human)
                esp_mark(players[i])
    }
    if (phase == 0) show_status()
    g_uavTick--
}

/*
 * ESP marker visible through walls.
 *
 * A beam is occluded by world geometry, so instead of drawing on the enemy we
 * trace from your eye toward them and paint the box where that trace hits the
 * wall, nudged 6 units back toward you. The result is a box "painted" on the
 * wall right in front of the enemy, scaled by distance so it reads as depth.
 */
esp_mark(target) {
    new Float:eye[3], Float:ofs[3], Float:tOrigin[3], Float:hit[3]
    pev(g_human, pev_origin, eye)
    pev(g_human, pev_view_ofs, ofs)
    xs_vec_add(eye, ofs, eye)
    pev(target, pev_origin, tOrigin)

    new tr = create_tr2()
    engfunc(EngFunc_TraceLine, eye, tOrigin, IGNORE_GLASS | IGNORE_MONSTERS, g_human, tr)
    get_tr2(tr, TR_vecEndPos, hit)
    free_tr2(tr)

    new Float:dir[3]
    xs_vec_sub(hit, eye, dir)
    new Float:distMark = xs_vec_len(dir)
    if (distMark < 1.0) return
    xs_vec_normalize(dir, dir)
    xs_vec_mul_scalar(dir, 6.0, dir)
    xs_vec_sub(hit, dir, hit)

    // perspective scale: how far the wall is relative to the enemy
    new Float:toEnemy[3]
    xs_vec_sub(tOrigin, eye, toEnemy)
    new Float:distEnemy = xs_vec_len(toEnemy)
    new Float:ratio = (distEnemy > 1.0) ? (distMark / distEnemy) : 1.0
    new Float:size = 20.0 * ratio
    if (size < 2.5) size = 2.5

    // the player's own screen axes, so the box always faces them
    new Float:ang[3], Float:up[3], Float:right[3]
    pev(g_human, pev_v_angle, ang)
    angle_vector(ang, ANGLEVECTOR_UP, up)
    angle_vector(ang, ANGLEVECTOR_RIGHT, right)
    xs_vec_normalize(up, up)
    xs_vec_normalize(right, right)
    xs_vec_mul_scalar(up, size, up)
    xs_vec_mul_scalar(right, size, right)

    new Float:c[4][3]
    xs_vec_copy(hit, c[0]); xs_vec_add(c[0], up, c[0]); xs_vec_add(c[0], right, c[0])
    xs_vec_copy(hit, c[1]); xs_vec_add(c[1], up, c[1]); xs_vec_sub(c[1], right, c[1])
    xs_vec_copy(hit, c[2]); xs_vec_sub(c[2], up, c[2]); xs_vec_add(c[2], right, c[2])
    xs_vec_copy(hit, c[3]); xs_vec_sub(c[3], up, c[3]); xs_vec_sub(c[3], right, c[3])

    esp_line(c[0], c[1]); esp_line(c[0], c[2])
    esp_line(c[2], c[3]); esp_line(c[3], c[1])
}

esp_line(const Float:a[3], const Float:b[3]) {
    message_begin(MSG_ONE_UNRELIABLE, SVC_TEMPENTITY, _, g_human)
    write_byte(0)                                   // TE_BEAMPOINTS
    engfunc(EngFunc_WriteCoord, a[0]); engfunc(EngFunc_WriteCoord, a[1]); engfunc(EngFunc_WriteCoord, a[2])
    engfunc(EngFunc_WriteCoord, b[0]); engfunc(EngFunc_WriteCoord, b[1]); engfunc(EngFunc_WriteCoord, b[2])
    write_short(g_beamSpr)
    write_byte(0); write_byte(0); write_byte(3); write_byte(8); write_byte(0)
    write_byte(255); write_byte(40); write_byte(40); write_byte(220); write_byte(0)
    message_end()
}

// Damage is dealt with you as the attacker, so every death produces its own
// DeathMsg in your name: points, medals and feed lines all count for you.
reward_nuke() {
    new players[32], num
    get_players(players, num, "a")
    if (num < 2) return
    ui_banner(g_human, UI_LEGEND, 6.5, "^n  * * *  N U K E  * * *  ^n%d kill streak^nThe whole map goes down^nEvery kill counts for you", NUKE_STREAK)
    if (get_pcvar_num(g_pSounds)) client_cmd(g_human, "spk AQS/holyshit")
    screen_fade(g_human, 255, 255, 255, 160, 25)
    remove_task(TASK_NUKE)
    set_task(1.6, "nuke_blast", TASK_NUKE)
}

public nuke_blast() {
    if (!g_human || !is_user_connected(g_human)) return
    new players[32], num
    get_players(players, num, "a")
    for (new i = 0; i < num; i++) {
        new v = players[i]
        if (v == g_human || !is_user_alive(v)) continue
        ExecuteHamB(Ham_TakeDamage, v, 0, g_human, 20000.0, DMG_BULLET)
    }
}

// ============================================================================
//  LOADOUT AND MOVEMENT
// ============================================================================

public ham_spawn_post(id) {
    if (!is_user_alive(id) || !get_pcvar_num(g_pEquip)) return HAM_IGNORED
    set_task(0.2, "give_loadout", id)
    return HAM_IGNORED
}

public give_loadout(id) {
    if (!is_user_alive(id)) return
    strip_user_weapons(id)
    give_item(id, "weapon_knife")
    give_item(id, "item_assaultsuit")

    new p = g_prim[id], s = g_sec[id]
    give_item(id, PRIM_ENT[p])
    cs_set_user_bpammo(id, PRIM_CSW[p], MAXBPAMMO[PRIM_CSW[p]])
    give_item(id, SEC_ENT[s])
    cs_set_user_bpammo(id, SEC_CSW[s], MAXBPAMMO[SEC_CSW[s]])
    client_cmd(id, "slot1")
}

public cmd_guns(id) {
    if (is_user_bot(id)) return PLUGIN_CONTINUE
    new menu = menu_create("Primary weapon:", "menu_prim")
    for (new i = 0; i < sizeof(PRIMARIES); i++)
        menu_additem(menu, PRIMARIES[i])
    menu_display(id, menu)
    return PLUGIN_HANDLED
}

public menu_prim(id, menu, item) {
    if (item != MENU_EXIT) {
        g_prim[id] = item
        new m2 = menu_create("Secondary weapon:", "menu_sec")
        for (new i = 0; i < sizeof(SECONDARIES); i++)
            menu_additem(m2, SECONDARIES[i])
        menu_display(id, m2)
    }
    menu_destroy(menu)
    return PLUGIN_HANDLED
}

public menu_sec(id, menu, item) {
    if (item != MENU_EXIT) {
        g_sec[id] = item
        client_print(id, print_chat, "[Arcade DM] %s + %s on your next respawn. Type 'guns' to change.",
            PRIMARIES[g_prim[id]], SECONDARIES[g_sec[id]])
        if (is_user_alive(id)) give_loadout(id)
    }
    menu_destroy(menu)
    return PLUGIN_HANDLED
}

public client_PreThink(id) {
    if (!get_pcvar_num(g_pBhop) || !is_user_alive(id)) return
    set_pev(id, pev_fuser2, 0.0)                      // kill the post-jump slowdown
    if (pev(id, pev_button) & IN_JUMP) {
        new flags = pev(id, pev_flags)
        if (!(flags & FL_GROUND)) return
        if (pev(id, pev_waterlevel) >= 2) return
        new Float:vel[3]
        pev(id, pev_velocity, vel)
        vel[2] += 250.0
        set_pev(id, pev_velocity, vel)
    }
}

// ============================================================================
//  PANELS AND HUD
// ============================================================================

show_board() {
    if (!g_human || !is_user_connected(g_human)) return

    new total = RIVALS + 1
    new scores[RIVALS + 1], idx[RIVALS + 1]
    for (new i = 0; i < RIVALS; i++) { scores[i] = g_rival[i]; idx[i] = i; }
    scores[RIVALS] = g_points
    idx[RIVALS] = -1

    for (new a = 0; a < total - 1; a++)
        for (new b = a + 1; b < total; b++)
            if (scores[b] > scores[a]) {
                new t = scores[a]; scores[a] = scores[b]; scores[b] = t
                t = idx[a]; idx[a] = idx[b]; idx[b] = t
            }

    new mypos = 0
    for (new i = 0; i < total; i++)
        if (idx[i] == -1) { mypos = i; break; }

    // show a window around your own position
    new from = mypos - 3
    if (from < 0) from = 0
    new to = from + 6
    if (to >= total) { to = total - 1; from = to - 6; if (from < 0) from = 0; }

    new board[512], line[64]
    formatex(board, charsmax(board), "===  LEADERBOARD  (place %d/%d)  ===^n", mypos + 1, total)
    for (new i = from; i <= to; i++) {
        if (idx[i] == -1) formatex(line, charsmax(line), "%d.  >> YOU <<   %d pts^n", i + 1, scores[i])
        else              formatex(line, charsmax(line), "%d.  %s   %d pts^n", i + 1, RIVAL_NAMES[idx[i]], scores[i])
        add(board, charsmax(board), line)
    }
    new t2 = ladder_top(g_points)
    if (t2 > 0) {
        formatex(line, charsmax(line), "^n%s ranking: #%d", LADDER_SCOPE[rank_idx(g_points)], t2)
        add(board, charsmax(board), line)
    }
    ui_board(g_human, UI_INFO, "%s", board)
}

show_weapons() {
    if (!g_human || !is_user_connected(g_human)) return

    new order[20]
    for (new i = 0; i < g_wpnCount; i++) order[i] = i
    for (new a = 0; a < g_wpnCount - 1; a++)
        for (new b = a + 1; b < g_wpnCount; b++)
            if (g_wpnKills[order[b]] > g_wpnKills[order[a]]) {
                new t = order[a]; order[a] = order[b]; order[b] = t
            }

    new board[512], line[64]
    formatex(board, charsmax(board), "===  YOUR WEAPONS  ===^n")
    new n = (g_wpnCount < 8) ? g_wpnCount : 8
    for (new i = 0; i < n; i++) {
        new w = order[i]
        new pct = g_wpnKills[w] ? (g_wpnHs[w] * 100 / g_wpnKills[w]) : 0
        formatex(line, charsmax(line), "%s:  %d kills  |  %d%% HS^n", g_wpnName[w], g_wpnKills[w], pct)
        add(board, charsmax(board), line)
    }
    if (!n) add(board, charsmax(board), "(no kills yet)^n")

    new tm = 0
    for (new i = 0; i < MED_TOTAL; i++) tm += g_medals[i]
    formatex(line, charsmax(line), "^nMedals: %d (session: %d)", tm, g_medalsSession)
    add(board, charsmax(board), line)

    new hsPct = g_kills ? (g_hs * 100 / g_kills) : 0
    new lbl[40]
    hs_label(hsPct, lbl, charsmax(lbl))
    formatex(line, charsmax(line), "^nHS %d%%  ->  %s", hsPct, lbl)
    add(board, charsmax(board), line)

    ui_board(g_human, UI_AMBER, "%s", board)
}

show_status() {
    if (!g_human || !is_user_connected(g_human)) return
    new txt[96]
    txt[0] = 0

    if (g_vampTier >= 2)      formatex(txt, charsmax(txt), "VAMPIRE++   +%d HP and reload per kill", VAMP_HEAL2)
    else if (g_vampTier == 1) formatex(txt, charsmax(txt), "VAMPIRE   +%d HP per kill", VAMP_HEAL)

    if (g_uavTick > 0) {
        new ln[32]
        formatex(ln, charsmax(ln), "%sUAV  %d s", txt[0] ? "^n" : "", g_uavTick / 5)
        add(txt, charsmax(txt), ln)
    }
    if (g_bullet) {
        new ln[32]
        formatex(ln, charsmax(ln), "%sBULLET TIME", txt[0] ? "^n" : "")
        add(txt, charsmax(txt), ln)
    }
    if (!txt[0]) return

    ui_text(g_human, UI_SLOT_STATUS, g_vampTier >= 2 ? UI_AMBER : UI_SUCCESS, UI_CH_STATUS, 3.3, "%s", txt)
}

public status_tick() { show_status(); }
public hud_tick()    { update_hud(); }

public time_tick() {
    if (!g_human || !is_user_connected(g_human)) return
    g_secs += 10
    g_sessionSecs += 10
    if (++g_saveTick >= 6) { g_saveTick = 0; save_data(); }
}

update_hud() {
    if (!g_human || !is_user_connected(g_human)) return

    new rname[48]
    rank_name(g_points, rname, charsmax(rname))

    new nextTxt[48]
    new ri = rank_idx(g_points)
    if (ri >= RK_CHAMPION) {
        new t = ladder_top(g_points)
        if (t <= 1 && ri == RK_DEITY) copy(nextTxt, charsmax(nextTxt), "TOP #1 GLOBAL")
        else if (t <= 1)              formatex(nextTxt, charsmax(nextTxt), "%s in: %d pts", RANK_NAMES[ri + 1], RANK_MIN[ri + 1] - g_points)
        else {
            new need = pts_for_top(ri, t - 1) - g_points
            if (need < 1) need = 1
            formatex(nextTxt, charsmax(nextTxt), "#%d in: %d pts", t - 1, need)
        }
    } else {
        new span = RANK_MIN[ri + 1] - RANK_MIN[ri]
        new into = g_points - RANK_MIN[ri]
        new divSpan = span / 3
        new nextAt = ((into / divSpan) + 1) * divSpan
        if (nextAt > span) nextAt = span
        formatex(nextTxt, charsmax(nextTxt), "next: %d pts", RANK_MIN[ri] + nextAt - g_points)
    }

    new kd100 = g_deaths ? (g_kills * 100 / g_deaths) : (g_kills * 100)
    new hsPct = g_kills ? (g_hs * 100 / g_kills) : 0
    new kpm100 = g_sessionSecs > 0 ? (g_sessionKills * 6000 / g_sessionSecs) : 0
    new stillPct = g_kills ? (g_stillKills * 100 / g_kills) : 0
    new tapPct   = g_kills ? (g_oneTaps * 100 / g_kills) : 0

    new starTxt[16]
    if (g_stars > 0) formatex(starTxt, charsmax(starTxt), "*%d  ", g_stars)
    else             starTxt[0] = 0

    new aimTxt[48]
    aim_name(aimTxt, charsmax(aimTxt))

    apply_adaptive()

    ui_hud(g_human, UI_TEXT, 4.0,
        "%s[ %s ]  %d pts  (%s)^nK/D %d.%02d  |  HS %d%%  |  %d.%02d kpm  |  Streak %d^nAIM: %s (%d)  |  still %d%%  |  1tap %d%%",
        starTxt, rname, g_points, nextTxt,
        kd100 / 100, kd100 % 100, hsPct, kpm100 / 100, kpm100 % 100, g_streak,
        aimTxt, floatround(g_aim), stillPct, tapPct)
}

wpn_track(const name[], headshot) {
    for (new i = 0; i < g_wpnCount; i++) {
        if (equal(g_wpnName[i], name)) {
            g_wpnKills[i]++
            if (headshot) g_wpnHs[i]++
            return
        }
    }
    if (g_wpnCount < 20) {
        copy(g_wpnName[g_wpnCount], 19, name)
        g_wpnKills[g_wpnCount] = 1
        g_wpnHs[g_wpnCount] = headshot ? 1 : 0
        g_wpnCount++
    }
}

// chat with your rank tag in front
public cmd_say(id) {
    if (is_user_bot(id) || id != g_human) return PLUGIN_CONTINUE
    new msg[160]
    read_args(msg, charsmax(msg))
    remove_quotes(msg)
    if (!msg[0]) return PLUGIN_CONTINUE
    // let other plugins' chat commands through
    if (msg[0] == '/' || equali(msg, "guns", 4)) return PLUGIN_CONTINUE

    new name[32], out[224]
    get_user_name(id, name, charsmax(name))
    formatex(out, charsmax(out), "^x04[%s]^x03 %s^x01 : %s", RANK_TAG[rank_idx(g_points)], name, msg)

    message_begin(MSG_ALL, get_user_msgid("SayText"), _, 0)
    write_byte(id)
    write_string(out)
    message_end()
    return PLUGIN_HANDLED
}

screen_fade(id, r, g, b, a, dur10) {
    message_begin(MSG_ONE, get_user_msgid("ScreenFade"), _, id)
    write_short(1 << 10)
    write_short(dur10 << 8)
    write_short(0x0000)
    write_byte(r); write_byte(g); write_byte(b); write_byte(a)
    message_end()
}

// ============================================================================
//  UI: components and runtime
//
//  The server can only send discrete messages, so animations run at UI_TICK
//  (10 Hz) and only animate colour and position. No scaling or real opacity:
//  that would require a custom client.dll.
// ============================================================================

stock ui_text(id, slot, color, ch, Float:hold, const fmt[], any:...) {
    new msg[192]
    vformat(msg, charsmax(msg), fmt, 7)
    set_hudmessage(UI_PALETTE[color][0], UI_PALETTE[color][1], UI_PALETTE[color][2],
        UI_POS[slot][0], UI_POS[slot][1], 0, 0.0, hold, 0.0, 0.25, ch)
    show_hudmessage(id, "%s", msg)
}

stock ui_hud(id, color, Float:hold, const fmt[], any:...) {
    new msg[224]
    vformat(msg, charsmax(msg), fmt, 5)
    set_hudmessage(UI_PALETTE[color][0], UI_PALETTE[color][1], UI_PALETTE[color][2],
        UI_POS[UI_SLOT_HUD][0], UI_POS[UI_SLOT_HUD][1], 0, 0.0, hold, 0.0, 0.3, UI_CH_HUD)
    show_hudmessage(id, "%s", msg)
}

stock ui_toast(id, color, const fmt[], any:...) {
    new msg[UI_TEXT_LEN]
    vformat(msg, charsmax(msg), fmt, 4)
    ui_anim(id, UI_CH_TOAST, UI_ANIM_RISE, color, UI_DIM, 1.1,
        UI_POS[UI_SLOT_TOAST][0], UI_POS[UI_SLOT_TOAST][1], msg)
}

stock ui_banner(id, color, Float:hold, const fmt[], any:...) {
    new msg[224]
    vformat(msg, charsmax(msg), fmt, 5)
    // effect 2 = the engine's typewriter reveal
    set_hudmessage(UI_PALETTE[color][0], UI_PALETTE[color][1], UI_PALETTE[color][2],
        UI_POS[UI_SLOT_BANNER][0], UI_POS[UI_SLOT_BANNER][1], 2, 0.08, hold, 0.05, 0.5, UI_CH_BANNER)
    show_hudmessage(id, "%s", msg)
}

stock ui_board(id, color, const fmt[], any:...) {
    new msg[512]
    vformat(msg, charsmax(msg), fmt, 4)
    set_hudmessage(UI_PALETTE[color][0], UI_PALETTE[color][1], UI_PALETTE[color][2],
        UI_POS[UI_SLOT_BOARD][0], UI_POS[UI_SLOT_BOARD][1], 0, 0.0, 5.0, 0.0, 0.5, UI_CH_BOARD)
    show_hudmessage(id, "%s", msg)
}

stock ui_clear(id, ch) {
    set_hudmessage(0, 0, 0, 0.0, 0.0, 0, 0.0, 0.1, 0.0, 0.0, ch)
    show_hudmessage(id, " ")
}

stock ui_anim(id, ch, type, ca, cb, Float:dur, Float:x, Float:y, const txt[]) {
    new slot = -1
    // reuse the slot already animating this channel
    for (new i = 0; i < UI_MAX_ANIM; i++)
        if (g_anim[i][UA_ON] && g_anim[i][UA_CH] == ch && g_anim[i][UA_ID] == id) { slot = i; break; }
    if (slot == -1)
        for (new i = 0; i < UI_MAX_ANIM; i++)
            if (!g_anim[i][UA_ON]) { slot = i; break; }
    if (slot == -1) slot = 0

    g_anim[slot][UA_ON]   = 1
    g_anim[slot][UA_ID]   = id
    g_anim[slot][UA_CH]   = ch
    g_anim[slot][UA_TYPE] = type
    g_anim[slot][UA_T]    = 0.0
    g_anim[slot][UA_DUR]  = dur
    g_anim[slot][UA_X]    = x
    g_anim[slot][UA_Y]    = y
    g_anim[slot][UA_CA]   = ca
    g_anim[slot][UA_CB]   = cb
    copy(g_anim[slot][UA_TXT], UI_TEXT_LEN - 1, txt)
}

// ease-out: fast at the start, soft at the end
stock Float:ui_ease(Float:t) {
    new Float:inv = 1.0 - t
    return 1.0 - inv * inv
}

stock ui_mix(a, b, Float:t) {
    return a + floatround((float(b) - float(a)) * t)
}

public ui_pump() {
    for (new i = 0; i < UI_MAX_ANIM; i++) {
        if (!g_anim[i][UA_ON]) continue
        new id = g_anim[i][UA_ID]
        if (!is_user_connected(id)) { g_anim[i][UA_ON] = 0; continue; }

        g_anim[i][UA_T] += UI_TICK
        new Float:t = g_anim[i][UA_T] / g_anim[i][UA_DUR]
        if (t >= 1.0) {
            g_anim[i][UA_ON] = 0
            ui_clear(id, g_anim[i][UA_CH])
            continue
        }

        new ca = g_anim[i][UA_CA], cb = g_anim[i][UA_CB]
        new r, g, b
        new Float:x = g_anim[i][UA_X], Float:y = g_anim[i][UA_Y]

        if (g_anim[i][UA_TYPE] == UI_ANIM_PULSE) {
            new step = floatround(g_anim[i][UA_T] / UI_TICK, floatround_floor)
            new src = (step % 2) ? ca : cb
            r = UI_PALETTE[src][0]; g = UI_PALETTE[src][1]; b = UI_PALETTE[src][2]
        } else {
            new Float:e = ui_ease(t)
            y -= 0.04 * e                      // rise ~4% of the screen
            r = ui_mix(UI_PALETTE[ca][0], UI_PALETTE[cb][0], e)
            g = ui_mix(UI_PALETTE[ca][1], UI_PALETTE[cb][1], e)
            b = ui_mix(UI_PALETTE[ca][2], UI_PALETTE[cb][2], e)
        }

        set_hudmessage(r, g, b, x, y, 0, 0.0, UI_TICK + 0.05, 0.0, 0.0, g_anim[i][UA_CH])
        show_hudmessage(id, "%s", g_anim[i][UA_TXT])
    }
}

// ============================================================================
//  PERSISTENCE
// ============================================================================

parse_ints(const src[], out[], maxn) {
    new n = 0, i = 0, tok[16], j
    while (src[i] && n < maxn) {
        while (src[i] == ' ') i++
        if (!src[i]) break
        j = 0
        while (src[i] && src[i] != ' ' && j < 15) tok[j++] = src[i++]
        tok[j] = 0
        out[n++] = str_to_num(tok)
    }
    return n
}

load_data() {
    new buf[512]
    g_aim = 40.0

    if (g_vault == INVALID_HANDLE) {
        for (new i = 0; i < RIVALS; i++) g_rival[i] = 50 + random_num(0, 450)
        return
    }

    if (nvault_get(g_vault, "pts", buf, charsmax(buf)))
        g_points = str_to_num(buf)

    if (nvault_get(g_vault, "rivals", buf, charsmax(buf))) {
        new vals[RIVALS]
        new n = parse_ints(buf, vals, RIVALS)
        for (new i = 0; i < RIVALS; i++)
            g_rival[i] = (i < n) ? vals[i] : (50 + random_num(0, 450))
    } else {
        for (new i = 0; i < RIVALS; i++) g_rival[i] = 50 + random_num(0, 450)
    }

    // tolerant load: older saves simply leave the newer fields at zero
    if (nvault_get(g_vault, "stats", buf, charsmax(buf))) {
        new vals[6]
        new n = parse_ints(buf, vals, 6)
        g_kills = vals[0]; g_deaths = vals[1]; g_hs = vals[2]; g_secs = vals[3]
        g_stillKills = (n > 4) ? vals[4] : 0
        g_oneTaps    = (n > 5) ? vals[5] : 0
    }

    if (nvault_get(g_vault, "aim", buf, charsmax(buf))) {
        new vals[2]
        parse_ints(buf, vals, 2)
        g_aim = float(vals[0]) / 10.0
        g_stars = vals[1]
        if (g_aim <= 0.0) g_aim = 40.0
    }

    if (nvault_get(g_vault, "medals", buf, charsmax(buf))) {
        new vals[MED_TOTAL]
        new n = parse_ints(buf, vals, MED_TOTAL)
        for (new i = 0; i < MED_TOTAL; i++)
            g_medals[i] = (i < n) ? vals[i] : 0
    }

    // weapons are stored as "name:kills:headshots,name:kills:headshots,..."
    g_wpnCount = 0
    if (nvault_get(g_vault, "weapons", buf, charsmax(buf))) {
        new i = 0
        while (buf[i] && g_wpnCount < 20) {
            new nm[20], t1[12], t2[12], j
            j = 0; while (buf[i] && buf[i] != ':' && j < 19) nm[j++] = buf[i++]
            nm[j] = 0; if (buf[i] == ':') i++
            j = 0; while (buf[i] && buf[i] != ':' && j < 11) t1[j++] = buf[i++]
            t1[j] = 0; if (buf[i] == ':') i++
            j = 0; while (buf[i] && buf[i] != ',' && j < 11) t2[j++] = buf[i++]
            t2[j] = 0; if (buf[i] == ',') i++
            if (nm[0]) {
                copy(g_wpnName[g_wpnCount], 19, nm)
                g_wpnKills[g_wpnCount] = str_to_num(t1)
                g_wpnHs[g_wpnCount] = str_to_num(t2)
                g_wpnCount++
            }
        }
    }
}

save_data() {
    if (g_vault == INVALID_HANDLE) return
    new buf[512], tmp[24]

    num_to_str(g_points, buf, charsmax(buf))
    nvault_set(g_vault, "pts", buf)

    buf[0] = 0
    for (new i = 0; i < RIVALS; i++) {
        formatex(tmp, charsmax(tmp), i ? " %d" : "%d", g_rival[i])
        add(buf, charsmax(buf), tmp)
    }
    nvault_set(g_vault, "rivals", buf)

    formatex(buf, charsmax(buf), "%d %d %d %d %d %d", g_kills, g_deaths, g_hs, g_secs, g_stillKills, g_oneTaps)
    nvault_set(g_vault, "stats", buf)

    formatex(buf, charsmax(buf), "%d %d", floatround(g_aim * 10.0), g_stars)
    nvault_set(g_vault, "aim", buf)

    buf[0] = 0
    for (new i = 0; i < MED_TOTAL; i++) {
        formatex(tmp, charsmax(tmp), i ? " %d" : "%d", g_medals[i])
        add(buf, charsmax(buf), tmp)
    }
    nvault_set(g_vault, "medals", buf)

    buf[0] = 0
    for (new i = 0; i < g_wpnCount; i++) {
        formatex(tmp, charsmax(tmp), "%s:%d:%d,", g_wpnName[i], g_wpnKills[i], g_wpnHs[i])
        add(buf, charsmax(buf), tmp)
    }
    nvault_set(g_vault, "weapons", buf)
}

