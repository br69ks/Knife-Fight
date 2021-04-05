#include <sourcemod>
#include <sdktools>
#include <knifefight>
#include <knifefight/chat.sp>
#tryinclude <devzones>
#include <clientprefs>

#pragma semicolon 1
#pragma newdecls required

#define PLUGIN_VERSION "1.0"

public Plugin myinfo = 
{
	name = "Knife Fight", 
	author = "brooks",  // based on the work of XARiUS and Otstrel.Ru Team :D
	description = "Last two players alive can choose to knife fight", 
	version = PLUGIN_VERSION, 
	url = "https://steamcommunity.com/id/brooooks"
};

#define WEAPONS_MAX_LENGTH 32
#define WEAPONS_SLOTS_MAX 5

int Player1, 
	Player2, 
	Player1Agree, 
	Player2Agree, 
	timeleft, 
	PreFightTimer, 
	g_beamsprite, 
	g_halosprite,
	songsfound = 0;

enum WeaponsSlot
{
	Slot_Invalid = -1, 
	Slot_Primary = 0, 
	Slot_Secondary = 1, 
	Slot_Melee = 2, 
	Slot_Projectile = 3, 
	Slot_Explosive = 4, 
	Slot_NVGs = 5, 
}

char g_FightSongs[20][PLATFORM_MAX_PATH];

char Player1Weapons[8][64], Player2Weapons[8][64];

bool FightInProgress, CSGO, CSS = false;
bool NoblockEnabled = true;

ConVar cvBuyAnywhere, 
       cvFightTime,
       cvTeleport,
       cvForce,
       cvMinPlayers,
       cvFightSong,
       cvDevZones;       

Handle Cookie_FightPref, Cookie_SoundPref = INVALID_HANDLE;
int C_FightPref[MAXPLAYERS + 1], C_SoundPref[MAXPLAYERS + 1];

Handle hFightStarted, hFightEnded;

public void OnPluginStart()
{
	if (GetEngineVersion() == Engine_CSGO)
		CSGO = true;
	if (GetEngineVersion() == Engine_CSS)
		CSS = true;
	
	CHAT_DetectColorMsg();
	LoadTranslations("knifefight.phrases");
	CreateConVar("sm_knifefight_version", PLUGIN_VERSION, "KnifeFight Version", FCVAR_REPLICATED | FCVAR_NOTIFY | FCVAR_DONTRECORD);
	cvFightTime = CreateConVar("sm_knifefight_time", "30", "Duration of the knife fight");
	cvTeleport = CreateConVar("sm_knifefight_teleport", "1", "Teleport players before the fight", _, true, 0.0, true, 1.0);
	cvForce = CreateConVar("sm_knifefight_forcefight", "0", "Force players to fight", _, true, 0.0, true, 1.0);
	cvMinPlayers = CreateConVar("sm_knifefight_minplayers", "3", "Min players to allow knife fight");
	cvFightSong = CreateConVar("sm_knifefight_fightsong", "0", "Play random song from config during the fight", _, true, 0.0, true, 1.0);
	cvDevZones = CreateConVar("sm_knifefight_devzones", "0", "Teleport player to a specific zone on a map (zone must be named <mapname>_knifefight)", _, true, 0.0, true, 1.0);
	
	if (cvDevZones.BoolValue)
		cvTeleport.BoolValue = false;
		
	AutoExecConfig(true, "knifefight");
	
	cvBuyAnywhere = FindConVar("mp_buy_anywhere");
	
	HookEvent("player_death", EventPlayerDeath);
	HookEvent("round_start", EventRoundStart);
	HookEvent("round_end", EventRoundEnd);
	HookEvent("player_disconnect", EventPlayerDisconnect);
	
	
	RegConsoleCmd("kfmenu", cmd_kfmenu, "Open preferences menu for knife fight");
	
	Cookie_FightPref = RegClientCookie("sm_knifefight_fightpref", "Automatically accept/deny knifefight for client", CookieAccess_Private);
	Cookie_SoundPref = RegClientCookie("sm_knifefight_soundpref", "Disable/Enable fight sounds", CookieAccess_Private);
	
	int info;
	SetCookieMenuItem(Client_CookieMenuHandler, info, "Knife Fight");
	
	for (int i = 1; i <= MaxClients; i++)
	{
		C_SoundPref[i] = 1;
		C_FightPref[i] = 0;
	}
	
	g_beamsprite = PrecacheModel("materials/sprites/lgtning.vmt");
	g_halosprite = PrecacheModel("materials/sprites/halo01.vmt");
	
	if (cvFightSong.BoolValue)
		ParseSongs();
}

