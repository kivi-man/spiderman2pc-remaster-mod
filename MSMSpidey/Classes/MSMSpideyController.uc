//=============================================================================
// Marvel's Spider-Man style traversal and combat for Spider-Man 2 (2004).
//
// A port of the reference game in ornekhtml/src: player.js (movement, swing
// physics, wall run, point launch, web zip, dodge/dive, combat), camera.js
// (third person camera) and input.js (key layout). The reference works in
// metres and m/s; S converts to unreal units (Spidey is ~96 uu tall).
//
// Everything runs inside the stock PlayerWalking state, so scripted sequences
// that leave and re-enter PlayerWalking keep working.
//=============================================================================
class MSMSpideyController extends SpideyPlayerController
	config(MSMSpidey);

const S = 53.0;              // unreal units per metre
const GRAV = 30.0;           // m/s^2 (player.js GRAVITY)
const MAXSPEED = 68.0;       // m/s   (player.js MAX_SPEED)
const ENGINEGRAV = 1500.0;   // uu/s^2 applied by PHYS_Falling, compensated below
const RAD2U = 10430.378;     // radians -> rotator units

struct MSMComic
{
	var string Text;
	var vector Loc;
	var float Life;
	var float MaxLife;
	var color Col;
};

var config float LookSensitivity;
var config bool bMSMDebug;
var config bool bDynamicReflections;  // live environment reflections (see _mod/loader/msm_reflect.cpp)
var config int ReflFacesPerFrame;     // cube faces re-rendered per frame (6 = every face every frame)
var config bool bPlanarReflections;   // mirror reflection of the wall in view
var float DebugT;

// Key layout (User.ini binds these with "Button")
var input byte bMSMSwing, bMSMJump, bMSMAttack, bMSMWeb, bMSMDodge, bMSMZip, bMSMPerch, bMSMFinisher;

var bool bMSMActive;

// input snapshot (held / pressed / released / previous)
var bool hSwing, hJump, hAttack, hWeb, hDodge, hZip, hPerch, hFinisher;
var bool pSwing, pJump, pAttack, pWeb, pDodge, pZip, pPerch, pFinisher;
var bool oSwing, oJump, oAttack, oWeb, oDodge, oZip, oPerch, oFinisher;
var float MoveX, MoveY;
var vector Wish;
var float WishLen;

// camera (camera.js)
var float CamYaw, CamPitch, CamDist, CamIdleT, CamShake, CamFOV, CamDT;
var vector CamTarget, CamLoc, CamFwd, CamFlatFwd, CamRight;
var rotator CamRot;
var bool bCamInit;
var float ScreenAspect;
var float LookX, LookY;

// player state (player.js)
var name MState;            // ground, air, swing, wall, perch, pointZip, zip
var vector Facing;
var float SwingCD, WallCD, ZipCD, WebCD, DodgeT, Invuln, FlipT, LandT, LaunchBuffer, ZipT, DownT, SinceHurt;
var float JumpCharge, AirTime;
var bool bDiving, bInCombat, bSenseActive, bThreat;
var int HitStreak, FinisherCount;
var float RegenAcc;

// swing
var vector Anchor;
var array<vector> Wraps;
var float RopeLen, RopeTarget, RopeFree, SwingT, WebShoot;
var bool bSwingRight;
var MSMAnchor RopeActor, ZipActor, ShotActor;

// wall
var vector WallN, WallFwd;
var bool bWallRunning;
var float WallRunSpeed;

// point launch / zip
var vector PerchTarget, ZipFrom, ZipTo, ZipDir;
var name LastLoggedState;
var name TmpBone;
var bool bPerchWall;   // the perch point is a wall face to cling to (not a ledge to stand on)
var vector PerchN;   // surface normal of the perch point (wall face or top)
var bool bHasPerch, bZipHasWeb;
var float PerchScanT;

// combat
var float Focus, ComboTimer;
var int Combo, ComboStep;
var bool bAtkActive, bAtkHitDone, bAtkQueued, bAtkFinisher, bAtkAnimStarted;
var float AtkT, AtkDur, AtkHitAt, AtkRate;
var int AtkStep;
var name AtkAnim;
var Actor AtkTarget;
var bool bLunge;
var float LungeT;
var Pawn WebShotTarget;
var float WebShotT, ShotRopeT;
var int LightHitIndex;

// time
var float HitstopT, SlowT, SlowScale;

// visuals
var rotator MeshRot;
var vector MeshX, MeshZ;
var float BodyPitch;
var name CurAnim;
var bool bTour;
var int TourIdx;
var float TourT;
var bool bTourShot;
var float CurRate;
var name ActAnim, ActKind;
var float ActEnd;
var bool bActAir;
var float IdleT;
var bool bFlipToggle;
var array<MSMComic> Comics;
var string HintText;
var float HintT;
var Interaction HudInt;

// stock mission targets (swing points etc.)
var WebSwingPoint CurWSP;
var array<WebSwingPoint> WSPs;
var array<float> WSPTouch;
var bool bWSPInit;

// dynamic reflections: 6 cube faces of 256x256 in a 1024x512 atlas
var ScriptedTexture ReflTex;    // 2048x1024: 6 cube faces of 512x512
var ScriptedTexture MirrorTex;  // 2048x2048: mirror view at screen resolution
var float ScreenW, ScreenH;
var int ReflFace;
var bool bShowReflAtlas;
// planar (mirror) reflection of the wall in view, rendered into the lower half
// of the atlas from the camera mirrored through that wall
var MSMAnchor ReflCam;
var bool bReflPlane;
var vector ReflN, ReflP;
var float ReflDbgT;
var vector ViewLocR;   // the view actually rendered this frame
var rotator ViewRotR;

//-----------------------------------------------------------------------------
// Setup

event PostBeginPlay()
{
	Super.PostBeginPlay();
	RopeActor = Spawn(class'MSMAnchor');
	ZipActor = Spawn(class'MSMAnchor');
	ShotActor = Spawn(class'MSMAnchor');
	JumpCharge = -1;
	CamPitch = -0.12;
	CamDist = 3.6 * S;
	CamFOV = 70;
	ScreenAspect = 16.0 / 9.0;
	if (bDynamicReflections)
	{
		ReflTex = new(None) class'ScriptedTexture';
		ReflTex.SetSize(2048, 1024);
		MirrorTex = new(None) class'ScriptedTexture';
		MirrorTex.SetSize(2048, 2048);
		MirrorTex.Client = self;
		ReflCam = Spawn(class'MSMAnchor');
		ReflTex.Client = self;
	}
	Log("MSMSpidey: controller ready");
}

event Destroyed()
{
	if (RopeActor != None) RopeActor.Destroy();
	if (ZipActor != None) ZipActor.Destroy();
	if (ShotActor != None) ShotActor.Destroy();
	if (ReflCam != None) ReflCam.Destroy();
	Super.Destroyed();
}

function Possess(Pawn aPawn)
{
	Super.Possess(aPawn);
	bAlwaysMouseLook = true;
	if (aPawn != None)
	{
		Facing = vector(aPawn.Rotation);
		Facing.Z = 0;
		Facing = Normal(Facing);
		CamYaw = aPawn.Rotation.Yaw / RAD2U;
		MeshX = Facing;
		MeshZ = vect(0,0,1);
		bCamInit = false;
	}
}

// Front-end maps (PreStartup / Startup) keep the stock controls and cameras.
function bool IsMenuLevel()
{
	return InStr(Caps(string(Level)), "STARTUP") >= 0;
}

function EnterMSM()
{
	if (Spidey == None || IsMenuLevel())
		return;
	if (Spidey.SpecialPhysics == SPHYS_Swinging)
		Spidey.EndSwing();
	Spidey.SpecialPhysics = SPHYS_None;
	Spidey.ReleaseWebRope();
	Wraps.Length = 0;
	bAtkActive = false;
	bLunge = false;
	JumpCharge = -1;
	CurAnim = '';
	ActAnim = '';
	if (Pawn.Physics == PHYS_Falling)
		MState = 'air';
	else
	{
		MState = 'ground';
		if (Pawn.Physics != PHYS_Walking)
			Pawn.SetPhysics(PHYS_Walking);
	}
	if (VSize(Facing) < 0.5)
		Facing = Normal(vector(Pawn.Rotation) * vect(1,1,0));
	MeshX = Facing;
	MeshZ = vect(0,0,1);
	Pawn.bRotateToDesired = false;
	bMSMActive = true;
}

function LeaveMSM()
{
	EndSwingPoint();
	bMSMActive = false;
	Level.TimeDilation = 1.0;
	HitstopT = 0;
	SlowT = 0;
	if (Spidey != None)
	{
		Spidey.ReleaseWebRope();
		Spidey.ReleaseBaseAnim();
		Spidey.SetRotation(rotator(Facing));
	}
	CurAnim = '';
}

//-----------------------------------------------------------------------------
// Small helpers

function float VSize2D(vector V)
{
	return Sqrt(V.X * V.X + V.Y * V.Y);
}

function vector Flat(vector V)
{
	V.Z = 0;
	if (VSize(V) < 0.0001)
		return vect(0,0,0);
	return Normal(V);
}

function float Decay(float PerStep, float Dt)
{
	// player.js multiplies per physics sub-step (~3 per 60 Hz frame)
	return PerStep ** (Dt * 180.0);
}

function vector Feet()
{
	return Pawn.Location - vect(0,0,1) * Pawn.CollisionHeight;
}

function vector ChestLoc()
{
	return Feet() + vect(0,0,1) * (1.3 * S);
}

function vector RopePivot()
{
	if (Wraps.Length > 0)
		return Wraps[Wraps.Length - 1];
	return Anchor;
}

function float WrappedLen()
{
	local float L;
	local vector Prev;
	local int i;

	Prev = Anchor;
	for (i = 0; i < Wraps.Length; i++)
	{
		L += VSize(Wraps[i] - Prev);
		Prev = Wraps[i];
	}
	return L;
}

// Distance from Spidey's feet down to the ground (MaxDist+1 when nothing below).
function float HeightAboveGround(float MaxDist)
{
	local vector HL, HN;

	if (Trace(HL, HN, Pawn.Location - vect(0,0,1) * (Pawn.CollisionHeight + MaxDist), Pawn.Location, false) == None)
		return MaxDist + 1;
	return Feet().Z - HL.Z;
}

function Thwip()
{
	if (Spidey != None)
		Spidey.PlaySound(Spidey.WebShootSounds[Rand(2)], SLOT_None, 1.0,,, RandRange(0.9, 1.15), false);
}

function Whoosh()
{
	if (Spidey != None)
		Spidey.PlaySound(Spidey.JumpSounds[Rand(5)], SLOT_None, 1.0,,, RandRange(0.9, 1.1), false);
}

function Hitstop(float Secs)
{
	HitstopT = FMax(HitstopT, Secs);
}

function Slowmo(float Secs, float Scale)
{
	SlowT = Secs;
	SlowScale = Scale;
}

function Shake(float Metres)
{
	CamShake = FMax(CamShake, Metres * S * class'MSMSettings'.default.CamShake);
}

function Hint(string Text, float Secs)
{
	HintText = Text;
	HintT = Secs;
}

function AddComic(string Text, vector Loc, float Life, byte R, byte G, byte B)
{
	local MSMComic C;

	C.Text = Text;
	C.Loc = Loc;
	C.Life = Life;
	C.MaxLife = Life;
	C.Col.R = R; C.Col.G = G; C.Col.B = B; C.Col.A = 255;
	if (Comics.Length > 12)
		Comics.Remove(0, 1);
	Comics[Comics.Length] = C;
}

//-----------------------------------------------------------------------------
// Enemies (enemies.js: findTarget, senseActive, threatWindow)

function bool Alive(Pawn P)
{
	return P != None && !P.bDeleteMe && P.Health > 0;
}

function bool Fighting(Pawn P)
{
	return Alive(P) && P.Controller != None && P.Controller.Enemy != None;
}

function bool Windup(Pawn P)
{
	return Alive(P) && P.Controller != None && P.Controller.IsInState('MeleeAttack');
}

function bool Webbed(Pawn P)
{
	return Thug01Pawn(P) != None && Thug01Pawn(P).IsWebbed;
}

function bool Airborne(Actor A)
{
	return A != None && A.Physics == PHYS_Falling;
}

function bool AliveA(Actor A)
{
	if (A == None || A.bDeleteMe)
		return false;
	if (Pawn(A) != None)
		return Pawn(A).Health > 0;
	if (DestructibleObject(A) != None)
		return DestructibleObject(A).Health > 0;
	return true;
}

