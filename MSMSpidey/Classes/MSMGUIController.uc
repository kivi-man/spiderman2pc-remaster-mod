// GUI controller (Webhead.ini [Engine.Engine] GUIController=MSMSpidey.MSMGUIController).
// The front end opens the stock video and controls pages by name; both go to the
// MSM settings page instead. The stock pages stay reachable with Param1 "stock".
class MSMGUIController extends WebheadGUIController
	config;

event bool OpenMenu(string NewMenuName, optional string Param1, optional string Param2)
{
	if (Param1 != "stock")
	{
		if (NewMenuName ~= "WebHead.PageVideo")
			return Super.OpenMenu("MSMSpidey.MSMPageSettings", "video", Param2);
		if (NewMenuName ~= "WebHead.PageControls")
			return Super.OpenMenu("MSMSpidey.MSMPageSettings", "keys", Param2);
	}
	return Super.OpenMenu(NewMenuName, Param1, Param2);
}
