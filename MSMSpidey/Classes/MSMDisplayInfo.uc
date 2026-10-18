// What the monitor is set to, written by the loader (d3d8.dll) at every start to System/MSMDisplay.ini.
// The settings page never offers a resolution or refresh rate above these.
class MSMDisplayInfo extends Object
	config(MSMDisplay);

var config int DesktopWidth;
var config int DesktopHeight;
var config int DesktopRefresh;
var config int MaxRefresh;      // fastest refresh rate the monitor offers at the desktop resolution

defaultproperties
{
	DesktopWidth=0
	DesktopHeight=0
	DesktopRefresh=0
	MaxRefresh=0
}
