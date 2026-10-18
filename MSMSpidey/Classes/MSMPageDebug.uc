// Debug menu (Insert key, see MSMSpideyController.MSMDebug). It carries everything the game's own debug window
// (UDebugMenu: show flags, render modes, Karma draws, stat counters and graphs, shot, flush, map loader) offers plus a
// few player commands, built on the settings page. Every choice acts at once and the game keeps running.
// (The stock Insert menu, Webhead.KWDebugRootWindow, only pauses this build and shows nothing.)
class MSMPageDebug extends MSMPageSettings;

const TAB_VIEW = 0;
const TAB_RENDER = 1;
const TAB_STATS = 2;
const TAB_PLAYER = 3;
const TAB_MAPS = 4;

var string StatVals, RModeVals, MoveVals, MapNames, GraphStats;
var string DebugNote[5];

function SetTabNames()
{
	TabName[0] = "SHOW";
	TabName[1] = "RENDER";
	TabName[2] = "STATS";
	TabName[3] = "PLAYER";
	TabName[4] = "MAPS";
}

function BuildRows()
{
	StatVals = "NONE|ALL|FPS|RENDER|GAME|ANIM|HARDWARE|MEM|ASSET|NET";
	RModeVals = "1|2|3|4|5|6|7|8|13|14|15";
	GraphStats = "Triangles|Meshes|Batches|StateChanges|StreamSourceChanges|TransformChanges|SpriteSetup|DynamicLights|LightChanges|MeshLightRender|ParticlesTicked|Sectors|Sections|Splits|BoxTests|BoxRejects|MaskTests|MaskRejects|Packets|PacketLoss|Bunches|Channels|ScriptTick|InternalTime|ContactGen|Dynamics|VertexGen|DynVBBytes|DynIBBytes|IndexBufferBytes|VertexStreamBytes|ScratchBytes|MipZero|Spawning|Coronas|Projectors|Decorations|Complexity";
	MoveVals = "Walk|Fly|Ghost";
	MapNames = "WallStreet_CityStreet|WallStreet_Bank|WallStreet_OsCorpLab|ParkAve_CityStreet|ParkAve_ConstructionSite|CB3_CityStreet|TwistedCity_Part01|TwistedCity_Part02|TwistedCity_Part03|Wharf_Docks|Wharf_Train|Wharf_TrainStation|Wharf_Warehouse|Entry";

	// show flags (the console command toggles each one)
	AddChoice(TAB_VIEW, 0, "sh_Actors", "Actors", "On|Off");
	AddChoice(TAB_VIEW, 1, "sh_StaticMeshes", "Static meshes", "On|Off");
	AddChoice(TAB_VIEW, 2, "sh_Terrain", "Terrain", "On|Off");
	AddChoice(TAB_VIEW, 3, "sh_Sky", "Sky", "On|Off");
	AddChoice(TAB_VIEW, 4, "sh_Fog", "Fog", "On|Off");
	AddChoice(TAB_VIEW, 5, "sh_Particles", "Particles", "On|Off");
	AddChoice(TAB_VIEW, 6, "sh_Coronas", "Coronas", "On|Off");
	AddChoice(TAB_VIEW, 7, "sh_collision", "Actor collision", "Off|On");
	AddChoice(TAB_VIEW, 8, "sh_volumes", "Volumes", "Off|On");
	AddChoice(TAB_VIEW, 9, "act_shot", "Screenshot (System folder)", "SAVE");
	AddChoice(TAB_VIEW, 10, "act_fullscreen", "Toggle fullscreen", "SWITCH");

	// render modes, render commands, Karma physics
	AddChoice(TAB_RENDER, 0, "rmode", "World view (RMode)", "Wireframe|Zones|Flat shaded BSP|BSP splits|Regular|Unlit|Lighting only|Depth complexity|Top down|Front|Side");
	AddChoice(TAB_RENDER, 1, "rd_blend", "Blend", "Off|On");
	AddChoice(TAB_RENDER, 2, "rd_bone", "Bone", "Off|On");
	AddChoice(TAB_RENDER, 3, "rd_skin", "Skin", "Off|On");
	AddChoice(TAB_RENDER, 4, "rd_collision", "Collision", "Off|On");
	AddChoice(TAB_RENDER, 5, "kd_Collision", "Karma: collision", "Off|On");
	AddChoice(TAB_RENDER, 6, "kd_Contacts", "Karma: contacts", "Off|On");
	AddChoice(TAB_RENDER, 7, "kd_Triangles", "Karma: triangles", "Off|On");
	AddChoice(TAB_RENDER, 8, "kd_Com", "Karma: centre of mass", "Off|On");
	AddChoice(TAB_RENDER, 9, "kd_KStop", "Karma: stop", "Off|On");
	AddChoice(TAB_RENDER, 10, "kd_KStep", "Karma: single step", "Off|On");
	AddChoice(TAB_RENDER, 11, "act_flush", "Reload all textures", "FLUSH");

	// stat counters and graphs
	AddChoice(TAB_STATS, 0, "stat", "On-screen counters", "None|All|FPS|Render|Game|Anim|Hardware|Memory|Assets|Network");
	AddChoice(TAB_STATS, 1, "gr_graph", "Line graph", "Hidden|Shown");
	AddChoice(TAB_STATS, 2, "gr_bar", "Bar graph", "Hidden|Shown");
	AddChoice(TAB_STATS, 3, "gr_stat", "Graph value", GraphStats);
	AddChoice(TAB_STATS, 4, "gr_addline", "Add the value to the line graph", "ADD");
	AddChoice(TAB_STATS, 5, "gr_remline", "Remove it from the line graph", "REMOVE");
	AddChoice(TAB_STATS, 6, "gr_addbar", "Add the value to the bar graph", "ADD");
	AddChoice(TAB_STATS, 7, "gr_rembar", "Remove it from the bar graph", "REMOVE");

	// player
	AddChoice(TAB_PLAYER, 0, "god", "God mode", "Off|On");
	AddSlider(TAB_PLAYER, 1, "slomo", "Game speed", 0.1, 2.0, 0.05);
	AddChoice(TAB_PLAYER, 2, "move", "Movement", "Walk|Fly|Ghost");
	AddChoice(TAB_PLAYER, 3, "act_info", "Print MSM info to the screen", "PRINT");
	AddChoice(TAB_PLAYER, 4, "act_atlas", "Show reflection atlas", "TOGGLE");

	// maps
	AddChoice(TAB_MAPS, 0, "map", "Map", MapNames);
	AddChoice(TAB_MAPS, 1, "loadmap", "Load the selected map", "LOAD");
	AddChoice(TAB_MAPS, 2, "act_video", "Video and input settings", "OPEN");
	AddChoice(TAB_MAPS, 3, "act_quit", "Exit the game", "EXIT");
}

