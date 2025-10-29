import Toybox.Application;
import Toybox.Lang;
import Toybox.Graphics;
import Toybox.System;
import Toybox.Application;
import Toybox.Communications;
import Toybox.WatchUi;
import Toybox.PersistedContent;

enum /*Mode*/ {
    MODE_NORMAL,
    MODE_ELEVATION,
    MODE_MAP_MOVE,
    MODE_DEBUG,
    MODE_MAX,
}

enum /*ElevationMode*/ {
    ELEVATION_MODE_STACKED,
    ELEVATION_MODE_ORDERED_ROUTES,
    ELEVATION_MODE_MAX,
}

enum /*ZoomMode*/ {
    ZOOM_AT_PACE_MODE_PACE,
    ZOOM_AT_PACE_MODE_STOPPED,
    ZOOM_AT_PACE_MODE_NEVER_ZOOM,
    ZOOM_AT_PACE_MODE_ALWAYS_ZOOM,
    ZOOM_AT_PACE_MODE_SHOW_ROUTES_WITHOUT_TRACK,
    ZOOM_AT_PACE_MODE_MAX,
}

enum /*UiMode*/ {
    UI_MODE_SHOW_ALL, // show a heap of ui elements on screen always
    UI_MODE_HIDDEN, // ui still active, but is hidden
    UI_MODE_NONE, // no accessible ui (touch events disabled)
    UI_MODE_MAX,
}

enum /*RenderMode*/ {
    /*RENDER_MODE_BUFFERED_ROTATING = 0,*/
    RENDER_MODE_UNBUFFERED_ROTATING = 1,
    /* RENDER_MODE_BUFFERED_NO_ROTATION = 2,*/
    RENDER_MODE_UNBUFFERED_NO_ROTATION = 3,
    RENDER_MODE_MAX,
}

enum /*RenderMode*/ {
    ALERT_TYPE_TOAST,
    ALERT_TYPE_ALERT,
    ALERT_TYPE_IMAGE,
    ALERT_TYPE_MAX,
}

// we are getting dangerously close to the app settings limit
// was getting "Unable to serialize app data" in the sim, but after a restart worked fine
// see
// https://forums.garmin.com/developer/connect-iq/f/discussion/409127/unable-to-serialize-app-data---watch-app?pifragment-1298=1#pifragment-1298=1
// is seems like this only happened when:
// * I tried to run on instinct 3 (that only has 128kb of memory)
// * Crashed with OOM
// * Then tried running on the venu2s which has enough memory it fails with "Unable to serialize app data"
// * Reset sim app data and remove apps
// * Works fine
class Settings {
    var mode as Number = MODE_NORMAL;
    var elevationMode as Number = ELEVATION_MODE_STACKED;
    
    var trackColour as Number = Graphics.COLOR_GREEN;
    var defaultRouteColour as Number = Graphics.COLOR_BLUE;
    var elevationColour as Number = Graphics.COLOR_ORANGE;
    var userColour as Number = Graphics.COLOR_ORANGE;
    
    // Renders around the users position
    var metersAroundUser as Number = 500; // keep this fairly high by default, too small and the map tiles start to go blurry
    var centerUserOffsetY as Float = 0.5f; // fraction of the screen to move the user down the page 0.5 - user appears in center, 0.75 - user appears 3/4 down the screen. Useful to see more of the route in front of the user.
    var mapMoveScreenSize as Float = 0.3f; // how far to move the map when the user presses on screen buttons, a fraction of the screen size.
    var zoomAtPaceMode as Number = ZOOM_AT_PACE_MODE_PACE;
    var zoomAtPaceSpeedMPS as Float = 1.0; // meters per second
    var uiMode as Number = UI_MODE_SHOW_ALL;
    var fixedLatitude as Float? = null;
    var fixedLongitude as Float? = null;
    
    // see keys below in routes = getArraySchema(...)
    // see oddity with route name and route loading new in context.newRoute
    var routes as Array<Dictionary> = [];
    var routesEnabled as Boolean = true;
    var displayRouteNames as Boolean = true;
    var normalModeColour as Number = Graphics.COLOR_BLUE;
    var uiColour as Number = Graphics.COLOR_DK_GRAY;
    var debugColour as Number = 0xfeffffff; // white, but colour_white results in FFFFFFFF (-1) when we parse it and that is fully transparent
    // I did get up to 4 large routes working with off track alerts, but any more than that and watchdog catches us out, 3 is a safer limit.
    // currently we still load disabled routes into memory, so its also not great having this large and a heap of disabled routes
    private var _routeMax as Number = 3;

    // note this only works if a single track is enabled (multiple tracks would always error)
    var enableOffTrackAlerts as Boolean = true;
    var offTrackAlertsDistanceM as Number = 20;
    var offTrackAlertsMaxReportIntervalS as Number = 60;
    var offTrackCheckIntervalS as Number = 15;
    var alertType as Number = ALERT_TYPE_TOAST;
    var offTrackWrongDirection as Boolean = false;
    var drawCheverons as Boolean = false;

    var drawLineToClosestPoint as Boolean = true;
    var displayLatLong as Boolean = true;

    // scratchpad used for rotations, but it also means we have a large bitmap stored around
    // I will also use that bitmap for re-renders though, and just do rotations every render rather than re-drawing all the tracks/tiles again
    var renderMode as Number = RENDER_MODE_UNBUFFERED_ROTATING;
    // how many seconds should we wait before even considering the next point
    // changes in speed/angle/zoom are not effected by this number. Though maybe they should be?
    var recalculateIntervalS as Number = 5;
    var turnAlertTimeS as Number = -1; // -1 disables the check
    var minTurnAlertDistanceM as Number = -1; // -1 disables the check
    var maxTrackPoints as Number = 400;

    // bunch of debug settings
    var showPoints as Boolean = false;
    var drawLineToClosestTrack as Boolean = false;
    var includeDebugPageInOnScreenUi as Boolean = false;
    var drawHitBoxes as Boolean = false;
    var showDirectionPoints as Boolean = false;
    var showDirectionPointTextUnderIndex as Number = 0;

    // these settings can only be modified externally, but we cache them for faster/easier lookup
    // https://www.youtube.com/watch?v=LasrD6SZkZk&ab_channel=JaylaB
    var distanceImperialUnits as Boolean =
        System.getDeviceSettings().distanceUnits == System.UNIT_STATUTE;
    var elevationImperialUnits as Boolean =
        System.getDeviceSettings().elevationUnits == System.UNIT_STATUTE;

