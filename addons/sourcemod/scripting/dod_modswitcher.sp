/**
* DoD:S Mod Switcher by Root
*
* Description:
*   Allows admins to switch game modes on-the-fly via menu.
*   Game modes that switcher supports: GunGame, Hide & Seek, DeathMatch, Zombie Mod and Realism Match Helper.
*
* Version 1.0
* Changelog & more info at http://goo.gl/4nKhJ
*/

// Make "adminmenu" plugin as optional
#undef REQUIRE_PLUGIN
#include <adminmenu>

// Make "steamtools extension" as optional too
#undef REQUIRE_EXTENSIONS
#tryinclude <steamtools>

// ====[ CONSTANTS ]===================================================
#define PLUGIN_NAME    "DoD:S Mod Switcher"
#define PLUGIN_VERSION "1.0"

enum // Game Modes defines
{
	GunGamePure,
	GunGameFull,
	GunGameOriginal,
	HideAndSeek,
	DeathMatch,
	ZombieMod,
	RealismMatch,
	Default
};

// Names of the supported plugins to search
static const String:PluginFileNames[][] =
{
	"dod_gungame4.2pure.smx",
	"dod_gungame4.2.smx",
	"dod_gungame.smx",
	"sm_hidenseek.smx",
	"dod_deathmatch.smx",
	"dod_zombiemod.smx",
	"dod_realismmatch_helper.smx"
};

// Appropriate configuration files for those plugins
static const String:PluginConfigFiles[][] =
{
	"modswitcher/gungame_pure.cfg",
	"modswitcher/gungame_full.cfg",
	"modswitcher/gungame_original.cfg",
	"modswitcher/hideandseek.cfg",
	"modswitcher/deathmatch.cfg",
	"modswitcher/zombiemod.cfg",
	"modswitcher/realismmatch.cfg"
};

// ====[ VARIABLES ]===================================================
new	bool:GG_Available, bool:GG_Loaded,
	bool:HS_Available, bool:HS_Loaded,
	bool:DM_Available, bool:DM_Loaded,
	bool:ZM_Available, bool:ZM_Loaded,
	bool:RM_Available, bool:RM_Loaded;

new	Handle:AdminMenuHandle  = INVALID_HANDLE,
	Handle:ModeSelectHandle = INVALID_HANDLE,
	Handle:mp_restartwarmup = INVALID_HANDLE,
	Handle:GameMode         = INVALID_HANDLE,
	Handle:SwitchAction     = INVALID_HANDLE,
	GunGameVersion          = -1,
	bool:PrintInfoAtStart   = false;

public Plugin:myinfo =
{
	name        = PLUGIN_NAME,
	author      = "Root",
	description = "Allows admins to switch game modes (GG, H&S, DM, ZM and Realism) on-the-fly",
	version     = PLUGIN_VERSION,
	url         = "http://dodsplugins.com/"
};


/* AskPluginLoad2()
 *
 * Called before plugin starts.
 * ----------------------------------------------------------------- */
public APLRes:AskPluginLoad2(Handle:myself, bool:late, String:error[], err_max)
{
	MarkNativeAsOptional("Steam_SetGameDescription");
	return APLRes_Success;
}

/* OnPluginStart()
 *
 * When the plugin starts up.
 * -------------------------------------------------------------------- */
public OnPluginStart()
{
	// Create console variables
	CreateConVar("dod_modswitcher_version", PLUGIN_VERSION, PLUGIN_NAME, FCVAR_NOTIFY|FCVAR_DONTRECORD);
	GameMode     = CreateConVar("dod_gamemode",               "",  "Sets the game mode:\n0 = Default\ng = GunGame\nh = Hide & Seek\nd = DeathMatch\nz = Zombie Mod\nr = Realism Match", FCVAR_PLUGIN, true, 0.0);
	SwitchAction = CreateConVar("dod_gamemode_switch_action", "1", "Determines an action when game mode has changed:\n0 = Round restart\n1 = Map restart", FCVAR_PLUGIN, true, 0.0, true, 1.0);

	// Hook main ConVar changes to detect selected game modes
	HookConVarChange(GameMode, UpdateGameMode);

	// It's better to make convar handle as a global one
	mp_restartwarmup = FindConVar("mp_restartwarmup");

	// Need to notify players about changed gameplay
	HookEvent("dod_round_active", OnRoundStart, EventHookMode_PostNoCopy);
}