function Pawn FindEnemy(vector Dir, float Range, bool bForWeb)
{
	local VillainPawn V;
	local Pawn Best;
	local vector D;
	local float Dist, Align, Score, BestScore;

	Dir = Flat(Dir);
	BestScore = 999999;
	foreach DynamicActors(class'VillainPawn', V)
	{
		if (!Alive(V) || (bForWeb && Webbed(V)))
			continue;
		D = V.Location - Pawn.Location;
		Dist = VSize(D);
		if (Dist > Range || Abs(D.Z) > 6 * S)
			continue;
		D.Z = 0;
		if (Dist > 0.01 * S)
			Align = Normal(D) dot Dir;
		else
			Align = 1;
		Score = Dist / S - Align * 6;
		if (Windup(V))
			Score -= 2;
		if (Score < BestScore)
		{
			BestScore = Score;
			Best = V;
		}
	}
	return Best;
}

function UpdateEnemies()
{
	local VillainPawn V;
	local float D, Nearest;

	Nearest = 999999;
	bSenseActive = false;
	bThreat = false;
	foreach DynamicActors(class'VillainPawn', V)
	{
		if (!Alive(V))
			continue;
		D = VSize(V.Location - Pawn.Location);
		if (Fighting(V) && D < Nearest)
			Nearest = D;
		if (Windup(V) && D < 30 * S)
		{
			bSenseActive = true;
			if (D < 3.5 * S)
				bThreat = true;
		}
	}
	bInCombat = Nearest < 18 * S;
}

//-----------------------------------------------------------------------------
// Stock mission targets: swing points, pull / web / shoot / use / zip targets.
// The stock targeting (FindTarget) follows the stock camera, so that camera is
// steered along the MSM view every frame and FindTarget runs as before; this
// also keeps the stock reticle icons on the HUD.

function UpdateContextTarget(float dt)
{
	local rotator R;
	local vector X, Y, Z, SX, SY, SZ;

	R.Yaw = CamYaw * RAD2U;
	R.Pitch = CamPitch * RAD2U;
	GetAxes(R, X, Y, Z);
	if (ThirdPersonCamera != None)
	{
		ThirdPersonCamera.DesiredPivotX = X;
		ThirdPersonCamera.DesiredPivotY = Y;
		ThirdPersonCamera.DesiredPivotZ = Z;
		ThirdPersonCamera.CameraTick(dt);
	}
	SX = ViewX; SY = ViewY; SZ = ViewZ;
	ViewX = X; ViewY = Y; ViewZ = Z;
	FindTarget();
	ViewX = SX; ViewY = SY; ViewZ = SZ;
}

function StockAction(name A)
{
	if (MState == 'swing')
		ReleaseWeb(false);
	DoAction(A);
}

// Right mouse on a pull / web / shoot / pick-up / use target does the stock action.
function bool StockContextAction()
{
	if (Target == None)
		return false;
	if (FireAction == 'Pull' || FireAction == 'Web' || FireAction == 'Shoot' || FireAction == 'Pickup' || FireAction == 'Use')
	{
		StockAction(FireAction);
		return true;
	}
	return false;
}

function InitSwingPoints()
{
	local WebSwingPoint W;

	bWSPInit = true;
	WSPs.Length = 0;
	WSPTouch.Length = 0;
	foreach AllActors(class'WebSwingPoint', W)
	{
		WSPs[WSPs.Length] = W;
		WSPTouch[WSPTouch.Length] = -100;
	}
}

function MarkSwingPoint(WebSwingPoint W)
{
	local int i;

	for (i = 0; i < WSPs.Length; i++)
		if (WSPs[i] == W)
			WSPTouch[i] = Level.TimeSeconds;
}

// Mission swing points take priority over plain building anchors.
function WebSwingPoint BestSwingPoint(vector Chest, vector Fwd)
{
	local int i;
	local WebSwingPoint W, Best;
	local vector D;
	local float Dist, Score, BestScore;

	if (!bWSPInit)
		InitSwingPoints();
	BestScore = 999999;
	for (i = 0; i < WSPs.Length; i++)
	{
		W = WSPs[i];
		if (W == None || W.bDeleteMe || W == Spidey.PrevSwingPoint)
			continue;
		D = W.Location - Chest;
		Dist = VSize(D);
		if (Dist > 60 * S || Dist < 3 * S || D.Z < 2 * S)
			continue;
		if ((Normal(D * vect(1,1,0)) dot Fwd) < -0.3)
			continue;
		if (!FastTrace(W.Location, Chest))
			continue;
		Score = Dist / S - (Normal(D * vect(1,1,0)) dot Fwd) * 10;
		if (Score < BestScore)
		{
			BestScore = Score;
			Best = W;
		}
	}
	return Best;
}

// Swinging past a mission swing point counts as swinging from it.
function TouchSwingPoints()
{
	local int i;
	local WebSwingPoint W;
	local vector Chest;

	if (!bWSPInit)
		InitSwingPoints();
	Chest = ChestLoc();
	for (i = 0; i < WSPs.Length; i++)
	{
		W = WSPs[i];
		if (W == None || W == CurWSP || Level.TimeSeconds - WSPTouch[i] < 3)
			continue;
		if (VSize(W.Location - Chest) > FMax(W.TargetableRadius, 8 * S))
			continue;
		WSPTouch[i] = Level.TimeSeconds;
		W.SwingTrigger();
		W.ReleaseTrigger();
	}
}

function EndSwingPoint()
{
	if (CurWSP == None)
		return;
	CurWSP.ReleaseTrigger();
	if (Spidey != None)
	{
		Spidey.PrevSwingPoint = CurWSP;
		Spidey.SwingPoint = None;
	}
	CurWSP = None;
}

//-----------------------------------------------------------------------------
// Input (input.js)

function ReadInput()
{
	local float L;

	hSwing = bMSMSwing != 0;
	hJump = bMSMJump != 0;
	hAttack = bMSMAttack != 0;
	hWeb = bMSMWeb != 0;
	hDodge = bMSMDodge != 0;
	hZip = bMSMZip != 0;
	hPerch = bMSMPerch != 0;
	hFinisher = bMSMFinisher != 0;

	pSwing = hSwing && !oSwing;
	pJump = hJump && !oJump;
	pAttack = hAttack && !oAttack;
	pWeb = hWeb && !oWeb;
	pDodge = hDodge && !oDodge;
	pZip = hZip && !oZip;
	pPerch = hPerch && !oPerch;
	pFinisher = hFinisher && !oFinisher;

	oSwing = hSwing; oJump = hJump; oAttack = hAttack; oWeb = hWeb;
	oDodge = hDodge; oZip = hZip; oPerch = hPerch; oFinisher = hFinisher;

	MoveX = 0;
	MoveY = 0;
	if (RightInput > 0.01) MoveX = 1; else if (RightInput < -0.01) MoveX = -1;
	if (ForwardInput > 0.01) MoveY = 1; else if (ForwardInput < -0.01) MoveY = -1;
	L = Sqrt(MoveX * MoveX + MoveY * MoveY);
	if (L > 1)
	{
		MoveX /= L;
		MoveY /= L;
	}
}

//-----------------------------------------------------------------------------
// Main tick

event PlayerTick(float DeltaTime)
{
	local float RDT, Scale;
	local int i;

	Super.PlayerTick(DeltaTime);

	if (HudInt == None && Player != None && Player.InteractionMaster != None)
		HudInt = Player.InteractionMaster.AddInteraction("MSMSpidey.MSMHud", Player);

	if (ReflectionsOn())
	{
		if (ReflTex != None)
			ReflTex.Revision++;
		if (MirrorTex != None)
			MirrorTex.Revision++;
	}

	if (!bMSMActive)
		return;

	// hitstop / slow motion run on real time (main.js)
	RDT = DeltaTime / FMax(0.01, Level.TimeDilation);
	CamDT += RDT;
	Scale = 1.0;
	if (HitstopT > 0)
	{
		HitstopT -= RDT;
		Scale = 0.05;
	}
	else if (SlowT > 0)
	{
		SlowT -= RDT;
		Scale = SlowScale;
	}
	if (Level.TimeDilation != Scale)
		Level.TimeDilation = Scale;

	for (i = Comics.Length - 1; i >= 0; i--)
	{
		Comics[i].Life -= RDT;
		if (Comics[i].Life <= 0)
			Comics.Remove(i, 1);
	}
	if (HintT > 0)
		HintT -= RDT;
}

function MSMUpdate(float dt)
{
	if (Spidey == None || Pawn == None)
		return;
	if (!bMSMActive)
		EnterMSM();
	if (!bMSMActive)
		return;

	ReadInput();
	// mouse look is accumulated here and applied by the camera at render time
	LookX += LookSensitivity * class'MSMSettings'.default.LookSpeed * 32.0 * dt * aTurn / RAD2U;
	LookY += LookSensitivity * class'MSMSettings'.default.LookSpeed * 32.0 * dt * aLookUp / RAD2U;
	aTurn = 0;
	aLookUp = 0;

	CamAxes();
	Wish = CamFlatFwd * MoveY + CamRight * MoveX;
	WishLen = FMin(1, VSize(Wish));
	if (WishLen > 0.01)
		Wish = Normal(Wish);

	if (SwingCD > 0) SwingCD -= dt;
	if (WallCD > 0) WallCD -= dt;
	if (ZipCD > 0) ZipCD -= dt;
	if (WebCD > 0) WebCD -= dt;
	if (DodgeT > 0) DodgeT -= dt;
	if (Invuln > 0) Invuln -= dt;
	if (FlipT > 0) FlipT -= dt;
	if (LandT > 0) LandT -= dt;
	if (LaunchBuffer > 0) LaunchBuffer -= dt;
	if (ZipT > 0) ZipT -= dt;
	if (DownT > 0) DownT -= dt;
	SinceHurt += dt;
	if (SinceHurt > 2)
		HitStreak = 0;
	if (ComboTimer > 0)
	{
		ComboTimer -= dt;
		if (ComboTimer <= 0)
			Combo = 0;
	}
	if (SinceHurt > 5 && Spidey.Health < Spidey.MaxHealth)
	{
		RegenAcc += 0.08 * Spidey.MaxHealth * dt;
		if (RegenAcc >= 1)
		{
			Spidey.Health = Min(Spidey.MaxHealth, Spidey.Health + int(RegenAcc));
			RegenAcc -= int(RegenAcc);
		}
	}

	if (Pawn.PhysicsVolume != None && Pawn.PhysicsVolume.TerminalVelocity < 85 * S)
		Pawn.PhysicsVolume.TerminalVelocity = 85 * S;

	UpdateEnemies();
	UpdateContextTarget(dt);
	if (MState == 'swing')
		TouchSwingPoints();
	PerchScanT -= dt;
	if (PerchScanT <= 0)
	{
		PerchScanT = 0.08;
		UpdatePerchTarget();
	}
	SyncPhysics();

	if (DownT <= 0)
	{
		if (pFinisher) DoFinisher();
		if (pAttack) Attack();
		if (pWeb) ShootWeb();
		if (pDodge) DodgeOrDive();
		if (pZip) WebZip();
		if (pPerch) PointLaunch();
		if (pJump) LaunchBuffer = 0.25;
		if (!bMSMActive)
			return;

		switch (MState)
		{
			case 'ground': GroundActions(dt); break;
			case 'air': AirActions(dt); break;
			case 'swing': SwingActions(dt); break;
			case 'wall': WallActions(dt); break;
			case 'perch': PerchActions(dt); break;
		}
	}

	UpdateAttack(dt);
	UpdateWebShot(dt);
	PhysicsStep(dt);
	Animate(dt);

	if (MState != 'pointZip' && Pawn != None && !Pawn.bCollideWorld)
		Pawn.bCollideWorld = true;

	if (bMSMDebug && MState != LastLoggedState)
	{
		Log("MSMSTATE " $ LastLoggedState $ " -> " $ MState $ " loc=" $ Pawn.Location $ " phys=" $ Pawn.Physics
			$ " perchWall=" $ bPerchWall $ " perchN=" $ PerchN $ " wallN=" $ WallN $ " act=" $ ActAnim);
		LastLoggedState = MState;
	}

	if (bMSMDebug)
	{
		DebugT -= dt;
		if (DebugT <= 0)
		{
			DebugT = 1.0;
			Log("MSMDBG st=" $ MState $ " phys=" $ Pawn.Physics $ " loc=" $ Pawn.Location $ " vel=" $ int(VSize(Pawn.Velocity))
				$ " cam=" $ CamLoc $ " camDist=" $ int(VSize(CamLoc - Pawn.Location)) $ " anim=" $ CurAnim $ " act=" $ ActAnim
				$ " move=" $ MoveX $ "," $ MoveY $ " fwdIn=" $ ForwardInput $ " swing=" $ hSwing $ " jump=" $ hJump
				$ " vt=" $ ViewTarget $ " ctl=" $ InControl() $ " perch=" $ bHasPerch $ " fov=" $ int(FovAngle));
		}
	}
}

