import Toybox.Activity;
import Toybox.Lang;
import Toybox.Time;
import Toybox.WatchUi;
import Toybox.Communications;
import Toybox.Graphics;


class SettingsFloatPicker extends FloatPicker {
    private var callback as Method;
    public var parent = null;
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
        if (parent != null && parent has :rerender)
        {
            parent.rerender();
        }
    }
}

class SettingsNumberPicker extends IntPicker {
    private var callback as Method;
    public var parent = null;
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
        if (parent != null && parent has :rerender)
        {
            parent.rerender();
        }
    }
}

class SettingsStringPicker extends WatchUi.TextPickerDelegate {
    private var callback as Method;
    public var parent = null;
    function initialize(callback as Method, parent) {
        TextPickerDelegate.initialize();
        self.callback = callback;
        self.parent = parent;
    }

    function onTextEntered(text as Lang.String, changed as Lang.Boolean) as Lang.Boolean {
        System.println("onTextEntered: " + text + " " + changed);

        callback.invoke(text);
        if (parent != null && parent has :rerender)
        {
            parent.rerender();
        }

        return true;
    }

    function onCancel() as Boolean {
        System.println("canceled");
        return true;
    }
}

class SettingsColourPicker extends ColourPicker {
    private var callback as Method;
    public var parent = null;
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
        if (parent != null && parent has :rerender)
        {
            parent.rerender();
        }
    }
}

function startPicker(picker as SettingsFloatPicker or SettingsColourPicker or SettingsNumberPicker, parent) as Void
{
    picker.parent = parent;
    WatchUi.pushView(new $.NumberPickerView(picker), new $.NumberPickerDelegate(picker), WatchUi.SLIDE_IMMEDIATE);
}

function safeSetSubLabel(menu as WatchUi.Menu2, id as Object, value as String) as Void
{
    var itemIndex = menu.findItemById(id);
    if (itemIndex <= -1)
    {
        return;
    }

    var item = menu.getItem(itemIndex);
    if (item == null)
    {
        return;
    }

    item.setSubLabel(value);
}

function safeSetLabel(menu as WatchUi.Menu2, id as Object, value as String) as Void
{
    var itemIndex = menu.findItemById(id);
    if (itemIndex <= -1)
    {
        return;
    }

    var item = menu.getItem(itemIndex);
    if (item == null)
    {
        return;
    }

    item.setLabel(value);
}


function safeSetToggle(menu as WatchUi.Menu2, id as Object, value as Boolean) as Void
{
    var itemIndex = menu.findItemById(id);
    if (itemIndex <= -1)
    {
        return;
    }

    var item = menu.getItem(itemIndex);
    if (item == null)
    {
        return;
    }

    if (item instanceof WatchUi.ToggleMenuItem)
    {
        item.setEnabled(value);
    }
}

// https://forums.garmin.com/developer/connect-iq/f/discussion/379406/vertically-center-icon-in-iconmenuitem-using-menu2#pifragment-1298=4
const iconMenuWidthPercent = 0.6;
class ColourIcon extends WatchUi.Drawable {
    var colour as Number;

    function initialize(colour as Number) {
        Drawable.initialize({});
        self.colour = colour;
    }

    function draw(dc as Graphics.Dc) {
        var iconWidthHeight;

        // Calculate Width Height of Icon based on drawing area
        if (dc.getHeight() > dc.getWidth()) {
            iconWidthHeight = iconMenuWidthPercent * dc.getHeight();
        } else {
            iconWidthHeight = iconMenuWidthPercent * dc.getWidth();
        }

        dc.setColor(colour, colour);
        dc.fillCircle(dc.getWidth() / 2, dc.getHeight() / 2, iconWidthHeight / 2f);
    }
}

function safeSetIcon(menu as WatchUi.Menu2, id as Object, value as WatchUi.Drawable) as Void
{
    var itemIndex = menu.findItemById(id);
    if (itemIndex <= -1)
    {
        return;
    }

    var item = menu.getItem(itemIndex);
    if (item == null)
    {
        return;
    }

    // support was added for icons on menuitems in API Level 3.4.0 but IconMenuItem had it from API 3.0.0
    // MenuItem and IconMenuItem, they both support icons
    if (item has :setIcon) 
    {
        item.setIcon(value);
    }
}

