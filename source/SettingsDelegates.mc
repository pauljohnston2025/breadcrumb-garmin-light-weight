import Toybox.Activity;
import Toybox.Lang;
import Toybox.Time;
import Toybox.WatchUi;
import Toybox.Communications;
import Toybox.Graphics;

// todo show currently selected option with '*' for mode menus - or switch them to a picker type
// think this requires menu2 so we can updateItem or setFocus or setIcon
class SettingsMainDelegate extends WatchUi.MenuInputDelegate {
    public function onMenuItem(item as Symbol) as Void {
        if (item == :settingsMainMode) {
            WatchUi.pushView(new $.Rez.Menus.SettingsMode(), new $.SettingsModeDelegate(), WatchUi.SLIDE_IMMEDIATE);
        } else if (item == :settingsMainModeUiMode) {
            WatchUi.pushView(new $.Rez.Menus.SettingsUiMode(), new $.SettingsUiModeDelegate(), WatchUi.SLIDE_IMMEDIATE);
        } else if (item == :settingsMainScale) {
            // todo float picker
        } else if (item == :settingsMainZoomAtPace) {
            WatchUi.pushView(new $.Rez.Menus.SettingsZoomAtPace(), new $.SettingsZoomAtPaceDelegate(), WatchUi.SLIDE_IMMEDIATE);
        } else if (item == :settingsMainMap) {
            WatchUi.pushView(new $.Rez.Menus.SettingsMap(), new $.SettingsMapDelegate(), WatchUi.SLIDE_IMMEDIATE);            
        } else if (item == :settingsMainColours) {
            WatchUi.pushView(new $.Rez.Menus.SettingsColours(), new $.SettingsColoursDelegate(), WatchUi.SLIDE_IMMEDIATE);            
        } else if (item == :settingsMainResetDefaults) {
            var dialog = new WatchUi.Confirmation("RestSettings?");
            WatchUi.pushView(
                dialog,
                new ResetSettingsDelegate(),
                WatchUi.SLIDE_IMMEDIATE
            );
        } else if (item == :settingsMainExit) {
            // todo close settings view (think we have a blank screen might need to launch straight to menus)
        }
    }
}

class ResetSettingsDelegate extends WatchUi.ConfirmationDelegate {
    function onResponse(response as Confirm) as Boolean {
        if (response == WatchUi.CONFIRM_YES) {
            getApp()._breadcrumbContext.settings().resetDefaults();
        }

        return true; // we always handle it
    }
} 

class SettingsModeDelegate extends WatchUi.MenuInputDelegate {
    public function onMenuItem(item as Symbol) as Void {
        if (item == :settingsModeTrackRoute) {
            getApp()._breadcrumbContext.settings().setMode(MODE_NORMAL);
        } else if (item == :settingsModeElevation) {
            getApp()._breadcrumbContext.settings().setMode(MODE_ELEVATION);
        }
    }
}

class SettingsUiModeDelegate extends WatchUi.MenuInputDelegate {
    public function onMenuItem(item as Symbol) as Void {
        if (item == :settingsUiModeShowall) {
            getApp()._breadcrumbContext.settings().setUiMode(UI_MODE_SHOW_ALL);
        } else if (item == :settingsUiModeHidden) {
            getApp()._breadcrumbContext.settings().setUiMode(UI_MODE_HIDDEN);
        } else if (item == :settingsUiModeSettings) {
            getApp()._breadcrumbContext.settings().setUiMode(UI_MODE_SETTINGS_ONLY);
        } else if (item == :settingsUiModeNone) {
            getApp()._breadcrumbContext.settings().setUiMode(UI_MODE_NONE);
        }
    }
}

class SettingsZoomAtPaceDelegate extends WatchUi.MenuInputDelegate {
    public function onMenuItem(item as Symbol) as Void {
        if (item == :settingsZoomAtPaceMode) {
            WatchUi.pushView(new $.Rez.Menus.SettingsZoomAtPaceMode(), new $.SettingsZoomAtPaceModeDelegate(), WatchUi.SLIDE_IMMEDIATE);
        } else if (item == :settingsZoomAtPaceUserMeters) {
            // todo number picker
        } else if (item == :settingsZoomAtPaceMPS) {
            // todo float picker
        }
    }
}

class SettingsZoomAtPaceModeDelegate extends WatchUi.MenuInputDelegate {
    public function onMenuItem(item as Symbol) as Void {
        if (item == :settingsZoomAtPaceModePace) {
            getApp()._breadcrumbContext.settings().setZoomAtPaceMode(ZOOM_AT_PACE_MODE_PACE);
        } else if (item == :settingsZoomAtPaceModeStopped) {
            getApp()._breadcrumbContext.settings().setZoomAtPaceMode(ZOOM_AT_PACE_MODE_STOPPED);
        }
    }
}

// todo remove the other itmes if maps eenabled
// maybe have a second view? and switch it out on maps enabled
class SettingsMapDelegate extends WatchUi.MenuInputDelegate {
    public function onMenuItem(item as Symbol) as Void {
        if (item == :settingsMapEnabled) {
            var dialog = new WatchUi.Confirmation("EnableMaps?");
            WatchUi.pushView(
                dialog,
                new MapEnabledDelegate(),
                WatchUi.SLIDE_IMMEDIATE
            );
        } else if (item == :settingsMapTileSize) {
            // todo number picker
        } else if (item == :settingsMapTileCacheSize) {
            // todo number picker
        } else if (item == :settingsMapMaxPendingWebRequests) {
            // todo number picker
        } else if (item == :settingsMapFixedLatitude) {
            // todo float picker
        } else if (item == :settingsMapFixedLongitude) {
            // todo float picker
        }
    }
}

class MapEnabledDelegate extends WatchUi.ConfirmationDelegate {
    function onResponse(response as Confirm) as Boolean {
        if (response == WatchUi.CONFIRM_YES) {
            getApp()._breadcrumbContext.settings().setMapEnabled(true);
        } else {
            getApp()._breadcrumbContext.settings().setMapEnabled(false);
        }

        return true; // we always handle it
    }
} 

class SettingsColoursDelegate extends WatchUi.MenuInputDelegate {
    public function onMenuItem(item as Symbol) as Void {
        if (item == :settingsColoursTrackColour) {
            // todo colour picker
        } else if (item == :settingsColoursRouteColour) {
            // todo colour picker
        } else if (item == :settingsColoursElevationColour) {
            // todo colour picker
        } else if (item == :settingsColoursUserColour) {
            // todo colour picker
        }
    }
}