// Keep MState in line with what the engine did (walked off a ledge, landed, etc.)
function SyncPhysics()
{
	if (MState == 'ground')
	{
		if (Pawn.Physics == PHYS_Falling)
			MState = 'air';
		else if (Pawn.Physics != PHYS_Walking)
			Pawn.SetPhysics(PHYS_Walking);
	}
	else if (MState == 'air' || MState == 'swing' || MState == 'zip')
	{
		if (Pawn.Physics == PHYS_Walking)
			DoLanded(Pawn.Velocity.Z);
		else if (Pawn.Physics != PHYS_Falling)
			Pawn.SetPhysics(PHYS_Falling);
	}
	else if (MState == 'wall' || MState == 'pointZip')
	{
		if (Pawn.Physics != PHYS_Flying)
			Pawn.SetPhysics(PHYS_Flying);
	}
}

function GoAir()
{
	MState = 'air';
	if (Pawn.Physics != PHYS_Falling)
		Pawn.SetPhysics(PHYS_Falling);
}

//-----------------------------------------------------------------------------
// State actions (player.js groundActions, airActions, ...)

function GroundActions(float dt)
{
	local float C, HS;
	local vector V;

	bDiving = false;
	AirTime = 0;
	if (pJump)
		JumpCharge = 0;
	if (JumpCharge >= 0)
	{
		JumpCharge += dt;
		if (!hJump || JumpCharge > 0.7)
		{
			C = FMin(1, JumpCharge / 0.7);
			V = Pawn.Velocity;
			V.Z = (12 + C * 12) * S;
			HS = VSize2D(V);
			if (hSwing && HS > 8 * S)
			{
				V.X *= 1.15;
				V.Y *= 1.15;
			}
			GoAir();
			Pawn.Velocity = V;
			JumpCharge = -1;
			LaunchBuffer = 0;
			if (C > 0.6)
			{
				FlipT = 0.6;
				Whoosh();
			}
			AnimEvent('jump', C > 0.6, bInCombat);
		}
	}
	else if (hSwing && WishLen > 0.5)
		CheckWallAhead();
}

function AirActions(float dt)
{
	AirTime += dt;
	JumpCharge = -1;
	if (hSwing && SwingCD <= 0 && Pawn.Velocity.Z < 7 * S && !bAtkActive
		&& HeightAboveGround(1.8 * S + 10) > 1.8 * S)
		AttachWeb();
}

function SwingActions(float dt)
{
	local vector Chest;

	SwingT += dt;
	WebShoot = FMin(1, WebShoot + dt * 9);
	Chest = ChestLoc();
	if (pJump)
	{
		ReleaseWeb(true);
		return;
	}
	if (!hSwing)
	{
		ReleaseWeb(false);
		return;
	}
	if (Chest.Z > RopePivot().Z - 1.2 * S || SwingT > 4.5)
	{
		ReleaseWeb(false);
		return;
	}
	if (Wraps.Length > 0 && RopeLen - WrappedLen() < 2 * S)
		ReleaseWeb(false);
}

function WallActions(float dt)
{
	local bool bWas;
	local vector V;

	bWas = bWallRunning;
	bWallRunning = hSwing;
	if (bWas && !bWallRunning && Pawn.Velocity.Z > 4 * S)
		AnimEvent('wallRunStop');
	if (pJump)
	{
		Log("MSMJUMP wall jump: bMSMJump=" $ bMSMJump $ " hJump=" $ hJump $ " oJump=" $ oJump $ " t=" $ Level.TimeSeconds);
		V = WallN * (11 * S) + vect(0,0,1) * (10 * S) + CamRight * (MoveX * 5 * S);
		GoAir();
		Pawn.Velocity = V;
		WallCD = 0.35;
		FlipT = 0.6;
		Facing = WallN;
		Whoosh();
		AnimEvent('wallJump', bWallRunning);
	}
}

function PerchActions(float dt)
{
	local vector V;

	Pawn.Velocity = vect(0,0,0);
	if (LaunchBuffer > 0)
	{
		LaunchBuffer = 0;
		V = Flat(ZipDir) * (14 * S) + vect(0,0,1) * (19 * S);
		GoAir();
		Pawn.Velocity = V;
		FlipT = 0.6;
		Whoosh();
		AnimEvent('launch', false);
	}
	else if (WishLen > 0.3)
	{
		MState = 'ground';
		Pawn.SetPhysics(PHYS_Walking);
	}
}

//-----------------------------------------------------------------------------
// Web swing

function bool FireRope(MSMAnchor A, vector Loc, bool bRight)
{
	local name Bone;

	if (A == None || Spidey == None)
		return false;
	A.SetLocation(Loc);
	if (bRight)
		Bone = Spidey.WebBoneRight;
	else
		Bone = Spidey.WebBoneLeft;
	return Spidey.FireWebRope(Bone, vect(0,0,0), A, 'None', vect(0,0,0), Normal(Pawn.Location - Loc), None);
}

function AttachWeb()
{
	local vector Chest, HV, Fwd, Right, Dir, HL, HN, Best, BestN;
	local float Sides[7], Ups[5], Score, BestScore, HS, Ground, Dist;
	local int i, j;
	local bool bFound;
	local WebSwingPoint W;

	Chest = ChestLoc();
	HV = Pawn.Velocity * vect(1,1,0);
	if (VSize(HV) > 4 * S)
		Fwd = Normal(HV);
	else
		Fwd = CamFlatFwd;
	if (WishLen * WishLen > 0.04)
		Fwd = Normal(Fwd + (Wish - Fwd) * 0.6);
	Right = Normal(vect(0,0,1) cross Fwd);

	W = BestSwingPoint(Chest, Fwd);
	if (W != None)
	{
		Best = W.Location;
		BestN = Normal(Chest - W.Location);
		bFound = true;
	}

	Sides[0] = 0; Sides[1] = -0.45; Sides[2] = 0.45; Sides[3] = -1; Sides[4] = 1; Sides[5] = -1.6; Sides[6] = 1.6;
	Ups[0] = 0.6; Ups[1] = 0.9; Ups[2] = 1.25; Ups[3] = 1.7; Ups[4] = 2.5;
	BestScore = -999999;

	// The web only sticks to buildings: fan of rays ahead and above
	for (i = 0; i < 7 && W == None; i++)
	{
		for (j = 0; j < 5; j++)
		{
			Dir = Normal(Fwd + Right * (Sides[i] * 0.75) + vect(0,0,1) * Ups[j]);
			if (Trace(HL, HN, Chest + Dir * (110 * S), Chest, false) == None)
				continue;
			if (HL.Z < Chest.Z + 4 * S)
				continue;
			Dist = VSize(HL - Chest) / S;
			Score = -Abs(Dist - 38) * 0.6 - Abs(Sides[i]) * 1.5 + (HL.Z / S) * 0.02;
			if (Sides[i] != 0)
				Score += 3;
			if (Score > BestScore)
			{
				BestScore = Score;
				Best = HL;
				BestN = HN;
				bFound = true;
			}
		}
	}
	if (!bFound)
	{
		// nothing to hold on to (rooftops / open space): keep falling
		SwingCD = 0.12;
		return;
	}

	Anchor = Best + BestN * 4;
	if (W != None)
	{
		Anchor = W.Location;
		CurWSP = W;
		Spidey.SwingPoint = W;
		MarkSwingPoint(W);
		W.SwingTrigger();
	}
	Wraps.Length = 0;
	RopeLen = VSize(Chest - Anchor);
	Ground = Feet().Z - HeightAboveGround(300 * S);
	RopeTarget = FMin(RopeLen, Anchor.Z - Ground - 3.2 * S);
	bSwingRight = ((Anchor - Chest) dot Right) > 0;

	// momentum gain
	HV = Pawn.Velocity;
	HS = VSize2D(HV);
	if (HS < 14 * S)
		HV += Fwd * (14 * S - HS);
	if (HV.Z < -25 * S)
		HV.Z *= 0.85;
	Pawn.Velocity = HV;

	MState = 'swing';
	SwingT = 0;
	WebShoot = 0;
	bDiving = false;
	if (Pawn.Physics != PHYS_Falling)
		Pawn.SetPhysics(PHYS_Falling);
	FireRope(RopeActor, Anchor, bSwingRight);
	Thwip();
	AnimEvent('swingStart');
	if (FRand() < 0.25)
		AddComic("THWIP!", Anchor + (Chest - Anchor) * 0.6, 0.6, 255, 255, 255);
}

function ReleaseWeb(bool bJump)
{
	local vector V, HV;
	local float HS;

	V = Pawn.Velocity;
	HV = V * vect(1,1,0);
	HS = VSize(HV);
	if (HS > 0.1)
		HV = HV / HS;
	if (bJump)
	{
		V.Z = FMax(V.Z, 0) + 11 * S;
		V += HV * (5 * S);
		FlipT = 0.65;
		SwingCD = 0.4;
		Whoosh();
	}
	else
	{
		if (V.Z > 0)
			V.Z *= 1.12;
		V += HV * (2.5 * S);
		SwingCD = 0.28;
	}
	GoAir();
	Pawn.Velocity = V;
	Spidey.ReleaseWebRope();
	Wraps.Length = 0;
	EndSwingPoint();
	if (bJump)
		AnimEvent('swingJump');
	else
		AnimEvent('swingRelease');
}

// Rope wrapping around building edges (approximation of player.js updateRopeWrap:
// the bend point is the first blocking hit pushed out of the surface).
function UpdateRopeWrap()
{
	local vector Chest, Prev, Pivot, HL, HN, Dir;
	local int k;

	Chest = ChestLoc();
	while (Wraps.Length > 0)
	{
		if (Wraps.Length > 1)
			Prev = Wraps[Wraps.Length - 2];
		else
			Prev = Anchor;
		Dir = Normal(Chest - Prev);
		if (!FastTrace(Prev + Dir * (0.35 * S), Chest))
			break;
		Wraps.Remove(Wraps.Length - 1, 1);
	}
	for (k = 0; k < 2 && Wraps.Length < 8; k++)
	{
		Pivot = RopePivot();
		if (VSize(Pivot - Chest) < S)
			break;
		Dir = Normal(Pivot - Chest);
		if (Trace(HL, HN, Pivot - Dir * (0.35 * S), Chest, false) == None)
			break;
		HL += HN * (0.12 * S);
		if (VSize(HL - Pivot) < 0.5 * S)
			break;
		Wraps[Wraps.Length] = HL;
	}
	if (RopeActor != None)
		RopeActor.SetLocation(RopePivot());
}

//-----------------------------------------------------------------------------
// Web zip (Q) and point launch (E)

function WebZip()
{
	local vector Dir, HL, HN, V;

	if (ZipCD > 0 || MState == 'pointZip' || MState == 'perch')
		return;
	if (MState == 'ground' && !bInCombat)
	{
		PointLaunch();
		return;
	}
	Dir = CamFwd;
	Dir.Z = FClamp(Dir.Z, -0.25, 0.45);
	Dir = Normal(Dir);
	if (MState == 'swing')
	{
		Spidey.ReleaseWebRope();
		EndSwingPoint();
	}
	AnimEvent('zip', MState == 'ground');
	Facing = Flat(Dir);
	V = Dir * FMax(30 * S, VSize(Pawn.Velocity) * 0.9) + vect(0,0,1) * (4 * S);
	MState = 'zip';
	if (Pawn.Physics != PHYS_Falling)
		Pawn.SetPhysics(PHYS_Falling);
	Pawn.Velocity = V;
	ZipT = 0.32;
	ZipCD = 0.55;
	// the web is only drawn if it hits a surface
	bZipHasWeb = Trace(HL, HN, ChestLoc() + CamFwd * (80 * S), ChestLoc(), false) != None;
	if (bZipHasWeb)
	{
		ZipTo = HL;
		FireRope(ZipActor, HL, true);
	}
	else
		Spidey.ReleaseWebRope();
	bDiving = false;
	Thwip();
}

// Roof point above a wall hit: climb the wall face with horizontal probes,
// then drop onto the roof just behind the edge.
function bool FindWallTop(vector HitLoc, vector N, out vector Top)
{
	local vector HL, HN, P;
	local float Z, Lo, Hi, Step;
	local int i;
	local bool bFound;

	N = Flat(N);
	Step = 200;
	for (Z = Step; Z < 9000; Z += Step)
	{
		P = HitLoc + vect(0,0,1) * Z + N * 16;
		if (Trace(HL, HN, P - N * 64, P, false) == None)
		{
			bFound = true;
			break;
		}
	}
	if (!bFound)
		return false;
	Lo = Z - Step;
	Hi = Z;
	for (i = 0; i < 4; i++)
	{
		Z = (Lo + Hi) / 2;
		P = HitLoc + vect(0,0,1) * Z + N * 16;
		if (Trace(HL, HN, P - N * 64, P, false) == None)
			Hi = Z;
		else
			Lo = Z;
	}
	P = HitLoc + vect(0,0,1) * (Hi + 120) - N * (0.35 * S);
	if (Trace(HL, HN, P - vect(0,0,1) * 400, P, false) == None || HN.Z < 0.7)
		return false;
	Top = HL;
	return true;
}