public void OnMapStart()
{
	if (cvFightSong.BoolValue)
		ParseSongs();
}

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	hFightStarted = CreateGlobalForward("OnKnifeFightStarted", ET_Ignore, Param_Cell, Param_Cell);
	hFightEnded = CreateGlobalForward("OnKnifeFightEnded", ET_Ignore, Param_Cell);
	
	return APLRes_Success;
}

public void OnClientCookiesCached(int client)
{
	char buffer[5];
	GetClientCookie(client, Cookie_SoundPref, buffer, sizeof(buffer));
	if (!StrEqual(buffer, ""))
		C_SoundPref[client] = StringToInt(buffer);
		
	GetClientCookie(client, Cookie_FightPref, buffer, sizeof(buffer));
	if (!StrEqual(buffer, ""))
		C_FightPref[client] = StringToInt(buffer);
}

public void Client_CookieMenuHandler(int client, CookieMenuAction action, any info, char[] buffer, int maxlen)
{
	client_kfmenu(client);
}

public Action cmd_kfmenu(int client, int args)
{
	client_kfmenu(client);
}

public void client_kfmenu(int client)
{
	Menu menu = CreateMenu(client_kfmenu_hndl);
	char buffer[64];
	Format(buffer, sizeof(buffer), "%t", "KnifeFight settings");
	menu.SetTitle(buffer);
	
	Format(buffer, sizeof(buffer), "%t %t", "Play fight songs", C_SoundPref[client] ? "Selected" : "NotSelected");
	menu.AddItem("Play fight songs", buffer);
	
	Format(buffer, sizeof(buffer), "%t", "Show fight panel");
	menu.AddItem("Show fight panel", buffer, (!FightInProgress && MaxClients >= 3 && GetLivePlayerCount() == 2) ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
	
	Format(buffer, sizeof(buffer), "%t %t", "Always agree to knife fight", C_FightPref[client] == 1 ? "Selected" : "NotSelected");
	menu.AddItem("Always agree to knife fight", buffer);
	
	Format(buffer, sizeof(buffer), "%t %t", "Always disagree to knife fight", C_FightPref[client] == -1 ? "Selected" : "NotSelected");
	menu.AddItem("Always disagree to knife fight", buffer);
	
	menu.ExitButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
}

public int client_kfmenu_hndl(Menu menu, MenuAction action, int client, int item)
{
	switch (action)
	{
		case MenuAction_Select:
		{
			if (item == 0)
			{
				C_SoundPref[client] = C_SoundPref[client] ? 0 : 1;
				char buffer[5];
				IntToString(C_SoundPref[client], buffer, sizeof(buffer));
				SetClientCookie(client, Cookie_SoundPref, buffer);
				client_kfmenu(client);
			}
			else if (item == 1)
			{
				if (!FightInProgress && MaxClients >= cvMinPlayers.IntValue && GetLivePlayerCount() == 2)
					SendKnifeMenu(client);
				else
					client_kfmenu(client);
			}
			else if (item == 2 || item == 3)
			{
				if ((item == 2 && C_FightPref[client] == 1) || (item == 3 && C_FightPref[client] == -1))
					C_FightPref[client] = 0;
				else
					C_FightPref[client] = item == 2 ? 1 : -1;
					
				char buffer[5];
				IntToString(C_FightPref[client], buffer, sizeof(buffer));
				SetClientCookie(client, Cookie_FightPref, buffer);
				client_kfmenu(client);
			}
		}
		case MenuAction_End:
			menu.Close();
	}
}

public Action EventPlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
	if (GetEngineVersion() == Engine_CSGO)
		if (GameRules_GetProp("m_bWarmupPeriod") == 1)
			return Plugin_Continue;
	
	if (FightInProgress)
		EndFight();
	
	if (MaxClients >= 3 && GetLivePlayerCount() == 2)
	{
		for (int i = 1; i <= MaxClients; i++)
		{
			if (IsClientInGame(i) && IsPlayerAlive(i))
			{
				if (Player1 == 0)
					Player1 = i;
				else if (Player2 == 0)
					Player2 = i;
			}
		}
		
		if (CSGO)
			if (FindConVar("mp_teammates_are_enemies").IntValue == 0 && GetClientTeam(Player1) == GetClientTeam(Player2))
				return Plugin_Continue;
		
		if (CSS)
			if (GetClientTeam(Player1) == GetClientTeam(Player2))
				return Plugin_Continue;
				
		PrintCenterTextAll("%t", "1v1 situation");
		InitKnifeFight();
		return Plugin_Continue;
	}
	return Plugin_Continue;
}