/* OnAllPluginsLoaded()
 *
 * Called after all plugins have been loaded.
 * -------------------------------------------------------------------- */
public OnAllPluginsLoaded()
{
	/** Not working for unknown reason
	*
	new Handle:MyPlugin = FindPluginByFile(PluginFileNames[MyPlugin]);
	if (MyPlugin != INVALID_HANDLE
	|| GetPluginStatus(MyPlugin) != Plugin_Running)
	{
	}
	*/

	// Admin menu integration
	new Handle:topmenu;
	if (LibraryExists("adminmenu") && ((topmenu = GetAdminTopMenu()) != INVALID_HANDLE))
	{
		OnAdminMenuReady(topmenu);
	}

	// Maximum path length
	decl String:GG[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, GG, sizeof(GG), "plugins/optional/%s", PluginFileNames[GunGamePure]);

	// Such a silly way to detect plugins
	if (FileExists(GG))
	{
		// Okay we're found 'Pure' version of GunGame now
		GG_Available   = true;
		GunGameVersion = GunGamePure;
	}
	else // Otherwise if we could not find pure GunGame, probably the 'full' version is running?
	{
		BuildPath(Path_SM, GG, sizeof(GG), "plugins/optional/%s", PluginFileNames[GunGameFull]);
		if (FileExists(GG))
		{
			// Yep, accept appropriate changes
			GG_Available   = true;
			GunGameVersion = GunGameFull;
		}
		else
		{
			// Format plugin string to properly find it within 'plugins/optional' folder
			BuildPath(Path_SM, GG, sizeof(GG), "plugins/optional/%s", PluginFileNames[GunGameOriginal]);
			if (FileExists(GG))
			{
				GG_Available = true;

				// Or it's even may be an original GunGame
				GunGameVersion = GunGameOriginal;
			}
		}
	}

	// Search for Hide & Seek as well
	decl String:HS[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, HS, sizeof(HS), "plugins/optional/%s", PluginFileNames[HideAndSeek]);
	if (FileExists(HS))
	{
		HS_Available = true;
	}

	decl String:DM[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, DM, sizeof(DM), "plugins/optional/%s", PluginFileNames[DeathMatch]);
	if (FileExists(DM))
	{
		// DeathMatch
		DM_Available = true;
	}

	// It's such a dirty way to detect plugins, but FindPluginByFile native is not working for plugins, which within an 'optional' folder
	decl String:ZM[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, ZM, sizeof(ZM), "plugins/optional/%s", PluginFileNames[ZombieMod]);
	if (FileExists(ZM))
	{
		// Those are not even running, but GetPluginStatus also wont work
		ZM_Available = true;
	}

	// So I have to use 'FileExists' check then, so if plugin is broken - it still mark it as 'available'
	decl String:RM[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, RM, sizeof(RM), "plugins/optional/%s", PluginFileNames[RealismMatch]);
	if (FileExists(RM))
	{
		RM_Available = true;
	}
}

/* OnAllPluginsLoaded()
 *
 * Called all AutoExecConfig() exec commands have been added.
 * -------------------------------------------------------------------- */
public OnAutoConfigsBuffered()
{
	// If any mod is running atm, exec specified config after mapchange
	if (GG_Loaded)
	{
		ServerCommand("exec %s", PluginConfigFiles[GunGameVersion]);
	}
	else if (HS_Loaded)
	{
		// It's also silly way actually...
		ServerCommand("exec %s", PluginConfigFiles[HideAndSeek]);
	}
	else if (DM_Loaded)
	{
		// But since only 1 mod can run per map/round, its working fine...
		ServerCommand("exec %s", PluginConfigFiles[DeathMatch]);
	}
	else if (ZM_Loaded)
	{
		// TBH I'd use AutoExecFile(false, "config file name here.cfg"), but if mod was once loaded...
		ServerCommand("exec %s", PluginConfigFiles[ZombieMod]);
	}
	else if (RM_Loaded)
	{
		// Then mod-specified config would load at every mapchange (didnt it?)
		ServerCommand("exec %s", PluginConfigFiles[RealismMatch]);
	}
}

