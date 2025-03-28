import Toybox.Activity;
import Toybox.Lang;
import Toybox.Time;
import Toybox.WatchUi;
import Toybox.Communications;
import Toybox.Graphics;

class SettingsFloatPicker extends FloatPicker {
    private var callback as Method;
    function initialize(callback as Method) {
        FloatPicker.initialize();
        self.callback = callback;
    }

    protected function onValue(value as Float or Null) as Void
    {
        if (value == null)
        {
            return;
        }

        callback.invoke(value);
    }
}

class SettingsNumberPicker extends IntPicker {
    private var callback as Method;
    function initialize(callback as Method) {
        IntPicker.initialize();
        self.callback = callback;
    }

    protected function onValue(value as Number or Null) as Void
    {
        if (value == null)
        {
            return;
        }

        callback.invoke(value);
    }
}

class SettingsColourPicker extends ColourPicker {
    private var callback as Method;
    function initialize(callback as Method) {
        ColourPicker.initialize();
        self.callback = callback;
    }

    protected function onValue(value as Number or Null) as Void
    {
        if (value == null)
        {
            return;
        }

        callback.invoke(value);
    }
}

function startPicker(picker as NumberPicker) as Void
{
    WatchUi.pushView(new $.NumberPickerView(picker), new $.NumberPickerDelegate(picker), WatchUi.SLIDE_IMMEDIATE);
}

// todo show currently selected option with '*' for mode menus - or switch them to a picker type
// think this requires menu2 so we can updateItem or setFocus or setIcon
class SettingsMainDelegate extends WatchUi.MenuInputDelegate {
    function initialize() {
        WatchUi.MenuInputDelegate.initialize();
    }

    public function onMenuItem(item as Symbol) as Void {
        var settings = getApp()._breadcrumbContext.settings();
        if (item == :settingsMainMode) {
            WatchUi.pushView(new $.Rez.Menus.SettingsMode(), new $.SettingsModeDelegate(), WatchUi.SLIDE_IMMEDIATE);
        } else if (item == :settingsMainModeUiMode) {
            WatchUi.pushView(new $.Rez.Menus.SettingsUiMode(), new $.SettingsUiModeDelegate(), WatchUi.SLIDE_IMMEDIATE);
        } else if (item == :settingsMainScale) {
            startPicker(new SettingsFloatPicker(settings.method(:setScale)));
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
        }
    }
}

class ResetSettingsDelegate extends WatchUi.ConfirmationDelegate {
    function initialize() {
        WatchUi.ConfirmationDelegate.initialize();
    }
    function onResponse(response as Confirm) as Boolean {
        if (response == WatchUi.CONFIRM_YES) {
            getApp()._breadcrumbContext.settings().resetDefaults();
        }

        return true; // we always handle it
    }
} 

class SettingsModeDelegate extends WatchUi.MenuInputDelegate {
    function initialize() {
        WatchUi.MenuInputDelegate.initialize();
    }
    public function onMenuItem(item as Symbol) as Void {
        var settings = getApp()._breadcrumbContext.settings();
        if (item == :settingsModeTrackRoute) {
            settings.setMode(MODE_NORMAL);
        } else if (item == :settingsModeElevation) {
            settings.setMode(MODE_ELEVATION);
        }
    }
}

class SettingsUiModeDelegate extends WatchUi.MenuInputDelegate {
    function initialize() {
        WatchUi.MenuInputDelegate.initialize();
    }
    public function onMenuItem(item as Symbol) as Void {
        var settings = getApp()._breadcrumbContext.settings();
        if (item == :settingsUiModeShowall) {
            settings.setUiMode(UI_MODE_SHOW_ALL);
        } else if (item == :settingsUiModeHidden) {
            settings.setUiMode(UI_MODE_HIDDEN);
        } else if (item == :settingsUiModeNone) {
            settings.setUiMode(UI_MODE_NONE);
        }
    }
}

class SettingsZoomAtPaceDelegate extends WatchUi.MenuInputDelegate {
    function initialize() {
        WatchUi.MenuInputDelegate.initialize();
    }
    public function onMenuItem(item as Symbol) as Void {
        var settings = getApp()._breadcrumbContext.settings();
        if (item == :settingsZoomAtPaceMode) {
            WatchUi.pushView(new $.Rez.Menus.SettingsZoomAtPaceMode(), new $.SettingsZoomAtPaceModeDelegate(), WatchUi.SLIDE_IMMEDIATE);
        } else if (item == :settingsZoomAtPaceUserMeters) {
            startPicker(new SettingsNumberPicker(settings.method(:setMetersAroundUser)));
        } else if (item == :settingsZoomAtPaceMPS) {
            startPicker(new SettingsFloatPicker(settings.method(:setZoomAtPaceSpeedMPS)));
        }
    }
}

class SettingsZoomAtPaceModeDelegate extends WatchUi.MenuInputDelegate {
    function initialize() {
        WatchUi.MenuInputDelegate.initialize();
    }
    public function onMenuItem(item as Symbol) as Void {
        var settings = getApp()._breadcrumbContext.settings();
        if (item == :settingsZoomAtPaceModePace) {
            settings.setZoomAtPaceMode(ZOOM_AT_PACE_MODE_PACE);
        } else if (item == :settingsZoomAtPaceModeStopped) {
            settings.setZoomAtPaceMode(ZOOM_AT_PACE_MODE_STOPPED);
        }
    }
}

// todo remove the other items if maps enabled
// maybe have a second view? and switch it out on maps enabled
class SettingsMapDelegate extends WatchUi.MenuInputDelegate {
    function initialize() {
        WatchUi.MenuInputDelegate.initialize();
    }
    public function onMenuItem(item as Symbol) as Void {
        var settings = getApp()._breadcrumbContext.settings();
        if (item == :settingsMapEnabled) {
            var dialog = new WatchUi.Confirmation("EnableMaps?");
            WatchUi.pushView(
                dialog,
                new MapEnabledDelegate(),
                WatchUi.SLIDE_IMMEDIATE
            );
        } else if (item == :settingsMapTileSize) {
            startPicker(new SettingsNumberPicker(settings.method(:setTileSize)));
        } else if (item == :settingsMapTileCacheSize) {
            startPicker(new SettingsNumberPicker(settings.method(:setTileCacheSize)));
        } else if (item == :settingsMapMaxPendingWebRequests) {
            startPicker(new SettingsNumberPicker(settings.method(:setMaxPendingWebRequests)));
        } else if (item == :settingsMapFixedLatitude) {
            startPicker(new SettingsFloatPicker(settings.method(:setFixedLatitude)));
        } else if (item == :settingsMapFixedLongitude) {
            startPicker(new SettingsFloatPicker(settings.method(:setFixedLongitude)));
        }
    }
}

class MapEnabledDelegate extends WatchUi.ConfirmationDelegate {
    function initialize() {
        WatchUi.ConfirmationDelegate.initialize();
    }
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
    function initialize() {
        WatchUi.MenuInputDelegate.initialize();
    }
    public function onMenuItem(item as Symbol) as Void {
        var settings = getApp()._breadcrumbContext.settings();
        if (item == :settingsColoursTrackColour) {
            startPicker(new SettingsColourPicker(settings.method(:setTrackColour)));
        } else if (item == :settingsColoursRouteColour) {
            startPicker(new SettingsColourPicker(settings.method(:setRouteColour)));
        } else if (item == :settingsColoursElevationColour) {
            startPicker(new SettingsColourPicker(settings.method(:setElevationColour)));
        } else if (item == :settingsColoursUserColour) {
            startPicker(new SettingsColourPicker(settings.method(:setUserColour)));
        }
    }
}