function InitComponent(GUIController MyController, GUIComponent MyOwner)
{
	bTightRows = true;
	Super.InitComponent(MyController, MyOwner);
	BtnReset.Caption = "ALL OFF";
	BtnApply.Caption = "CLOSE";
	DebugNote[0] = "Click toggles at once, right click goes back. Flags start from the normal state.";
	DebugNote[1] = "View numbers are the classic Unreal ones. Karma draws need physics objects in view.";
	DebugNote[2] = "Counters appear on the game screen. Pick a value, then add or remove it on a graph.";
	DebugNote[3] = "God, Fly and Ghost only work where this game supports them.";
	DebugNote[4] = "Loading a map leaves the current game. Quit closes the game.";
}

function LoadValues()
{
	SetChoice("sh_Actors", 0, true);
	SetChoice("sh_StaticMeshes", 0, true);
	SetChoice("sh_Terrain", 0, true);
	SetChoice("sh_Sky", 0, true);
	SetChoice("sh_Fog", 0, true);
	SetChoice("sh_Particles", 0, true);
	SetChoice("sh_Coronas", 0, true);
	SetChoice("sh_collision", 0, true);
	SetChoice("sh_volumes", 0, true);
	SetChoice("act_shot", 0, true);
	SetChoice("act_fullscreen", 0, true);
	SetChoice("rmode", 4, true);
	SetChoice("rd_blend", 0, true);
	SetChoice("rd_bone", 0, true);
	SetChoice("rd_collision", 0, true);
	SetChoice("rd_skin", 0, true);
	SetChoice("kd_Collision", 0, true);
	SetChoice("kd_Contacts", 0, true);
	SetChoice("kd_Triangles", 0, true);
	SetChoice("kd_Com", 0, true);
	SetChoice("kd_KStop", 0, true);
	SetChoice("kd_KStep", 0, true);
	SetChoice("act_flush", 0, true);
	SetChoice("stat", 0, true);
	SetChoice("gr_graph", 0, true);
	SetChoice("gr_bar", 0, true);
	SetChoice("gr_stat", 0, true);
	SetChoice("gr_addline", 0, true);
	SetChoice("gr_remline", 0, true);
	SetChoice("gr_addbar", 0, true);
	SetChoice("gr_rembar", 0, true);
	SetChoice("god", 0, true);
	SetSlider("slomo", PlayerOwner().Level.TimeDilation, true);
	SetChoice("move", 0, true);
	SetChoice("act_info", 0, true);
	SetChoice("act_atlas", 0, true);
	SetChoice("map", 0, true);
	SetChoice("loadmap", 0, true);
	SetChoice("act_video", 0, true);
	SetChoice("act_quit", 0, true);
	Note.Caption = DebugNote[0];
}

function ShowTab(int T)
{
	Super.ShowTab(T);
	if (bBuilt && T >= 0 && T < 5)
		Note.Caption = DebugNote[T];
}