/* OnAllPluginsLoaded()
 *
 * Called when the admin menu is ready to have items added.
 * -------------------------------------------------------------------- */
public OnAdminMenuReady(Handle:topmenu)
{
	// Block menu handle from being called more than once
	if (topmenu == AdminMenuHandle)
	{
		return;
	}

	AdminMenuHandle = topmenu;

	// If the category is third party, it will have its own unique name
	new TopMenuObject:server_commands = FindTopMenuCategory(AdminMenuHandle, ADMINMENU_SERVERCOMMANDS);

	if (server_commands == INVALID_TOPMENUOBJECT)
	{
		// Error!
		return;
	}

	// Add 'Game Modes' category to "ServerCommands" menu
	AddToTopMenu(AdminMenuHandle, "gamemode", TopMenuObject_Item, AdminMenu_SetGameMode, server_commands, "gamemode_overrides", ADMFLAG_RCON);
}

/* UpdateGameMode()
 *
 * Called when the game mode has changed.
 * -------------------------------------------------------------------- */
public UpdateGameMode(Handle:convar, const String:oldValue[], const String:newValue[])
{
	// If any mod was loaded before, unload it now
	if (GG_Loaded)
	{
		GG_Loaded = false;

		// Unload _appropriate_ gungame plugin version
		UnloadPlugin(GunGameVersion);
	}
	else if (HS_Loaded)
	{
		// Also dont forget to set global bool to 'false' for given mod
		HS_Loaded = false;
		UnloadPlugin(HideAndSeek);
	}
	else if (DM_Loaded)
	{
		DM_Loaded = false;
		UnloadPlugin(DeathMatch);
	}

	// Only one mod can be loaded at a time, so 'else if' statement is better to use in this case
	else if (ZM_Loaded)
	{
		ZM_Loaded = false;
		UnloadPlugin(ZombieMod);
	}
	else if (RM_Loaded)
	{
		RM_Loaded = false;
		UnloadPlugin(RealismMatch);
	}

	// I dont like to convert string to an integer. And I also dont like comparing with old value; Well is not necessary here
	switch (newValue[0])
	{
		// Gameplay changed to 'GunGame'
		case 'g':
		{
			if (GG_Available)
			{
				GG_Loaded = true;
				LoadPlugin(GunGameVersion);
			}
		}
		case 'h': // Hide & Seek
		{
			// Make sure plugin is available
			if (HS_Available)
			{
				HS_Loaded = true;
				LoadPlugin(HideAndSeek);
			}
		}
		case 'd': // DeathMatch
		{
			// Because I like to keep plugin 'clean'
			if (DM_Available)
			{
				DM_Loaded = true;
				LoadPlugin(DeathMatch);
			}
		}
		case 'z': // Zombie Mod
		{
			if (ZM_Available)
			{
				// Set the global bool, so mod is loaded
				ZM_Loaded = true;
				LoadPlugin(ZombieMod);
			}
		}
		case 'r': // Realism Match
		{
			if (RM_Available)
			{
				RM_Loaded = true;

				// And finally load the plugin
				LoadPlugin(RealismMatch);
			}
		}

#if defined _steamtools_included
		default:
		{
			// If mod was changed to default, once again make sure SteamTools is working
			if (LibraryExists("SteamTools"))
			{
				// And now set the game description to original (because GG, H&S, DM, ZM is having custom game description)
				Steam_SetGameDescription("Day of Defeat: Source");
			}
		}
#endif

	}

	// Refresh configs after changing a mode
	OnAutoConfigsBuffered();

	// BTW 4 seconds is actually 3 for mp_restartwarmup cvar
	if (SetConVarInt(mp_restartwarmup, 4))
	{
		// Make sure to notify players about changed game play during game
		PrintInfoAtStart = true;
	}

	// If map should be changed, create 3-second timer and just refresh the current map (to accept all plugin hooks)
	if (GetConVarInt(SwitchAction))
	{
		CreateTimer(3.0, Timer_RefreshMap, _, TIMER_FLAG_NO_MAPCHANGE);
	}
}

