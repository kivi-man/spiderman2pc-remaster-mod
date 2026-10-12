// The MSM settings page: replaces the stock video and controls pages (see MSMGUIController).
// Tabs: display, graphics, camera & mouse, keys, reflections. Values are read when the page
// opens and applied with "APPLY"; key bindings are saved as soon as a key is pressed.
// All texts are plain ASCII English (the stock localisation of this game uses ASCII only).
class MSMPageSettings extends WebheadGUIPage;

const KIND_CHOICE = 0;
const KIND_SLIDER = 1;
const KIND_KEY = 2;

const NUM_TABS = 5;
const TAB_DISPLAY = 0;
const TAB_GRAPHICS = 1;
const TAB_CAMERA = 2;
const TAB_KEYS = 3;
const TAB_REFLECT = 4;

struct SRow
{
	var int Tab;
	var int Kind;
	var string Id;
	var string Opts;        // choice: "A|B|C"
	var int Count;          // choice: number of options
	var int Index;          // choice: current option
	var int Start;          // choice: option when the page opened
	var float Value;        // slider
	var float StartValue;
	var float Step;         // slider: shown with decimals if < 1
	var string Alias;       // key: input alias
	var string KeyName;     // key: bound key
	var GUILabel Lbl;
	var GUIComponent Ctl;
	var GUILabel ValLbl;    // slider value
};

var array<SRow> Rows;
var GUIButton TabBtn[5];
var string TabName[5];
var int CurTab;
var GUIImage Panel, TabLine;
var GUILabel Title, Note;
var GUIButton BtnBack, BtnReset, BtnApply;
var array<string> ResList;
var int PollRow;            // key row waiting for a key, -1 = none
var bool bBuilt;

var Color TextColor, DimColor, AccentColor;

//-----------------------------------------------------------------------------
// building

function InitComponent(GUIController MyController, GUIComponent MyOwner)
{
	Super.InitComponent(MyController, MyOwner);
	PollRow = -1;
	BuildPage();
}

function GUILabel NewLabel(string Text, float X, float Y, float W, float H, Color C, optional bool bRight, optional string Font)
{
	local GUILabel L;

	L = new(None) class'GUILabel';
	L.Caption = Text;
	L.WinLeft = X;
	L.WinTop = Y;
	L.WinWidth = W;
	L.WinHeight = H;
	L.TextColor = C;
	L.FocusedTextColor = C;
	if (bRight)
		L.TextAlign = TXTA_Right;
	else
		L.TextAlign = TXTA_Left;
	if (Font != "")
		L.TextFont = Font;
	L.RenderWeight = 0.5;
	AppendComponent(L);
	return L;
}

function GUIButton NewButton(string Caption, float X, float Y, float W, float H)
{
	local GUIButton B;

	B = new(None) class'GUIButton';
	B.Caption = Caption;
	B.StyleName = "WHRoundButton";
	B.WinLeft = X;
	B.WinTop = Y;
	B.WinWidth = W;
	B.WinHeight = H;
	B.RenderWeight = 0.5;
	B.OnClick = ButtonClick;
	B.OnRightClick = ButtonRightClick;
	B.OnKeyEvent = ButtonKeyEvent;
	AppendComponent(B);
	return B;
}

function int RowY(int N, out float Y, out float H)
{
	Y = 0.215 + N * 0.047;
	H = 0.04;
	return N;
}

function AddChoice(int Tab, int N, string Id, string Label, string Opts)
{
	local int i;
	local float Y, H;

	RowY(N, Y, H);
	i = Rows.Length;
	Rows.Length = i + 1;
	Rows[i].Tab = Tab;
	Rows[i].Kind = KIND_CHOICE;
	Rows[i].Id = Id;
	Rows[i].Opts = Opts;
	Rows[i].Count = CountOpts(Opts);
	Rows[i].Lbl = NewLabel(Label, 0.10, Y, 0.36, H, TextColor);
	Rows[i].Ctl = NewButton("", 0.48, Y, 0.32, H);
}

function AddSlider(int Tab, int N, string Id, string Label, float Min, float Max, float Step)
{
	local int i;
	local float Y, H;
	local GUISlider S;

	RowY(N, Y, H);
	i = Rows.Length;
	Rows.Length = i + 1;
	Rows[i].Tab = Tab;
	Rows[i].Kind = KIND_SLIDER;
	Rows[i].Id = Id;
	Rows[i].Step = Step;
	Rows[i].Lbl = NewLabel(Label, 0.10, Y, 0.36, H, TextColor);
	S = new(None) class'GUISlider';
	S.StyleName = "WHSlider";
	S.CaptionStyleName = "";
	S.MinValue = Min;
	S.MaxValue = Max;
	S.WinLeft = 0.48;
	S.WinTop = Y + 0.005;
	S.WinWidth = 0.32;
	S.WinHeight = 0.03;
	S.RenderWeight = 0.5;
	S.OnChange = SliderChange;
	AppendComponent(S);
	Rows[i].Ctl = S;
	Rows[i].ValLbl = NewLabel("", 0.81, Y, 0.09, H, AccentColor);
}