function DoRow(int i)
{
	local string Id, Cmd;

	Id = Rows[i].Id;
	if (Left(Id, 3) == "sh_")
		PlayerOwner().ConsoleCommand("show " $ Mid(Id, 3));
	else if (Left(Id, 3) == "rd_")
		PlayerOwner().ConsoleCommand("rend " $ Mid(Id, 3));
	else if (Left(Id, 3) == "kd_")
		PlayerOwner().ConsoleCommand("kdraw " $ Mid(Id, 3));
	else if (Id == "rmode")
		PlayerOwner().ConsoleCommand("rmode " $ GetOpt(RModeVals, Rows[i].Index));
	else if (Id == "stat")
		PlayerOwner().ConsoleCommand("stat " $ GetOpt(StatVals, Rows[i].Index));
	else if (Id == "gr_graph")
	{
		if (Rows[i].Index == 1)
			PlayerOwner().ConsoleCommand("GRAPH SHOW");
		else
			PlayerOwner().ConsoleCommand("GRAPH HIDE");
	}
	else if (Id == "gr_addline")
		PlayerOwner().ConsoleCommand("GRAPH ADDSTAT=\"" $ GetOpt(GraphStats, GetChoice("gr_stat")) $ "\"");
	else if (Id == "gr_remline")
		PlayerOwner().ConsoleCommand("GRAPH REMOVESTAT=\"" $ GetOpt(GraphStats, GetChoice("gr_stat")) $ "\"");
	else if (Id == "gr_addbar")
		PlayerOwner().ConsoleCommand("BARGRAPH ADDSTAT=\"" $ GetOpt(GraphStats, GetChoice("gr_stat")) $ "\"");
	else if (Id == "gr_rembar")
		PlayerOwner().ConsoleCommand("BARGRAPH REMOVESTAT=\"" $ GetOpt(GraphStats, GetChoice("gr_stat")) $ "\"");
	else if (Id == "act_video")
		Controller.OpenMenu("MSMSpidey.MSMPageSettings");
	else if (Id == "gr_bar")
	{
		if (Rows[i].Index == 1)
			PlayerOwner().ConsoleCommand("BARGRAPH SHOW");
		else
			PlayerOwner().ConsoleCommand("BARGRAPH HIDE");
	}
	else if (Id == "god")
		PlayerOwner().ConsoleCommand("God");
	else if (Id == "move")
		PlayerOwner().ConsoleCommand(GetOpt(MoveVals, Rows[i].Index));
	else if (Id == "act_shot")
		PlayerOwner().ConsoleCommand("SHOT");
	else if (Id == "act_fullscreen")
		PlayerOwner().ConsoleCommand("togglefullscreen");
	else if (Id == "act_flush")
		PlayerOwner().ConsoleCommand("flush");
	else if (Id == "act_info")
		PlayerOwner().ConsoleCommand("MSMInfo");
	else if (Id == "act_atlas")
		PlayerOwner().ConsoleCommand("MSMShowAtlas");
	else if (Id == "act_quit")
		PlayerOwner().ConsoleCommand("quit");
	else if (Id == "loadmap")
	{
		Cmd = GetOpt(MapNames, GetChoice("map"));
		Note.Caption = "Loading " $ Cmd $ " ...";
		PlayerOwner().ConsoleCommand("open " $ Cmd);
	}
}

function bool ButtonClick(GUIComponent Sender)
{
	local int i;
	local bool b;

	if (Sender == BtnApply)
	{
		Controller.CloseMenu(true);
		return true;
	}
	if (Sender == BtnReset)
	{
		ResetTab();
		return true;
	}
	b = Super.ButtonClick(Sender);
	i = RowOf(Sender);
	if (i >= 0 && Rows[i].Kind == KIND_CHOICE && Rows[i].Id != "map" && Rows[i].Id != "gr_stat")
		DoRow(i);
	return b;
}

function bool ButtonRightClick(GUIComponent Sender)
{
	local int i;
	local bool b;

	b = Super.ButtonRightClick(Sender);
	i = RowOf(Sender);
	if (i >= 0 && Rows[i].Kind == KIND_CHOICE && Rows[i].Count > 1 && Rows[i].Id != "map" && Rows[i].Id != "gr_stat")
		DoRow(i);
	return b;
}

function SliderChange(GUIComponent Sender)
{
	local int i;

	Super.SliderChange(Sender);
	i = RowOf(Sender);
	if (i >= 0 && Rows[i].Id == "slomo")
		PlayerOwner().Level.TimeDilation = Rows[i].Value;
}

// ALL OFF: counters and graphs off, normal view, game speed back to 1.0
function ResetTab()
{
	SetChoice("stat", 0);
	PlayerOwner().ConsoleCommand("stat NONE");
	SetChoice("gr_graph", 0);
	SetChoice("gr_bar", 0);
	PlayerOwner().ConsoleCommand("GRAPH HIDE");
	PlayerOwner().ConsoleCommand("BARGRAPH HIDE");
	SetChoice("rmode", 4);
	PlayerOwner().ConsoleCommand("rmode 5");
	SetSlider("slomo", 1.0);
	PlayerOwner().Level.TimeDilation = 1.0;
	Note.Caption = "Counters and graphs off, normal view, game speed 1.0.";
}

function ApplyAll()
{
	Controller.CloseMenu(true);
}

defaultproperties
{
	PageName="MSMPageDebug"
	PageTitle="DEBUG"
	bPauseIfPossible=false
	bAllowedAsLast=true
}
