// Invisible point in the world that a WebRope can connect to
// (swing pivot, zip / point-launch target, web-shot end point).
class MSMAnchor extends Actor;

defaultproperties
{
	bHidden=true
	DrawType=DT_None
	bCollideActors=false
	bBlockActors=false
	bBlockPlayers=false
	bCollideWorld=false
	RemoteRole=ROLE_None
}