function UpdatePerchTarget()
{
	local vector HL, HN, T;
	local float D;

	bHasPerch = false;
	bPerchWall = false;
	// player.js updatePerchTarget: a wall -> the top edge of that building, a roof -> the hit point
	if (Trace(HL, HN, CamLoc + CamFwd * (110 * S), CamLoc, false) == None)
		return;
	if (HN.Z > 0.5)
		T = HL;
	else if (HN.Z < -0.5)
		return;
	else if (!FindWallTop(HL, HN, T))
		return;
	D = VSize(T - Feet());
	if (D < 5 * S || D > 95 * S)
		return;
	PerchTarget = T;
	PerchN = HN;
	bHasPerch = true;
}

function PointLaunch()
{
	if (Target != None && FireAction == 'Zip' && MState != 'pointZip')
	{
		StockAction('Zip');
		return;
	}
	if (!bHasPerch || MState == 'pointZip')
		return;
	if (MState == 'swing')
	{
		Spidey.ReleaseWebRope();
		EndSwingPoint();
	}
	AnimEvent('pointZip', MState == 'ground' || MState == 'perch');
	ZipFrom = Pawn.Location;
	if (bPerchWall)
		ZipTo = PerchTarget + Flat(PerchN) * (Pawn.CollisionRadius + 3);   // in front of the wall face
	else
		ZipTo = PerchTarget + vect(0,0,1) * (Pawn.CollisionHeight + 4);
	ZipDir = Normal(ZipTo - ZipFrom);
	MState = 'pointZip';
	// the web pulls him straight to the point: the capsule must not snag on the facade edge
	Pawn.bCollideWorld = false;
	Pawn.SetPhysics(PHYS_Flying);
	Pawn.Velocity = vect(0,0,0);
	WebShoot = 0;
	bAtkActive = false;
	bLunge = false;
	bDiving = false;
	Wraps.Length = 0;
	FireRope(ZipActor, PerchTarget, true);
	Thwip();
}

//-----------------------------------------------------------------------------
// Dodge / dive (C)

function DodgeOrDive()
{
	local vector Dir, V;
	local bool bPerfect;

	if ((MState == 'air' || MState == 'zip') && !bInCombat)
	{
		if (!bDiving)
		{
			bDiving = true;
			V = Pawn.Velocity;
			V.Z = FMin(V.Z - 12 * S, -20 * S);
			Pawn.Velocity = V;
			Whoosh();
			AnimEvent('dive');
		}
		return;
	}
	if (MState == 'wall')
	{
		GoAir();
		WallCD = 0.5;
		return;
	}
	if (DodgeT > 0)
		return;
	if (WishLen > 0.1)
		Dir = Wish;
	else
		Dir = -Facing;
	Dir = Flat(Dir);
	Facing = Dir;
	AnimEvent('dodge');
	bPerfect = bThreat;
	V = Pawn.Velocity;
	V.X = Dir.X * 14 * S;
	V.Y = Dir.Y * 14 * S;
	Pawn.Velocity = V;
	DodgeT = 0.35;
	Invuln = 0.45;
	bAtkActive = false;
	bLunge = false;
	Whoosh();
	if (bPerfect)
	{
		Focus = FMin(3, Focus + 0.25);
		Slowmo(0.45, 0.3);
		AddComic("WHOOSH!", ChestLoc(), 0.7, 255, 255, 255);
	}
}

//-----------------------------------------------------------------------------
// Combat (player.js attack/startAttack/updateAttack, shootWeb, finisher)

function name AttackAnimFor(int Step, bool bAir, bool bFinisher)
{
	if (bFinisher)
	{
		if (bAir)
			return 'AttackJumpDeath_01';
		switch (Step % 5)
		{
			case 0: return 'AttackGroundDeath_01';
			case 1: return 'AttackGroundDeath_02';
			case 2: return 'AttackGroundDeath_03';
			case 3: return 'AttackGroundDeath_04';
			default: return 'AttackGroundDeath_05';
		}
	}
	if (bAir)
	{
		if (Step % 2 == 1)
			return 'AttackJumpH_02';
		return 'AttackJumpL_01';
	}
	// 12 step combo, every 4th hit (index 3, 7, 11) is heavy
	switch (Step % 12)
	{
		case 0: return 'AttackGround_01';
		case 1: return 'AttackGround_02';
		case 2: return 'AttackGroundSpec_06';
		case 3: return 'AttackGroundSpec_08';
		case 4: return 'AttackGround_03';
		case 5: return 'AttackGroundSpec_09';
		case 6: return 'AttackGround_04';
		case 7: return 'AttackGroundSpec_10';
		case 8: return 'AttackGround_05';
		case 9: return 'AttackGround_07';
		case 10: return 'AttackGround_02';
		default: return 'AttackGroundSpec_06';
	}
}

function Attack()
{
	if (MState == 'wall' || MState == 'pointZip' || MState == 'perch')
		return;
	if (bAtkActive && !bLunge)
	{
		if (AtkT > AtkDur * 0.3)
			bAtkQueued = true;
		return;
	}
	StartAttack(-1);
}

function StartAttack(int ForceStep)
{
	local vector Dir;
	local Actor Target;
	local int Step;
	local bool bAir, bFin;
	local float Len, HitFrac;

	if (MState == 'swing')
		ReleaseWeb(false);
	if (WishLen > 0.1)
		Dir = Wish;
	else
		Dir = CamFlatFwd;
	Target = FindEnemy(Dir, 14 * S, false);
	if (Target == None && BreakTarget != None && AliveA(BreakTarget) && VSize(BreakTarget.Location - Pawn.Location) < 14 * S)
		Target = BreakTarget;
	if (ComboTimer <= 0)
		ComboStep = 0;
	if (ForceStep >= 0)
		Step = ForceStep;
	else
		Step = ComboStep;
	bFin = ForceStep >= 0;
	bAir = MState == 'air' || MState == 'zip';
	if (bFin)
		AtkAnim = AttackAnimFor(FinisherCount++, bAir, true);
	else
		AtkAnim = AttackAnimFor(Step, bAir, false);

	// timing: the hit lands ~0.14 s after the clip starts (spideyAnim.js timing())
	HitFrac = 0.3;
	Len = Spidey.AnimGetLength(AtkAnim, 1.0);
	if (Len <= 0)
		Len = 0.6;
	AtkRate = FClamp(HitFrac * Len / 0.14, 1.1, 3.0);
	AtkHitAt = HitFrac * Len / AtkRate;
	AtkDur = AtkHitAt + 0.16;

	bAtkActive = true;
	AtkT = 0;
	AtkStep = Step;
	AtkTarget = Target;
	bAtkHitDone = false;
	bAtkQueued = false;
	bAtkFinisher = bFin;
	bAtkAnimStarted = false;
	ComboStep++;
	if (Target != None)
	{
		bLunge = VSize(Target.Location - Pawn.Location) > 2.1 * S;
		LungeT = 0;
		Facing = Flat(Target.Location - Pawn.Location);
	}
	else
		bLunge = false;
	Whoosh();
}

function UpdateAttack(float dt)
{
	local vector D, V;
	local float Dist;
	local bool bHeavy;

	if (!bAtkActive)
		return;
	if (AtkTarget != None && !AliveA(AtkTarget))
		AtkTarget = None;
	if (bLunge)
	{
		LungeT += dt;
		if (AtkTarget == None || LungeT > 0.45)
		{
			bLunge = false;
			return;
		}
		D = AtkTarget.Location - Pawn.Location;
		if (MState != 'air')
			D.Z = 0;
		Dist = VSize(D);
		if (Dist < 1.7 * S)
		{
			bLunge = false;
			Pawn.Velocity = Pawn.Velocity * 0.1;
			return;
		}
		V = Normal(D) * (30 * S);
		if (MState == 'ground')
			V.Z = 0;
		Pawn.Velocity = V;
		Facing = Flat(D);
		return;
	}
	AtkT += dt;
	if (MState == 'ground')
	{
		V = Pawn.Velocity;
		V.X *= 0.8 ** (dt * 60);
		V.Y *= 0.8 ** (dt * 60);
		Pawn.Velocity = V;
	}
	if (MState == 'air' && AtkTarget != None && Airborne(AtkTarget))
	{
		V = Pawn.Velocity;
		V.Z = FMax(V.Z, 0.5 * S);
		Pawn.Velocity = V;
	}
	if (!bAtkHitDone && AtkT > AtkHitAt)
	{
		bAtkHitDone = true;
		if (AtkTarget != None && VSize(AtkTarget.Location - Pawn.Location) < 2.8 * S)
		{
			bHeavy = (AtkStep % 4) == 3 || bAtkFinisher;
			DealHit(AtkTarget, bHeavy, bAtkFinisher);
		}
	}
	if (AtkT >= AtkDur)
	{
		if (bAtkQueued)
			StartAttack(-1);
		else
			bAtkActive = false;
	}
}

function DealHit(Actor T, bool bHeavy, bool bFinisher)
{
	local vector Dir, Mom, HitPos;
	local int Dmg, HMax;
	local class<DamageType> DT;
	local bool bAir;
	local Pawn P;

	P = Pawn(T);
	Dir = Flat(T.Location - Pawn.Location);
	if (P != None)
		HMax = Max(1, P.default.Health);
	else
		HMax = 40;
	bAir = Airborne(T);
	if (bFinisher)
	{
		Dmg = 999;
		if (P != None)
			Dmg = P.Health + 999;
		DT = class'DamageDeathBlowChin';
		Mom = Dir * (16 * S) + vect(0,0,1) * (9 * S);
	}
	else if (bHeavy)
	{
		Dmg = Max(1, int(14.0 / 40.0 * HMax + 0.5));
		DT = class'DamageKickChin';
		Mom = Dir * (5 * S);
		if (bAir)
			Mom.Z = 4 * S;
		else
			Mom.Z = 10 * S;
	}
	else
	{
		Dmg = Max(1, int(9.0 / 40.0 * HMax + 0.5));
		switch (LightHitIndex++ % 4)
		{
			case 0: DT = class'DamageHeadFront'; break;
			case 1: DT = class'DamageHeadLeft'; break;
			case 2: DT = class'DamageHeadRight'; break;
			default: DT = class'DamageGut'; break;
		}
		Mom = Dir * (3.5 * S);
		if (bAir)
			Mom.Z = 4 * S;
	}
	if (P != None && Webbed(P))
		Dmg = int(Dmg * 1.5);
	HitPos = T.Location + vect(0,0,1) * 30;
	T.TakeDamage(Dmg, Pawn, HitPos, Mom * T.Mass, DT);

	Combo++;
	ComboTimer = 2.5;
	if (bHeavy)
		Focus = FMin(3, Focus + 0.12);
	else
		Focus = FMin(3, Focus + 0.07);
	if (bHeavy)
	{
		Hitstop(0.09);
		Shake(0.35);
	}
	else
	{
		Hitstop(0.05);
		Shake(0.15);
	}
	if (bFinisher)
		AddComic("KAPOW!", HitPos + vect(0,0,40), 1.1, 255, 220, 40);
	else if (bHeavy || FRand() < 0.35)
	{
		switch (Rand(6))
		{
			case 0: AddComic("POW!", HitPos + vect(0,0,40), 0.8, 255, 230, 60); break;
			case 1: AddComic("BAM!", HitPos + vect(0,0,40), 0.8, 255, 230, 60); break;
			case 2: AddComic("WHAM!", HitPos + vect(0,0,40), 0.8, 255, 230, 60); break;
			case 3: AddComic("THWAK!", HitPos + vect(0,0,40), 0.8, 255, 230, 60); break;
			case 4: AddComic("SMACK!", HitPos + vect(0,0,40), 0.8, 255, 230, 60); break;
			default: AddComic("BIFF!", HitPos + vect(0,0,40), 0.8, 255, 230, 60); break;
		}
	}
	if (P != None && !Alive(P))
		OnKO(P);
}

function OnKO(Pawn T)
{
	local VillainPawn V;

	Focus = FMin(3, Focus + 0.1);
	foreach DynamicActors(class'VillainPawn', V)
		if (Fighting(V) && VSize(V.Location - T.Location) < 25 * S)
			return;
	Focus = FMin(3, Focus + 0.5);
	Hint("CRIME PREVENTED!", 2.5);
	AddComic("CRIME PREVENTED!", T.Location + vect(0,0,160), 1.4, 255, 255, 255);
}

function ShootWeb()
{
	local vector Dir, End;
	local Pawn Target;

	if (WebCD > 0 || MState == 'pointZip')
		return;
	if (StockContextAction())
		return;
	WebCD = 0.35;
	if (WishLen > 0.1)
		Dir = Wish;
	else
		Dir = CamFlatFwd;
	Target = FindEnemy(Dir, 32 * S, true);
	if (Target != None)
	{
		Facing = Flat(Target.Location - Pawn.Location);
		WebShotTarget = Target;
		WebShotT = VSize(Target.Location - Pawn.Location) / (70 * S);
		End = Target.Location + vect(0,0,1) * 20;
	}
	else
	{
		WebShotTarget = None;
		End = ChestLoc() + CamFwd * (30 * S);
	}
	// one rope at a time: don't cut the swing line for a web shot
	if (MState != 'swing')
	{
		FireRope(ShotActor, End, true);
		ShotRopeT = 0.4;
	}
	Thwip();
	AnimEvent('webShot', MState != 'ground');
}

