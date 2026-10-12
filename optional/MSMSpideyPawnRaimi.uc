// Spider-Man with the Raimi suit (Marvel's Spider-Man Remastered port, retargeted to the stock skeleton).
// MSMSuit.ukx holds the skeletal mesh (stock bone names/order/bind pose, MeshAnimation = SpideyAnim) and the
// textures; Skins(i) = PSK material i. Select it with Class=MSMSpidey.MSMSpideyPawnRaimi in Webhead.ini [URL].
class MSMSpideyPawnRaimi extends MSMSpideyPawn;

event PostBeginPlay()
{
	Super.PostBeginPlay();
	LinkSkelAnim(MeshAnimation'SpideyAnimations.SpideyAnim', Mesh);
	Log("MSMRAIMI pawn mesh=" $ Mesh $ " hasIdle=" $ HasAnim('IdleRest') $ " len=" $ AnimGetLength('IdleRest', 1.0));
}

defaultproperties
{
	Mesh=SkeletalMesh'MSMSuit.RaimiSuit'
	Skins(0)=Texture'MSMSuit.Raimi_m07'
	Skins(1)=Texture'MSMSuit.Raimi_m08'
	Skins(2)=Texture'MSMSuit.Raimi_m09'
	Skins(3)=Texture'MSMSuit.Raimi_m10'
	Skins(4)=Texture'MSMSuit.Raimi_m11'
	Skins(5)=Texture'MSMSuit.Raimi_m12'
	Skins(6)=Texture'MSMSuit.Raimi_m13'
	Skins(7)=Texture'MSMSuit.Raimi_m14'
	Skins(8)=Texture'MSMSuit.Raimi_m15'
	Skins(9)=Texture'MSMSuit.Raimi_m16'
	Skins(10)=Texture'MSMSuit.Raimi_m17'
	Skins(11)=Texture'MSMSuit.Raimi_m18'
	Skins(12)=Texture'MSMSuit.Raimi_m19'
	Skins(13)=Texture'MSMSuit.Raimi_m20'
}