/* OnRoundStart()
 *
 * Called when the new round is started.
 * -------------------------------------------------------------------- */
public OnRoundStart(Handle:event, const String:name[], bool:dontBroadcast)
{
	// Players should be notified about mod changes?
	if (PrintInfoAtStart == true)
	{
		// Retrieve the ConVar string to show to 'what mod we have changed exactly'
		decl String:value[2], String:gamemodestr[32];
		GetConVarString(GameMode, value, sizeof(value));

		// Once again retrieve the convar string
		switch (value[0])
		{
			// Just compare the string and prepare message
			case 'g': FormatEx(gamemodestr, sizeof(gamemodestr), "GunGame");
			case 'h': FormatEx(gamemodestr, sizeof(gamemodestr), "Hide & Seek");
			case 'd': FormatEx(gamemodestr, sizeof(gamemodestr), "DeathMatch");
			case 'z': FormatEx(gamemodestr, sizeof(gamemodestr), "Zombie Mod");
			case 'r': FormatEx(gamemodestr, sizeof(gamemodestr), "Realism Match");
			default:  FormatEx(gamemodestr, sizeof(gamemodestr), "default gamemode");
		}

		// Notify all players about new gameplay
		PrintToChatAll("\x01[\x04Mod Switcher\x01] \x05Server is now running \x04%s.", gamemodestr);

		// Don't show message next time
		PrintInfoAtStart = false;
	}
}

/* AdminMenu_SetGameMode()
 *
 * Called when the new round is started.
 * -------------------------------------------------------------------- */
public AdminMenu_SetGameMode(Handle:topmenu, TopMenuAction:action, TopMenuObject:object_id, param, String:buffer[], maxlength)
{
	switch (action)
	{
		// Display Menu selection item
		case TopMenuAction_DisplayOption:
		{
			// A name of the 'ServerCommands' category
			Format(buffer, maxlength, "Set Game Mode");
		}
		case TopMenuAction_SelectOption:
		{
			// Create topmenu handler for 'Select Mode' section
			ModeSelectHandle = CreateMenu(MenuHandler_GameMode, MenuAction_DrawItem|MenuAction_Select);

			// Set the menu title
			SetMenuTitle(ModeSelectHandle, "Select Mode");

			decl String:GameModeIdx[2];

			// Add game mode if available
			if (GG_Available)
			{
				IntToString(GunGameVersion, GameModeIdx, sizeof(GameModeIdx));
				AddMenuItem(ModeSelectHandle, GameModeIdx, "GunGame");
			}
			if (HS_Available)
			{
				// Convert mode index as a string to menu
				IntToString(HideAndSeek, GameModeIdx, sizeof(GameModeIdx));
				AddMenuItem(ModeSelectHandle, GameModeIdx, "Hide & Seek");
			}
			if (DM_Available)
			{
				// Add this into GameModes menu
				IntToString(DeathMatch, GameModeIdx, sizeof(GameModeIdx));
				AddMenuItem(ModeSelectHandle, GameModeIdx, "DeathMatch");
			}
			if (ZM_Available)
			{
				IntToString(ZombieMod, GameModeIdx, sizeof(GameModeIdx));
				AddMenuItem(ModeSelectHandle, GameModeIdx, "Zombie Mod");
			}
			if (RM_Available)
			{
				IntToString(RealismMatch, GameModeIdx, sizeof(GameModeIdx));
				AddMenuItem(ModeSelectHandle, GameModeIdx, "Realism Match");
			}

			// Also dont forget to add 'default gameplay' item into menu
			IntToString(Default, GameModeIdx, sizeof(GameModeIdx));
			AddMenuItem(ModeSelectHandle, GameModeIdx, "Default");

			// Add exit button too
			SetMenuExitButton(ModeSelectHandle, true);

			// And display menu as long as possible
			DisplayMenu(ModeSelectHandle, param, MENU_TIME_FOREVER);
		}
	}
}