function AddKey(int N, string Alias, string Label)
{
	local int i;
	local float Y, H;

	Y = 0.215 + N * 0.04;
	H = 0.035;
	i = Rows.Length;
	Rows.Length = i + 1;
	Rows[i].Tab = TAB_KEYS;
	Rows[i].Kind = KIND_KEY;
	Rows[i].Id = "key";
	Rows[i].Alias = Alias;
	Rows[i].Lbl = NewLabel(Label, 0.10, Y, 0.36, H, TextColor);
	Rows[i].Ctl = NewButton("", 0.48, Y, 0.32, H);
}

function BuildPage()
{
	local int i;

	TextColor.R = 235; TextColor.G = 235; TextColor.B = 240; TextColor.A = 255;
	DimColor.R = 150; DimColor.G = 160; DimColor.B = 185; DimColor.A = 255;
	AccentColor.R = 255; AccentColor.G = 205; AccentColor.B = 60; AccentColor.A = 255;

	Panel = new(None) class'GUIImage';
	Panel.Image = Texture'Engine.WhiteSquareTexture';
	Panel.ImageStyle = ISTY_Stretched;
	Panel.ImageRenderStyle = MSTY_Alpha;
	Panel.ImageColor.R = 8; Panel.ImageColor.G = 10; Panel.ImageColor.B = 24; Panel.ImageColor.A = 215;
	Panel.WinLeft = 0.07;
	Panel.WinTop = 0.06;
	Panel.WinWidth = 0.86;
	Panel.WinHeight = 0.86;
	Panel.RenderWeight = 0.2;
	Panel.bAcceptsInput = false;
	AppendComponent(Panel);

	TabLine = new(None) class'GUIImage';
	TabLine.Image = Texture'Engine.WhiteSquareTexture';
	TabLine.ImageStyle = ISTY_Stretched;
	TabLine.ImageRenderStyle = MSTY_Alpha;
	TabLine.ImageColor.R = 200; TabLine.ImageColor.G = 20; TabLine.ImageColor.B = 30; TabLine.ImageColor.A = 255;
	TabLine.WinLeft = 0.09;
	TabLine.WinTop = 0.197;
	TabLine.WinWidth = 0.82;
	TabLine.WinHeight = 0.004;
	TabLine.RenderWeight = 0.3;
	TabLine.bAcceptsInput = false;
	AppendComponent(TabLine);

	Title = NewLabel("SETTINGS", 0.09, 0.075, 0.5, 0.05, AccentColor, false, "FontWHButton");

	TabName[0] = "DISPLAY";
	TabName[1] = "GRAPHICS";
	TabName[2] = "CAMERA AND MOUSE";
	TabName[3] = "KEYS";
	TabName[4] = "REFLECTIONS";
	for (i = 0; i < NUM_TABS; i++)
		TabBtn[i] = NewButton(TabName[i], 0.09 + i * 0.165, 0.14, 0.155, 0.05);

	// display
	AddChoice(TAB_DISPLAY, 0, "res", "Resolution", ResolutionOptions());
	AddChoice(TAB_DISPLAY, 1, "mode", "Display mode", "Windowed|Fullscreen");
	AddChoice(TAB_DISPLAY, 2, "vsync", "Vertical sync (VSync)", "Off|On");
	AddChoice(TAB_DISPLAY, 3, "fps", "Frame rate limit", "Unlimited|30|60|75|120|144|165|240");
	AddSlider(TAB_DISPLAY, 4, "fov", "Field of view (FOV)", 50, 90, 1);
	AddSlider(TAB_DISPLAY, 5, "gamma", "Gamma", 0.7, 2.3, 0.05);
	AddSlider(TAB_DISPLAY, 6, "bright", "Brightness", 0.3, 0.8, 0.01);
	AddSlider(TAB_DISPLAY, 7, "contrast", "Contrast", 0.2, 0.8, 0.01);

	// graphics
	AddChoice(TAB_GRAPHICS, 0, "tex", "Texture detail", "Low|Normal|High|Ultra");
	AddChoice(TAB_GRAPHICS, 1, "world", "World detail", "Low|Normal|High");
	AddChoice(TAB_GRAPHICS, 2, "shadow", "Character shadows", "None|Simple|Detailed");
	AddChoice(TAB_GRAPHICS, 3, "msaa", "Anti-aliasing (MSAA)", "Off|2x|4x|8x");
	AddChoice(TAB_GRAPHICS, 4, "aniso", "Anisotropic filtering", "Off|2x|4x|8x|16x");
	AddChoice(TAB_GRAPHICS, 5, "dynlight", "Dynamic lights", "Off|On");
	AddChoice(TAB_GRAPHICS, 6, "trilinear", "Trilinear filtering", "Off|On");
	AddChoice(TAB_GRAPHICS, 7, "detailtex", "Detail textures", "Off|On");
	AddChoice(TAB_GRAPHICS, 8, "projectors", "Projectors (light/shadow)", "Off|On");
	AddChoice(TAB_GRAPHICS, 9, "decals", "Decals", "Off|On");
	AddChoice(TAB_GRAPHICS, 10, "coronas", "Light coronas", "Off|On");

	// camera and mouse
	AddSlider(TAB_CAMERA, 0, "mousesens", "Mouse sensitivity", 0.5, 15, 0.5);
	AddSlider(TAB_CAMERA, 1, "lookspeed", "Camera turn speed", 0.25, 3, 0.05);
	AddChoice(TAB_CAMERA, 2, "invert", "Invert mouse", "Off|On");
	AddChoice(TAB_CAMERA, 3, "smooth", "Mouse smoothing", "Off|On");
	AddSlider(TAB_CAMERA, 4, "camdist", "Camera distance", 0.6, 1.6, 0.05);
	AddChoice(TAB_CAMERA, 5, "shake", "Camera shake", "Off|Low|Normal|High");
	AddChoice(TAB_CAMERA, 6, "autocam", "Auto camera (movement)", "Off|On");

	// keys
	AddKey(0, "MoveForward", "Forward");
	AddKey(1, "MoveBackward", "Backward");
	AddKey(2, "StrafeLeft", "Strafe left");
	AddKey(3, "StrafeRight", "Strafe right");
	AddKey(4, "MSMSwing", "Swing / parkour / wall run");
	AddKey(5, "MSMJump", "Jump / release");
	AddKey(6, "MSMAttack", "Attack");
	AddKey(7, "MSMWeb", "Web shot / pull");
	AddKey(8, "MSMDodge", "Dodge / dive");
	AddKey(9, "MSMZip", "Web zip");
	AddKey(10, "MSMPerch", "Point launch");
	AddKey(11, "MSMFinisher", "Finisher");
	AddKey(12, "MSMUse", "Legacy context action");
	AddKey(13, "ShowStatus", "Status screen");

	// reflections
	AddChoice(TAB_REFLECT, 0, "refl", "Live reflections", "Off|On");
	AddChoice(TAB_REFLECT, 1, "mirror", "Mirror reflection (nearby facades)", "Off|On");

	Note = NewLabel("", 0.10, 0.79, 0.80, 0.04, DimColor);
	BtnBack = NewButton("BACK", 0.09, 0.85, 0.16, 0.05);
	BtnReset = NewButton("DEFAULTS", 0.42, 0.85, 0.18, 0.05);
	BtnApply = NewButton("APPLY", 0.75, 0.85, 0.16, 0.05);
	bBuilt = true;
	ShowTab(TAB_DISPLAY);
}