// https://forums.garmin.com/developer/connect-iq/f/discussion/304179/programmatically-set-the-state-of-togglemenuitem
class SettingsMain extends Rez.Menus.SettingsMain {
    function initialize() {
        Rez.Menus.SettingsMain.initialize();
        rerender();
    }

    function rerender() as Void
    {
        var settings = getApp()._breadcrumbContext.settings();
        var modeString = "";
        switch(settings.mode)
        {
            case MODE_NORMAL:
                modeString = Rez.Strings.track_route_mode;
                break;
            case MODE_ELEVATION:
                modeString = Rez.Strings.elevation_mode;
                break;
            case MODE_MAP_MOVE:
                modeString = Rez.Strings.mapMove;
                break;
            case MODE_DEBUG:
                modeString = Rez.Strings.debug;
                break;
        }
        safeSetSubLabel(me, :settingsMainMode, modeString);
        var uiModeString = "";
        switch(settings.uiMode)
        {
            case UI_MODE_SHOW_ALL:
                uiModeString = Rez.Strings.uiModeShowAll;
                break;
            case UI_MODE_HIDDEN:
                uiModeString = Rez.Strings.uiModeHidden;
                break;
            case UI_MODE_NONE:
                uiModeString = Rez.Strings.uiModeNone;
                break;
        }
        safeSetSubLabel(me, :settingsMainModeUiMode, uiModeString);
        var scaleString = settings.scale == null ? "Auto" : settings.scale.format("%.5f");
        safeSetSubLabel(me, :settingsMainScale, scaleString);
    }
}

class SettingsZoomAtPace extends Rez.Menus.SettingsZoomAtPace {
    function initialize() {
        Rez.Menus.SettingsZoomAtPace.initialize();
        rerender();
    }

    function rerender() as Void
    {
        var settings = getApp()._breadcrumbContext.settings();
        var modeString = "";
        switch(settings.zoomAtPaceMode)
        {
            case ZOOM_AT_PACE_MODE_PACE:
                modeString = Rez.Strings.zoomAtPaceModePace;
                break;
            case ZOOM_AT_PACE_MODE_STOPPED:
                modeString = Rez.Strings.zoomAtPaceModeStopped;
                break;
        }
        safeSetSubLabel(me, :settingsZoomAtPaceMode, modeString);
        safeSetSubLabel(me, :settingsZoomAtPaceUserMeters, settings.metersAroundUser.toString() + "m");
        safeSetSubLabel(me, :settingsZoomAtPaceMPS, settings.zoomAtPaceSpeedMPS.format("%.2f") + "m/s");
    }
}

class SettingsMap extends Rez.Menus.SettingsMap {
    function initialize() {
        Rez.Menus.SettingsMap.initialize();
        rerender();
    }

    function rerender() as Void
    {
        var settings = getApp()._breadcrumbContext.settings();
        safeSetToggle(me, :settingsMapEnabled, true);
        safeSetSubLabel(me, :settingsTileUrl, settings.tileUrl);
        safeSetSubLabel(me, :settingsMapTileSize, settings.tileSize.toString());
        safeSetSubLabel(me, :settingsMapTileCacheSize, settings.tileCacheSize.toString());
        safeSetSubLabel(me, :settingsMapMaxPendingWebRequests, settings.maxPendingWebRequests.toString());
        var latString = settings.fixedLatitude == null ? "Disabled" : settings.fixedLatitude.format("%.5f");
        safeSetSubLabel(me, :settingsMapFixedLatitude, latString);
        var longString = settings.fixedLongitude == null ? "Disabled" : settings.fixedLongitude.format("%.5f");
        safeSetSubLabel(me, :settingsMapFixedLongitude, longString);
    }
}

class SettingsMapDisabled extends Rez.Menus.SettingsMapDisabled {
    function initialize() {
        Rez.Menus.SettingsMapDisabled.initialize();
        rerender();
    }

    function rerender() as Void
    {
        safeSetToggle(me, :settingsMapEnabled, false);
    }
}

class SettingsColours extends Rez.Menus.SettingsColours {
    function initialize() {
        Rez.Menus.SettingsColours.initialize();
        rerender();
    }