/* MenuHandler_GameMode()
 *
 * Menu handler for server commands/game modes category.
 * -------------------------------------------------------------------- */
public MenuHandler_GameMode(Handle:menu, MenuAction:action, client, param)
{
	// Retrieve the action
	switch (action)
	{
		// Items is about to be displayed
		case MenuAction_DrawItem:
		{
			// Retrieve the information about a menu item
			decl String:display[2];
			GetMenuItem(menu, param, display, sizeof(display));

			// Convert menu item string to integer to conpare with mod index
			switch (StringToInt(display))
			{
				// Gungame mode is about to be displayed
				case
					GunGamePure,
					GunGameFull,     // If GunGame is loaded, dont allow player to select it once again
					GunGameOriginal: return (GG_Loaded) ? ITEMDRAW_DISABLED : ITEMDRAW_DEFAULT;
				case HideAndSeek:    return (HS_Loaded) ? ITEMDRAW_DISABLED : ITEMDRAW_DEFAULT;
				case DeathMatch:     return (DM_Loaded) ? ITEMDRAW_DISABLED : ITEMDRAW_DEFAULT;
				case ZombieMod:      return (ZM_Loaded) ? ITEMDRAW_DISABLED : ITEMDRAW_DEFAULT;
				case RealismMatch:   return (RM_Loaded) ? ITEMDRAW_DISABLED : ITEMDRAW_DEFAULT;
				default:
				{
					if (!GG_Loaded
					&&  !HS_Loaded
					&&  !DM_Loaded
					&&  !ZM_Loaded
					&&  !RM_Loaded)
					{
						// However if no mods were loaded, do the same with visibility 'Default gamemode' category
						return ITEMDRAW_DISABLED;
					}

					// Otherwise allow to select 'Default' category there
					return ITEMDRAW_DEFAULT;
				}
			}
		}

		// An item was selected
		case MenuAction_Select:
		{
			// Why? Because every mode has unique index in menu - so lets select mod corectly
			decl String:display[2];
			GetMenuItem(menu, param, display, sizeof(display));

			switch (StringToInt(display))
			{
				// Just set game mode on selection, all the stuff is starting after that
				case
					GunGamePure,
					GunGameFull,
					GunGameOriginal: SetConVarString(GameMode, "g");
				case HideAndSeek:    SetConVarString(GameMode, "h");
				case DeathMatch:     SetConVarString(GameMode, "d");
				case ZombieMod:      SetConVarString(GameMode, "z");
				case RealismMatch:   SetConVarString(GameMode, "r");
				default:             SetConVarString(GameMode, "0");
			}
		}

		// Menu handle must be freed!
		case MenuAction_End:
		{
			CloseHandle(menu);
		}
	}

	// We should return a value, so return 0
	return 0;
}

/* Timer_RefreshMap()
 *
 * 3-Seconds timer to refresh the map.
 * -------------------------------------------------------------------- */
public Action:Timer_RefreshMap(Handle:timer)
{
	// Get the current map and use ForceChangeLevel native (Approve rules?)
	decl String:curmap[PLATFORM_MAX_PATH];
	GetCurrentMap(curmap, sizeof(curmap));

	// No reason
	ForceChangeLevel(curmap, NULL_STRING);
}

/* LoadPlugin()
 *
 * Loads a plugin by unique index.
 * -------------------------------------------------------------------- */
LoadPlugin(PluginIndex)
{
	// Add 'optional' prefix to plugin name obviously
	decl String:PluginName[PLATFORM_MAX_PATH];
	Format(PluginName, sizeof(PluginName), "optional/%s", PluginFileNames[PluginIndex]);
	ServerCommand("sm plugins load %s", PluginName);
}

/* UnloadPlugin()
 *
 * Unoads a plugin by unique index.
 * -------------------------------------------------------------------- */
UnloadPlugin(PluginIndex)
{
	decl String:PluginName[PLATFORM_MAX_PATH];
	Format(PluginName, sizeof(PluginName), "optional/%s", PluginFileNames[PluginIndex]);

	// And unload it using default 'sm plugins unload' command
	ServerCommand("sm plugins unload %s", PluginName);
}