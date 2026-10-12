// Settings of the MSM mod, edited in MSMPageSettings, saved to System/MSMSpidey.ini
// [MSMSpidey.MSMSettings]. The loader (d3d8.dll) reads the driver-level ones from the
// same section: MSAA, Anisotropy, bVSync, FrameLimit, bReflections, bMirror.
class MSMSettings extends Object
	config(MSMSpidey);

// driver level (_mod/loader)
var config int MSAA;            // 0, 2, 4, 8
var config int Anisotropy;      // 1 = off, 2, 4, 8, 16
var config bool bVSync;
var config int FrameLimit;      // 0 = unlimited
var config bool bReflections;   // live reflections
var config bool bMirror;        // mirror reflection of the wall in view

// camera
var config float FOV;           // vertical field of view at rest, degrees
var config float CamDistance;   // camera distance scale
var config float CamShake;      // camera shake scale (0 = off)
var config bool bAutoCamera;    // camera swings behind Spider-Man while traversing
var config float LookSpeed;     // camera turn speed scale

defaultproperties
{
	MSAA=0
	Anisotropy=8
	bVSync=false
	FrameLimit=0
	bReflections=true
	bMirror=true
	FOV=65
	CamDistance=1.0
	CamShake=1.0
	bAutoCamera=true
	LookSpeed=1.0
}