public Action EventRoundEnd(Event event, const char[] name, bool dontBroadcast)
{	
	if (FightInProgress)
		EndFight();
	
	ResetFight();
}

public Action EventRoundStart(Event event, const char[] name, bool dontBroadcast)
{
	ResetFight();
}

public Action EventPlayerDisconnect(Event event, const char[] name, bool dontBroadcast)
{
	if (!FightInProgress)
		return Plugin_Continue;
	
	int client = GetClientOfUserId(event.GetInt("userid"));
	if (client == Player1 || client == Player2)
	{
		EndFight();
		return Plugin_Continue;
	}
	return Plugin_Continue;
}

void InitKnifeFight()
{
	char message[MAX_CHAT_SIZE];
	if (cvForce.BoolValue)
	{
		StartFight();
		return;
	}
	
	if (IsFakeClient(Player1))
	{
		Player1Agree = 1;
		Format(message, sizeof(message), " \x04[\x01KnifeFight\x04] \x03%N \x04%t", Player1, "Player agrees");
		CHAT_SayText(0, Player1, message);
	}
	else if (C_FightPref[Player1] == 1)
	{
		Player1Agree = 1;
		Format(message, sizeof(message), " \x04[\x01KnifeFight\x04] \x03%N \x04%t", Player1, "Player agrees");
		CHAT_SayText(0, Player1, message);
	}
	else if (C_FightPref[Player1] == -1)
	{
		Format(message, sizeof(message), " \x04[\x01KnifeFight\x04] \x03%N \x04%t", Player1, "Player disagrees");
		CHAT_SayText(0, Player1, message);
	}
	else
		SendKnifeMenu(Player1);
	
	
	if (IsFakeClient(Player2))
	{
		Player2Agree = 1;
		Format(message, sizeof(message), " \x04[\x01KnifeFight\x04] \x03%N \x04%t", Player2, "Player agrees");
		CHAT_SayText(0, Player2, message);
	}
	else if (C_FightPref[Player2] == 1)
	{
		Player2Agree = 1;
		Format(message, sizeof(message), " \x04[\x01KnifeFight\x04] \x03%N \x04%t", Player2, "Player agrees");
		CHAT_SayText(0, Player2, message);
	}
	else if (C_FightPref[Player2] == -1)
	{
		Format(message, sizeof(message), " \x04[\x01KnifeFight\x04] \x03%N \x04%t", Player2, "Player disagrees");
		CHAT_SayText(0, Player2, message);
	}
	else
		SendKnifeMenu(Player2);
	
	if (Player1Agree == 1 && Player2Agree == 1)
		StartFight();
}

void SendKnifeMenu(int client)
{
	char title[128], question[128], yes[128], no[128];
	Format(title, sizeof(title), "%t", "Knife menu title");
	Format(question, sizeof(question), "%t", "Knife question");
	Format(yes, sizeof(yes), "%t", "Yes option");
	Format(no, sizeof(no), "%t", "No option");
	
	Panel kfmenu = CreatePanel();
	kfmenu.SetTitle(title);
	kfmenu.DrawItem(" ", ITEMDRAW_SPACER | ITEMDRAW_RAWLINE);
	kfmenu.DrawText(question);
	kfmenu.DrawText("-----------------------------");
	kfmenu.DrawItem(yes);
	kfmenu.DrawItem(no);
	kfmenu.DrawText("-----------------------------");
	kfmenu.Send(client, kfmenu_hndl, 10);
	kfmenu.Close();
}