function UpdateWebShot(float dt)
{
	if (WebShotTarget != None)
	{
		WebShotT -= dt;
		ShotActor.SetLocation(WebShotTarget.Location + vect(0,0,1) * 20);
		if (WebShotT <= 0)
		{
			ApplyWeb(WebShotTarget);
			WebShotTarget = None;
		}
	}
	if (ShotRopeT > 0)
	{
		ShotRopeT -= dt;
		if (ShotRopeT <= 0 && MState != 'swing' && MState != 'pointZip' && !(MState == 'zip' && bZipHasWeb))
			Spidey.ReleaseWebRope();
	}
}

function ApplyWeb(Pawn T)
{
	if (!Alive(T))
		return;
	if (Thug01Pawn(T) != None)
	{
		if (!Thug01Pawn(T).IsWebbed)
		{
			Thug01Pawn(T).CurrentBoneTarget.Bone = 'Torso';
			Thug01Pawn(T).PlayWebBlinded();
		}
	}
	else
		T.TakeDamage(1, Pawn, T.Location, vect(0,0,0), class'DamageWebUp');
	AddComic("THWIP!", T.Location + vect(0,0,60), 0.6, 255, 255, 255);
}

function DoFinisher()
{
	local Pawn Target;

	if (Focus < 1)
	{
		Hint("Not enough focus!", 1);
		return;
	}
	Target = FindEnemy(CamFlatFwd, 7 * S, false);
	if (Target == None)
		return;
	Focus -= 1;
	StartAttack(3);
	AtkTarget = Target;
	bAtkFinisher = true;
	Invuln = 1;
	Slowmo(0.6, 0.35);
}

// Called by MSMSpideyPawn.TakeDamage
function bool CanTakeHit()
{
	return !(Invuln > 0 || MState == 'pointZip' || DownT > 0);
}

function OnHurt(int Damage, Pawn Attacker)
{
	local vector FromDir, V;
	local bool bAir, bBig;

	if (Attacker != None)
		FromDir = Flat(Pawn.Location - Attacker.Location);
	else
		FromDir = -Facing;
	SinceHurt = 0;
	Combo = 0;
	ComboTimer = 0;
	Invuln = 0.5;
	HitStreak++;
	bAir = MState != 'ground';
	if (MState == 'swing')
		ReleaseWeb(false);
	if (MState == 'perch' || MState == 'wall')
		GoAir();
	V = Pawn.Velocity + FromDir * (8 * S);
	if (bAir)
		V.Z += 3 * S;
	Pawn.Velocity = V;
	bAtkActive = false;
	bLunge = false;
	bBig = !bAir && (HitStreak >= 3 || Spidey.Health < Spidey.MaxHealth * 0.3);
	if (bBig)
	{
		DownT = 1.7;
		Invuln = 1.9;
		HitStreak = 0;
		Facing = -FromDir;
	}
	AnimEvent('hurt', bAir, bBig);
	Shake(0.4);
}

//-----------------------------------------------------------------------------
// Walls (player.js tryWall / wallStep)

// Top of a low obstacle in front of Spidey, if it is lower than MaxH above his feet.
function bool FindLedgeTop(vector N, float MaxH, out vector Top)
{
	local vector P, HL, HN;
	local float FeetZ;

	N = Flat(N);
	FeetZ = Feet().Z;
	P = Pawn.Location - N * (Pawn.CollisionRadius + 24);
	P.Z = FeetZ + MaxH + 8;
	if (!FastTrace(P, Pawn.Location + vect(0,0,1) * (P.Z - Pawn.Location.Z)))
		return false;
	if (Trace(HL, HN, P - vect(0,0,1) * (MaxH + 4), P, false) == None)
		return false;
	if (HN.Z < 0.7 || HL.Z < FeetZ + 4)
		return false;
	Top = HL;
	return true;
}

function bool HopOnto(vector Top, vector N)
{
	local vector NewLoc;

	NewLoc = Top + vect(0,0,1) * (Pawn.CollisionHeight + 3) - Flat(N) * (0.4 * S);
	return Pawn.SetLocation(NewLoc);
}

// On the ground with Shift held: run up the wall in front, or vault low obstacles.
function CheckWallAhead()
{
	local vector HL, HN, Start, Top;

	Start = Pawn.Location;
	if (Trace(HL, HN, Start + Wish * (Pawn.CollisionRadius + 16), Start, false) == None)
		return;
	if (Abs(HN.Z) > 0.5 || -(Wish dot Flat(HN)) < 0.5 || bAtkActive)
		return;
	if (FindLedgeTop(HN, 1.7 * S, Top))
		HopOnto(Top, HN);
	else
		TryWall(HN);
}

function TryWall(vector N)
{
	local vector Top, V;
	local float HS;

	if (WallCD > 0 || bAtkActive)
		return;
	if (FindLedgeTop(N, 1.4 * S, Top))
	{
		if (HopOnto(Top, N))
		{
			V = Pawn.Velocity;
			V.Z = FMax(V.Z, 2 * S);
			Pawn.Velocity = V;
		}
		return;
	}
	if (MState == 'swing')
	{
		Spidey.ReleaseWebRope();
		Wraps.Length = 0;
		EndSwingPoint();
	}
	V = Pawn.Velocity;
	HS = VSize2D(V);
	WallN = Flat(N);
	WallRunSpeed = FClamp(HS / S * 0.7 + FMax(0, V.Z / S) * 0.5, 13, 26) * S;
	MState = 'wall';
	Pawn.SetPhysics(PHYS_Flying);
	Pawn.Velocity = vect(0,0,1) * (FMax(0, V.Z) * 0.5);
	WallFwd = vect(0,0,1);
	bDiving = false;
	Whoosh();
}

function ClimbOverTop(bool bRun)
{
	local vector P, HL, HN, V;

	P = Pawn.Location + vect(0,0,1) * (Pawn.CollisionHeight + 90) - WallN * (0.7 * S + Pawn.CollisionRadius);
	if (Trace(HL, HN, P - vect(0,0,1) * (Pawn.CollisionHeight * 2 + 200), P, false) == None || HN.Z < 0.7)
		return;
	if (!Pawn.SetLocation(HL + vect(0,0,1) * (Pawn.CollisionHeight + 4)))
		return;
	if (bRun)
		V = -WallN * (7 * S) + vect(0,0,1) * (6 * S);
	else
		V = -WallN * (3 * S) + vect(0,0,1) * (2 * S);
	GoAir();
	Pawn.Velocity = V;
	WallCD = 0.2;
	if (bRun)
		FlipT = 0.5;
	Facing = -WallN;
	AnimEvent('wallTop', bRun);
}

function WallStep(float h)
{
	local vector Lat, Target, V, HL, HN, Low;
	local bool bRun;
	local float My, Mx, Sp, K, Corr;

	Lat = CamRight - WallN * (CamRight dot WallN);
	Lat.Z = 0;
	if (VSize(Lat) < 0.1)
		Lat = vect(0,0,1) cross WallN;
	Lat = Normal(Lat);

	bRun = hSwing;
	My = MoveY;
	Mx = MoveX;
	if (bRun && Abs(My) < 0.1 && Abs(Mx) < 0.1)
		My = 1;
	if (bRun)
	{
		Sp = WallRunSpeed;
		WallRunSpeed = FMax(13 * S, WallRunSpeed - 4 * S * h);
	}
	else
		Sp = 5 * S;
	Target = Lat * (Mx * Sp) + vect(0,0,1) * (My * Sp);
	K = FMin(1, 14 * h);
	V = Pawn.Velocity;
	V += (Target - V) * K;

	// stick to the wall
	if (Trace(HL, HN, Pawn.Location - WallN * (Pawn.CollisionRadius + 40), Pawn.Location, false) != None && Abs(HN.Z) < 0.5)
	{
		WallN = Flat(HN);
		Corr = ((HL + WallN * (Pawn.CollisionRadius + 2)) - Pawn.Location) dot WallN;
		V = V - WallN * (V dot WallN) + WallN * (Corr / FMax(h, 0.001) * 0.5);
	}
	else
	{
		// no wall at chest height: either the top (wall continues below) or a side edge
		Low = Pawn.Location - vect(0,0,1) * (Pawn.CollisionHeight * 0.8);
		if (Trace(HL, HN, Low - WallN * (Pawn.CollisionRadius + 40), Low, false) != None)
			ClimbOverTop(bRun);
		else
		{
			GoAir();
			WallCD = 0.3;
		}
		return;
	}

	// reached the ground while climbing down
	if (My < 0 && HeightAboveGround(8) <= 6)
	{
		MState = 'ground';
		Pawn.SetPhysics(PHYS_Walking);
		return;
	}
	if (VSize(V - WallN * (V dot WallN)) > 0.5 * S)
		WallFwd = Normal(V - WallN * (V dot WallN));
	else if (Abs(WallFwd dot WallN) > 0.5)
		WallFwd = vect(0,0,1);
	// the body stays upright on the wall (moving down must not flip it over)
	if (WallFwd.Z < 0)
		WallFwd.Z = -WallFwd.Z;
	Facing = -WallN;
	Pawn.Velocity = V;
	if (VSize(V) > 1)
		Pawn.Acceleration = Normal(V);
	else
		Pawn.Acceleration = vect(0,0,0);
}

//-----------------------------------------------------------------------------
// Physics (player.js physicsStep)

function PointZipStep(float h)
{
	local vector D, V;
	local float Dist, Sp;

	WebShoot = FMin(1, WebShoot + h * 7);
	if (WebShoot < 1)
	{
		Pawn.Velocity = vect(0,0,0);
		Pawn.Acceleration = vect(0,0,0);
		return;
	}
	D = ZipTo - Pawn.Location;
	Dist = VSize(D);
	Sp = 52 * S;
	if (Dist < Sp * h + 0.3 * S)
	{
		Pawn.SetLocation(ZipTo);
		Pawn.Velocity = vect(0,0,0);
		Spidey.ReleaseWebRope();
		if (LaunchBuffer > 0)
		{
			// timed point launch: stronger
			LaunchBuffer = 0;
			V = Flat(ZipDir) * (22 * S) + vect(0,0,1) * (22 * S);
			GoAir();
			Pawn.Velocity = V;
			FlipT = 0.65;
			Whoosh();
			AddComic("ZWIP!", ChestLoc(), 0.6, 255, 255, 255);
			AnimEvent('launch', true);
		}
		else if (bPerchWall && Abs(PerchN.Z) < 0.5)
		{
			// arrived at a wall face: cling to it (wall pose), facing the wall
			WallN = Flat(PerchN);
			WallRunSpeed = 13 * S;
			WallFwd = vect(0,0,1);
			WallCD = 0;
			Facing = -WallN;
			MeshX = WallFwd;
			MeshZ = WallN;
			MState = 'wall';
			Pawn.SetPhysics(PHYS_Flying);
			Pawn.Velocity = vect(0,0,0);
			ActAnim = '';
		}
		else
		{
			MState = 'perch';
			Pawn.SetPhysics(PHYS_Walking);
		}
		return;
	}
	V = D * (Sp / Dist);
	Pawn.Velocity = V;
	Pawn.Acceleration = Normal(V);
	Facing = Flat(ZipDir);
}