//-----------------------------------------------------------------------------
// helpers

function int CountOpts(string Opts)
{
	local int N, P;

	N = 1;
	P = InStr(Opts, "|");
	while (P >= 0)
	{
		N++;
		Opts = Mid(Opts, P + 1);
		P = InStr(Opts, "|");
	}
	return N;
}

function string GetOpt(string Opts, int Index)
{
	local int P;

	while (Index > 0)
	{
		P = InStr(Opts, "|");
		if (P < 0)
			return "";
		Opts = Mid(Opts, P + 1);
		Index--;
	}
	P = InStr(Opts, "|");
	if (P >= 0)
		return Left(Opts, P);
	return Opts;
}

function int FindRow(string Id)
{
	local int i;

	for (i = 0; i < Rows.Length; i++)
		if (Rows[i].Id == Id)
			return i;
	return -1;
}

function int GetChoice(string Id)
{
	local int i;

	i = FindRow(Id);
	if (i < 0)
		return 0;
	return Rows[i].Index;
}

function float GetSlider(string Id)
{
	local int i;

	i = FindRow(Id);
	if (i < 0)
		return 0;
	return Rows[i].Value;
}

function bool Changed(string Id)
{
	local int i;

	i = FindRow(Id);
	if (i < 0)
		return false;
	if (Rows[i].Kind == KIND_SLIDER)
		return Abs(Rows[i].Value - Rows[i].StartValue) > 0.0001;
	return Rows[i].Index != Rows[i].Start;
}

function SetChoice(string Id, int Index, optional bool bInitial)
{
	local int i;

	i = FindRow(Id);
	if (i < 0)
		return;
	Rows[i].Index = Clamp(Index, 0, Rows[i].Count - 1);
	if (bInitial)
		Rows[i].Start = Rows[i].Index;
	GUIButton(Rows[i].Ctl).Caption = "<  " $ GetOpt(Rows[i].Opts, Rows[i].Index) $ "  >";
}