    (:lowMemory)
    function routeMax() as Number {
        return 1; // can only get 1 route (second route crashed on storage save), we also still need space for the track
    }

    (:highMemory)
    function routeMax() as Number {
        return _routeMax;
    }

    function setMode(_mode as Number) as Void {
        mode = _mode;
        // directly set mode, its only for what is displayed, which takes effect ont he next onUpdate
        // we do not want to call view.onSettingsChanged because it clears timestamps when going to the debug page.
        // The setValue method on this class calls the view changed method, so do not call it.
        Application.Properties.setValue("mode", mode);
    }

    (:settingsView)
    function setElevationMode(value as Number) as Void {
        elevationMode = value;
        setValue("elevationMode", elevationMode);
    }

    (:settingsView)
    function setUiMode(_uiMode as Number) as Void {
        uiMode = _uiMode;
        setValue("uiMode", uiMode);
    }

    (:settingsView)
    function setAlertType(_alertType as Number) as Void {
        alertType = _alertType;
        setValue("alertType", alertType);
    }

    (:settingsView)
    function setRenderMode(_renderMode as Number) as Void {
        renderMode = _renderMode;
        setValue("renderMode", renderMode);
        updateCachedValues();
        updateViewSettings();
    }

    function setFixedPositionRaw(lat as Float, long as Float) as Void {
        // hack method so that cached values can update the settings without reloading itself
        // its guaranteed to only be when moving around, and will never go to null
        fixedLatitude = lat;
        fixedLongitude = long;
        Application.Properties.setValue("fixedLatitude", lat);
        Application.Properties.setValue("fixedLongitude", long);
    }

    function setFixedPosition(lat as Float?, long as Float?) as Void {
        // logT("moving to: " + lat + " " + long);
        // be very careful about putting null into properties, it breaks everything
        if (lat == null || !(lat instanceof Float)) {
            lat = 0f;
        }
        if (long == null || !(long instanceof Float)) {
            long = 0f;
        }
        fixedLatitude = lat;
        fixedLongitude = long;
        setValue("fixedLatitude", lat);
        setValue("fixedLongitude", long);

        var latIsBasicallyNull = fixedLatitude == null || fixedLatitude == 0;
        var longIsBasicallyNull = fixedLongitude == null || fixedLongitude == 0;
        if (latIsBasicallyNull || longIsBasicallyNull) {
            fixedLatitude = null;
            fixedLongitude = null;
            updateCachedValues();
            return;
        }

        // we should have a lat and a long at this point
        // updateCachedValues(); already called by the above sets
        // var latlong = RectangularPoint.xyToLatLon(fixedPosition.x, fixedPosition.y);
        // logT("round trip conversion result: " + latlong);
    }

    function setFixedPositionWithoutUpdate(
        lat as Float?,
        long as Float?
    ) as Void {
        // logT("moving to: " + lat + " " + long);
        // be very careful about putting null into properties, it breaks everything
        if (lat == null || !(lat instanceof Float)) {
            lat = 0f;
        }
        if (long == null || !(long instanceof Float)) {
            long = 0f;
        }
        fixedLatitude = lat;
        fixedLongitude = long;
        Application.Properties.setValue("fixedLatitude", lat);
        Application.Properties.setValue("fixedLongitude", long);

        var latIsBasicallyNull = fixedLatitude == null || fixedLatitude == 0;
        var longIsBasicallyNull = fixedLongitude == null || fixedLongitude == 0;
        if (latIsBasicallyNull || longIsBasicallyNull) {
            fixedLatitude = null;
            fixedLongitude = null;
            updateCachedValues();
            return;
        }

        // we should have a lat and a long at this point
        // updateCachedValues(); already called by the above sets
        // var latlong = RectangularPoint.xyToLatLon(fixedPosition.x, fixedPosition.y);
        // logT("round trip conversion result: " + latlong);
    }

    function setValue(key as String, value as PropertyValueType) as Void {
        Application.Properties.setValue(key, value);
        setValueSideEffect();
    }

    function setValueSideEffect() as Void {
        updateCachedValues();
        updateViewSettings();
        updateRouteSettings();
    }

    function setZoomAtPaceMode(_zoomAtPaceMode as Number) as Void {
        zoomAtPaceMode = _zoomAtPaceMode;
        setValue("zoomAtPaceMode", zoomAtPaceMode);
    }

    (:settingsView)
    function setZoomAtPaceSpeedMPS(mps as Float) as Void {
        zoomAtPaceSpeedMPS = mps;
        setValue("zoomAtPaceSpeedMPS", zoomAtPaceSpeedMPS);
    }

    (:settingsView)
    function setMetersAroundUser(value as Number) as Void {
        metersAroundUser = value;
        setValue("metersAroundUser", metersAroundUser);
    }

    (:settingsView)
    function setFixedLatitude(value as Float) as Void {
        setFixedPosition(value, fixedLongitude);
    }

    (:settingsView)
    function setFixedLongitude(value as Float) as Void {
        setFixedPosition(fixedLatitude, value);
    }

    (:settingsView)
    function setTurnAlertTimeS(value as Number) as Void {
        turnAlertTimeS = value;
        setValue("turnAlertTimeS", turnAlertTimeS);
    }

    (:settingsView)
    function setMinTurnAlertDistanceM(value as Number) as Void {
        minTurnAlertDistanceM = value;
        setValue("minTurnAlertDistanceM", minTurnAlertDistanceM);
    }

    (:settingsView)
    function setMaxTrackPoints(value as Number) as Void {
        var oldmaxTrackPoints = maxTrackPoints;
        maxTrackPoints = value;
        if (oldmaxTrackPoints != maxTrackPoints) {
            maxTrackPointsChanged();
        }
        setValue("maxTrackPoints", maxTrackPoints);
    }

    function maxTrackPointsChanged() as Void {
        getApp()._breadcrumbContext.track.coordinates.restrictPointsToMaxMemory(maxTrackPoints);
    }

    (:settingsView)
    function setShowDirectionPointTextUnderIndex(value as Number) as Void {
        showDirectionPointTextUnderIndex = value;
        setValue("showDirectionPointTextUnderIndex", showDirectionPointTextUnderIndex);
    }

    (:settingsView)
    function setOffTrackAlertsDistanceM(value as Number) as Void {
        offTrackAlertsDistanceM = value;
        setValue("offTrackAlertsDistanceM", offTrackAlertsDistanceM);
        updateViewSettings();
    }