function PhysicsStep(float h)
{
	local vector V, Chest, Pivot, ToA, Steer, Next;
	local float MaxSp, TX, TY, Acc, DX, DY, DL, GMul, HS, Base, K, Sp, D, Free, Stretch, VR, MaxStretch, Lim;

	if (MState == 'pointZip')
	{
		PointZipStep(h);
		return;
	}
	if (MState == 'perch')
	{
		Pawn.Velocity = vect(0,0,0);
		Pawn.Acceleration = vect(0,0,0);
		return;
	}
	if (MState == 'wall')
	{
		WallStep(h);
		return;
	}

	V = Pawn.Velocity;
	if (MState == 'ground')
	{
		if (hSwing)
			MaxSp = 17 * S;
		else
			MaxSp = 7.5 * S;
		if (DownT > 0)
		{
			V.X *= Decay(0.85, h);
			V.Y *= Decay(0.85, h);
		}
		else if (!bAtkActive && DodgeT <= 0 && JumpCharge < 0)
		{
			TX = Wish.X * MaxSp * WishLen;
			TY = Wish.Y * MaxSp * WishLen;
			if (WishLen > 0.05)
				Acc = 45 * S * h;
			else
				Acc = 35 * S * h;
			DX = TX - V.X;
			DY = TY - V.Y;
			DL = Sqrt(DX * DX + DY * DY);
			if (DL <= Acc)
			{
				V.X = TX;
				V.Y = TY;
			}
			else
			{
				V.X += DX / DL * Acc;
				V.Y += DY / DL * Acc;
			}
		}
		else if (JumpCharge >= 0)
		{
			V.X *= Decay(0.9, h);
			V.Y *= Decay(0.9, h);
		}
		Pawn.GroundSpeed = FMax(Pawn.default.GroundSpeed, VSize2D(V) + 20);
		Pawn.Velocity = V;
		if (VSize2D(V) > 1)
			Pawn.Acceleration = Normal(V * vect(1,1,0));
		else
			Pawn.Acceleration = vect(0,0,0);
		return;
	}

	if (MState == 'air' || MState == 'zip')
	{
		GMul = 1;
		if (bDiving)
			GMul = 1.7;
		if (MState == 'zip')
			GMul = 0.15;
		if (bAtkActive && AtkTarget != None && Airborne(AtkTarget))
			GMul = 0.1;
		V.Z -= (GRAV * GMul * S - ENGINEGRAV) * h;
		if (MState == 'zip' && ZipT <= 0)
		{
			MState = 'air';
			if (bZipHasWeb)
				Spidey.ReleaseWebRope();
		}
		// air control
		HS = VSize2D(V);
		if (WishLen > 0.05 && !bAtkActive)
		{
			Base = FMax(HS, 9 * S);
			K = FMin(1, 1.6 * h) * WishLen;
			V.X += (Wish.X * Base - V.X) * K;
			V.Y += (Wish.Y * Base - V.Y) * K;
		}
		if (bDiving)
			V.Z = FMax(V.Z, -85 * S);
		else
			V.Z = FMax(V.Z, -55 * S);
	}
	else if (MState == 'swing')
	{
		V.Z -= (GRAV * S - ENGINEGRAV) * h;
		Chest = ChestLoc();
		Pivot = RopePivot();
		ToA = Normal(Pivot - Chest);
		// steering: force perpendicular to the rope
		Steer = Wish * (13 * S * WishLen);
		Steer -= ToA * (Steer dot ToA);
		V += Steer * h;
		// momentum pump while below the pivot
		if (Chest.Z < Pivot.Z)
		{
			Sp = VSize(V);
			if (Sp > 0.1)
				V += V * (7 * S * h / Sp);
		}
		if (RopeLen > RopeTarget)
			RopeLen = FMax(RopeTarget, RopeLen - 22 * S * h);

		// elastic rope: spring + damping past the free length, hard stop at the stretch limit
		UpdateRopeWrap();
		Pivot = RopePivot();
		Free = FMax(1.5 * S, RopeLen - WrappedLen());
		RopeFree = Free;
		ToA = Pivot - Chest;
		D = VSize(ToA);
		MaxStretch = Free * 0.05 + 0.4 * S;
		if (D > Free)
		{
			ToA = ToA / D;
			Stretch = D - Free;
			VR = V dot ToA;
			V += ToA * ((Stretch * 140 - FMin(0, VR) * 9) * h);
			if (Stretch > MaxStretch)
			{
				Pawn.Move(ToA * (Stretch - MaxStretch));
				if (VR < 0)
					V += ToA * (-VR);
			}
		}
		// one physics step per frame here: don't let this frame's move overshoot the rope
		Chest = ChestLoc();
		Next = Chest + V * h - vect(0,0,1) * (ENGINEGRAV * h * h);
		Lim = Free + MaxStretch;
		D = VSize(Next - Pivot);
		if (D > Lim)
		{
			Next = Pivot + (Next - Pivot) * (Lim / D);
			V = (Next - Chest) / h + vect(0,0,1) * (ENGINEGRAV * h);
		}
	}

	Sp = VSize(V);
	if (Sp > MAXSPEED * S)
		V = V * (MAXSPEED * S / Sp);
	Pawn.Velocity = V;
	Pawn.Acceleration = vect(0,0,0);
}

function DoLanded(float PrevVZ)
{
	local float HS;
	local VillainPawn E;
	local vector Dir;

	if (MState == 'swing')
	{
		Spidey.ReleaseWebRope();
		EndSwingPoint();
	}
	Wraps.Length = 0;
	HS = VSize2D(Pawn.Velocity);
	AnimEvent('land', PrevVZ < -14 * S, HS > 9 * S, bDiving && PrevVZ < -30 * S);
	if (PrevVZ < -22 * S)
	{
		LandT = 0.3;
		Shake(FMin(0.5, -PrevVZ / S * 0.008));
		Whoosh();
		if (bDiving && PrevVZ < -50 * S)
		{
			// dive landing shockwave
			foreach DynamicActors(class'VillainPawn', E)
			{
				if (Alive(E) && VSize(E.Location - Pawn.Location) < 6 * S)
				{
					Dir = Flat(E.Location - Pawn.Location);
					E.TakeDamage(Max(1, int(15.0 / 40.0 * E.default.Health)), Pawn, E.Location, (Dir * (5 * S) + vect(0,0,10) * S) * E.Mass, class'DamageKickChin');
				}
			}
		}
	}
	MState = 'ground';
	bDiving = false;
	FlipT = 0;
	if (Pawn.Physics != PHYS_Walking)
		Pawn.SetPhysics(PHYS_Walking);
}

function HandleHitWall(vector N, Actor Wall)
{
	local vector Top;
	local float Into;

	if (MState == 'pointZip')
	{
		GoAir();
		Pawn.Velocity = vect(0,0,0);
		Spidey.ReleaseWebRope();
		return;
	}
	if (MState == 'wall')
	{
		if (N.Z > 0.7)
		{
			MState = 'ground';
			Pawn.SetPhysics(PHYS_Walking);
		}
		return;
	}
	if (Abs(N.Z) > 0.5)
		return;
	if (MState == 'ground')
	{
		Into = -(Wish dot Flat(N));
		if (Into > 0.5 && !bAtkActive && FindLedgeTop(N, 1.7 * S, Top))
			HopOnto(Top, N);
		else if (Into > 0.5 && hSwing && !bAtkActive)
			TryWall(N);
		return;
	}
	if (MState == 'air' || MState == 'swing' || MState == 'zip')
		TryWall(N);
}

//-----------------------------------------------------------------------------
// Camera (camera.js)

function CamAxes()
{
	local float CY, SY, CP, SP;

	CY = Cos(CamYaw);
	SY = Sin(CamYaw);
	CP = Cos(CamPitch);
	SP = Sin(CamPitch);
	CamFwd.X = CY * CP; CamFwd.Y = SY * CP; CamFwd.Z = SP;
	CamFlatFwd.X = CY; CamFlatFwd.Y = SY; CamFlatFwd.Z = 0;
	CamRight.X = -SY; CamRight.Y = CY; CamRight.Z = 0;
}

function UpdateCamera(float dt)
{
	local vector V, Goal, Pivot, Back, HL, HN;
	local float HS, Want, D, Follow, Speed, FovWant, HalfV;
	local bool bLookActive, bTraversing;

	CamYaw += LookX;
	CamPitch = FClamp(CamPitch + LookY, -1.3, 1.0);
	bLookActive = Abs(LookX) + Abs(LookY) > 0.0005;
	LookX = 0;
	LookY = 0;
	if (bLookActive)
		CamIdleT = 0;
	else
		CamIdleT += dt;

	V = Pawn.Velocity;
	HS = VSize2D(V);
	bTraversing = MState == 'swing' || MState == 'air' || MState == 'zip' || MState == 'pointZip' || (MState == 'ground' && HS > 12 * S);
	if (class'MSMSettings'.default.bAutoCamera && CamIdleT > 0.9 && HS > 9 * S && bTraversing && !bInCombat)
	{
		Want = Atan(V.Y, V.X);
		D = Want - CamYaw;
		D = Atan(Sin(D), Cos(D));
		CamYaw += D * FMin(1, dt * 1.6);
		CamPitch += (-0.18 - CamPitch) * FMin(1, dt * 1.0);
	}
	CamAxes();

	// target: Spidey's shoulder
	Speed = VSize(V);
	Goal = Feet() + vect(0,0,1) * (1.55 * S);
	if (!bCamInit)
	{
		CamTarget = Goal;
		bCamInit = true;
	}
	if (Speed > 20 * S)
		Follow = 1 - Exp(-dt * 10);
	else
		Follow = 1 - Exp(-dt * 16);
	CamTarget += (Goal - CamTarget) * Follow;

	Want = 3.6 * S;
	if (MState == 'swing' || MState == 'air' || MState == 'zip')
		Want = (4.3 + FMin(1.8, Speed / S * 0.03)) * S;
	if (bInCombat)
		Want = 4.8 * S;
	if (MState == 'wall')
		Want = 4.4 * S;
	Want *= FClamp(class'MSMSettings'.default.CamDistance, 0.4, 2.0);
	CamDist += (Want - CamDist) * FMin(1, dt * 3);

	Pivot = CamTarget + CamRight * (0.45 * S);
	Back = -CamFwd;
	D = CamDist;
	if (Trace(HL, HN, Pivot + Back * (D + 0.4 * S), Pivot, false) != None)
		D = FMax(0.7 * S, VSize(HL - Pivot) - 0.4 * S);
	CamLoc = Pivot + Back * D;

	if (CamShake > 0.05)
	{
		CamLoc.X += (FRand() - 0.5) * CamShake;
		CamLoc.Y += (FRand() - 0.5) * CamShake;
		CamLoc.Z += (FRand() - 0.5) * CamShake;
		CamShake *= Exp(-dt * 12);
	}
	CamRot = rotator((Pivot + CamFwd * (2 * S)) - CamLoc);

	// vertical FOV from the reference, converted to the engine's horizontal FOV
	FovWant = FClamp(class'MSMSettings'.default.FOV, 40, 100) + FClamp((Speed / S - 12) * 0.4, 0, 15);
	CamFOV += (FovWant - CamFOV) * FMin(1, dt * 3);
	HalfV = CamFOV * 0.5 * 3.14159265 / 180;
	FovAngle = 2 * Atan(Sin(HalfV) / Cos(HalfV) * ScreenAspect, 1) * 180 / 3.14159265;
	DesiredFOV = FovAngle;
}

event PlayerCalcView(out Actor ViewActor, out vector CameraLocation, out rotator CameraRotation)
{
	if (bMSMActive && Pawn != None && InControl() && ViewTarget == Pawn && !bInterpolating)
	{
		UpdateCamera(FMin(CamDT, 0.1));
		CamDT = 0;
		CalcViewDeltaTime = 0;
		if (ActiveCamera != None)
			ViewActor = ActiveCamera;
		else
			ViewActor = Pawn;
		CameraLocation = CamLoc;
		CameraRotation = CamRot;
		ViewLocR = CameraLocation;
		ViewRotR = CameraRotation;
		return;
	}
	Super.PlayerCalcView(ViewActor, CameraLocation, CameraRotation);
	ViewLocR = CameraLocation;
	ViewRotR = CameraRotation;
}

//-----------------------------------------------------------------------------
// Animation (spideyAnim.js) using the stock Spidey animations

function LoopA(name A, float Rate, float Tween)
{
	if (A == CurAnim && Abs(Rate - CurRate) < 0.15)
		return;
	if (!Spidey.HasAnim(A))
		return;
	Spidey.ForceLoopBaseAnim(A, Rate, Tween);
	CurAnim = A;
	CurRate = Rate;
}

function Act(name A, float Rate, float Until, name Kind, bool bAir)
{
	local float Len;

	if (!Spidey.HasAnim(A))
		return;
	Len = Spidey.AnimGetLength(A, 1.0);
	if (Len <= 0)
		Len = 0.5;
	ActAnim = A;
	ActKind = Kind;
	ActEnd = Level.TimeSeconds + Len / Rate * Until;
	bActAir = bAir;
	Spidey.ForcePlayBaseAnim(A, Rate, 0.1);
	CurAnim = A;
	CurRate = Rate;
}