public int kfmenu_hndl(Menu kfmenu, MenuAction action, int client, int item)
{
	char message[MAX_CHAT_SIZE];
	switch (action)
	{
		case MenuAction_Select:
		{
			
			if (item == 1)
			{
				if (Player1 == client)
				{
					Player1Agree = 1;
					Format(message, sizeof(message), " \x04[\x01KnifeFight\x04] \x03%N \x04%t", Player1, "Player agrees");
					CHAT_SayText(0, Player1, message);
				}
				else
				{
					Player2Agree = 1;
					Format(message, sizeof(message), " \x04[\x01KnifeFight\x04] \x03%N \x04%t", Player2, "Player agrees");
					CHAT_SayText(0, Player2, message);
				}
			}
			
			if (item == 2)
			{
				if (Player1 == client)
				{
					Format(message, sizeof(message), " \x04[\x01KnifeFight\x04] \x03%N \x04%t", Player1, "Player disagrees");
					CHAT_SayText(0, Player1, message);
				}
				else
				{
					Format(message, sizeof(message), " \x04[\x01KnifeFight\x04] \x03%N \x04%t", Player2, "Player disagrees");
					CHAT_SayText(0, Player2, message);
				}
			}
		}
		
		case MenuAction_Cancel:
		{
			if (IsClientInGame(client) && IsPlayerAlive(client))
			{
				Format(message, sizeof(message), " \x04[\x01KnifeFight\x04] %t", "Restore fight menu");
				CHAT_SayText(client, 0, message);
			}
		}
	}
	
	if (Player1Agree == 1 && Player2Agree == 1)
	{
		Format(message, sizeof(message), " \x04[\x01KnifeFight\x04] %t", "Both agree");
		CHAT_SayText(0, 0, message);
		StartFight();
	}
}

void StartFight()
{
	FightInProgress = true;
	
	if (CSGO)
		if (cvBuyAnywhere.IntValue == 1)
			cvBuyAnywhere.SetInt(0);
			
	if (cvFightSong.BoolValue)
	{
		int[] clients = new int[MaxClients];
		int total = 0;
		int randomsong = 0;
		char song[PLATFORM_MAX_PATH];
		
		if (songsfound > 1)
            randomsong = GetRandomInt(0, songsfound - 1);
		strcopy(song, sizeof(song), g_FightSongs[randomsong]);
        
		for (int i = 1; i <= MaxClients; i++)
			if (IsClientInGame(i) && C_SoundPref[i] == 1)
				clients[total++] = i;
		
		EmitSound(clients, total, song, _, SNDCHAN_AUTO, SNDLEVEL_NORMAL, SND_NOFLAGS, SNDVOL_NORMAL, SNDPITCH_NORMAL);
				
	}
	
	PrintCenterTextAll("%t", "Removing weapons");
	RemoveMapWeapons();
	RemovePlayersWeapons(Player1);
	RemovePlayersWeapons(Player2);
	SetEntityHealth(Player1, 100);
	SetEntityHealth(Player2, 100);
	UnblockEntity(Player1);
	UnblockEntity(Player2);
	
	timeleft = cvFightTime.IntValue;
	PreFightTimer = 5;
	
	CreateTimer(2.0, StartBeacon, Player1, TIMER_REPEAT);
	CreateTimer(2.0, StartBeacon, Player2, TIMER_REPEAT);
	CreateTimer(1.0, PreStart, _, TIMER_REPEAT);
	
	Call_StartForward(hFightStarted);
	Call_PushCell(Player1);
	Call_PushCell(Player2);
	Call_Finish();
}

public Action PreStart(Handle timer)
{
	if (!FightInProgress)
	{
		return Plugin_Stop;
	}
	
	if (PreFightTimer > 0)
	{
		PrintCenterTextAll("%t: %d", "Prepare fight", PreFightTimer);
		if (PreFightTimer == 3)
		{
			TeleportPlayers();
		}
	}
	else
	{
		EquipKnife(Player1);
		EquipKnife(Player2);
		PrintCenterTextAll("%t", "Fight");
		CreateTimer(1.0, FightTimer, _, TIMER_REPEAT);
		return Plugin_Stop;
	}
	PreFightTimer--;
	return Plugin_Continue;
}