    (:settingsView)
    function setOffTrackAlertsMaxReportIntervalS(value as Number) as Void {
        offTrackAlertsMaxReportIntervalS = value;
        setValue("offTrackAlertsMaxReportIntervalS", offTrackAlertsMaxReportIntervalS);
        updateViewSettings();
    }

    (:settingsView)
    function setOffTrackCheckIntervalS(value as Number) as Void {
        offTrackCheckIntervalS = value;
        setValue("offTrackCheckIntervalS", offTrackCheckIntervalS);
        updateViewSettings();
    }

    (:settingsView)
    function setRouteMax(value as Number) as Void {
        var oldRouteMax = _routeMax;
        _routeMax = value;
        if (oldRouteMax > _routeMax) {
            routeMaxReduced();
        }
        setValue("routeMax", _routeMax);
        updateCachedValues();
        updateViewSettings();
    }

    function routeMaxReduced() as Void {
        // remove the first oes or the last ones? we do not have an age, so just remove the last ones.
        var routesToRemove = [] as Array<Number>;
        for (var i = _routeMax; i < routes.size(); ++i) {
            var oldRouteEntry = routes[i];
            var oldRouteId = oldRouteEntry["routeId"] as Number;
            routesToRemove.add(oldRouteId);
        }
        for (var i = 0; i < routesToRemove.size(); ++i) {
            var routeId = routesToRemove[i];
            clearRouteFromContext(routeId);
            // do not use the clear route helper method, it will stack overflow
            var routeIndex = getRouteIndexById(routeId);
            if (routeIndex == null) {
                continue;
            }
            routes.remove(routes[routeIndex]);
        }

        saveRoutesNoSideEffect();
    }

    (:settingsView)
    function setMapMoveScreenSize(value as Float) as Void {
        mapMoveScreenSize = value;
        setValue("mapMoveScreenSize", mapMoveScreenSize);
    }

    (:settingsView)
    function setCenterUserOffsetY(value as Float) as Void {
        centerUserOffsetY = value;
        setValue("centerUserOffsetY", centerUserOffsetY);
    }

    (:settingsView)
    function setRecalculateIntervalS(value as Number) as Void {
        recalculateIntervalS = value;
        recalculateIntervalS = recalculateIntervalS <= 0 ? 1 : recalculateIntervalS;
        setValue("recalculateIntervalS", recalculateIntervalS);
    }

    (:settingsView)
    function setDrawLineToClosestPoint(value as Boolean) as Void {
        drawLineToClosestPoint = value;
        setValue("drawLineToClosestPoint", drawLineToClosestPoint);
        updateViewSettings();
    }

    (:settingsView)
    function setShowPoints(value as Boolean) as Void {
        showPoints = value;
        setValue("showPoints", showPoints);
    }
    (:settingsView)
    function setDrawLineToClosestTrack(value as Boolean) as Void {
        drawLineToClosestTrack = value;
        setValue("drawLineToClosestTrack", drawLineToClosestTrack);
    }
    (:settingsView)
    function setIncludeDebugPageInOnScreenUi(value as Boolean) as Void {
        includeDebugPageInOnScreenUi = value;
        setValue("includeDebugPageInOnScreenUi", includeDebugPageInOnScreenUi);
    }

    (:settingsView)
    function setDrawHitBoxes(value as Boolean) as Void {
        drawHitBoxes = value;
        setValue("drawHitBoxes", drawHitBoxes);
    }

    (:settingsView)
    function setShowDirectionPoints(value as Boolean) as Void {
        showDirectionPoints = value;
        setValue("showDirectionPoints", showDirectionPoints);
    }

    (:settingsView)
    function setDisplayLatLong(value as Boolean) as Void {
        displayLatLong = value;
        setValue("displayLatLong", displayLatLong);
    }
    (:settingsView)
    function setDisplayRouteNames(_displayRouteNames as Boolean) as Void {
        displayRouteNames = _displayRouteNames;
        setValue("displayRouteNames", displayRouteNames);
    }

    function setRoutesEnabled(_routesEnabled as Boolean) as Void {
        routesEnabled = _routesEnabled;
        setValue("routesEnabled", routesEnabled);
    }

    function routeColour(routeId as Number) as Number {
        var routeIndex = getRouteIndexById(routeId);
        if (routeIndex == null) {
            return defaultRouteColour;
        }

        return routes[routeIndex]["colour"] as Number;
    }

    // see oddity with route name and route loading new in context.newRoute
    function routeName(routeId as Number) as String {
        var routeIndex = getRouteIndexById(routeId);
        if (routeIndex == null) {
            return "";
        }

        return routes[routeIndex]["name"] as String;
    }

    (:storage)
    function atLeast1RouteEnabled() as Boolean {
        if (!routesEnabled) {
            return false;
        }

        for (var i = 0; i < routes.size(); ++i) {
            var route = routes[i];
            if (route["enabled"]) {
                return true;
            }
        }

        return false;
    }

    function routeEnabled(routeId as Number) as Boolean {
        if (!routesEnabled) {
            return false;
        }

        var routeIndex = getRouteIndexById(routeId);
        if (routeIndex == null) {
            return false;
        }
        return routes[routeIndex]["enabled"] as Boolean;
    }

    function routeReversed(routeId as Number) as Boolean {
        var routeIndex = getRouteIndexById(routeId);
        if (routeIndex == null) {
            return false;
        }
        return routes[routeIndex]["reversed"] as Boolean;
    }

    function setRouteColour(routeId as Number, value as Number) as Void {
        ensureRouteId(routeId);
        var routeIndex = getRouteIndexById(routeId);
        if (routeIndex == null) {
            return;
        }

        routes[routeIndex]["colour"] = value;
        saveRoutes();
    }

    // see oddity with route name and route loading new in context.newRoute
    function setRouteName(routeId as Number, value as String) as Void {
        ensureRouteId(routeId);
        var routeIndex = getRouteIndexById(routeId);
        if (routeIndex == null) {
            return;
        }

        routes[routeIndex]["name"] = value;
        saveRoutes();
    }

    function setRouteEnabled(routeId as Number, value as Boolean) as Void {
        ensureRouteId(routeId);
        var routeIndex = getRouteIndexById(routeId);
        if (routeIndex == null) {
            return;
        }

        routes[routeIndex]["enabled"] = value;
        saveRoutes();
        updateViewSettings(); // routes enabled/disabled can effect off track alerts and other view renderring
    }