    function rerender() as Void
    {
        var settings = getApp()._breadcrumbContext.settings();
        safeSetIcon(me, :settingsColoursTrackColour, new ColourIcon(settings.trackColour));
        safeSetIcon(me, :settingsColoursUserColour, new ColourIcon(settings.userColour));
        safeSetIcon(me, :settingsColoursElevationColour, new ColourIcon(settings.elevationColour));
    }
}

class SettingsRoute extends Rez.Menus.SettingsRoute {
    var settings as Settings;
    var routeId as Number;
    var parent as SettingsRoutes;
    function initialize(settings as Settings, routeId as Number, parent as SettingsRoutes) {
        Rez.Menus.SettingsRoute.initialize();
        self.settings = settings;
        self.routeId = routeId;
        self.parent = parent;
        rerender();
    }

    function rerender() as Void
    {
        var name = settings.routeName(routeId);
        setTitle(name);
        safeSetSubLabel(me, :settingsRouteName, name);
        safeSetToggle(me, :settingsRouteEnabled, settings.routeEnabled(routeId));
        safeSetIcon(me, :settingsRouteColour, new ColourIcon(settings.routeColour(routeId)));
        parent.rerender();
    }

    function setName(value as String) as Void
    {
        settings.setRouteName(routeId, value);
    }
    
    function setEnabled(value as Boolean) as Void
    {
        settings.setRouteEnabled(routeId, value);
    }
    
    function routeEnabled() as Boolean
    {
        return settings.routeEnabled(routeId);
    }

    function setColour(value as Number) as Void
    {
        settings.setRouteColour(routeId, value);
    }
}

class SettingsRoutes extends WatchUi.Menu2 {
    var settings as Settings;
    function initialize(settings as Settings) {
        WatchUi.Menu2.initialize({
            :title => Rez.Strings.routesTitle,
        });
        me.settings = settings;
        setup();
        rerender();
    }

    function setup() {
        addItem(
            new ToggleMenuItem(
                Rez.Strings.routesEnabled,
                "", // sublabel
                :settingsRoutesEnabled,
                settings.routesEnabled,
                {}
            )
        );
        if (!settings.routesEnabled)
        {
            return;
        }
        
        for (var i = 0; i < ROUTE_MAX; ++i) {
            var routeName = settings.routeName(i);
            addItem(
                // do not be tempted to switch this to a menuitem (IconMenuItem is supported since API 3.0.0, MenuItem only supports icons from API 3.4.0)
                new IconMenuItem(
                    routeName.equals("") ? "<unlabeled>" : routeName,
                    settings.routeEnabled(i) ? "Enabled" : "Disabled",
                    i,
                    new ColourIcon(settings.routeColour(i)),
                    {
                        // only get left or right, no center :(
                        :alignment => MenuItem.MENU_ITEM_LABEL_ALIGN_LEFT,
                    }
                )
            );
        }
    }

    function rerender() as Void
    {
        safeSetToggle(me, :settingsRoutesEnabled, settings.routesEnabled);
        for (var i = 0; i < ROUTE_MAX; ++i) {
            var routeName = settings.routeName(i);
            safeSetLabel(me, i, routeName.equals("") ? "<unlabeled>" : routeName);
            safeSetIcon(me, i, new ColourIcon(settings.routeColour(i)));
            safeSetSubLabel(me, i, settings.routeEnabled(i) ? "Enabled" : "Disabled");
        }
    }
}

class SettingsMainDelegate extends WatchUi.Menu2InputDelegate {
    var view as SettingsMain;
    function initialize(view as SettingsMain) {
        WatchUi.Menu2InputDelegate.initialize();
        me.view = view;
    }