void TeleportPlayers()
{
	if (cvTeleport.BoolValue)
	{
		float pos[3], angles[3], velocity[3];
		GetClientAbsOrigin(Player1, pos);
		GetClientEyeAngles(Player1, angles);
		velocity = GetClientVelocity(Player1);
		TeleportEntity(Player2, pos, angles, velocity);
	}
	else if (cvDevZones.BoolValue)
	{
		float position[3];
		char mapname[64], zone[64];
		GetCurrentMap(mapname, sizeof(mapname));
		Format(zone, sizeof(zone), "%s_knifefight", mapname);
		Zone_GetZonePosition(zone, false, position);
		TeleportEntity(Player1, position, NULL_VECTOR, NULL_VECTOR);
		TeleportEntity(Player2, position, NULL_VECTOR, NULL_VECTOR);
	}
}

public void EquipKnife(int client)
{
	GivePlayerItem(client, "weapon_knife");
	FakeClientCommand(client, "use weapon_knife");
}

public Action FightTimer(Handle timer)
{
	if (!FightInProgress)
	{
		return Plugin_Stop;
	}
	
	if (timeleft > 0)
	{
		PrintCenterTextAll("%t: %d", "Time remaining", timeleft);
	}
	if (timeleft <= 0)
	{
		EndFight();
		return Plugin_Stop;
	}
	timeleft--;
	return Plugin_Continue;
}

public Action StartBeacon(Handle timer, int client)
{
	if (!FightInProgress || !IsClientInGame(Player1) || !IsClientInGame(Player2))
	{
		return Plugin_Stop;
	}
	
	// isFighting && both fighters alive
	int redColor[4] =  { 255, 75, 75, 255 };
	int blueColor[4] =  { 75, 75, 255, 255 };
	float vec[3];
	GetClientAbsOrigin(client, vec);
	vec[2] += 10;
	
	if (GetClientTeam(client) == 2)
	{
		TE_SetupBeamRingPoint(vec, 10.0, 800.0, g_beamsprite, g_halosprite, 
			0, 10, 1.0, 10.0, 0.0, redColor, 0, 0);
	}
	else if (GetClientTeam(client) == 3)
	{
		TE_SetupBeamRingPoint(vec, 10.0, 800.0, g_beamsprite, g_halosprite, 
			0, 10, 1.0, 10.0, 0.0, blueColor, 0, 0);
	}
	TE_SendToAll();
	
	GetClientEyePosition(client, vec);
	EmitAmbientSound("buttons/blip1.wav", vec, client, SNDLEVEL_RAIDSIREN);
	return Plugin_Continue;
}

void EndFight()
{
	FightInProgress = false;
	if (CSGO)
		if (cvBuyAnywhere.IntValue == 1)
			cvBuyAnywhere.SetInt(1);
			
	char message[MAX_CHAT_SIZE];
	if (IsPlayerAlive(Player1) && IsPlayerAlive(Player2))
	{
		ForcePlayerSuicide(Player1);
		ForcePlayerSuicide(Player2);
		PrintCenterTextAll("%t", "Fight draw");
		Format(message, sizeof(message), " \x04[\x01KnifeFight\x04] %t", "Fight draw");
		CHAT_SayText(0, 0, message);
	}
	int who_won = IsClientInGame(Player1) && IsPlayerAlive(Player1) ? Player1 : Player2;
	GivePlayersWeapons(who_won);
	Format(message, sizeof(message), " \x04[\x01KnifeFight\x04] \x03%N \x04%t", who_won, "has won");
	CHAT_SayText(0, who_won, message);
	BlockEntity(Player1);
	BlockEntity(Player2);
	
	Call_StartForward(hFightEnded);
	Call_PushCell(who_won);
	Call_Finish();
}

