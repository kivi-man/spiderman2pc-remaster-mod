// HUD overlay for the MSM controls: focus segments, combo counter, point-launch
// icon, spider-sense, hints and comic hit words. Drawn on top of the stock HUD.
class MSMHud extends Interaction;

var Texture White;
var Texture PerchIcon;
var Texture SenseIcon;

function MSMSpideyController PC()
{
	if (ViewportOwner == None)
		return None;
	return MSMSpideyController(ViewportOwner.Actor);
}

function DrawBox(Canvas C, float X, float Y, float W, float H)
{
	C.SetPos(X, Y);
	C.DrawTile(White, W, H, 0, 0, 2, 2);
}

function PostRender(Canvas C)
{
	local MSMSpideyController P;
	local int i;
	local float X, Y, W, H, F, XL, YL;
	local vector S;

	P = PC();
	if (P == None || P.Pawn == None)
		return;
	P.ScreenW = C.ClipX;
	P.ScreenH = C.ClipY;

	// Use both reflection textures every frame (cutscenes too) so the engine
	// re-renders them: one additive pixel at 1/255, invisible. Pure black is
	// skipped by the canvas and then the textures are never refreshed.
	if (P.ReflTex != None && P.ReflectionsOn())
	{
		C.Style = 3; // STY_Translucent
		C.DrawColor.R = 1; C.DrawColor.G = 1; C.DrawColor.B = 1; C.DrawColor.A = 255;
		C.SetPos(0, 0);
		C.DrawTile(P.ReflTex, 1, 1, 0, 0, 1, 1);
		if (P.MirrorTex != None)
		{
			C.SetPos(0, 0);
			C.DrawTile(P.MirrorTex, 1, 1, 0, 0, 1, 1);
		}
	}
	if (!P.bMSMActive)
		return;
	P.ScreenAspect = C.ClipX / FMax(1, C.ClipY);
	if (P.ReflTex != None && P.bShowReflAtlas)
	{
		C.Style = 1; // STY_Normal
		C.DrawColor.R = 255; C.DrawColor.G = 255; C.DrawColor.B = 255; C.DrawColor.A = 255;
		C.SetPos(C.ClipX - 520, 10);
		C.DrawTile(P.ReflTex, 512, 256, 0, 0, 2048, 1024);
		if (P.MirrorTex != None && P.ScreenW > 0)
		{
			C.SetPos(C.ClipX - 520, 276);
			C.DrawTile(P.MirrorTex, 512, 512 * P.ScreenH / P.ScreenW, 0, 0, P.ScreenW * 1.06, P.ScreenH * 1.06);
		}
	}
	C.Style = 5; // STY_Alpha
	C.Font = C.MedFont;

	// Focus: 3 segments, bottom left above the stock health meter
	W = C.ClipX * 0.06;
	H = C.ClipY * 0.012;
	X = C.ClipX * 0.03;
	Y = C.ClipY * 0.80;
	for (i = 0; i < 3; i++)
	{
		F = FClamp(P.Focus - i, 0, 1);
		C.DrawColor.R = 20; C.DrawColor.G = 20; C.DrawColor.B = 30; C.DrawColor.A = 170;
		DrawBox(C, X + i * (W + 6), Y, W, H);
		if (F >= 1) { C.DrawColor.R = 255; C.DrawColor.G = 220; C.DrawColor.B = 60; }
		else { C.DrawColor.R = 120; C.DrawColor.G = 190; C.DrawColor.B = 255; }
		C.DrawColor.A = 230;
		DrawBox(C, X + i * (W + 6), Y, W * F, H);
	}

	// Combo counter
	if (P.Combo >= 2)
	{
		C.DrawColor.R = 255; C.DrawColor.G = 230; C.DrawColor.B = 90; C.DrawColor.A = 255;
		C.TextSize("x" $ P.Combo $ " KOMBO", XL, YL);
		C.SetPos(C.ClipX * 0.97 - XL, C.ClipY * 0.30);
		C.DrawText("x" $ P.Combo $ " KOMBO");
	}

	// Point-launch target
	if (P.bHasPerch && P.MState != 'pointZip')
	{
		S = WorldToScreen(P.PerchTarget);
		if (S.Z > 0 && S.X > 0 && S.X < C.ClipX && S.Y > 0 && S.Y < C.ClipY)
		{
			C.DrawColor.R = 255; C.DrawColor.G = 255; C.DrawColor.B = 255; C.DrawColor.A = 255;
			C.SetPos(S.X - 16, S.Y - 16);
			C.DrawTile(PerchIcon, 32, 32, 0, 0, PerchIcon.USize, PerchIcon.VSize);
		}
	}

	// Spider-sense above Spidey's head
	if (P.bSenseActive)
	{
		S = WorldToScreen(P.Pawn.Location + vect(0,0,95));
		if (S.Z > 0)
		{
			C.DrawColor.R = 255; C.DrawColor.G = 255; C.DrawColor.B = 255; C.DrawColor.A = 255;
			C.SetPos(S.X - 24, S.Y - 60);
			C.DrawTile(SenseIcon, 48, 48, 0, 0, SenseIcon.USize, SenseIcon.VSize);
		}
	}

	// Comic words (POW! BAM! ...)
	for (i = 0; i < P.Comics.Length; i++)
	{
		S = WorldToScreen(P.Comics[i].Loc);
		if (S.Z <= 0)
			continue;
		C.DrawColor = P.Comics[i].Col;
		C.DrawColor.A = byte(255 * FClamp(P.Comics[i].Life / P.Comics[i].MaxLife * 1.5, 0, 1));
		C.TextSize(P.Comics[i].Text, XL, YL);
		C.SetPos(S.X - XL / 2, S.Y - YL / 2 - (1 - P.Comics[i].Life / P.Comics[i].MaxLife) * 30);
		C.DrawText(P.Comics[i].Text);
	}

	// Hint
	if (P.HintT > 0 && P.HintText != "")
	{
		C.DrawColor.R = 255; C.DrawColor.G = 255; C.DrawColor.B = 255; C.DrawColor.A = byte(255 * FClamp(P.HintT, 0, 1));
		C.TextSize(P.HintText, XL, YL);
		C.SetPos((C.ClipX - XL) / 2, C.ClipY * 0.22);
		C.DrawText(P.HintText);
	}
}

defaultproperties
{
	bActive=true
	bVisible=true
	White=Texture'Engine.WhiteSquareTexture'
	PerchIcon=Texture'ReticuleTextures.ContextZip'
	SenseIcon=Texture'ReticuleTextures.ContextAttack'
}