    function setRouteReversed(routeId as Number, value as Boolean) as Void {
        ensureRouteId(routeId);
        var routeIndex = getRouteIndexById(routeId);
        if (routeIndex == null) {
            return;
        }

        var oldVal = routes[routeIndex]["reversed"];
        if (oldVal != value) {
            getApp()._breadcrumbContext.reverseRouteId(routeId);
        }
        routes[routeIndex]["reversed"] = value;
        saveRoutes();
        updateViewSettings();
    }

    function ensureRouteId(routeId as Number) as Void {
        var routeIndex = getRouteIndexById(routeId);
        if (routeIndex != null) {
            return;
        }

        if (routes.size() >= _routeMax) {
            return;
        }

        routes.add({
            "routeId" => routeId,
            "name" => routeName(routeId),
            "enabled" => true,
            "colour" => routeColour(routeId),
            "reversed" => routeReversed(routeId),
        });
        saveRoutes();
    }

    function getRouteIndexById(routeId as Number) as Number? {
        for (var i = 0; i < routes.size(); ++i) {
            var route = routes[i];
            if (route["routeId"] == routeId) {
                return i;
            }
        }

        return null;
    }

    function clearRoutes() as Void {
        routes = [];
        saveRoutes();
    }
    
    function clearRoute(routeId as Number) as Void {
        var routeIndex = getRouteIndexById(routeId);
        if (routeIndex == null) {
            return;
        }
        routes.remove(routes[routeIndex]);
        saveRoutes();
    }

    function routesToSave() as Array<Dictionary<String, PropertyValueType> > {
        var toSave = [] as Array<Dictionary<String, PropertyValueType> >;
        for (var i = 0; i < routes.size(); ++i) {
            var entry = routes[i];
            var toAdd =
                ({
                    "routeId" => entry["routeId"] as Number,
                    "name" => entry["name"] as String,
                    "enabled" => entry["enabled"] as Boolean,
                    "colour" => (entry["colour"] as Number).format("%X"), // this is why we have to copy it :(
                    "reversed" => entry["reversed"] as Boolean,
                }) as Dictionary<String, PropertyValueType>;
            toSave.add(toAdd);
        }
        return toSave;
    }

    function saveRoutes() as Void {
        saveRoutesNoSideEffect();
        setValueSideEffect();
    }

    function saveRoutesNoSideEffect() as Void {
        var toSave = routesToSave();
        // note toSave is Array<Dictionary<String, PropertyValueType>>
        // but the compiler only allows "Array<PropertyValueType>" even though the array of dicts seems to work on sim and real watch
        safeSetStorage(
            "routes",
            toSave as Array<PropertyValueType>
        );
    }

    (:settingsView)
    function setTrackColour(value as Number) as Void {
        trackColour = value;
        setValue("trackColour", trackColour.format("%X"));
    }

    (:settingsView)
    function setDefaultRouteColour(value as Number) as Void {
        defaultRouteColour = value;
        setValue("defaultRouteColour", defaultRouteColour.format("%X"));
    }

    (:settingsView)
    function setUserColour(value as Number) as Void {
        userColour = value;
        setValue("userColour", userColour.format("%X"));
    }

    (:settingsView)
    function setNormalModeColour(value as Number) as Void {
        normalModeColour = value;
        setValue("normalModeColour", normalModeColour.format("%X"));
    }

    (:settingsView)
    function setDebugColour(value as Number) as Void {
        debugColour = value;
        setValue("debugColour", debugColour.format("%X"));
    }

    (:settingsView)
    function setUiColour(value as Number) as Void {
        uiColour = value;
        setValue("uiColour", uiColour.format("%X"));
    }

    (:settingsView)
    function setElevationColour(value as Number) as Void {
        elevationColour = value;
        setValue("elevationColour", elevationColour.format("%X"));
    }

    (:settingsView)
    function toggleDrawLineToClosestPoint() as Void {
        drawLineToClosestPoint = !drawLineToClosestPoint;
        setValue("drawLineToClosestPoint", drawLineToClosestPoint);
    }
    (:settingsView)
    function toggleShowPoints() as Void {
        showPoints = !showPoints;
        setValue("showPoints", showPoints);
    }
    (:settingsView)
    function toggleDrawLineToClosestTrack() as Void {
        drawLineToClosestTrack = !drawLineToClosestTrack;
        setValue("drawLineToClosestTrack", drawLineToClosestTrack);
    }
    (:settingsView)
    function toggleIncludeDebugPageInOnScreenUi() as Void {
        includeDebugPageInOnScreenUi = !includeDebugPageInOnScreenUi;
        setValue("includeDebugPageInOnScreenUi", includeDebugPageInOnScreenUi);
    }
    (:settingsView)
    function toggleDrawHitBoxes() as Void {
        drawHitBoxes = !drawHitBoxes;
        setValue("drawHitBoxes", drawHitBoxes);
    }
    (:settingsView)
    function toggleShowDirectionPoints() as Void {
        showDirectionPoints = !showDirectionPoints;
        setValue("showDirectionPoints", showDirectionPoints);
    }
    (:settingsView)
    function toggleDisplayLatLong() as Void {
        displayLatLong = !displayLatLong;
        setValue("displayLatLong", displayLatLong);
    }
    (:settingsView)
    function toggleDisplayRouteNames() as Void {
        displayRouteNames = !displayRouteNames;
        setValue("displayRouteNames", displayRouteNames);
    }
    (:settingsView)
    function toggleEnableOffTrackAlerts() as Void {
        enableOffTrackAlerts = !enableOffTrackAlerts;
        setValue("enableOffTrackAlerts", enableOffTrackAlerts);
    }
    (:settingsView)
    function toggleOffTrackWrongDirection() as Void {
        offTrackWrongDirection = !offTrackWrongDirection;
        setValue("offTrackWrongDirection", offTrackWrongDirection);
    }
    (:settingsView)
    function toggleDrawCheverons() as Void {
        drawCheverons = !drawCheverons;
        setValue("drawCheverons", drawCheverons);
    }
    (:settingsView)
    function toggleRoutesEnabled() as Void {
        routesEnabled = !routesEnabled;
        setValue("routesEnabled", routesEnabled);
    }

    function nextMode() as Void {
        // logT("mode cycled");
        // could just add one and check if over MODE_MAX?
        mode++;
        if (mode >= MODE_MAX) {
            mode = MODE_NORMAL;
        }

        if (mode == MODE_DEBUG && !includeDebugPageInOnScreenUi) {
            nextMode();
        }

        setMode(mode);
    }

