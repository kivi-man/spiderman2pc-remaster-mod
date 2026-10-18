// Settings of the MSM mod, edited in MSMPageSettings, saved to System/MSMSpidey.ini
// [MSMSpidey.MSMSettings]. The loader (d3d8.dll) reads the driver-level ones from the
// same section: MSAA, Anisotropy, bVSync, FrameLimit, RefreshRate, bBorderless, Adapter,
// PostAA, Sharpen, MipBias, bReflections, bMirror.
class MSMSettings extends Object
	config(MSMSpidey);

// driver level (_mod/loader)
var config int MSAA;            // 0, 2, 4, 8
var config int Anisotropy;      // 1 = off, 2, 4, 8, 16
var config bool bVSync;
var config int FrameLimit;      // 0 = unlimited, -1 = auto (just under the refresh rate)
var config int RefreshRate;     // fullscreen refresh rate in Hz, 0 = desktop rate
var config bool bBorderless;    // "fullscreen" is a borderless window
var config int Adapter;         // display adapter, -1 = as the game asks (needs a restart)
var config int PostAA;          // 0 = off, 1 = FXAA
var config int Sharpen;         // 0 = off .. 3 = high
var config int CrowdDensity;   // NPCs and vehicles alive at once: 0 = stock, 1 = 2x, 2 = 5x, 3 = 10x, 4 = 20x
var config int DrawDistance;   // 0 = stock, 1 = 1.5x, 2 = 2x, 3 = 3x, 4 = 5x
var config int MipBias;         // 0 = default, 1 = sharp, 2 = sharper
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
	RefreshRate=0
	bBorderless=true
	Adapter=-1
	PostAA=0
	Sharpen=0
	MipBias=0
	DrawDistance=2
	CrowdDensity=4
	bReflections=true
	bMirror=true
	FOV=65
	CamDistance=1.0
	CamShake=1.0
	bAutoCamera=true
	LookSpeed=1.0
}