function SetSlider(string Id, float V, optional bool bInitial)
{
	local int i;
	local GUISlider S;

	i = FindRow(Id);
	if (i < 0)
		return;
	S = GUISlider(Rows[i].Ctl);
	S.SetValue(V);
	Rows[i].Value = S.Value;
	if (bInitial)
		Rows[i].StartValue = S.Value;
	Rows[i].ValLbl.Caption = FormatValue(Rows[i].Value, Rows[i].Step);
}

function string FormatValue(float V, float Step)
{
	local int Whole, Frac;

	if (Step >= 1)
		return string(int(V + 0.5));
	Whole = int(V);
	Frac = int((V - Whole) * 100 + 0.5);
	if (Frac >= 100)
	{
		Whole++;
		Frac -= 100;
	}
	if (Frac < 10)
		return Whole $ ".0" $ Frac;
	return Whole $ "." $ Frac;
}

function float Snap(float V, float Step)
{
	if (Step <= 0)
		return V;
	return int(V / Step + 0.5) * Step;
}

function int IndexOfInt(int V, string Opts, int Fallback)
{
	local int i, N;

	N = CountOpts(Opts);
	for (i = 0; i < N; i++)
		if (int(GetOpt(Opts, i)) == V)
			return i;
	return Fallback;
}

function string Ini(string Key)
{
	return PlayerOwner().ConsoleCommand("get ini:" $ Key);
}

function bool IniBool(string Key)
{
	local string S;

	S = Ini(Key);
	return S ~= "true" || S == "1";
}

function SetIni(string Key, coerce string Value)
{
	PlayerOwner().ConsoleCommand("set ini:" $ Key $ " " $ Value);
}

function string BoolStr(bool B)
{
	if (B)
		return "True";
	return "False";
}

//-----------------------------------------------------------------------------
// resolutions

function string ResolutionOptions()
{
	local string Cand[18], Cur, Opts;
	local int i, W, H, P;

	Cand[0] = "800x600";
	Cand[1] = "1024x768";
	Cand[2] = "1280x720";
	Cand[3] = "1280x800";
	Cand[4] = "1280x1024";
	Cand[5] = "1366x768";
	Cand[6] = "1440x900";
	Cand[7] = "1600x900";
	Cand[8] = "1600x1200";
	Cand[9] = "1680x1050";
	Cand[10] = "1920x1080";
	Cand[11] = "1920x1200";
	Cand[12] = "2560x1080";
	Cand[13] = "2560x1440";
	Cand[14] = "2560x1600";
	Cand[15] = "3440x1440";
	Cand[16] = "3840x1600";
	Cand[17] = "3840x2160";

	Cur = PlayerOwner().ConsoleCommand("GETCURRENTRES");
	ResList.Length = 0;
	for (i = 0; i < 18; i++)
	{
		P = InStr(Cand[i], "x");
		W = int(Left(Cand[i], P));
		H = int(Mid(Cand[i], P + 1));
		if (Cand[i] == Cur || PlayerOwner().ConsoleCommand("SUPPORTEDRESOLUTION WIDTH=" $ W $ " HEIGHT=" $ H $ " BITDEPTH=32") == "1")
			ResList[ResList.Length] = Cand[i];
	}
	// the current size may not be in the list (odd window sizes)
	for (i = 0; i < ResList.Length && ResList[i] != Cur; i++) {}
	if (i == ResList.Length && InStr(Cur, "x") > 0)
		ResList[ResList.Length] = Cur;
	if (ResList.Length == 0)
		ResList[0] = "1280x720";
	for (i = 0; i < ResList.Length; i++)
	{
		if (i > 0)
			Opts = Opts $ "|";
		Opts = Opts $ ResList[i];
	}
	return Opts;
}

//-----------------------------------------------------------------------------
// reading the current values

event Opened(GUIComponent Sender)
{
	Super.Opened(Sender);
	LoadValues();
}

event HandleParameters(string Param1, string Param2)
{
	if (Param1 == "keys")
		ShowTab(TAB_KEYS);
	else
		ShowTab(TAB_DISPLAY);
}