    function nextZoomAtPaceMode() as Void {
        if (mode != MODE_NORMAL) {
            return;
        }

        // could also do this? not sure what better for perf (probably the modulo 1 less instruction), below is more readable
        // zoomAtPaceMode = (zoomAtPaceMode + 1) % ZOOM_AT_PACE_MODE_MAX;
        zoomAtPaceMode++;
        if (zoomAtPaceMode >= ZOOM_AT_PACE_MODE_MAX) {
            zoomAtPaceMode = ZOOM_AT_PACE_MODE_PACE;
        }

        setZoomAtPaceMode(zoomAtPaceMode);
    }

    function updateViewSettings() as Void {
        getApp()._view.onSettingsChanged();
    }

    function updateRouteSettings() as Void {
        var contextRoutes = getApp()._breadcrumbContext.routes;
        for (var i = 0; i < contextRoutes.size(); ++i) {
            var route = contextRoutes[i];
            // we do not care if its curently disabled, nuke the data anyway
            // if (!routeEnabled(route.storageIndex)) {
            //     continue;
            // }
            // todo only call this if setting sthat effect it changed, taking nuclear approach for now
            route.settingsChanged();
        }
    }

    function updateCachedValues() as Void {
        getApp()._breadcrumbContext.cachedValues.recalculateAll();
    }

    function clearContextRoutes() as Void {
        getApp()._breadcrumbContext.clearRoutes();
    }

    function clearRouteFromContext(routeId as Number) as Void {
        getApp()._breadcrumbContext.clearRouteId(routeId);
    }

    function purgeRoutesFromContext() as Void {
        getApp()._breadcrumbContext.purgeRoutes();
    }

    // some times these parserswere throwing when it was an empty strings seem to result in, or wrong type
    //
    // Error: Unhandled Exception
    // Exception: UnexpectedTypeException: Expected Number/Float/Long/Double/Char, given null/Number
    function parseColour(key as String, defaultValue as Number) as Number {
        try {
            return parseColourRaw(key, Application.Properties.getValue(key), defaultValue);
        } catch (e) {
            logE("Error parsing float: " + key);
        }
        return defaultValue;
    }

    static function parseColourRaw(
        key as String,
        colourString as PropertyValueType,
        defaultValue as Number
    ) as Number {
        try {
            if (colourString == null) {
                return defaultValue;
            }

            if (colourString instanceof String) {
                // want final string as AARRGGBB
                // colourString = padStart(colourString, 6, '0'); // fill in 24 bit colour with 0's
                // colourString = padStart(colourString, 8, 'F'); // pad alpha channel with FF
                // empty or invalid strings convert to null
                // anything with leading FF (when 8 characters supplied) needs to be a long, because its too big to fit in Number
                // if a user chooses FFFFFFFF (white) it is (-1) which is fully transparent, should choose FFFFFF (no alpha) or something close like FFFFFFFE
                // in any case we are currently ignoring alpha because we use setColor (text does not support alpha)
                var long = colourString.toLongWithBase(16);
                if (long == null) {
                    return defaultValue;
                }

                // calling tonumber breaks - because its out of range, but we need to set the alpha bits
                var number = (long & 0xffffffffl).toNumber();
                if (number == 0xffffffff) {
                    // -1 is transparent and will not render
                    number = 0xfeffffff;
                }
                return number;
            }

            return parseNumberRaw(key, colourString, defaultValue);
        } catch (e) {
            logE("Error parsing colour: " + key + " " + colourString);
        }
        return defaultValue;
    }

    function parseNumber(key as String, defaultValue as Number) as Number {
        try {
            return parseNumberRaw(key, Application.Properties.getValue(key), defaultValue);
        } catch (e) {
            logE("Error parsing float: " + key);
        }
        return defaultValue;
    }

    static function parseNumberRaw(
        key as String,
        value as PropertyValueType,
        defaultValue as Number
    ) as Number {
        try {
            if (value == null) {
                return defaultValue;
            }

            if (
                value instanceof String ||
                value instanceof Float ||
                value instanceof Number ||
                value instanceof Double
            ) {
                // empty or invalid strings convert to null
                var ret = value.toNumber();
                if (ret == null) {
                    return defaultValue;
                }

                return ret;
            }

            return defaultValue;
        } catch (e) {
            logE("Error parsing number: " + key + " " + value);
        }
        return defaultValue;
    }

    function parseBool(key as String, defaultValue as Boolean) as Boolean {
        try {
            return parseBoolRaw(key, Application.Properties.getValue(key), defaultValue);
        } catch (e) {
            logE("Error parsing bool: " + key);
        }
        return defaultValue;
    }

    function parseBoolRaw(
        key as String,
        value as PropertyValueType,
        defaultValue as Boolean
    ) as Boolean {
        try {
            if (value == null) {
                return false;
            }

            if (value instanceof String) {
                return (
                    value.equals("") ||
                    value.equals("false") ||
                    value.equals("False") ||
                    value.equals("FALSE") ||
                    value.equals("0")
                );
            }

            if (!(value instanceof Boolean)) {
                return false;
            }

            return value;
        } catch (e) {
            logE("Error parsing bool: " + key + " " + value);
        }
        return defaultValue;
    }

    function parseFloat(key as String, defaultValue as Float) as Float {
        try {
            return parseFloatRaw(key, Application.Properties.getValue(key), defaultValue);
        } catch (e) {
            logE("Error parsing float: " + key);
        }
        return defaultValue;
    }

    static function parseFloatRaw(
        key as String,
        value as PropertyValueType,
        defaultValue as Float
    ) as Float {
        try {
            if (value == null) {
                return defaultValue;
            }

            if (
                value instanceof String ||
                value instanceof Float ||
                value instanceof Number ||
                value instanceof Double
            ) {
                // empty or invalid strings convert to null
                var ret = value.toFloat();
                if (ret == null) {
                    return defaultValue;
                }

                return ret;
            }

            return defaultValue;
        } catch (e) {
            logE("Error parsing float: " + key + " " + value);
        }
        return defaultValue;
    }

    function parseString(key as String, defaultValue as String) as String {
        try {
            return parseStringRaw(key, Application.Properties.getValue(key), defaultValue);
        } catch (e) {
            logE("Error parsing string: " + key);
        }
        return defaultValue;
    }

