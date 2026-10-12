// Spidey for the MSM controller. Keeps the stock mesh, animations, health and
// sounds, but lets MSMSpideyController own damage reactions, attack timing and
// the mesh orientation.
class MSMSpideyPawn extends SpideyPawn;

event PostBeginPlay()
{
	Super.PostBeginPlay();
	// Level scripts look for the player by tag.
	Tag = 'SpideyPawn';
}

simulated function Tick(float DeltaTime)
{
	local MSMSpideyController C;

	Super.Tick(DeltaTime);
	C = MSMSpideyController(Controller);
	if (C != None && C.bMSMActive)
		SetRotation(C.MeshRot);
}

function TakeDamage(int Damage, Pawn instigatedBy, vector HitLocation, vector Momentum, class<DamageType> DamageType)
{
	local MSMSpideyController C;

	C = MSMSpideyController(Controller);
	if (C != None && C.bMSMActive && Damage > 0)
	{
		if (!C.CanTakeHit())
			return;
		Super.TakeDamage(Damage, instigatedBy, HitLocation, vect(0,0,0), DamageType);
		C.OnHurt(Damage, instigatedBy);
		return;
	}
	Super.TakeDamage(Damage, instigatedBy, HitLocation, Momentum, DamageType);
}

// Animation notifies from the stock attack animations: hits are timed by the
// controller instead.
function NotifyAttack()
{
	if (MSMSpideyController(Controller) == None || !MSMSpideyController(Controller).bMSMActive)
		Super.NotifyAttack();
}

function NotifyCombatMoveStart()
{
	if (MSMSpideyController(Controller) == None || !MSMSpideyController(Controller).bMSMActive)
		Super.NotifyCombatMoveStart();
}

function NotifyCombatMoveStop()
{
	if (MSMSpideyController(Controller) == None || !MSMSpideyController(Controller).bMSMActive)
		Super.NotifyCombatMoveStop();
}

// helpers for MSMPageSettings (the enums live in the Actor classes)
static function SetShadowType(WebheadPawn P, int Type)
{
	if (Type <= 0)
		P.ShadowType = SH_None;
	else if (Type == 1)
		P.ShadowType = SH_Blob;
	else
		P.ShadowType = SH_Rendered;
	P.InitShadow();
}

static function SetWorldDetail(LevelInfo L, int Detail)
{
	if (Detail <= 0)
		L.DetailChange(DM_Low);
	else if (Detail == 1)
		L.DetailChange(DM_High);
	else
		L.DetailChange(DM_SuperHigh);
}

defaultproperties
{
	AirSpeed=4500.0
	GroundSpeed=950.0
}