function LoadValues()
{
	local string Cur, S;
	local int i;

	// display
	Cur = PlayerOwner().ConsoleCommand("GETCURRENTRES");
	for (i = 0; i < ResList.Length && ResList[i] != Cur; i++) {}
	SetChoice("res", i, true);
	S = PlayerOwner().ConsoleCommand("ISFULLSCREEN");
	SetChoice("mode", int(S ~= "true" || S == "1"), true);
	SetChoice("vsync", int(class'MSMSettings'.default.bVSync), true);
	SetChoice("fps", IndexOfInt(class'MSMSettings'.default.FrameLimit, "0|30|60|75|120|144|165|240", 0), true);
	SetSlider("fov", class'MSMSettings'.default.FOV, true);
	SetSlider("gamma", float(Ini("Engine.Engine.ViewportManager Gamma")), true);
	SetSlider("bright", float(Ini("Engine.Engine.ViewportManager Brightness")), true);
	SetSlider("contrast", float(Ini("Engine.Engine.ViewportManager Contrast")), true);

	// graphics
	S = Ini("Engine.Engine.ViewportManager TextureDetailWorld");
	if (S ~= "UltraHigh")
		i = 3;
	else if (S ~= "Higher" || S ~= "High")
		i = 2;
	else if (S ~= "Normal")
		i = 1;
	else
		i = 0;
	SetChoice("tex", i, true);
	if (IniBool("Engine.Engine.RenderDevice SuperHighDetailActors"))
		i = 2;
	else if (IniBool("Engine.Engine.RenderDevice HighDetailActors"))
		i = 1;
	else
		i = 0;
	SetChoice("world", i, true);
	SetChoice("shadow", int(Ini("Engine.Engine.ViewportManager ShadowPref")), true);
	SetChoice("msaa", IndexOfInt(class'MSMSettings'.default.MSAA, "0|2|4|8", 0), true);
	SetChoice("aniso", IndexOfInt(class'MSMSettings'.default.Anisotropy, "1|2|4|8|16", 0), true);
	SetChoice("dynlight", int(!IniBool("Engine.Engine.ViewportManager NoDynamicLights")), true);
	SetChoice("trilinear", int(IniBool("Engine.Engine.RenderDevice UseTrilinear")), true);
	SetChoice("detailtex", int(IniBool("Engine.Engine.RenderDevice DetailTextures")), true);
	SetChoice("projectors", int(IniBool("Engine.Engine.ViewportManager Projectors")), true);
	SetChoice("decals", int(IniBool("Engine.Engine.ViewportManager Decals")), true);
	SetChoice("coronas", int(IniBool("Engine.Engine.ViewportManager Coronas")), true);

	// camera and mouse
	SetSlider("mousesens", float(PlayerOwner().ConsoleCommand("get PlayerInput MouseSensitivity")), true);
	SetSlider("lookspeed", class'MSMSettings'.default.LookSpeed, true);
	S = PlayerOwner().ConsoleCommand("get PlayerInput bInvertMouse");
	SetChoice("invert", int(S ~= "true" || S == "1"), true);
	SetChoice("smooth", int(int(PlayerOwner().ConsoleCommand("get PlayerInput MouseSmoothingMode")) > 0), true);
	SetSlider("camdist", class'MSMSettings'.default.CamDistance, true);
	i = 2;
	if (class'MSMSettings'.default.CamShake < 0.25)
		i = 0;
	else if (class'MSMSettings'.default.CamShake < 0.75)
		i = 1;
	else if (class'MSMSettings'.default.CamShake > 1.25)
		i = 3;
	SetChoice("shake", i, true);
	SetChoice("autocam", int(class'MSMSettings'.default.bAutoCamera), true);

	// reflections
	SetChoice("refl", int(class'MSMSettings'.default.bReflections), true);
	SetChoice("mirror", int(class'MSMSettings'.default.bMirror), true);

	LoadKeys();
	Note.Caption = "";
}

//-----------------------------------------------------------------------------
// keys

function string KeyBinding(string KeyName)
{
	return PlayerOwner().ConsoleCommand("KEYBINDING " $ KeyName);
}

function string FindKeyFor(string Alias)
{
	local int k;
	local string Name;

	for (k = 1; k < 255; k++)
	{
		Name = PlayerOwner().ConsoleCommand("KEYNAME " $ k);
		if (Name != "" && KeyBinding(Name) ~= Alias)
			return Name;
	}
	return "";
}

function string ShowKey(string Name)
{
	switch (Name)
	{
		case "": return "(unbound)";
		case "LeftMouse": return "Left click";
		case "RightMouse": return "Right click";
		case "MiddleMouse": return "Middle click";
		case "MouseWheelUp": return "Wheel up";
		case "MouseWheelDown": return "Wheel down";
		case "Space": return "Space";
		case "Shift": return "Shift";
		case "Ctrl": return "Ctrl";
		case "Alt": return "Alt";
		case "Tab": return "Tab";
		case "Enter": return "Enter";
		case "Up": return "Up arrow";
		case "Down": return "Down arrow";
		case "Left": return "Left arrow";
		case "Right": return "Right arrow";
	}
	return Caps(Name);
}

function LoadKeys()
{
	local int i;

	for (i = 0; i < Rows.Length; i++)
		if (Rows[i].Kind == KIND_KEY)
		{
			Rows[i].KeyName = FindKeyFor(Rows[i].Alias);
			GUIButton(Rows[i].Ctl).Caption = ShowKey(Rows[i].KeyName);
		}
}