    function parseStringRaw(
        key as String,
        value as PropertyValueType,
        defaultValue as String
    ) as String {
        try {
            if (value == null) {
                return defaultValue;
            }

            if (value instanceof String) {
                return value;
            }

            return defaultValue;
        } catch (e) {
            logE("Error parsing string: " + key + " " + value);
        }
        return defaultValue;
    }

    function parseOptionalFloat(key as String, defaultValue as Float?) as Float? {
        try {
            return parseOptionalFloatRaw(key, Application.Properties.getValue(key), defaultValue);
        } catch (e) {
            logE("Error parsing optional float: " + key);
        }
        return defaultValue;
    }

    function parseOptionalFloatRaw(
        key as String,
        value as PropertyValueType,
        defaultValue as Float?
    ) as Float? {
        try {
            if (value == null) {
                return null;
            }

            // as Float is a bit of a hack, it can be null, but we just want allow us to use our helper
            // (duck typing means at runtime the null passes through fine)
            return parseFloatRaw(key, value, defaultValue as Float);
        } catch (e) {
            logE("Error parsing optional float: " + key);
        }
        return defaultValue;
    }

    function getArraySchema(
        key as String,
        expectedKeys as Array<String>,
        parsers as Array<Method>,
        defaultValue as Array<Dictionary>
    ) as Array<Dictionary> {
        var value = null;
        try {
            value = Application.Storage.getValue(key);
            if (value == null) {
                return defaultValue;
            }

            if (!(value instanceof Array)) {
                return defaultValue;
            }

            // The dict we get is memory mapped, do not use it directly - need to create a copy so we can change the colour type from string to int
            // If we use it directly the storage value gets overwritten
            var result = [] as Array<Dictionary>;
            for (var i = 0; i < value.size(); ++i) {
                var entry = value[i];
                var entryOut = {};
                if (!(entry instanceof Dictionary)) {
                    return defaultValue;
                }

                for (var j = 0; j < expectedKeys.size(); ++j) {
                    var thisKey = expectedKeys[j];
                    var thisParser = parsers[j];
                    if (!entry.hasKey(thisKey)) {
                        return defaultValue;
                    }

                    entryOut[thisKey] = thisParser.invoke(
                        key + "." + i + "." + thisKey,
                        entry[thisKey]
                    );
                }
                result.add(entryOut);
            }

            return result;
        } catch (e) {
            logE("Error parsing array: " + key + " " + value);
        }
        return defaultValue;
    }

    function resetDefaults() as Void {
        logT("Resetting settings to default values");
        // clear the flag first thing in case of crash we do not want to try clearing over and over
        setValue("resetDefaults", false);

        // note: this pulls the defaults from whatever we have at the top of the file these may differ from the defaults in properties.xml
        var defaultSettings = new Settings();
        turnAlertTimeS = defaultSettings.turnAlertTimeS;
        minTurnAlertDistanceM = defaultSettings.minTurnAlertDistanceM;
        maxTrackPoints = defaultSettings.maxTrackPoints;
        showDirectionPointTextUnderIndex = defaultSettings.showDirectionPointTextUnderIndex;
        centerUserOffsetY = defaultSettings.centerUserOffsetY;
        mapMoveScreenSize = defaultSettings.mapMoveScreenSize;
        drawLineToClosestPoint = defaultSettings.drawLineToClosestPoint;
        showPoints = defaultSettings.showPoints;
        drawLineToClosestTrack = defaultSettings.drawLineToClosestTrack;
        includeDebugPageInOnScreenUi = defaultSettings.includeDebugPageInOnScreenUi;
        drawHitBoxes = defaultSettings.drawHitBoxes;
        showDirectionPoints = defaultSettings.showDirectionPoints;
        displayLatLong = defaultSettings.displayLatLong;
        trackColour = defaultSettings.trackColour;
        defaultRouteColour = defaultSettings.defaultRouteColour;
        elevationColour = defaultSettings.elevationColour;
        userColour = defaultSettings.userColour;
        metersAroundUser = defaultSettings.metersAroundUser;
        zoomAtPaceMode = defaultSettings.zoomAtPaceMode;
        zoomAtPaceSpeedMPS = defaultSettings.zoomAtPaceSpeedMPS;
        uiMode = defaultSettings.uiMode;
        elevationMode = defaultSettings.elevationMode;
        alertType = defaultSettings.alertType;
        renderMode = defaultSettings.renderMode;
        fixedLatitude = defaultSettings.fixedLatitude;
        fixedLongitude = defaultSettings.fixedLongitude;
        routes = defaultSettings.routes;
        routesEnabled = defaultSettings.routesEnabled;
        displayRouteNames = defaultSettings.displayRouteNames;
        enableOffTrackAlerts = defaultSettings.enableOffTrackAlerts;
        offTrackWrongDirection = defaultSettings.offTrackWrongDirection;
        drawCheverons = defaultSettings.drawCheverons;
        offTrackAlertsDistanceM = defaultSettings.offTrackAlertsDistanceM;
        offTrackAlertsMaxReportIntervalS = defaultSettings.offTrackAlertsMaxReportIntervalS;
        offTrackCheckIntervalS = defaultSettings.offTrackCheckIntervalS;
        _routeMax = defaultSettings.routeMax();
        normalModeColour = defaultSettings.normalModeColour;
        uiColour = defaultSettings.uiColour;
        debugColour = defaultSettings.debugColour;

        // raw write the settings to disk
        var dict = asDict();
        saveSettings(dict);

        // purge storage, all routes and caches
        Application.Storage.clearValues();
        purgeRoutesFromContext();
        updateCachedValues();
        updateViewSettings();
    }