    public function onSelect(item as WatchUi.MenuItem) as Void {
        var settings = getApp()._breadcrumbContext.settings();
        var itemId = item.getId();
        if (itemId == :settingsMainMode) {
            WatchUi.pushView(new $.Rez.Menus.SettingsMode(), new $.SettingsModeDelegate(view), WatchUi.SLIDE_IMMEDIATE);
        } else if (itemId == :settingsMainModeUiMode) {
            WatchUi.pushView(new $.Rez.Menus.SettingsUiMode(), new $.SettingsUiModeDelegate(view), WatchUi.SLIDE_IMMEDIATE);
        } else if (itemId == :settingsMainScale) {
            startPicker(new SettingsFloatPicker(settings.method(:setScale)), view);
        } else if (itemId == :settingsMainZoomAtPace) {
            var view = new $.SettingsZoomAtPace();
            WatchUi.pushView(view, new $.SettingsZoomAtPaceDelegate(view), WatchUi.SLIDE_IMMEDIATE);
        } else if (itemId == :settingsMainRoutes) {
            var view = new $.SettingsRoutes(settings);
            WatchUi.pushView(view, new $.SettingsRoutesDelegate(view, settings), WatchUi.SLIDE_IMMEDIATE);
        } else if (itemId == :settingsMainMap) {
            if (settings.mapEnabled)
            {
                var view = new SettingsMap();
                WatchUi.pushView(view, new $.SettingsMapDelegate(view), WatchUi.SLIDE_IMMEDIATE);
                return;
            }
            var disabledView = new SettingsMapDisabled();
            WatchUi.pushView(disabledView, new $.SettingsMapDisabledDelegate(disabledView), WatchUi.SLIDE_IMMEDIATE);
        } else if (itemId == :settingsMainColours) {
            var view = new SettingsColours();
            WatchUi.pushView(view, new $.SettingsColoursDelegate(view), WatchUi.SLIDE_IMMEDIATE);            
        } else if (itemId == :settingsMainResetDefaults) {
            var dialog = new WatchUi.Confirmation("Reset all settings?");
            WatchUi.pushView(
                dialog,
                new ResetSettingsDelegate(),
                WatchUi.SLIDE_IMMEDIATE
            );
        }
    }