function BindKey(int Row, string Name)
{
	local int i;

	// the key leaves whatever it did before; the action leaves its old key
	for (i = 0; i < Rows.Length; i++)
		if (Rows[i].Kind == KIND_KEY && Rows[i].KeyName == Name && i != Row)
			Rows[i].KeyName = "";
	if (Rows[Row].KeyName != "" && Rows[Row].KeyName != Name)
		PlayerOwner().ConsoleCommand("SET Input " $ Rows[Row].KeyName $ " ");
	PlayerOwner().ConsoleCommand("SET Input " $ Name $ " " $ Rows[Row].Alias);
	Rows[Row].KeyName = Name;
	for (i = 0; i < Rows.Length; i++)
		if (Rows[i].Kind == KIND_KEY)
			GUIButton(Rows[i].Ctl).Caption = ShowKey(Rows[i].KeyName);
	Note.Caption = Rows[Row].Lbl.Caption $ ": " $ ShowKey(Name) $ " (saved)";
}

function bool ButtonKeyEvent(out byte Key, out byte State, float Delta)
{
	local string Name;

	if (PollRow < 0)
		return false;
	// 1 = press
	if (State != 1)
		return true;
	Name = PlayerOwner().ConsoleCommand("KEYNAME " $ Key);
	if (Key == 27 || Name ~= "Escape")
	{
		GUIButton(Rows[PollRow].Ctl).Caption = ShowKey(Rows[PollRow].KeyName);
		Note.Caption = "Cancelled.";
	}
	else if (Name != "")
		BindKey(PollRow, Name);
	PollRow = -1;
	return true;
}

//-----------------------------------------------------------------------------
// input

function ShowTab(int T)
{
	local int i;
	local bool bShow;

	if (!bBuilt)
		return;
	CurTab = T;
	PollRow = -1;
	for (i = 0; i < NUM_TABS; i++)
	{
		if (i == T)
			TabBtn[i].Caption = "> " $ TabName[i] $ " <";
		else
			TabBtn[i].Caption = TabName[i];
	}
	for (i = 0; i < Rows.Length; i++)
	{
		bShow = Rows[i].Tab == T;
		Rows[i].Lbl.bVisible = bShow;
		Rows[i].Ctl.bVisible = bShow;
		Rows[i].Ctl.bAcceptsInput = bShow;
		if (Rows[i].ValLbl != None)
			Rows[i].ValLbl.bVisible = bShow;
	}
	switch (T)
	{
		case TAB_DISPLAY: Note.Caption = "Left click: next option, right click: previous. Changes take effect with APPLY."; break;
		case TAB_GRAPHICS: Note.Caption = "The screen is briefly re-created when MSAA or VSync is applied."; break;
		case TAB_CAMERA: Note.Caption = "Camera settings apply to the Marvel's Spider-Man style camera."; break;
		case TAB_KEYS: Note.Caption = "Click an action, then press the new key (Esc: cancel). Keys are saved immediately."; break;
		case TAB_REFLECT: Note.Caption = "If live reflections are off, the game's old static reflections are used."; break;
	}
}

function int RowOf(GUIComponent C)
{
	local int i;

	for (i = 0; i < Rows.Length; i++)
		if (Rows[i].Ctl == C)
			return i;
	return -1;
}

function bool ButtonClick(GUIComponent Sender)
{
	local int i;

	for (i = 0; i < NUM_TABS; i++)
		if (Sender == TabBtn[i])
		{
			ShowTab(i);
			return true;
		}
	if (Sender == BtnBack)
	{
		Controller.CloseMenu(true);
		return true;
	}
	if (Sender == BtnApply)
	{
		ApplyAll();
		return true;
	}
	if (Sender == BtnReset)
	{
		ResetTab();
		return true;
	}
	i = RowOf(Sender);
	if (i < 0)
		return false;
	if (Rows[i].Kind == KIND_CHOICE)
		SetChoice(Rows[i].Id, (Rows[i].Index + 1) % Rows[i].Count);
	else if (Rows[i].Kind == KIND_KEY)
	{
		if (PollRow == i)
		{
			// a click on the waiting button binds the left mouse button
			BindKey(i, "LeftMouse");
			PollRow = -1;
			return true;
		}
		if (PollRow >= 0)
			GUIButton(Rows[PollRow].Ctl).Caption = ShowKey(Rows[PollRow].KeyName);
		PollRow = i;
		GUIButton(Sender).Caption = "... press a key ...";
		Note.Caption = Rows[i].Lbl.Caption $ " - press the new key (Esc: cancel).";
	}
	return true;
}

function bool ButtonRightClick(GUIComponent Sender)
{
	local int i;

	i = RowOf(Sender);
	if (i < 0)
		return false;
	if (Rows[i].Kind == KIND_CHOICE)
		SetChoice(Rows[i].Id, (Rows[i].Index + Rows[i].Count - 1) % Rows[i].Count);
	else if (Rows[i].Kind == KIND_KEY && PollRow == i)
	{
		BindKey(i, "RightMouse");
		PollRow = -1;
	}
	return true;
}

function SliderChange(GUIComponent Sender)
{
	local int i;
	local GUISlider S;

	i = RowOf(Sender);
	if (i < 0)
		return;
	S = GUISlider(Sender);
	S.SetValue(Snap(S.Value, Rows[i].Step));
	Rows[i].Value = S.Value;
	Rows[i].ValLbl.Caption = FormatValue(Rows[i].Value, Rows[i].Step);
}