    function asDict() as Dictionary<String, PropertyValueType> {
        // all these return values should be identical to the storage value
        // eg. nulls are exposed as 0
        // colours are strings

        return (
            ({
                "turnAlertTimeS" => turnAlertTimeS,
                "minTurnAlertDistanceM" => minTurnAlertDistanceM,
                "maxTrackPoints" => maxTrackPoints,
                "showDirectionPointTextUnderIndex" => showDirectionPointTextUnderIndex,
                "centerUserOffsetY" => centerUserOffsetY,
                "mapMoveScreenSize" => mapMoveScreenSize,
                "recalculateIntervalS" => recalculateIntervalS,
                "mode" => mode,
                "drawLineToClosestPoint" => drawLineToClosestPoint,
                "showPoints" => showPoints,
                "drawLineToClosestTrack" => drawLineToClosestTrack,
                "includeDebugPageInOnScreenUi" => includeDebugPageInOnScreenUi,
                "drawHitBoxes" => drawHitBoxes,
                "showDirectionPoints" => showDirectionPoints,
                "displayLatLong" => displayLatLong,
                "trackColour" => trackColour.format("%X"),
                "defaultRouteColour" => defaultRouteColour.format("%X"),
                "elevationColour" => elevationColour.format("%X"),
                "userColour" => userColour.format("%X"),
                "metersAroundUser" => metersAroundUser,
                "zoomAtPaceMode" => zoomAtPaceMode,
                "zoomAtPaceSpeedMPS" => zoomAtPaceSpeedMPS,
                "uiMode" => uiMode,
                "elevationMode" => elevationMode,
                "alertType" => alertType,
                "renderMode" => renderMode,
                "fixedLatitude" => fixedLatitude == null ? 0f : fixedLatitude,
                "fixedLongitude" => fixedLongitude == null ? 0f : fixedLongitude,
                "routes" => routesToSave(),
                "routesEnabled" => routesEnabled,
                "displayRouteNames" => displayRouteNames,
                "enableOffTrackAlerts" => enableOffTrackAlerts,
                "offTrackWrongDirection" => offTrackWrongDirection,
                "drawCheverons" => drawCheverons,
                "offTrackAlertsDistanceM" => offTrackAlertsDistanceM,
                "offTrackAlertsMaxReportIntervalS" => offTrackAlertsMaxReportIntervalS,
                "offTrackCheckIntervalS" => offTrackCheckIntervalS,
                "normalModeColour" => normalModeColour.format("%X"),
                "routeMax" => _routeMax,
                "uiColour" => uiColour.format("%X"),
                "debugColour" => debugColour.format("%X"),
                "resetDefaults" => false,
            }) as Dictionary<String, PropertyValueType>
        );
    }

    function saveSettings(settings as Dictionary<String, PropertyValueType>) as Void {
        // should we sanitize this as its untrusted? makes it significantly more annoying to do
        var keys = settings.keys();
        for (var i = 0; i < keys.size(); ++i) {
            var key = keys[i] as Application.PropertyKeyType;
            var value = settings[key];
            // for now just blindly trust the users
            // we do reload which sanitizes, but they could break garmins settings page with unexpected types
            try {
                if (key.equals("routes")) {
                    Application.Storage.setValue(
                        key,
                        value as Dictionary<PropertyKeyType, PropertyValueType>
                    );
                } else {
                    Application.Properties.setValue(key, value as PropertyValueType);
                }
            } catch (e) {
                logE("failed property save: " + e.getErrorMessage() + " " + key + ":" + value);
                ++$.globalExceptionCounter;
            }
        }
    }

    function setup() as Void {
        // assert the map choice when we load the settings, as it may have been changed when the app was not running and onSettingsChanged might not be called
        loadSettings();
    }

    function loadSettingsPart1() as Void {
        turnAlertTimeS = parseNumber("turnAlertTimeS", turnAlertTimeS);
        minTurnAlertDistanceM = parseNumber("minTurnAlertDistanceM", minTurnAlertDistanceM);
        maxTrackPoints = parseNumber("maxTrackPoints", maxTrackPoints);
        showDirectionPointTextUnderIndex = parseNumber(
            "showDirectionPointTextUnderIndex",
            showDirectionPointTextUnderIndex
        );
        centerUserOffsetY = parseFloat("centerUserOffsetY", centerUserOffsetY);
        mapMoveScreenSize = parseFloat("mapMoveScreenSize", mapMoveScreenSize);
        recalculateIntervalS = parseNumber("recalculateIntervalS", recalculateIntervalS);
        recalculateIntervalS = recalculateIntervalS <= 0 ? 1 : recalculateIntervalS;
        mode = parseNumber("mode", mode);
        drawLineToClosestPoint = parseBool("drawLineToClosestPoint", drawLineToClosestPoint);
        showPoints = parseBool("showPoints", showPoints);
        drawLineToClosestTrack = parseBool("drawLineToClosestTrack", drawLineToClosestTrack);
        includeDebugPageInOnScreenUi = parseBool(
            "includeDebugPageInOnScreenUi",
            includeDebugPageInOnScreenUi
        );
        drawHitBoxes = parseBool("drawHitBoxes", drawHitBoxes);
        showDirectionPoints = parseBool("showDirectionPoints", showDirectionPoints);
        displayLatLong = parseBool("displayLatLong", displayLatLong);
        displayRouteNames = parseBool("displayRouteNames", displayRouteNames);
        enableOffTrackAlerts = parseBool("enableOffTrackAlerts", enableOffTrackAlerts);
        offTrackWrongDirection = parseBool("offTrackWrongDirection", offTrackWrongDirection);
        drawCheverons = parseBool("drawCheverons", drawCheverons);
        routesEnabled = parseBool("routesEnabled", routesEnabled);
        trackColour = parseColour("trackColour", trackColour);
        defaultRouteColour = parseColour("defaultRouteColour", defaultRouteColour);
        elevationColour = parseColour("elevationColour", elevationColour);
        userColour = parseColour("userColour", userColour);
        normalModeColour = parseColour("normalModeColour", normalModeColour);
    }

    function loadSettingsPart2() as Void {
        _routeMax = parseColour("routeMax", _routeMax);
        uiColour = parseColour("uiColour", uiColour);
        debugColour = parseColour("debugColour", debugColour);
        metersAroundUser = parseNumber("metersAroundUser", metersAroundUser);
        zoomAtPaceMode = parseNumber("zoomAtPaceMode", zoomAtPaceMode);
        zoomAtPaceSpeedMPS = parseFloat("zoomAtPaceSpeedMPS", zoomAtPaceSpeedMPS);
        uiMode = parseNumber("uiMode", uiMode);
        elevationMode = parseNumber("elevationMode", elevationMode);
        alertType = parseNumber("alertType", alertType);
        renderMode = parseNumber("renderMode", renderMode);

        fixedLatitude = parseOptionalFloat("fixedLatitude", fixedLatitude);
        fixedLongitude = parseOptionalFloat("fixedLongitude", fixedLongitude);
        setFixedPositionWithoutUpdate(fixedLatitude, fixedLongitude);
        routes = getArraySchema(
            "routes",
            ["routeId", "name", "enabled", "colour", "reversed"],
            [
                method(:defaultNumberParser),
                method(:emptyString),
                method(:defaultFalse),
                method(:defaultColourParser),
                method(:defaultFalse),
            ],
            routes
        );
        logT("parsed routes: " + routes);
        offTrackAlertsDistanceM = parseNumber("offTrackAlertsDistanceM", offTrackAlertsDistanceM);
        offTrackAlertsMaxReportIntervalS = parseNumber(
            "offTrackAlertsMaxReportIntervalS",
            offTrackAlertsMaxReportIntervalS
        );
        offTrackCheckIntervalS = parseNumber("offTrackCheckIntervalS", offTrackCheckIntervalS);
    }