function AnimEvent(name E, optional bool A, optional bool B, optional bool C)
{
	switch (E)
	{
		case 'jump':
			// A = charged, B = in combat
			if (B) Act('JumpStandingMid', 1.0, 1, E, true);
			else if (A) Act('JumpUp', 1.25, 1, E, true);
			else Act('JumpRunningMid', 1.5, 0.6, E, true);
			break;
		case 'land':
			// A = hard, B = fast, C = dive
			if (C) Act('RollForwards', 1.25, 1, E, false);
			else if (B) Act('FromFallToRun', 1.2, 1, E, false);
			else if (A) Act('JumpStandingLand', 1.3, 1, E, false);
			else ActAnim = '';
			break;
		case 'swingStart':
			if (bSwingRight) Act('SwingRightHand', 2.2, 0.55, E, true);
			else Act('SwingLeftHand', 2.2, 0.55, E, true);
			break;
		case 'swingJump':
			bFlipToggle = !bFlipToggle;
			Act('JumpRunningMid', 1.7, 0.8, E, true);
			break;
		case 'swingRelease': Act('JumpRunningMid', 1.3, 0.9, E, true); break;
		case 'dive': Act('Fall', 1.6, 1, E, true); break;
		case 'wallJump':
			if (A) Act('JumpRunningMid', 1.5, 0.8, E, true);
			else Act('WallCrawlJump', 1.2, 1, E, true);
			break;
		case 'wallTop':
			if (A) Act('JumpRunningMid', 1.8, 0.75, E, true);
			else Act('PullUp', 1.5, 1, E, false);
			break;
		case 'wallRunStop': Act('IdleWall', 1.2, 1, E, false); break;
		case 'zip':
			if (A) Act('WebZipStraightPart1', 1.8, 0.7, E, true);
			else Act('WebZipFromFallPart1', 1.8, 0.7, E, true);
			break;
		case 'pointZip':
			if (A) Act('WebZipStraightPart1', 1.6, 0.85, E, true);
			else Act('WebZipFromFallPart1', 1.6, 0.85, E, true);
			break;
		case 'launch':
			if (A) Act('JumpUp', 1.3, 1, E, true);
			else Act('JumpRunningMid', 1.8, 0.5, E, true);
			break;
		case 'dodge': Act('RollForwards', 1.7, 1, E, false); break;
		case 'webShot':
			if (!bAtkActive)
			{
				if (A) Act('WebZipFromFallPart1', 2, 0.32, E, true);
				else Act('WebShootStraightPart1', 2, 0.6, E, false);
			}
			break;
		case 'hurt':
			// A = in air, B = knocked down
			if (A) Act('HitInAir', 1.3, 0.5, E, true);
			else if (B) Act('DieBackwards', 1.0, 0.6, E, false);
			else Act('HitFromFront', 1.3, 1, E, false);
			break;
		case 'getup': Act('StandupButtFlip', 1.1, 1, E, false); break;
	}
}

function Animate(float dt)
{
	local vector V, X, Z, Y, Up, Fwd, X2, Z2;
	local float HS, K, Want, A, CA, SA;
	local bool bEnd;

	if (bTour)
	{
		TourTick(dt);
		return;
	}

	V = Pawn.Velocity;
	HS = VSize2D(V);

	// facing (vertical axis only)
	if (MState == 'ground' && !bAtkActive && HS > 0.6 * S && DodgeT <= 0 && DownT <= 0)
		Facing = Flat(V);
	if ((MState == 'air' || MState == 'zip' || MState == 'swing') && !bAtkActive && HS > 2 * S)
		Facing = Flat(V);

	// attack clip starts once the lunge is over
	if (bAtkActive && !bLunge && !bAtkAnimStarted)
	{
		bAtkAnimStarted = true;
		Act(AtkAnim, AtkRate, 1, 'attack', MState != 'ground');
	}
	if (bAtkActive && bLunge)
	{
		ActAnim = '';
		LoopA('AttackJumpL_01', 0.6, 0.08);
	}

	// end or cancel the one-shot action
	if (ActAnim != '')
	{
		bEnd = Level.TimeSeconds >= ActEnd;
		if (ActKind == 'attack' && !bAtkActive && WishLen * WishLen > 0.09) bEnd = true;
		if (bActAir && MState == 'ground' && ActKind != 'attack') bEnd = true;
		if (!bActAir && MState != 'ground' && MState != 'perch' && ActKind != 'hurt' && ActKind != 'attack') bEnd = true;
		if (MState == 'swing' && ActKind != 'swingStart') bEnd = true;
		if (MState == 'wall' && ActKind != 'wallRunStop') bEnd = true;
		if (ActKind == 'hurt' && DownT > 0) bEnd = false;
		if (bEnd)
			ActAnim = '';
	}

	if (ActAnim == '' && !bLunge)
		Locomotion(dt, HS);
	if (DownT > 0 && DownT < 0.85 && ActKind != 'getup')
		AnimEvent('getup');
	if (MState == 'ground' && HS < 0.5 * S && ActAnim == '' && !bAtkActive)
		IdleT += dt;
	else
		IdleT = 0;

	// mesh orientation
	Up = vect(0,0,1);
	if (MState == 'wall' && !bActAir)
	{
		Z = WallN;
		X = WallFwd;
	}
	else if (MState == 'swing')
	{
		Z = Normal(Normal(RopePivot() - ChestLoc()) * 0.75 + Up * 0.25);
		Fwd = V - Z * (V dot Z);
		if (VSize(Fwd) < 0.1 * S)
			Fwd = Facing;
		X = Normal(Fwd);
	}
	else
	{
		Z = Up;
		X = Facing;
	}
	if (MState == 'wall')
		K = 12;
	else if (MState == 'swing')
		K = 8;
	else
		K = 14;
	A = 1 - Exp(-dt * K);
	// leaving a wall can leave the body inverted: on the ground snap it back upright
	if (MState != 'wall' && MeshZ dot Up < 0.2)
	{
		MeshZ = Up;
		MeshX = Facing;
	}
	MeshX = Normal(MeshX + (X - MeshX) * A);
	MeshZ = Normal(MeshZ + (Z - MeshZ) * A);
	Y = Normal(MeshZ cross MeshX);
	X = Normal(Y cross MeshZ);
	Z = MeshZ;

	// body pitch: flips, dive, zip
	Want = 0;
	if (FlipT > 0)
		Want = (1 - FlipT / 0.65) * 2 * 3.14159265;
	else if (bDiving)
		Want = 1.35;
	else if (MState == 'zip')
		Want = 0.8;
	else if (MState == 'pointZip' && WebShoot >= 1)
		Want = FClamp(Atan(-ZipDir.Z, Sqrt(FMax(0, 1 - ZipDir.Z * ZipDir.Z))) + 0.7, -0.6, 0.9);
	else if (MState == 'air' && HS > 20 * S)
		Want = 0.5;
	if (FlipT > 0)
		BodyPitch = Want;
	else
		BodyPitch += (Want - BodyPitch) * FMin(1, dt * 8);
	CA = Cos(BodyPitch);
	SA = Sin(BodyPitch);
	X2 = X * CA - Z * SA;
	Z2 = Z * CA + X * SA;
	MeshRot = OrthoRotation(X2, Y, Z2);

	// controller faces where Spidey faces (used by stock code for ViewX/ViewY)
	ViewX = Facing;
	ViewZ = Up;
	ViewY = Normal(ViewZ cross ViewX);
	SetRotation(rotator(Facing));
}

function Locomotion(float dt, float HS)
{
	local float Rate;

	switch (MState)
	{
		case 'ground':
			if (DownT > 0)
				break;
			if (JumpCharge >= 0)
				LoopA('Perch', 1, 0.1);
			else if (HS < 0.5 * S)
			{
				if (IdleT > 7)
				{
					IdleT = 0;
					Act('Fidget1', 1, 0.98, 'fidget', false);
				}
				else if (bInCombat)
					LoopA('IdleCombat', 1, 0.2);
				else
					LoopA('IdleRest', 1, 0.2);
			}
			else if (HS < 3.6 * S)
				LoopA('Walk', FClamp(HS / 160, 0.5, 1.8), 0.2);
			else
			{
				Rate = FClamp(HS / 600, 0.9, 2.3);
				LoopA('RunForwards', Rate, 0.18);
			}
			break;
		case 'air':
			if (bDiving)
				LoopA('Fall', 1, 0.25);
			else
				LoopA('Fall', 1, 0.3);
			break;
		case 'zip':
			LoopA('WebZipFromFallPart1', 1.5, 0.1);
			break;
		case 'swing':
			LoopA('TarzanAll', 1, 0.35);
			break;
		case 'wall':
			if (bWallRunning && Pawn.Velocity.Z > 4 * S)
				LoopA('WallCrawl', FClamp(VSize(Pawn.Velocity) / 300, 0.9, 2.2), 0.15);
			else if (VSize(Pawn.Velocity) > S)
				LoopA('WallCrawl', FClamp(VSize(Pawn.Velocity) / 120, 0.6, 2.5), 0.15);
			else
				LoopA('IdleWall', 1, 0.15);
			break;
		case 'pointZip':
			LoopA('WebZipStraightPart2', 1.4, 0.12);
			break;
		case 'perch':
			LoopA('Perch', 1, 0.15);
			break;
	}
}

//-----------------------------------------------------------------------------
// Dynamic reflections (see _mod/loader/msm_reflect.cpp).
// Upper half of the 1024x1024 atlas: 6 cube faces of 256x256 around the camera,
// laid out for the D3D cube convention with D3D (X,Y,Z) = Unreal (Y,Z,X); the
// loader binds that cube with a matching texture matrix.
// Lower half: the wall in view as a mirror. The scene is rendered from the
// camera reflected through the wall plane; the loader projects that image onto
// the reflective surfaces lying in the plane, so they show the real mirror image
// (Spider-Man included, at the right distance and the right way up).

function rotator ReflFaceRotation(int i)
{
	local vector X, Y, Z;

	// X = view direction, Y = image right, Z = image up
	switch (i)
	{
		case 0: X = vect(0,1,0); Y = vect(-1,0,0); Z = vect(0,0,1); break;  // D3D +X
		case 1: X = vect(0,-1,0); Y = vect(1,0,0); Z = vect(0,0,1); break;  // D3D -X
		case 2: X = vect(0,0,1); Y = vect(0,1,0); Z = vect(-1,0,0); break;  // D3D +Y
		case 3: X = vect(0,0,-1); Y = vect(0,1,0); Z = vect(1,0,0); break;  // D3D -Y
		case 4: X = vect(1,0,0); Y = vect(0,1,0); Z = vect(0,0,1); break;   // D3D +Z
		default: X = vect(-1,0,0); Y = vect(0,-1,0); Z = vect(0,0,1); break; // D3D -Z
	}
	return OrthoRotation(X, Y, Z);
}

// Pick the wall the camera looks at (keeps the previous plane while it is still in view).
function bool FindReflPlane(vector Loc, rotator Rot)
{
	local vector HL, HN, BestN, BestP;
	local float Score, BestScore;
	local int i, Off;
	local rotator R;
	local bool bFound;
	local Actor A;
	local string Dbg;

	R = Rot;
	R.Pitch = Clamp(((R.Pitch + 32768) & 65535) - 32768, -3000, 3000);
	BestScore = 1000000;
	for (i = 0; i < 5; i++)
	{
		Off = ((i + 1) / 2) * 4500;
		if ((i & 1) == 0)
			Off = -Off;
		R.Yaw = Rot.Yaw + Off;
		// actors too: walls are static meshes; skip people
		A = Pawn.Trace(HL, HN, Loc + vector(R) * (150 * S), Loc, true);
		if (i == 0)
			Dbg = "fwd hit=" $ A $ " n=" $ HN $ " d=" $ int(VSize(HL - Loc));
		if (A == None || Pawn(A) != None || Abs(HN.Z) > 0.25)
			continue;
		HN.Z = 0;
		HN = Normal(HN);
		if ((Loc - HL) dot HN < 0.3 * S)
			continue;
		Score = VSize(HL - Loc) * (1 + 0.6 * Abs(Off) / 4500.0);
		if (Score < BestScore)
		{
			BestScore = Score;
			BestN = HN;
			BestP = HL;
			bFound = true;
		}
	}
	// the nearest wall wins; while it stays the same wall keep the old values (no jitter)
	if (bFound && !(bReflPlane && (BestN dot ReflN) > 0.97 && Abs((BestP - ReflP) dot ReflN) < 40))
	{
		ReflN = BestN;
		ReflP = BestP;
	}
	bReflPlane = bFound;
	if (bMSMDebug && Level.TimeSeconds - ReflDbgT > 1)
	{
		ReflDbgT = Level.TimeSeconds;
		Log("MSMREFL " $ Dbg $ " found=" $ bFound $ " N=" $ ReflN $ " P=" $ ReflP $ " cam=" $ Loc);
	}
	return bFound;
}