function ResetTab()
{
	switch (CurTab)
	{
		case TAB_DISPLAY:
			SetChoice("vsync", 0);
			SetChoice("fps", 0);
			SetSlider("fov", 65);
			SetSlider("gamma", 0.8);
			SetSlider("bright", 0.8);
			SetSlider("contrast", 0.7);
			break;
		case TAB_GRAPHICS:
			SetChoice("tex", 3);
			SetChoice("world", 2);
			SetChoice("shadow", 2);
			SetChoice("msaa", 0);
			SetChoice("aniso", 3);
			SetChoice("dynlight", 1);
			SetChoice("trilinear", 1);
			SetChoice("detailtex", 1);
			SetChoice("projectors", 1);
			SetChoice("decals", 1);
			SetChoice("coronas", 1);
			break;
		case TAB_CAMERA:
			SetSlider("mousesens", 3);
			SetSlider("lookspeed", 1);
			SetChoice("invert", 0);
			SetChoice("smooth", 0);
			SetSlider("camdist", 1);
			SetChoice("shake", 2);
			SetChoice("autocam", 1);
			break;
		case TAB_KEYS:
			BindKey(FindKeyRow("MoveForward"), "W");
			BindKey(FindKeyRow("MoveBackward"), "S");
			BindKey(FindKeyRow("StrafeLeft"), "A");
			BindKey(FindKeyRow("StrafeRight"), "D");
			BindKey(FindKeyRow("MSMSwing"), "Shift");
			BindKey(FindKeyRow("MSMJump"), "Space");
			BindKey(FindKeyRow("MSMAttack"), "LeftMouse");
			BindKey(FindKeyRow("MSMWeb"), "RightMouse");
			BindKey(FindKeyRow("MSMDodge"), "C");
			BindKey(FindKeyRow("MSMZip"), "Q");
			BindKey(FindKeyRow("MSMPerch"), "E");
			BindKey(FindKeyRow("MSMFinisher"), "F");
			BindKey(FindKeyRow("MSMUse"), "R");
			BindKey(FindKeyRow("ShowStatus"), "Tab");
			Note.Caption = "Default keys restored.";
			return;
		case TAB_REFLECT:
			SetChoice("refl", 1);
			SetChoice("mirror", 1);
			break;
	}
	Note.Caption = "Defaults selected; press APPLY to save.";
}

function int FindKeyRow(string Alias)
{
	local int i;

	for (i = 0; i < Rows.Length; i++)
		if (Rows[i].Kind == KIND_KEY && Rows[i].Alias == Alias)
			return i;
	return 0;
}

//-----------------------------------------------------------------------------
// applying