    // Load the values initially from storage
    function loadSettings() as Void {
        // fix for a garmin bug where bool settings are not changable if they default to true
        // https://forums.garmin.com/developer/connect-iq/i/bug-reports/bug-boolean-properties-with-default-value-true-can-t-be-changed-in-simulator
        var haveDoneFirstLoadSetup = Application.Properties.getValue("haveDoneFirstLoadSetup");
        if (haveDoneFirstLoadSetup instanceof Boolean && !haveDoneFirstLoadSetup) {
            setValue("haveDoneFirstLoadSetup", true);
            resetDefaults(); // pulls from our defaults
        }

        var resetDefaults = Application.Properties.getValue("resetDefaults") as Boolean;
        if (resetDefaults) {
            resetDefaults();
            return;
        }

        var returnToUser = Application.Properties.getValue("returnToUser") as Boolean;
        if (returnToUser) {
            Application.Properties.setValue("returnToUser", false);
            getApp()._breadcrumbContext.cachedValues.returnToUser();
        }

        logT("loadSettings: Loading all settings");
        loadSettingsPart1();
        loadSettingsPart2();

        // testing coordinates (piper-comanche-wreck)
        // setFixedPosition(-27.297773, 152.753883);
        // // cachedValues.setScale(0.39); // zoomed out a bit
        // cachedValues.setScale(1.96); // really close
    }

    function emptyString(key as String, value as PropertyValueType) as String {
        return parseStringRaw(key, value, "");
    }

    function defaultNumberParser(key as String, value as PropertyValueType) as Number {
        return parseNumberRaw(key, value, 0);
    }

    function defaultFalse(key as String, value as PropertyValueType) as Boolean {
        if (value instanceof Boolean) {
            return value;
        }

        return false;
    }

    function defaultColourParser(key as String, value as PropertyValueType) as Number {
        return parseColourRaw(key, value, Graphics.COLOR_RED);
    }

    function onSettingsChanged() as Void {
        logT("onSettingsChanged: Setting Changed, loading");
        var oldRoutes = routes;
        var oldRouteMax = _routeMax;
        var oldMaxTrackPoints = maxTrackPoints;
        loadSettings();
        // route settins do not work because garmins setting spage cannot edit them
        // when any property is modified, so we have to explain to users not to touch the settings, but we cannot because it looks
        // like garmmins settings are not rendering desciptions anymore :(
        for (var i = 0; i < oldRoutes.size(); ++i) {
            var oldRouteEntry = oldRoutes[i];
            var oldRouteId = oldRouteEntry["routeId"] as Number;

            var routeIndex = getRouteIndexById(oldRouteId);
            if (routeIndex != null) {
                // we have the same route
                if (oldRouteEntry["reversed"] != routes[routeIndex]["reversed"]) {
                    getApp()._breadcrumbContext.reverseRouteId(oldRouteId);
                }

                continue;
            }

            // clear the route
            clearRouteFromContext(oldRouteId);
        }

        if (oldRouteMax > _routeMax) {
            routeMaxReduced();
        }

        if (oldMaxTrackPoints != maxTrackPoints) {
            maxTrackPointsChanged();
        }

        setValueSideEffect();
    }
}

// As the number of settings and number of cached variables updated are increasing stack overflows are becoming more common
// I think the main issue is the setBlah methods are meant to be used for on app settings, so they all call into setValue()
// but we need to not do that when we are comming from the context of onSettingsChanged, since we manually call the updateCachedValues at the end of onSettingsChanged

// Error: Stack Overflow Error
// Details: 'Failed invoking <symbol>'
// Time: 2025-05-14T11:00:57Z
// Part-Number: 006-B3704-00
// Firmware-Version: '19.05'
// Language-Code: eng
// ConnectIQ-Version: 5.1.1
// Filename: BreadcrumbDataField
// Appname: BreadcrumbDataField
// Stack:
//   - pc: 0x10002541
//     File: 'BreadcrumbDataField\source\Settings.mc'
//     Line: 875
//     Function: getRouteIndexById
//   - pc: 0x100024ef
//     File: 'BreadcrumbDataField\source\Settings.mc'
//     Line: 813
//     Function: routeEnabled
//   - pc: 0x10008ec0
//     File: 'BreadcrumbDataField\source\CachedValues.mc'
//     Line: 114
//     Function: calcOuterBoundingBoxFromTrackAndRoutes
//   - pc: 0x1000833a
//     File: 'BreadcrumbDataField\source\CachedValues.mc'
//     Line: 170
//     Function: getNewScaleAndUpdateCenter
//   - pc: 0x100092f2
//     File: 'BreadcrumbDataField\source\CachedValues.mc'
//     Line: 128
//     Function: updateScaleCenterAndMap
//   - pc: 0x100093c8
//     File: 'BreadcrumbDataField\source\CachedValues.mc'
//     Line: 440
//     Function: recalculateAll
//   - pc: 0x100043d6
//     File: 'BreadcrumbDataField\source\Settings.mc'
//     Line: 1169
//     Function: updateCachedValues
//   - pc: 0x10004359
//     File: 'BreadcrumbDataField\source\Settings.mc'
//     Line: 417
//     Function: setValue
//   - pc: 0x10002a86
//     File: 'BreadcrumbDataField\source\Settings.mc'
//     Line: 649
//     Function: setTileLayerMax
//   - pc: 0x10003948
//     File: 'BreadcrumbDataField\source\Settings.mc'
//     Line: 541
//     Function: updateMapChoiceChange
//   - pc: 0x10003ff6
//     File: 'BreadcrumbDataField\source\Settings.mc'
//     Line: 428
//     Function: setMapChoice
//   - pc: 0x10001e3e
//     File: 'BreadcrumbDataField\source\Settings.mc'
//     Line: 1817
//     Function: onSettingsChanged
//   - pc: 0x10006d39
//     File: 'BreadcrumbDataField\source\BreadcrumbDataFieldApp.mc'
//     Line: 253
//     Function: onPhone