simulated event RenderTexture(ScriptedTexture Tex)
{
	local int k, N;
	local vector Loc, X, Y, Z, VLoc;
	local float D, TanH, F, Margin, W, H;
	local bool bWasHidden;

	if (Pawn == None || (Tex != ReflTex && Tex != MirrorTex))
		return;
	Loc = ViewLocR;
	if (VSize(Loc) < 1)
		Loc = Pawn.Location;
	if (Tex == ReflTex)
	{
		// the cube is shot from the camera, right behind Spider-Man: leave him out
		// (he shows up in the mirror view below, where he belongs)
		bWasHidden = Pawn.bHidden;
		Pawn.bHidden = true;
		N = Clamp(ReflFacesPerFrame, 1, 6);
		for (k = 0; k < N; k++)
		{
			Tex.DrawPortal((ReflFace % 4) * 512, (ReflFace / 4) * 512, 512, 512, Pawn, Loc, ReflFaceRotation(ReflFace), 90, true);
			ReflFace = (ReflFace + 1) % 6;
		}
		Pawn.bHidden = bWasHidden;
		return;
	}

	if (!bPlanarReflections || !class'MSMSettings'.default.bMirror || ReflCam == None || !FindReflPlane(Loc, ViewRotR))
		return;
	D = (Loc - ReflP) dot ReflN;
	VLoc = Loc - 2 * D * ReflN;
	GetAxes(ViewRotR, X, Y, Z);
	X = X - 2 * (X dot ReflN) * ReflN;
	Z = Z - 2 * (Z dot ReflN) * ReflN;
	Y = Z cross X;
	ReflCam.SetLocation(VLoc);
	// same pixel density as the screen, with a small margin around it
	W = FMax(320, ScreenW);
	H = FMax(240, ScreenH);
	Margin = FMin(1.06, FMin(2048 / W, 2048 / H));
	W = int(W * Margin);
	H = int(H * Margin);
	TanH = Tan(FovAngle * 0.5 * 3.14159265 / 180);
	F = 2 * Atan(TanH * Margin, 1) * 180 / 3.14159265;
	Tex.DrawPortal(0, 0, W, H, ReflCam, VLoc, OrthoRotation(X, Y, Z), int(F + 0.5), true);
}

function bool ReflectionsOn()
{
	return bDynamicReflections && class'MSMSettings'.default.bReflections;
}

// MSMPageSettings saved new values (they are read from MSMSettings every frame)
function SettingsChanged()
{
	if (!class'MSMSettings'.default.bMirror)
		bReflPlane = false;
}

// Swap Spider-Man's skeletal mesh at runtime: MSMMesh MSMSuit.RaimiSuit
// The new mesh uses the stock skeleton, so the stock animation set is linked to it. Textures named
// <Package>.Raimi_m07 .. Raimi_m20 are applied as skins 0..13 (the PSK materials in import order).
exec function MSMMesh(string MeshName)
{
	local Mesh M;
	local MeshAnimation A;
	local Material Mt;
	local string Pkg, N;
	local int i, P;

	if (Pawn == None)
		return;
	M = Mesh(DynamicLoadObject(MeshName, class'Mesh', true));
	if (M == None)
	{
		Log("MSMMESH not found: " $ MeshName);
		return;
	}
	A = MeshAnimation(DynamicLoadObject("SpideyAnimations.SpideyAnim", class'MeshAnimation', true));
	Pawn.LinkMesh(M, false);
	if (A != None)
		Pawn.LinkSkelAnim(A, M);
	P = InStr(MeshName, ".");
	if (P > 0)
	{
		Pkg = Left(MeshName, P);
		if (Left(Pkg, 7) ~= "MSMSuit")
			Pkg = "MSMSuit";
		for (i = 0; i < 14; i++)
		{
			N = string(i + 7);
			if (i + 7 < 10)
				N = "0" $ N;
			Mt = Material(DynamicLoadObject(Pkg $ ".Raimi_m" $ N, class'Material', true));
			if (Mt != None)
				Pawn.Skins[i] = Mt;
		}
	}
	CurAnim = '';
	ActAnim = '';
	Log("MSMMESH linked " $ M $ " anim=" $ A $ " hasIdle=" $ Pawn.HasAnim('IdleRest') $ " hasRun=" $ Pawn.HasAnim('RunFast') $ " len=" $ Spidey.AnimGetLength('IdleRest', 1.0));
	Pawn.LoopAnim('IdleRest');
}

// Cycle through the stock animation names and screenshot each one: MSMTour
exec function MSMTour()
{
	bTour = !bTour;
	TourIdx = -1;
	TourT = 0;
	bTourShot = false;
	Log("MSMTOUR " $ bTour);
}

function TourTick(float dt)
{
	local name N;

	TourT -= dt;
	if (TourT > 0)
		return;
	if (bTourShot)
	{
		ConsoleCommand("SHOT");
		bTourShot = false;
		TourT = 0.5;
		return;
	}
	TourIdx++;
	switch (TourIdx / 2)
	{
		case 0: N = 'IdleRest'; break;
		case 1: N = 'Fidget1'; break;
		case 2: N = 'RunForwards'; break;
		case 3: N = 'Walk'; break;
		case 4: N = 'IdleCombat'; break;
		case 5: N = 'JumpRunningMid'; break;
		case 6: N = 'JumpStandingMid'; break;
		case 7: N = 'Fall'; break;
		case 8: N = 'SwingLeftHand'; break;
		case 9: N = 'TarzanAll'; break;
		case 10: N = 'WallCrawl'; break;
		case 11: N = 'IdleWall'; break;
		case 12: N = 'Perch'; break;
		case 13: N = 'HitFromFront'; break;
		case 14: N = 'RollForwards'; break;
		case 15: N = 'WebZipStraightPart1'; break;
		default:
			bTour = false;
			Log("MSMTOUR done");
			return;
	}
	Spidey.ForceLoopBaseAnim(N, 1.0, 0.0);
	CurAnim = N;
	if (TourIdx % 2 == 1)
		Pawn.LODBias = -20;
	else
		Pawn.LODBias = 1;
	Log("MSMTOUR " $ TourIdx $ " " $ N $ " has=" $ Spidey.HasAnim(N));
	bTourShot = true;
	TourT = 1.2;
}

// In-game screenshot (no window focus needed): MSMShot
exec function MSMShot()
{
	ConsoleCommand("SHOT");
	Log("MSMSHOT requested");
}

// Diagnostics for the mesh swap (F-key binds in User.ini)
exec function MSMMeshInfo()
{
	local int i;

	if (Pawn == None)
		return;
	Log("MSMINFO mesh=" $ Pawn.Mesh $ " hidden=" $ Pawn.bHidden $ " drawtype=" $ Pawn.DrawType
		$ " scale=" $ Pawn.DrawScale $ " scale3d=" $ Pawn.DrawScale3D $ " lodbias=" $ Pawn.LODBias
		$ " loc=" $ Pawn.Location $ " rot=" $ Pawn.Rotation);
	for (i = 0; i < 14; i++)
		Log("MSMINFO skin[" $ i $ "]=" $ Pawn.Skins[i]);
}

// Spawn a separate mesh actor in front of the player (tests the mesh itself, not the pawn swap)
exec function MSMSpawnMesh(string MeshName)
{
	local Mesh M;
	local Actor A;
	local Material Mt;
	local MeshAnimation An;
	local vector Loc;

	if (Pawn == None)
		return;
	M = Mesh(DynamicLoadObject(MeshName, class'Mesh', true));
	if (M == None)
	{
		Log("MSMSPAWN mesh not found " $ MeshName);
		return;
	}
	Loc = Pawn.Location + vector(Pawn.Rotation) * 120 + vect(0, 0, 10);
	A = Spawn(class'MSMAnchor', None, '', Loc);
	if (A == None)
	{
		Log("MSMSPAWN spawn failed");
		return;
	}
	A.bHidden = false;
	A.SetDrawType(DT_Mesh);
	A.LinkMesh(M);
	An = MeshAnimation(DynamicLoadObject("SpideyAnimations.SpideyAnim", class'MeshAnimation', true));
	if (An != None)
		A.LinkSkelAnim(An, M);
	A.LoopAnim('IdleRest');
	Mt = Material(DynamicLoadObject("MSMSuit.Raimi_m10", class'Material', true));
	if (Mt != None)
		A.Skins[0] = Mt;
	Log("MSMSPAWN " $ A $ " mesh=" $ A.Mesh $ " at " $ A.Location $ " draw=" $ A.DrawType);
}

exec function MSMSkinsOff()
{
	local int i;

	if (Pawn == None)
		return;
	for (i = 0; i < 14; i++)
		Pawn.Skins[i] = None;
	Log("MSMSKINS cleared");
}

exec function MSMLod(float F)
{
	if (Pawn != None)
	{
		Pawn.LODBias = F;
		Log("MSMLOD " $ F);
	}
}

exec function MSMScale(float F)
{
	if (Pawn != None)
	{
		Pawn.SetDrawScale(F);
		Log("MSMSCALE " $ F);
	}
}

// Log world positions of a few bones (retarget verification)
exec function MSMBones()
{
	local int i;
	local string N[12], S;
	local coords C;

	if (Pawn == None)
		return;
	N[0] = "Spiderman_Body:RootParent";
	N[1] = "Spiderman_body:head";
	N[2] = "Spiderman_Body:R_hand";
	N[3] = "Spiderman_Body:L_hand";
	N[4] = "Spiderman_Body:R_ankle";
	N[5] = "Spiderman_Body:L_ankle";
	N[6] = "Spiderman_Body:R_upper_arm";
	N[7] = "Spiderman_Body:L_upper_arm";
	N[8] = "Spiderman_Body:R_lower_leg";
	N[9] = "Spiderman_Body:L_lower_leg";
	N[10] = "Spiderman_Body:spine_04";
	N[11] = "Spiderman_Body:neck";
	for (i = 0; i < 12; i++)
	{
		S = N[i];
		SetPropertyText("TmpBone", S);
		C = Pawn.GetBoneCoords(TmpBone);
		Log("MSMBONE " $ N[i] $ " " $ C.Origin - Pawn.Location);
	}
}

exec function MSMShowAtlas()
{
	bShowReflAtlas = !bShowReflAtlas;
}

exec function MSMReflections(bool bOn)
{
	bDynamicReflections = bOn;
	SaveConfig();
	ClientMessage("Dynamic reflections " $ bOn $ " (restart the level to apply)");
}

//-----------------------------------------------------------------------------
// Extra commands

// Old context action (pick up / use / pull) for mission objects: R
exec function MSMUse()
{
	// swing points are handled by Shift (MSM swing); the stock swing would take over the controls
	if (Target != None && FireAction != 'None' && FireAction != 'attack' && FireAction != 'swing')
		StockAction(FireAction);
}

exec function MSMInfo()
{
	ClientMessage("MSM state=" $ MState $ " phys=" $ Pawn.Physics $ " vel=" $ int(VSize(Pawn.Velocity) / S) $ "m/s focus=" $ Focus
		$ " combat=" $ bInCombat $ " perch=" $ bHasPerch $ " anim=" $ CurAnim);
}

exec function MSMAnim(name A)
{
	if (Spidey != None)
	{
		ClientMessage("anim " $ A $ " has=" $ Spidey.HasAnim(A) $ " len=" $ Spidey.AnimGetLength(A, 1.0));
		Spidey.ForceLoopBaseAnim(A, 1, 0.1);
		CurAnim = A;
		ActAnim = A;
		ActEnd = Level.TimeSeconds + 5;
		ActKind = 'debug';
	}
}

//-----------------------------------------------------------------------------
// The stock walking state hosts all of the above

state PlayerWalking
{
	event BeginState()
	{
		Super.BeginState();
		EnterMSM();
	}

	event EndState()
	{
		LeaveMSM();
		Super.EndState();
	}

	function PlayerMove(float DeltaTime)
	{
		if (IsMenuLevel())
			Super.PlayerMove(DeltaTime);
		else if (InControl())
			MSMUpdate(DeltaTime);
	}

	function UpdateRotation(float DeltaTime, float maxPitch)
	{
		if (!bMSMActive)
			Super.UpdateRotation(DeltaTime, maxPitch);
	}

	function ProcessMove(float DeltaTime, vector NewAccel, EDoubleClickDir DoubleClickMove, rotator DeltaRot)
	{
		if (!bMSMActive)
			Super.ProcessMove(DeltaTime, NewAccel, DoubleClickMove, DeltaRot);
	}

	function bool DoJump(bool bUpdating)
	{
		if (!bMSMActive)
			return Super.DoJump(bUpdating);
		return false;
	}

	event bool NotifyLanded(vector HitNormal)
	{
		if (!bMSMActive)
			return Super.NotifyLanded(HitNormal);
		if (MState == 'air' || MState == 'swing' || MState == 'zip')
			DoLanded(Pawn.Velocity.Z);
		return false;
	}

	event bool NotifyHitWall(vector HitNormal, Actor Wall)
	{
		if (!bMSMActive)
			return Super.NotifyHitWall(HitNormal, Wall);
		HandleHitWall(HitNormal, Wall);
		return true;
	}

	event bool NotifyBump(Actor Other)
	{
		return false;
	}

	event ClimbOntoLedge()
	{
	}

	exec function Look()
	{
	}

	exec function Block()
	{
	}

	exec function Fire(optional float F)
	{
		if (!bMSMActive)
			Super.Fire(F);
	}

	// Space also sends the stock Jump (needed to leave stock states); ignore it here
	exec function Jump(optional float F)
	{
		if (!bMSMActive)
			Super.Jump(F);
	}

	exec function AltFire(optional float F)
	{
		if (!bMSMActive)
			Super.AltFire(F);
	}
}

defaultproperties
{
	LookSensitivity=1.0
	bMSMDebug=true
	bDynamicReflections=true
	ReflFacesPerFrame=6
	bPlanarReflections=true
	bAlwaysMouseLook=true
}