function ApplyAll()
{
	local bool bReset, bResChange;
	local string Res, Cmd;
	local int i;
	local WebheadPawn P;
	local MSMSpideyController C;

	// MSM settings (the loader re-reads them every 2 s; MSAA/VSync on the next device reset)
	bReset = Changed("msaa") || Changed("vsync");
	class'MSMSettings'.default.bVSync = GetChoice("vsync") == 1;
	class'MSMSettings'.default.FrameLimit = int(GetOpt("0|30|60|75|120|144|165|240", GetChoice("fps")));
	class'MSMSettings'.default.FOV = GetSlider("fov");
	class'MSMSettings'.default.MSAA = int(GetOpt("0|2|4|8", GetChoice("msaa")));
	class'MSMSettings'.default.Anisotropy = int(GetOpt("1|2|4|8|16", GetChoice("aniso")));
	class'MSMSettings'.default.LookSpeed = GetSlider("lookspeed");
	class'MSMSettings'.default.CamDistance = GetSlider("camdist");
	class'MSMSettings'.default.CamShake = float(GetOpt("0|0.5|1|1.5", GetChoice("shake")));
	class'MSMSettings'.default.bAutoCamera = GetChoice("autocam") == 1;
	class'MSMSettings'.default.bReflections = GetChoice("refl") == 1;
	class'MSMSettings'.default.bMirror = GetChoice("mirror") == 1;
	class'MSMSettings'.static.StaticSaveConfig();
	C = MSMSpideyController(PlayerOwner());
	if (C != None)
		C.SettingsChanged();

	// brightness
	if (Changed("gamma"))
	{
		PlayerOwner().ConsoleCommand("GAMMA " $ GetSlider("gamma"));
		SetIni("Engine.Engine.ViewportManager Gamma", GetSlider("gamma"));
	}
	if (Changed("bright"))
	{
		PlayerOwner().ConsoleCommand("BRIGHTNESS " $ GetSlider("bright"));
		SetIni("Engine.Engine.ViewportManager Brightness", GetSlider("bright"));
	}
	if (Changed("contrast"))
	{
		PlayerOwner().ConsoleCommand("CONTRAST " $ GetSlider("contrast"));
		SetIni("Engine.Engine.ViewportManager Contrast", GetSlider("contrast"));
	}

	// graphics
	if (Changed("tex"))
	{
		Cmd = "Engine.Engine.ViewportManager TextureDetail";
		switch (GetChoice("tex"))
		{
			case 0: SetIni(Cmd $ "Terrain", "Normal"); SetIni(Cmd $ "World", "Low"); SetIni(Cmd $ "Rendermap", "VeryLow"); SetIni(Cmd $ "Lightmap", "UltraLow"); SetIni(Cmd $ "PlayerSkin", "Normal"); SetIni(Cmd $ "WeaponSkin", "Normal"); SetIni(Cmd $ "Interface", "Normal"); break;
			case 1: SetIni(Cmd $ "Terrain", "Normal"); SetIni(Cmd $ "World", "Normal"); SetIni(Cmd $ "Rendermap", "Lower"); SetIni(Cmd $ "Lightmap", "Lower"); SetIni(Cmd $ "PlayerSkin", "Normal"); SetIni(Cmd $ "WeaponSkin", "Normal"); SetIni(Cmd $ "Interface", "Higher"); break;
			case 2: SetIni(Cmd $ "Terrain", "Higher"); SetIni(Cmd $ "World", "Higher"); SetIni(Cmd $ "Rendermap", "Normal"); SetIni(Cmd $ "Lightmap", "Normal"); SetIni(Cmd $ "PlayerSkin", "Higher"); SetIni(Cmd $ "WeaponSkin", "Higher"); SetIni(Cmd $ "Interface", "Higher"); break;
			default: SetIni(Cmd $ "Terrain", "UltraHigh"); SetIni(Cmd $ "World", "UltraHigh"); SetIni(Cmd $ "Rendermap", "UltraHigh"); SetIni(Cmd $ "Lightmap", "UltraHigh"); SetIni(Cmd $ "PlayerSkin", "UltraHigh"); SetIni(Cmd $ "WeaponSkin", "UltraHigh"); SetIni(Cmd $ "Interface", "UltraHigh"); break;
		}
		PlayerOwner().ConsoleCommand("flush");
	}
	if (Changed("world"))
	{
		i = GetChoice("world");
		SetIni("Engine.Engine.RenderDevice HighDetailActors", BoolStr(i >= 1));
		SetIni("Engine.Engine.RenderDevice SuperHighDetailActors", BoolStr(i >= 2));
		SetIni("Engine.Engine.RenderDevice RecommendedLOD", i);
		class'MSMSpideyPawn'.static.SetWorldDetail(PlayerOwner().Level, i);
	}
	if (Changed("shadow"))
	{
		i = GetChoice("shadow");
		foreach PlayerOwner().AllActors(class'WebheadPawn', P)
			class'MSMSpideyPawn'.static.SetShadowType(P, i);
		SetIni("Engine.Engine.ViewportManager ShadowPref", i);
	}
	if (Changed("dynlight"))
		SetIni("Engine.Engine.ViewportManager NoDynamicLights", BoolStr(GetChoice("dynlight") == 0));
	if (Changed("trilinear"))
		SetIni("Engine.Engine.RenderDevice UseTrilinear", BoolStr(GetChoice("trilinear") == 1));
	if (Changed("detailtex"))
		SetIni("Engine.Engine.RenderDevice DetailTextures", BoolStr(GetChoice("detailtex") == 1));
	if (Changed("projectors"))
		SetIni("Engine.Engine.ViewportManager Projectors", BoolStr(GetChoice("projectors") == 1));
	if (Changed("decals"))
		SetIni("Engine.Engine.ViewportManager Decals", BoolStr(GetChoice("decals") == 1));
	if (Changed("coronas"))
		SetIni("Engine.Engine.ViewportManager Coronas", BoolStr(GetChoice("coronas") == 1));

	// mouse
	if (Changed("mousesens"))
		PlayerOwner().ConsoleCommand("set PlayerInput MouseSensitivity " $ GetSlider("mousesens"));
	if (Changed("invert"))
		PlayerOwner().ConsoleCommand("set PlayerInput bInvertMouse " $ BoolStr(GetChoice("invert") == 1));
	if (Changed("smooth"))
		PlayerOwner().ConsoleCommand("set PlayerInput MouseSmoothingMode " $ GetChoice("smooth"));

	// resolution last: it rebuilds the device (that also applies MSAA / VSync)
	bResChange = Changed("res") || Changed("mode");
	if (bResChange || bReset)
	{
		Res = ResList[GetChoice("res")];
		if (GetChoice("mode") == 1)
			Res = Res $ "x32f";
		else
			Res = Res $ "x32w";
		PlayerOwner().ConsoleCommand("SETRES " $ Res);
	}

	LoadValues();
	Note.Caption = "Settings applied and saved.";
}

defaultproperties
{
	PageName="MSMPageSettings"
	bRequire640x480=false
	bRenderWorld=true
	bPauseIfPossible=true
}