    function onBack() as Void
    {
        System.println("onBack");
        Menu2InputDelegate.onBack();
    }
    function onDone() as Void
    {
        System.println("onDone");
    }
    function onFooter() as Void
    {
        System.println("onFooter");
    }
    function onNextPage() as Lang.Boolean
    {
        System.println("onNextPage");
        return true;
    }
    function onPreviousPage() as Lang.Boolean
    {
        System.println("onPreviousPage");
        return true;
    }
    function onTitle() as Void
    {
        System.println("onTitle");
    }
    function onWrap(key as WatchUi.Key) as Lang.Boolean
    {
        System.println("onWrap");
        return true;
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

class SettingsModeDelegate extends WatchUi.Menu2InputDelegate {
    var parent as SettingsMain;
    function initialize(parent as SettingsMain) {
        WatchUi.Menu2InputDelegate.initialize();
        me.parent = parent;
    }
    public function onSelect(item as WatchUi.MenuItem) as Void {
        var settings = getApp()._breadcrumbContext.settings();
        var itemId = item.getId();
        if (itemId == :settingsModeTrackRoute) {
            settings.setMode(MODE_NORMAL);
        } else if (itemId == :settingsModeElevation) {
            settings.setMode(MODE_ELEVATION);
        } else if (itemId == :settingsModeMapMove) {
            settings.setMode(MODE_MAP_MOVE);
        } else if (itemId == :settingsModeMapDebug) {
            settings.setMode(MODE_DEBUG);
        }

        parent.rerender();
        WatchUi.popView(WatchUi.SLIDE_IMMEDIATE);
    }

    function onBack() as Void
    {
        System.println("onBack from mode menu");
        Menu2InputDelegate.onBack();
    }
    function onDone() as Void
    {
        System.println("onDone  from mode menu");
    }
    function onFooter() as Void
    {
        System.println("onFooter  from mode menu");
    }
    function onNextPage() as Lang.Boolean
    {
        System.println("onNextPage  from mode menu");
        return false;
    }
    function onPreviousPage() as Lang.Boolean
    {
        System.println("onPreviousPage  from mode menu");
        return false;
    }
    function onTitle() as Void
    {
        System.println("onTitle  from mode menu");
    }
    function onWrap(key as WatchUi.Key) as Lang.Boolean
    {
        System.println("onWrap  from mode menu");
        return false;
    }
}

class SettingsUiModeDelegate extends WatchUi.Menu2InputDelegate {
    var parent as SettingsMain;
    function initialize(parent as SettingsMain) {
        WatchUi.Menu2InputDelegate.initialize();
        me.parent = parent;
    }
    public function onSelect(item as WatchUi.MenuItem) as Void {
        var settings = getApp()._breadcrumbContext.settings();
        var itemId = item.getId();
        if (itemId == :settingsUiModeShowall) {
            settings.setUiMode(UI_MODE_SHOW_ALL);
        } else if (itemId == :settingsUiModeHidden) {
            settings.setUiMode(UI_MODE_HIDDEN);
        } else if (itemId == :settingsUiModeNone) {
            settings.setUiMode(UI_MODE_NONE);
        }

        parent.rerender();
        WatchUi.popView(WatchUi.SLIDE_IMMEDIATE);
    }
}

class SettingsZoomAtPaceDelegate extends WatchUi.Menu2InputDelegate {
    var view as SettingsZoomAtPace;
    function initialize(view as SettingsZoomAtPace) {
        WatchUi.Menu2InputDelegate.initialize();
        me.view = view;
    }
    public function onSelect(item as WatchUi.MenuItem) as Void {
        var settings = getApp()._breadcrumbContext.settings();
        var itemId = item.getId();
        if (itemId == :settingsZoomAtPaceMode) {
            WatchUi.pushView(new $.Rez.Menus.SettingsZoomAtPaceMode(), new $.SettingsZoomAtPaceModeDelegate(view), WatchUi.SLIDE_IMMEDIATE);
        } else if (itemId == :settingsZoomAtPaceUserMeters) {
            startPicker(new SettingsNumberPicker(settings.method(:setMetersAroundUser)), view);
        } else if (itemId == :settingsZoomAtPaceMPS) {
            startPicker(new SettingsFloatPicker(settings.method(:setZoomAtPaceSpeedMPS)), view);
        }
    }
}

class SettingsRoutesDelegate extends WatchUi.Menu2InputDelegate {
    var view as SettingsRoutes;
    var settings as Settings;
    function initialize(view as SettingsRoutes, settings as Settings) {
        WatchUi.Menu2InputDelegate.initialize();
        me.view = view;
        me.settings = settings;
    }
    public function onSelect(item as WatchUi.MenuItem) as Void {
        var itemId = item.getId();
        if (itemId == :settingsRoutesEnabled) {
            settings.toggleRoutesEnabled();
            WatchUi.popView(WatchUi.SLIDE_IMMEDIATE);
            var view = new $.SettingsRoutes(settings);
            WatchUi.pushView(view, new $.SettingsRoutesDelegate(view, settings), WatchUi.SLIDE_IMMEDIATE);
        }

        // itemId should now be the route storageIndex = routeId
        if (itemId instanceof Number)
        {
            var thisView = new $.SettingsRoute(settings, itemId, view);
            WatchUi.pushView(thisView, new $.SettingsRouteDelegate(thisView, settings), WatchUi.SLIDE_IMMEDIATE);
        }
    }
}

class SettingsRouteDelegate extends WatchUi.Menu2InputDelegate {
    var view as SettingsRoute;
    var settings as Settings;
    function initialize(view as SettingsRoute, settings as Settings) {
        WatchUi.Menu2InputDelegate.initialize();
        me.view = view;
        me.settings = settings;
    }
    public function onSelect(item as WatchUi.MenuItem) as Void {
        var itemId = item.getId();
        if (itemId == :settingsRouteName) {
            var picker = new SettingsStringPicker(view.method(:setName), view);
            WatchUi.pushView(new WatchUi.TextPicker(settings.routeName(view.routeId)), picker, WatchUi.SLIDE_IMMEDIATE);
        } else if (itemId == :settingsRouteEnabled) {
            if (view.routeEnabled())
            {
                view.setEnabled(false);
            }
            else 
            {
                view.setEnabled(true);
            }
            view.rerender();
        } else if (itemId == :settingsRouteColour) {
            startPicker(new SettingsColourPicker(view.method(:setColour)), view);
        }
    }
}

class SettingsZoomAtPaceModeDelegate extends WatchUi.Menu2InputDelegate {
    var parent as SettingsZoomAtPace;
    function initialize(parent as SettingsZoomAtPace) {
        WatchUi.Menu2InputDelegate.initialize();
        me.parent = parent;
    }
    public function onSelect(item as WatchUi.MenuItem) as Void {
        var settings = getApp()._breadcrumbContext.settings();
        var itemId = item.getId();
        if (itemId == :settingsZoomAtPaceModePace) {
            settings.setZoomAtPaceMode(ZOOM_AT_PACE_MODE_PACE);
        } else if (itemId == :settingsZoomAtPaceModeStopped) {
            settings.setZoomAtPaceMode(ZOOM_AT_PACE_MODE_STOPPED);
        }

        parent.rerender();
        WatchUi.popView(WatchUi.SLIDE_IMMEDIATE);
    }
}

class SettingsMapDelegate extends WatchUi.Menu2InputDelegate {
    var view as SettingsMap;
    function initialize(view as SettingsMap) {
        WatchUi.Menu2InputDelegate.initialize();
        me.view = view;
    }
    public function onSelect(item as WatchUi.MenuItem) as Void {
        var settings = getApp()._breadcrumbContext.settings();
        var itemId = item.getId();
        if (itemId == :settingsMapEnabled) {
            settings.setMapEnabled(false);
            var view = new SettingsMapDisabled();
            WatchUi.popView(WatchUi.SLIDE_IMMEDIATE);
            WatchUi.pushView(view, new $.SettingsMapDisabledDelegate(view), WatchUi.SLIDE_IMMEDIATE);
        } else if (itemId == :settingsTileUrl) {
            var picker = new SettingsStringPicker(settings.method(:setTileUrl), view);
            WatchUi.pushView(new WatchUi.TextPicker(settings.tileUrl), picker, WatchUi.SLIDE_IMMEDIATE);
        } else if (itemId == :settingsMapTileSize) {
            startPicker(new SettingsNumberPicker(settings.method(:setTileSize)), view);
        } else if (itemId == :settingsMapTileCacheSize) {
            startPicker(new SettingsNumberPicker(settings.method(:setTileCacheSize)), view);
        } else if (itemId == :settingsMapMaxPendingWebRequests) {
            startPicker(new SettingsNumberPicker(settings.method(:setMaxPendingWebRequests)), view);
        } else if (itemId == :settingsMapFixedLatitude) {
            startPicker(new SettingsFloatPicker(settings.method(:setFixedLatitude)), view);
        } else if (itemId == :settingsMapFixedLongitude) {
            startPicker(new SettingsFloatPicker(settings.method(:setFixedLongitude)), view);
        }
    }
}

class SettingsMapDisabledDelegate extends WatchUi.Menu2InputDelegate {
    var view as SettingsMapDisabled;
    function initialize(view as SettingsMapDisabled) {
        WatchUi.Menu2InputDelegate.initialize();
        me.view = view;
    }
    public function onSelect(item as WatchUi.MenuItem) as Void {
        var settings = getApp()._breadcrumbContext.settings();
        var itemId = item.getId();
        if (itemId == :settingsMapEnabled) {
            settings.setMapEnabled(true);
            var view = new SettingsMap();
            WatchUi.popView(WatchUi.SLIDE_IMMEDIATE);
            WatchUi.pushView(view, new $.SettingsMapDelegate(view), WatchUi.SLIDE_IMMEDIATE);
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

class SettingsColoursDelegate extends WatchUi.Menu2InputDelegate {
    var view as SettingsColours;
    function initialize(view as SettingsColours) {
        WatchUi.Menu2InputDelegate.initialize();
        me.view = view;
    }
    public function onSelect(item as WatchUi.MenuItem) as Void {
        var settings = getApp()._breadcrumbContext.settings();
        var itemId = item.getId();
        if (itemId == :settingsColoursTrackColour) {
            startPicker(new SettingsColourPicker(settings.method(:setTrackColour)), view);
        } else if (itemId == :settingsColoursElevationColour) {
            startPicker(new SettingsColourPicker(settings.method(:setElevationColour)), view);
        } else if (itemId == :settingsColoursUserColour) {
            startPicker(new SettingsColourPicker(settings.method(:setUserColour)), view);
        }
    }
}