void RemovePlayersWeapons(int client)
{
	for (int i = 0; i <= 128; i += 4)
	{
		int count = 0;
		int weapon = -1;
		char classname[32];
		int g_iMyWeapons = FindSendPropInfo("CBaseCombatCharacter", "m_hMyWeapons");
		weapon = GetEntDataEnt2(client, (g_iMyWeapons + i));
		
		if (!IsValidEdict(weapon))
			return;
		
		GetEdictClassname(weapon, classname, sizeof(classname));
		
		if ((weapon != -1) && !StrEqual(classname, "worldspawn", false))
		{
			RemovePlayerItem(client, weapon);
			RemoveEdict(weapon);
			if (client == Player1)
				Player1Weapons[count++] = classname;
			
			else if (client == Player2)
				Player2Weapons[count++] = classname;
		}
	}
}

void RemoveMapWeapons()
{
	int maxent = GetMaxEntities();
	char weapon[64];
	int g_WeaponParent = FindSendPropInfo("CBaseCombatWeapon", "m_hOwnerEntity");
	for (int i = MaxClients; i < maxent; i++)
	{
		if (IsValidEdict(i) && IsValidEntity(i) && GetEntDataEnt2(i, g_WeaponParent) == -1)
		{
			GetEdictClassname(i, weapon, sizeof(weapon));
			if (StrContains(weapon, "weapon_") != -1 // remove weapons
				 || StrEqual(weapon, "hostage_entity", true) // remove hostages
				 || StrContains(weapon, "item_") != -1) // remove bombs
			{
				RemoveEdict(i);
			}
		}
	}
}

void GivePlayersWeapons(int client)
{
	for (int i = 0; i <= 7; i++)
	{
		if (IsClientInGame(client))
		{
			if (client == Player1)
			{
				if (!StrEqual(Player1Weapons[i], "", false))
					GivePlayerItem(client, Player1Weapons[i]);
			}
			else if (client == Player2)
			{
				if (!StrEqual(Player2Weapons[i], "", false))
					GivePlayerItem(client, Player2Weapons[i]);
			}
		}
	}
}

void ResetFight()
{
	Player1 = 0;
	Player2 = 0;
	Player1Agree = 0;
	Player2Agree = 0;
	FightInProgress = false;
}

void UnblockEntity(int entity)
{
	int g_offsCollisionGroup = FindSendPropInfo("CBaseEntity", "m_CollisionGroup");
	if (GetEntData(entity, g_offsCollisionGroup, 4) == 5)
	{
		NoblockEnabled = false;
		SetEntData(entity, g_offsCollisionGroup, 2, 4, true);
	}
}

void BlockEntity(int entity)
{
	int g_offsCollisionGroup = FindSendPropInfo("CBaseEntity", "m_CollisionGroup");
	if (!NoblockEnabled)
		SetEntData(entity, g_offsCollisionGroup, 5, 4, true);
}

void ParseSongs()
{
	KeyValues kv = CreateKeyValues("Songs");
	
	char path[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, path, sizeof(path), "configs/knifefight_songs.cfg");
	
	if (!kv.ImportFromFile(path)) 
	{
		SetFailState("[KnifeFight] Couldn't load config file %s.", path);
		return;
	}
	
	kv.Rewind();
	
	songsfound = 0;
	if (kv.JumpToKey("Songs") && kv.GotoFirstSubKey())
	{
		do
		{
			kv.GetString("path", g_FightSongs[songsfound], PLATFORM_MAX_PATH);
			AddFileToDownloadsTable(g_FightSongs[songsfound]);
			PrecacheSound(g_FightSongs[songsfound]);
			songsfound++;
		}
		while (kv.GotoNextKey());
	}
	kv.Close();
	
}

int GetLivePlayerCount()
{
	int count;
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientConnected(i) && IsClientInGame(i) && IsPlayerAlive(i))
			count++;
	}
	return count;
}

float GetClientVelocity(int client)
{
	float vel[3];
	vel[0] = GetEntPropFloat(client, Prop_Send, "m_vecVelocity[0]");
	vel[1] = GetEntPropFloat(client, Prop_Send, "m_vecVelocity[1]");
	vel[2] = GetEntPropFloat(client, Prop_Send, "m_vecVelocity[2]");
	return vel;
} 