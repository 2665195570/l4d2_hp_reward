#include <sourcemod>
#include <sdktools>
#include <sdkhooks>

#pragma semicolon 1
#pragma newdecls required

#define PLUGIN_VERSION "1.0.0"

#define TEAM_SURVIVOR 2
#define TEAM_INFECTED 3

// 特感类型 (L4D2 m_zombieClass 数值)
enum
{
    ZC_SMOKER = 1,
    ZC_BOOMER,
    ZC_HUNTER,
    ZC_SPITTER,
    ZC_JOCKEY,
    ZC_CHARGER,
    ZC_WITCH,
    ZC_TANK
};

char g_sClassName[ZC_TANK + 1][] =
{
    "",
    "Smoker",
    "Boomer",
    "Hunter",
    "Spitter",
    "Jockey",
    "Charger",
    "Witch",
    "Tank"
};

ConVar g_cvEnabled;
ConVar g_cvMaxHealth;
ConVar g_cvOverheal;
ConVar g_cvShowHint;
ConVar g_cvHp[ZC_TANK + 1];

bool g_bWitchRewarded[2048];

public Plugin myinfo =
{
    name = "特感击杀奖励生命值",
    author = "OpenClaw",
    description = "击杀每种特感后奖励可配置的生命值",
    version = PLUGIN_VERSION,
    url = ""
};

public void OnPluginStart()
{
    CreateConVar("l4d_si_hp_reward_version", PLUGIN_VERSION, "插件版本", FCVAR_NOTIFY | FCVAR_DONTRECORD);

    g_cvEnabled    = CreateConVar("l4d_si_hp_enable",  "1",   "启用特感击杀奖励生命值 (1=开 0=关)", FCVAR_NOTIFY, true, 0.0, true, 1.0);
    g_cvMaxHealth  = CreateConVar("l4d_si_hp_max",     "100", "奖励后永久生命值上限", FCVAR_NOTIFY, true, 1.0, true, 100.0);
    g_cvOverheal   = CreateConVar("l4d_si_hp_overheal", "1",  "超出上限的血量转为临时血量 (1=开 0=关)", FCVAR_NOTIFY, true, 0.0, true, 1.0);
    g_cvShowHint   = CreateConVar("l4d_si_hp_hint",     "1",  "击杀后显示奖励提示 (1=开 0=关)", FCVAR_NOTIFY, true, 0.0, true, 1.0);

    g_cvHp[ZC_SMOKER]  = CreateConVar("l4d_si_hp_smoker",  "2",  "击杀Smoker奖励的生命值", FCVAR_NOTIFY, true, 0.0);
    g_cvHp[ZC_BOOMER]  = CreateConVar("l4d_si_hp_boomer",  "2",  "击杀Boomer奖励的生命值", FCVAR_NOTIFY, true, 0.0);
    g_cvHp[ZC_HUNTER]  = CreateConVar("l4d_si_hp_hunter",  "2",  "击杀Hunter奖励的生命值", FCVAR_NOTIFY, true, 0.0);
    g_cvHp[ZC_SPITTER] = CreateConVar("l4d_si_hp_spitter", "2",  "击杀Spitter奖励的生命值", FCVAR_NOTIFY, true, 0.0);
    g_cvHp[ZC_JOCKEY]  = CreateConVar("l4d_si_hp_jockey",  "2",  "击杀Jockey奖励的生命值", FCVAR_NOTIFY, true, 0.0);
    g_cvHp[ZC_CHARGER] = CreateConVar("l4d_si_hp_charger", "2",  "击杀Charger奖励的生命值", FCVAR_NOTIFY, true, 0.0);
    g_cvHp[ZC_WITCH]   = CreateConVar("l4d_si_hp_witch",   "10",  "击杀Witch奖励的生命值", FCVAR_NOTIFY, true, 0.0);
    g_cvHp[ZC_TANK]    = CreateConVar("l4d_si_hp_tank",    "15", "击杀Tank奖励的生命值", FCVAR_NOTIFY, true, 0.0);

    HookEvent("player_death", Event_PlayerDeath);
    HookEvent("witch_spawn",  Event_WitchSpawn);

    AutoExecConfig(true, "l4d_si_hp_reward");
}

public void Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
    if (!g_cvEnabled.BoolValue)
        return;

    int victim   = GetClientOfUserId(event.GetInt("userid"));
    int attacker = GetClientOfUserId(event.GetInt("attacker"));

    if (victim == 0 || !IsClientInGame(victim) || GetClientTeam(victim) != TEAM_INFECTED)
        return;

    int zombieClass = GetEntProp(victim, Prop_Send, "m_zombieClass");
    if (zombieClass < ZC_SMOKER || zombieClass > ZC_TANK)
        return;

    if (zombieClass == ZC_WITCH)
        return;

    RewardPlayer(attacker, zombieClass);
}

public void Event_WitchSpawn(Event event, const char[] name, bool dontBroadcast)
{
    int witch = event.GetInt("witchid");
    if (witch > 0 && IsValidEntity(witch))
        SDKHook(witch, SDKHook_OnTakeDamagePost, OnWitchTakeDamagePost);
}

public void OnWitchTakeDamagePost(int victim, int attacker, int inflictor, float damage,
    int damagetype, int weapon, const float damageForce[3], const float damagePosition[3], int damagecustom)
{
    if (!g_cvEnabled.BoolValue)
        return;

    if (GetEntProp(victim, Prop_Data, "m_iHealth") <= 0)
    {
        if (!g_bWitchRewarded[victim])
        {
            g_bWitchRewarded[victim] = true;
            RewardPlayer(attacker, ZC_WITCH);
        }
    }
}

public void OnEntityDestroyed(int entity)
{
    if (entity >= 0 && entity < 2048)
        g_bWitchRewarded[entity] = false;
}

void RewardPlayer(int client, int zombieClass)
{
    if (client <= 0 || client > MaxClients || !IsClientInGame(client) || !IsPlayerAlive(client))
        return;
    if (GetClientTeam(client) != TEAM_SURVIVOR)
        return;
    if (GetEntProp(client, Prop_Send, "m_isIncapacitated"))
        return;

    float reward = g_cvHp[zombieClass].FloatValue;
    if (reward <= 0.0)
        return;

    int curHealth = GetClientHealth(client);
    int maxHealth = g_cvMaxHealth.IntValue;

    if (!g_cvOverheal.BoolValue)
    {
        int newHealth = curHealth + RoundToNearest(reward);
        if (newHealth > maxHealth)
            newHealth = maxHealth;
        if (newHealth > curHealth)
            SetEntityHealth(client, newHealth);
    }
    else
    {
        int target = curHealth + RoundToNearest(reward);
        if (target > maxHealth)
        {
            float excess = float(target - maxHealth);
            if (maxHealth > curHealth)
                SetEntityHealth(client, maxHealth);

            float buffer = GetEntPropFloat(client, Prop_Send, "m_healthBuffer");
            SetEntPropFloat(client, Prop_Send, "m_healthBuffer", buffer + excess);
            SetEntPropFloat(client, Prop_Send, "m_healthBufferTime", GetGameTime());
        }
        else if (target > curHealth)
        {
            SetEntityHealth(client, target);
        }
    }

    if (g_cvShowHint.BoolValue)
        PrintHintText(client, "击杀 %s 奖励 +%.0f 生命值", g_sClassName[zombieClass], reward);
}
