import Toybox.Application;
import Toybox.Lang;
import Toybox.Graphics;
import Toybox.System;

enum /*Mode*/ {
  MODE_NORMAL,
  MODE_ELEVATION,
  MODE_MAP_MOVE,
  MODE_DEBUG,
  MODE_MAX,
}

enum /*ZoomMode*/ {
  ZOOM_AT_PACE_MODE_PACE,
  ZOOM_AT_PACE_MODE_STOPPED,
  ZOOM_AT_PACE_MODE_NEVER_ZOOM,
  ZOOM_AT_PACE_MODE_ALWAYS_ZOOM,
  ZOOM_AT_PACE_MODE_MAX,
}

enum /*UiMode*/ {
  UI_MODE_SHOW_ALL, // show a heap of ui elements on screen always
  UI_MODE_HIDDEN, // ui still active, but is hidden
  UI_MODE_NONE, // no accessible ui (touch events disabled)
  UI_MODE_MAX
}

enum /*RenderMode*/ {
  RENDER_MODE_BUFFERED_ROTATING,
  RENDER_MODE_UNBUFFERED_ROTATING,
  RENDER_MODE_BUFFERED_NO_ROTATION,
  RENDER_MODE_UNBUFFERED_NO_ROTATION,
  RENDER_MODE_MAX,
}

const COMPANION_APP_TILE_URL = "http://127.0.0.1:8080";

class Settings {
    // should be a multiple of 256 (since thats how tiles are stored, though the companion app will render them scaled for you)
    // we will support rounding up though. ie. if we use 50 the 256 tile will be sliced into 6 chunks on the phone, this allows us to support more pixel sizes. 
    // so math.ceil should be used what figuring out how many meters a tile is.
    // eg. maybe we cannot do 128 but we can do 120 (this would limit the number of tiles, but the resolution would be slightly off)
    var tileSize as Number = 64;
    // website says: Worldwide, Zoom to 17. (Zoom limited to 15 on website opentopomap.org)
    // real world test showed 17 produced errors (maybe you need to be authed to get this?)
    var tileLayerMax as Number = 15;
    var tileLayerMin as Number = 2;
    // there is both a memory limit to the number of tiles we can store, as well as a storage limit
    // for now this is both, though we may be able to store more than we can in memory 
    // so we could use the storage as a tile cache, and revert to loading from there, as it would be much faster than 
    // fetching over bluetooth
    // not sure if we can even store bitmaps into storage, it says only BitmapResource
    // id have to serialise it to an array and back out (might not be too hard)
    // 64 is enough to render outside the screen a bit 64*64 tiles with 64 tiles gives us 512*512 worth of pixel data
    var tileCacheSize as Number = 64; // represented in number of tiles, parsed from a string eg. "64"=64tiles, "100KB"=100/2Kb per tile = 50 
    var mode as Number = MODE_NORMAL;
    // todo clear tile cache when this changes
    var mapEnabled as Boolean = false;
    var trackColour as Number = Graphics.COLOR_GREEN;
    var elevationColour as Number = Graphics.COLOR_ORANGE;
    var userColour as Number = Graphics.COLOR_ORANGE;
    // this should probably be the same as tileCacheSize? since there is no point hadving 20 outstanding if we can only store 10 of them
    var maxPendingWebRequests as Number = 100;
    var scale as Float or Null = null;
    // note: this renders around the users position, but may result in a
    // different zoom level `scale` is set
    var metersAroundUser as Number = 100;
    var zoomAtPaceMode as Number = ZOOM_AT_PACE_MODE_PACE;
    var zoomAtPaceSpeedMPS as Float = 1.0; // meters per second
    var uiMode as Number = UI_MODE_SHOW_ALL;
    var fixedLatitude as Float or Null = null;
    var fixedLongitude as Float or Null = null;
    // supports place holders such as 
    // use http://127.0.0.1:8080 for companion app
    // but you can also use something like https://a.tile.opentopomap.org/{z}/{x}/{y}.png
    // to make this work on the emulator you ned to run 
    // adb forward tcp:8080 tcp:8080
    var tileUrl as String = COMPANION_APP_TILE_URL;
    // see keys below in routes = getArraySchema(...)
    // see oddity with route name and route loading new in context.newRoute
    var routes as Array<Dictionary> = [];
    var routesEnabled as Boolean = true;
    var disableMapsFailureCount as Number = 200; // 0 for unlimited
    var displayRouteNames as Boolean = true;
    var normalModeColour as Number = Graphics.COLOR_BLUE;
    var uiColour as Number = Graphics.COLOR_DK_GRAY;
    var debugColour as Number = 0xFEFFFFFF; // white, but colour_white results in FFFFFFFF (-1) when we parse it and that is fully transparent
    var routeMax as Number = 5;

    // note this only works if a single track is enabled (multiple tracks would always error)
    var enableOffTrackAlerts as Boolean = true;
    var offTrackAlertsDistanceM as Number = 20;
    var offTrackAlertsMaxReportIntervalS as Number = 60;

    var drawLineToClosestPoint as Boolean = true;
    
    // scratrchpad used for rotations, but it also means we have a large bitmap stored around
    // I will also use that bitmap for re-renders though, and just do rotations every render rather than re-drawing all the tracks/tiles again 
    var renderMode as Number = RENDER_MODE_BUFFERED_ROTATING;
    // how many seconds should we wait before even considerring the next point
    // changes in speed/angle/zoom are not effected by this number. Though maybe they should be?
    var recalculateItervalS as Number = 5;
    // pre seed tiles on either side of the viewable area
    var tileCachePadding as Number = 0;

    // this is a painn to implement in a way that does not effect performance
    // either we 
    // check the setting seach loop iteration and change the colour to and from the point colour
    // have another whole method that rescales the route and draw points (only one setColor call)
    // save around the scaled point array (slow to add scaled points to array if we do not have this feature on, also bad for memory saving a temp copy of the route)
    // have a unique code path for each combination of settings (duplicate code, but alomost no perf hit if setting is off)
    // seems like a pretty bad feature, only really used for debugging - so not implementing for now
    // var showPoints as Boolean = true;

    // derived settings values (could be moved into cached values class)
    var onlyRouteEnabledId as Number or Null;
    
    function setMode(_mode as Number) as Void {
        mode = _mode;
        setValue("mode", mode);
    }
    
    function setUiMode(_uiMode as Number) as Void {
        uiMode = _uiMode;
        setValue("uiMode", uiMode);
    }
    
    function setRenderMode(_renderMode as Number) as Void {
        renderMode = _renderMode;
        setValue("renderMode", renderMode);
    }
    
    function setFixedPositionRaw(lat as Float, long as Float) as Void {
        // hack method so that cached values can update the settings without reloading itself
        // its guaranteed to only be when moving around, and will never go to null
        fixedLatitude = lat;
        fixedLongitude = long;
        Application.Properties.setValue("fixedLatitude", lat);
        Application.Properties.setValue("fixedLongitude", long);
        clearPendingWebRequests();
    }

    function setFixedPosition(lat as Float or Null, long as Float or Null, clearRequests as Boolean) as Void {
        // System.println("moving to: " + lat + " " + long);
        // be very careful about putting null into properties, it breaks everything
        if (lat == null || !(lat instanceof Float))
        {
            lat = 0f;
        }
        if (long == null || !(long instanceof Float))
        {
            long = 0f;
        }
        fixedLatitude = lat;
        fixedLongitude = long;
        setValue("fixedLatitude", lat);
        setValue("fixedLongitude", long);

        var latIsBasicallyNull = fixedLatitude == null || fixedLatitude == 0;
        var longIsBasicallyNull = fixedLongitude == null || fixedLongitude == 0;
        if (latIsBasicallyNull || longIsBasicallyNull)
        {
            fixedLatitude = null;
            fixedLongitude = null;
            if (clearRequests)
            {
                clearPendingWebRequests(); // we want the new position to render faster, that might be the same position, which is fine they queue up pretty quick
            }
            updateCachedValues();
            return;
        }

        // we should have a lat and a long at this point
        // updateCachedValues(); already called by the above sets
        // var latlong = RectangularPoint.xyToLatLon(fixedPosition.x, fixedPosition.y);
        // System.println("round trip conversion result: " + latlong);
        if (clearRequests)
        {
            clearPendingWebRequests(); // we want the new position to render faster, that might be the same position, which is fine they queue up pretty quick
        }
    }

    function setValue(key as String, value) as Void
    {
        Application.Properties.setValue(key, value);
        updateCachedValues();
    }
    
    function setZoomAtPaceMode(_zoomAtPaceMode as Number) as Void {
        zoomAtPaceMode = _zoomAtPaceMode;
        setValue("zoomAtPaceMode", zoomAtPaceMode);
    }
    
    function setTileUrl(_tileUrl as String) as Void {
        tileUrl = _tileUrl;
        setValue("tileUrl", tileUrl);
        clearPendingWebRequests();
        clearTileCache();
    }
    
    function setZoomAtPaceSpeedMPS(mps as Float) as Void {
        zoomAtPaceSpeedMPS = mps;
        setValue("zoomAtPaceSpeedMPS", zoomAtPaceSpeedMPS);
    }
    
    function setMetersAroundUser(value as Number) as Void {
        metersAroundUser = value;
        setValue("metersAroundUser", metersAroundUser);
    }

    function setFixedLatitude(value as Float) as Void {
        setFixedPosition(value, fixedLongitude, true);
    }
    
    function setFixedLongitude(value as Float) as Void {
        setFixedPosition(fixedLatitude, value, true);
    }

    function setMaxPendingWebRequests(value as Number) as Void {
        maxPendingWebRequests = value;
        setValue("maxPendingWebRequests", maxPendingWebRequests);
    }
    
    function setTileSize(value as Number) as Void {
        tileSize = value;
        setValue("tileSize", tileSize);
        clearPendingWebRequests();
        clearTileCache();
    }
    
    function setTileLayerMax(value as Number) as Void {
        tileLayerMax = value;
        setValue("tileLayerMax", tileLayerMax);
    }
    
    function setTileLayerMin(value as Number) as Void {
        tileLayerMin = value;
        setValue("tileLayerMin", tileLayerMin);
    }
    
    function setDisableMapsFailureCount(value as Number) as Void {
        disableMapsFailureCount = value;
        setValue("disableMapsFailureCount", disableMapsFailureCount);
    }
    
    function setOffTrackAlertsDistanceM(value as Number) as Void {
        offTrackAlertsDistanceM = value;
        setValue("offTrackAlertsDistanceM", offTrackAlertsDistanceM);
    }
    
    function setOffTrackAlertsMaxReportIntervalS(value as Number) as Void {
        offTrackAlertsMaxReportIntervalS = value;
        setValue("offTrackAlertsMaxReportIntervalS", offTrackAlertsMaxReportIntervalS);
    }
    
    function setRouteMax(value as Number) as Void {
        routeMax = value;
        setValue("routeMax", routeMax);
    }
    
    function setTileCacheSize(value as Number) as Void {
        tileCacheSize = value;
        setValue("tileCacheSize", tileCacheSize);
        clearPendingWebRequests();
        clearTileCache();
    }
    
    function setTileCachePadding(value as Number) as Void {
        tileCachePadding = value;
        setValue("tileCachePadding", tileCachePadding);
    }
    
    function setRecalculateItervalS(value as Number) as Void {
        recalculateItervalS = value;
        setValue("recalculateItervalS", recalculateItervalS);
    }
    
    function setMapEnabled(_mapEnabled as Boolean) as Void {
        mapEnabled = _mapEnabled;
        setValue("mapEnabled", mapEnabled);

        if (!mapEnabled)
        {
           clearTileCache();
           clearPendingWebRequests();
           clearTileCacheStats();
           clearWebStats();
           return;
        }

        // prompts user to open the app
        if (tileUrl.equals(COMPANION_APP_TILE_URL))
        {
          Communications.transmit([PROTOCOL_SEND_OPEN_APP], {}, getApp()._commStatus);
        }
    }
    
    function setDrawLineToClosestPoint(value as Boolean) as Void {
        drawLineToClosestPoint = value;
        setValue("drawLineToClosestPoint", drawLineToClosestPoint);
    }
    
    function setDisplayRouteNames(_displayRouteNames as Boolean) as Void {
        displayRouteNames = _displayRouteNames;
        setValue("displayRouteNames", displayRouteNames);
    }
    
    function setEnableOffTrackAlerts(_enableOffTrackAlerts as Boolean) as Void {
        enableOffTrackAlerts = _enableOffTrackAlerts;
        setValue("enableOffTrackAlerts", enableOffTrackAlerts);
    }
        
    function setRoutesEnabled(_routesEnabled as Boolean) as Void {
        routesEnabled = _routesEnabled;
        setValue("routesEnabled", routesEnabled);
    }

    function routeColour(routeId as Number) as Number
    {
        var routeIndex = getRouteIndexById(routeId);
        if (routeIndex == null)
        {
            return Graphics.COLOR_BLUE;
        }

        return routes[routeIndex]["colour"];
    }

    // see oddity with route name and route loading new in context.newRoute
    function routeName(routeId as Number) as String
    {
        var routeIndex = getRouteIndexById(routeId);
        if (routeIndex == null)
        {
            return "";
        }
        
        return routes[routeIndex]["name"];
    }

    function routeEnabled(routeId as Number) as Boolean
    {
        if (!routesEnabled)
        {
            return false;
        }

        var routeIndex = getRouteIndexById(routeId);
        if (routeIndex == null)
        {
            return false;
        }
        return routes[routeIndex]["enabled"];
    }

    function setRouteColour(routeId as Number, value as Number) as Void {
        ensureRouteId(routeId);
        var routeIndex = getRouteIndexById(routeId);
        if (routeIndex == null)
        {
            return;
        }

        routes[routeIndex]["colour"] = value;
        saveRoutes();
    }
    
    // see oddity with route name and route loading new in context.newRoute
    function setRouteName(routeId as Number, value as String) as Void {
        ensureRouteId(routeId);
        var routeIndex = getRouteIndexById(routeId);
        if (routeIndex == null)
        {
            return;
        }

        routes[routeIndex]["name"] = value;
        saveRoutes();
    }

    function setRouteEnabled(routeId as Number, value as Boolean) as Void {
        ensureRouteId(routeId);
        var routeIndex = getRouteIndexById(routeId);
        if (routeIndex == null)
        {
            return;
        }
        
        routes[routeIndex]["enabled"] = value;
        saveRoutes();
    }

    function ensureRouteId(routeId as Number) as Void
    {
        var routeIndex = getRouteIndexById(routeId);
        if (routeIndex != null)
        {
            return;
        }

        if (routes.size() >= routeMax)
        {
            return;
        }

        routes.add(
            {
                "routeId" => routeId,
                "name" => routeName(routeId),
                "enabled" => true,
                "colour" => routeColour(routeId)
            }
        );
        saveRoutes();
    }

    function getRouteIndexById(routeId as Number) as Number or Null
    {
        for (var i = 0; i < routes.size(); ++i) {
            var route = routes[i];
            if (route["routeId"] == routeId)
            {
                return i;
            }
        }

        return null;
    }
    
    function getOnlyEnabledRouteId() as Number or Null
    {
        return onlyRouteEnabledId;
    }

    function clearRoutes() as Void {
        routes = [];
        saveRoutes();
    }
    
    function routesToSave() as Array
    {
        var toSave = [];
        for (var i = 0; i < routes.size(); ++i) {
            var entry = routes[i];
            toSave.add(
                {
                    "routeId" => entry["routeId"],
                    "name" => entry["name"],
                    "enabled" => entry["enabled"],
                    "colour" => entry["colour"].format("%X") // this is why we have to copy it :(
                }
            );
        }
        return toSave;
    }
    
    function saveRoutes() as Void
    {
        var toSave = routesToSave();
        setValue("routes", toSave);
        updateOnlyEnabledRoute();
    }
    
    function setTrackColour(value as Number) as Void {
        trackColour = value;
        setValue("trackColour", trackColour.format("%X"));
    }
    
    function setUserColour(value as Number) as Void {
        userColour = value;
        setValue("userColour", userColour.format("%X"));
    }
    
    function setNormalModeColour(value as Number) as Void {
        normalModeColour = value;
        setValue("normalModeColour", normalModeColour.format("%X"));
    }
    
    function setDebugColour(value as Number) as Void {
        debugColour = value;
        setValue("debugColour", debugColour.format("%X"));
    }
    
    function setUiColour(value as Number) as Void {
        uiColour = value;
        setValue("uiColour", uiColour.format("%X"));
    }
    
    function setElevationColour(value as Number) as Void {
        elevationColour = value;
        setValue("elevationColour", elevationColour.format("%X"));
    }

    function toggleMapEnabled() as Void 
    {
        if (mapEnabled)
        {
            setMapEnabled(false);
            return;
        }

        setMapEnabled(true);
    }
    
    function toggleDrawLineToClosestPoint() as Void 
    {
        if (drawLineToClosestPoint)
        {
            setDrawLineToClosestPoint(false);
            return;
        }

        setDrawLineToClosestPoint(true);
    }
    
    function toggleDisplayRouteNames() as Void 
    {
        if (displayRouteNames)
        {
            setDisplayRouteNames(false);
            return;
        }

        setDisplayRouteNames(true);
    }
    
    function toggleEnableOffTrackAlerts() as Void 
    {
        if (enableOffTrackAlerts)
        {
            setEnableOffTrackAlerts(false);
            return;
        }

        setEnableOffTrackAlerts(true);
    }
        
    function toggleRoutesEnabled() as Void 
    {
        if (routesEnabled)
        {
            setRoutesEnabled(false);
            return;
        }

        setRoutesEnabled(true);
    }
    
    function setScale(_scale as Float or Null) as Void {
        scale = _scale;
        // be very careful about putting null into properties, it breaks everything
        if (scale == null)
        {
            setValue("scale", 0);
            clearPendingWebRequests(); // we want the new position to render faster, that might be the same position, which is fine they queue up pretty quick
            return;
        }

        setValue("scale", scale);
        clearPendingWebRequests(); // we want the new position to render faster, that might be the same position, which is fine they queue up pretty quick
    }

    function nextMode() as Void
    {
        // System.println("mode cycled");
        // could just add one and check if over MODE_MAX?
        mode++;
        if (mode >= MODE_MAX)
        {
            mode = MODE_NORMAL;
        }
        
        if (mode == MODE_MAP_MOVE && !mapEnabled)
        {
            nextMode();
        }

        setMode(mode);
    }

    function nextZoomAtPaceMode() as Void { 
        if (mode != MODE_NORMAL)
        {
            return;
        }

        zoomAtPaceMode++;
        if (zoomAtPaceMode >= ZOOM_AT_PACE_MODE_MAX)
        {
            zoomAtPaceMode = ZOOM_AT_PACE_MODE_PACE;
        }

        setZoomAtPaceMode(zoomAtPaceMode);
    }

    function clearTileCache() as Void {
        // symbol not found if the loadSettings method is called before we set tile cache
        // should n ot happen unless onsettingschange is called before initalise finishes
        // it alwasys has the symbol, but it might not be initalised yet
        // _breadcrumbContext also may not be set yet, as we are loading the settings from within the contructor
        var context = getApp()._breadcrumbContext;
        if (context != null and context instanceof BreadcrumbContext && context has :_tileCache && context._tileCache != null && context._tileCache instanceof TileCache)
        {
            context._tileCache.clearValues();
        }
    }
    
    function clearTileCacheStats() as Void {
        // symbol not found if the loadSettings method is called before we set tile cache
        // should n ot happen unless onsettingschange is called before initalise finishes
        // it alwasys has the symbol, but it might not be initalised yet
        // _breadcrumbContext also may not be set yet, as we are loading the settings from within the contructor
        var context = getApp()._breadcrumbContext;
        if (context != null and context instanceof BreadcrumbContext && context has :_tileCache && context._tileCache != null && context._tileCache instanceof TileCache)
        {
            context._tileCache.clearStats();
        }
    }
    
    function clearPendingWebRequests() as Void {
        // symbol not found if the loadSettings method is called before we set tile cache
        // should n ot happen unless onsettingschange is called before initalise finishes
        // it alwasys has the symbol, but it might not be initalised yet
        // _breadcrumbContext also may not be set yet, as we are loading the settings from within the contructor
        var context = getApp()._breadcrumbContext;
        if (context != null and context instanceof BreadcrumbContext && context has :_webRequestHandler && context._webRequestHandler != null && context._webRequestHandler instanceof WebRequestHandler)
        {
            context._webRequestHandler.clearValues();
        }
    }
    
    function updateCachedValues() as Void {
        // symbol not found if the loadSettings method is called before we set tile cache
        // should n ot happen unless onsettingschange is called before initalise finishes
        // it alwasys has the symbol, but it might not be initalised yet
        // _breadcrumbContext also may not be set yet, as we are loading the settings from within the contructor
        var context = getApp()._breadcrumbContext;
        if (context != null and context instanceof BreadcrumbContext && context has :_cachedValues && context._cachedValues != null && context._cachedValues instanceof CachedValues)
        {
            context._cachedValues.recalculateAll();
        }
    }
    
    function clearWebStats() as Void {
        // symbol not found if the loadSettings method is called before we set tile cache
        // should n ot happen unless onsettingschange is called before initalise finishes
        // it alwasys has the symbol, but it might not be initalised yet
        // _breadcrumbContext also may not be set yet, as we are loading the settings from within the contructor
        var context = getApp()._breadcrumbContext;
        if (context != null and context instanceof BreadcrumbContext && context has :_webRequestHandler && context._webRequestHandler != null && context._webRequestHandler instanceof WebRequestHandler)
        {
            context._webRequestHandler.clearStats();
        }
    }
    
    function clearContextRoutes() as Void {
        // symbol not found if the loadSettings method is called before we set tile cache
        // should n ot happen unless onsettingschange is called before initalise finishes
        // it alwasys has the symbol, but it might not be initalised yet
        // _breadcrumbContext also may not be set yet, as we are loading the settings from within the contructor
        var context = getApp()._breadcrumbContext;
        if (context != null and context instanceof BreadcrumbContext)
        {
            context.clearRoutes();
        }
    }
    
    function clearRouteFromContext(routeId as Number) as Void {
        // symbol not found if the loadSettings method is called before we set tile cache
        // should n ot happen unless onsettingschange is called before initalise finishes
        // it alwasys has the symbol, but it might not be initalised yet
        // _breadcrumbContext also may not be set yet, as we are loading the settings from within the contructor
        var context = getApp()._breadcrumbContext;
        if (context != null and context instanceof BreadcrumbContext)
        {
            context.clearRouteId(routeId);
        }
    }

    // some times these parserswere throwing when it was an empty strings seem to result in, or wrong type
    // 
    // Error: Unhandled Exception
    // Exception: UnexpectedTypeException: Expected Number/Float/Long/Double/Char, given null/Number

    function parseColour(key as String, defaultValue as Number) as Number {
        try {
            return parseColourRaw(key, Application.Properties.getValue(key), defaultValue);
        } catch (e) {
            System.println("Error parsing float: " + key);
        }
        return defaultValue;
    }
    
    static function parseColourRaw(key as String, colourString as String or Null, defaultValue as Number) as Number {
        try {
            if (colourString == null)
            {
                return defaultValue;
            }

            if (colourString instanceof String)
            {
                // want final string as AARRGGBB
                // colourString = padStart(colourString, 6, '0'); // fill in 24 bit colour with 0's
                // colourString = padStart(colourString, 8, 'F'); // pad alpha channel with FF
                // empty or invalid strings convert to null
                // anything with leading FF (when 8 characters supplied) needs to be a long, because its too big to fit in Number
                // if a user chooses FFFFFFFF (white) it is (-1) which is fully transparent, should choose FFFFFF (no alpha) or something close like FFFFFFFE
                // in any case we are currently ignoring alpha because we use setColor (text does not support alpha)
                var long = colourString.toLongWithBase(16);
                if (long == null)
                {
                    return defaultValue;
                }

                // calling tonumber breaks - because its out of range, but we need to set the alpha bits
                var number = (long & 0xFFFFFFFFl).toNumber(); 
                return number;
            }

            return parseNumberRaw(key, colourString, defaultValue);
                
        } catch (e) {
            System.println("Error parsing colour: " + key + " " + colourString);
        }
        return defaultValue;
    }

    function parseNumber(key as String, defaultValue as Number) as Number {
        try {
            return parseNumberRaw(key, Application.Properties.getValue(key), defaultValue);
        } catch (e) {
            System.println("Error parsing float: " + key);
        }
        return defaultValue;
    }
    
    function parseNumberRaw(key as String, value as String or Null or Float or Number or Double, defaultValue as Number) as Number {
        try {
            if (value == null)
            {
                return defaultValue;
            }

            if (value instanceof String || value instanceof Float || value instanceof Number || value instanceof Double)
            {
                // empty or invalid strings convert to null
                var ret = value.toNumber();
                if (ret == null)
                {
                    return defaultValue;
                }

                return ret;
            }

            return defaultValue;
        } catch (e) {
            System.println("Error parsing number: " + key + " " + value);
        }
        return defaultValue;
    }
    
    function parseBool(key as String, defaultValue as Boolean) as Boolean {
        try {
            return parseBoolRaw(key, Application.Properties.getValue(key), defaultValue);
        } catch (e) {
            System.println("Error parsing bool: " + key);
        }
        return defaultValue;
    }
    
    function parseBoolRaw(key as String, value as String or Boolean or Null, defaultValue as Boolean) as Boolean {
        try {
            if (value == null)
            {
                return false;
            }

            if (value instanceof String)
            {
                return value.equals("") || value.equals("false") || value.equals("False") || value.equals("FALSE") || value.equals("0");
            }

            if (!(value instanceof Boolean))
            {
                return false;
            }

            return value;
        } catch (e) {
            System.println("Error parsing bool: " + key + " " + value);
        }
        return defaultValue;
    }

    function parseFloat(key as String, defaultValue as Float) as Float {
        try {
            return parseFloatRaw(key, Application.Properties.getValue(key), defaultValue);
        } catch (e) {
            System.println("Error parsing float: " + key);
        }
        return defaultValue;
    }
    
    function parseFloatRaw(key as String, value as String or Null or Float or Number or Double , defaultValue as Float) as Float {
        try {
            if (value == null)
            {
                return defaultValue;
            }

            if (value instanceof String || value instanceof Float || value instanceof Number || value instanceof Double)
            {
                // empty or invalid strings convert to null
                var ret = value.toFloat();
                if (ret == null)
                {
                    return defaultValue;
                }

                return ret;
            }

            return defaultValue;
        } catch (e) {
            System.println("Error parsing float: " + key + " " + value);
        }
        return defaultValue;
    }
    
    function parseString(key as String, defaultValue as String) as String {
        try {
            return parseStringRaw(key, Application.Properties.getValue(key), defaultValue);
        } catch (e) {
            System.println("Error parsing string: " + key);
        }
        return defaultValue;
    }

    function parseStringRaw(key as String, value as String or Null, defaultValue as String) as String {
        try {
            if (value == null)
            {
                return defaultValue;
            }

            if (value instanceof String)
            {

                return value;
            }

            return defaultValue;
        } catch (e) {
            System.println("Error parsing string: " + key + " " + value);
        }
        return defaultValue;
    }

    function parseOptionalFloat(key as String, defaultValue as Float or Null) as Float or Null {
        try {
            return parseOptionalFloatRaw(key, Application.Properties.getValue(key), defaultValue);
        } catch (e) {
            System.println("Error parsing optional float: " + key);
        }
        return defaultValue;
    }

    function parseOptionalFloatRaw(key as String, value as String or Float or Null, defaultValue as Float or Null) as Float or Null {
        try {
            if (value == null)
            {
                return null;
            }

            return parseFloatRaw(key, value, defaultValue);
        } catch (e) {
            System.println("Error parsing optional float: " + key);
        }
        return defaultValue;
    }
    
    function getArraySchema(key as String, expectedKeys as Array<String>, parsers as Array<Method>, defaultValue as Array) as Array {
        var value = null;
        try {
            value = Application.Properties.getValue(key);
            if (value == null)
            {
                return defaultValue;
            }

            if (!(value instanceof Array))
            {
                return defaultValue;
            }

            for (var i = 0; i < value.size(); ++i) {
                var entry = value[i];
                if (!(entry instanceof Dictionary))
                {
                    return defaultValue;
                }

                for (var j = 0; j < expectedKeys.size(); ++j) {
                    var thisKey = expectedKeys[j];
                    var thisParser = parsers[j];
                    if (!entry.hasKey(thisKey))
                    {
                        return defaultValue;
                    }

                    entry[thisKey] = thisParser.invoke(key + "." + i + "." + thisKey, entry[thisKey]);
                }
            }

            return value;
        } catch (e) {
            System.println("Error parsing array: " + key + " " + value);
        }
        return defaultValue;
    }

    function resetDefaults() as Void
    {
        System.println("Resetting settings to default values");
        // clear the flag first thing in case of crash we do not want to try clearing over and over
        setValue("resetDefaults", false);

        // note: this pulls the defaults from whatever we have at the top of the filem these may differ from the defaults in properties.xml
        var defaultSettings = new Settings();
        setTileSize(defaultSettings.tileSize);
        setTileLayerMax(defaultSettings.tileLayerMax);
        setTileLayerMin(defaultSettings.tileLayerMin);
        setTileCacheSize(defaultSettings.tileCacheSize);
        setTileCachePadding(defaultSettings.tileCachePadding);
        setRecalculateItervalS(defaultSettings.recalculateItervalS);
        setMode(defaultSettings.mode);
        setMapEnabled(defaultSettings.mapEnabled);
        setDrawLineToClosestPoint(defaultSettings.drawLineToClosestPoint);
        setTrackColour(defaultSettings.trackColour);
        setElevationColour(defaultSettings.elevationColour);
        setUserColour(defaultSettings.userColour);
        setMaxPendingWebRequests(defaultSettings.maxPendingWebRequests);
        setScale(defaultSettings.scale);
        setMetersAroundUser(defaultSettings.metersAroundUser);
        setZoomAtPaceMode(defaultSettings.zoomAtPaceMode);
        setZoomAtPaceSpeedMPS(defaultSettings.zoomAtPaceSpeedMPS);
        setUiMode(defaultSettings.uiMode);
        setRenderMode(defaultSettings.renderMode);
        setFixedLatitude(defaultSettings.fixedLatitude);
        setFixedLongitude(defaultSettings.fixedLongitude);
        setTileUrl(defaultSettings.tileUrl);
        routes = defaultSettings.routes;
        saveRoutes();
        setRoutesEnabled(defaultSettings.routesEnabled);
        setDisplayRouteNames(defaultSettings.displayRouteNames);
        setDisableMapsFailureCount(defaultSettings.disableMapsFailureCount);
        setEnableOffTrackAlerts(defaultSettings.enableOffTrackAlerts);
        setOffTrackAlertsDistanceM(defaultSettings.offTrackAlertsDistanceM);
        setOffTrackAlertsMaxReportIntervalS(defaultSettings.offTrackAlertsMaxReportIntervalS);
        setRouteMax(defaultSettings.routeMax);
        setNormalModeColour(defaultSettings.normalModeColour);
        setUiColour(defaultSettings.uiColour);
        setDebugColour(defaultSettings.debugColour);

        // purge storage too on reset
        Application.Storage.clearValues();
        clearTileCache();
        clearPendingWebRequests();
        clearTileCacheStats();
        clearWebStats();
        clearContextRoutes();
        // load all the settings we just wrote
        loadSettings();
        updateCachedValues();
    }

    function asDict() as Dictionary
    {
        // all thse return values should bnebe identical to the storage value
        // eg. nulls are exposed as 0
        // colours are strings

        return {
            "tileSize" => tileSize,
            "tileLayerMax" => tileLayerMax,
            "tileLayerMin" => tileLayerMin,
            "tileCacheSize" => tileCacheSize,
            "tileCachePadding" => tileCachePadding,
            "recalculateItervalS" => recalculateItervalS,
            "mode" => mode,
            "mapEnabled" => mapEnabled,
            "drawLineToClosestPoint" => drawLineToClosestPoint,
            "trackColour" => trackColour.format("%X"),
            "elevationColour" => elevationColour.format("%X"),
            "userColour" => userColour.format("%X"),
            "maxPendingWebRequests" => maxPendingWebRequests,
            "scale" => scale == null ? 0f : scale,
            "metersAroundUser" => metersAroundUser,
            "zoomAtPaceMode" => zoomAtPaceMode,
            "zoomAtPaceSpeedMPS" => zoomAtPaceSpeedMPS,
            "uiMode" => uiMode,
            "renderMode" => renderMode,
            "fixedLatitude" => fixedLatitude == null ? 0f : fixedLatitude,
            "fixedLongitude" => fixedLongitude == null ? 0f : fixedLongitude,
            "tileUrl" => tileUrl,
            "routes" => routesToSave(),
            "routesEnabled" => routesEnabled,
            "displayRouteNames" => displayRouteNames,
            "disableMapsFailureCount" => disableMapsFailureCount,
            "enableOffTrackAlerts" => enableOffTrackAlerts,
            "offTrackAlertsDistanceM" => offTrackAlertsDistanceM,
            "offTrackAlertsMaxReportIntervalS" => offTrackAlertsMaxReportIntervalS,
            "normalModeColour" => normalModeColour.format("%X"),
            "routeMax" => routeMax,
            "uiColour" => uiColour.format("%X"),
            "debugColour" => debugColour.format("%X"),
            "resetDefaults" => false,
        };
    }

    function saveSettings(settings as Dictionary) as Void
    {
        // should we sanitize this as its untrusted? makes it significantly more annoying to do
        var keys = settings.keys();
        for (var i = 0; i < keys.size(); ++i) {
            var key = keys[i] as Application.PropertyKeyType;
            var value = settings[key];
            // for now just blindly trust the users
            // we do reload which sanitizes, but they could break garmins settings page with unexpected types
            setValue(key, value);
        }
        onSettingsChanged();
    }

    // Load the values initially from storage
    function loadSettings() as Void {
        // fix for a garmin bug where bool settings are not changable if they default to true
        // https://forums.garmin.com/developer/connect-iq/i/bug-reports/bug-boolean-properties-with-default-value-true-can-t-be-changed-in-simulator
        var haveDoneFirstLoadSetup = Application.Properties.getValue("haveDoneFirstLoadSetup");
        if (!haveDoneFirstLoadSetup)
        {
            setValue("haveDoneFirstLoadSetup", true);
            resetDefaults(); // pulls from our defaults
        }

        var resetDefaults = Application.Properties.getValue("resetDefaults") as Boolean;
        if (resetDefaults)
        {
            resetDefaults();
            return;
        }

        System.println("loadSettings: Loading all settings");
        tileSize = parseNumber("tileSize", tileSize);
        tileLayerMax = parseNumber("tileLayerMax", tileLayerMax);
        tileLayerMin = parseNumber("tileLayerMin", tileLayerMin);
        // System.println("tileSize: " + tileSize);
        if (tileSize < 2)
        {
            tileSize = 2;
        }
        else if (tileSize > 256)
        {
            tileSize = 256;
        }
        
        tileCacheSize = parseNumber("tileCacheSize", tileCacheSize);
        tileCachePadding = parseNumber("tileCachePadding", tileCachePadding);
        recalculateItervalS = parseNumber("recalculateItervalS", recalculateItervalS);
        mode = parseNumber("mode", mode);
        mapEnabled = parseBool("mapEnabled", mapEnabled);
        setMapEnabled(mapEnabled); // prompt for app to open if needed
        drawLineToClosestPoint = parseBool("drawLineToClosestPoint", drawLineToClosestPoint);
        displayRouteNames = parseBool("displayRouteNames", displayRouteNames);
        enableOffTrackAlerts = parseBool("enableOffTrackAlerts", enableOffTrackAlerts);
        routesEnabled = parseBool("routesEnabled", routesEnabled);
        trackColour = parseColour("trackColour", trackColour);
        elevationColour = parseColour("elevationColour", elevationColour);
        userColour = parseColour("userColour", userColour);
        normalModeColour = parseColour("normalModeColour", normalModeColour);
        routeMax = parseColour("routeMax", routeMax);
        uiColour = parseColour("uiColour", uiColour);
        debugColour = parseColour("debugColour", debugColour);
        maxPendingWebRequests = parseNumber("maxPendingWebRequests", maxPendingWebRequests);
        scale = parseOptionalFloat("scale", scale);
        if (scale == 0)
        {
            scale = null;
        }
        metersAroundUser = parseNumber("metersAroundUser", metersAroundUser);
        zoomAtPaceMode = parseNumber("zoomAtPaceMode", zoomAtPaceMode);
        zoomAtPaceSpeedMPS = parseFloat("zoomAtPaceSpeedMPS", zoomAtPaceSpeedMPS);
        uiMode = parseNumber("uiMode", uiMode);
        renderMode = parseNumber("renderMode", renderMode);

        fixedLatitude = parseOptionalFloat("fixedLatitude", fixedLatitude);
        fixedLongitude = parseOptionalFloat("fixedLongitude", fixedLongitude);
        setFixedPosition(fixedLatitude, fixedLongitude, false);
        tileUrl = parseString("tileUrl", tileUrl);
        routes = getArraySchema(
            "routes", 
            ["routeId", "name", "enabled", "colour"], 
            [method(:defaultNumberParser), method(:emptyString), method(:defaultFalse), method(:defaultColourParser)],
            routes
        );
        System.println("parsed routes: " + routes);
        updateOnlyEnabledRoute();
        disableMapsFailureCount = parseNumber("disableMapsFailureCount", disableMapsFailureCount);
        offTrackAlertsDistanceM = parseNumber("offTrackAlertsDistanceM", offTrackAlertsDistanceM);
        offTrackAlertsMaxReportIntervalS = parseNumber("offTrackAlertsMaxReportIntervalS", offTrackAlertsMaxReportIntervalS);


        // testing coordinates (piper-comanche-wreck)
        // setFixedPosition(-27.297773, 152.753883);
        // // setScale(0.39); // zoomed out a bit
        // setScale(1.96); // really close
    }

    function updateOnlyEnabledRoute() as Void
    {
        var checkingOnlyRouteEnabledId = null;
        for (var i = 0; i < routes.size(); ++i) {
            var route = routes[i];

            if (route["enabled"] && checkingOnlyRouteEnabledId == null)
            {
                // we found the first enabled one
                checkingOnlyRouteEnabledId = route["routeId"];
                break;
            }

            if (route["enabled"] && checkingOnlyRouteEnabledId != null)
            {
                // we found a second enabled one
                checkingOnlyRouteEnabledId = null;
                break;
            }
        }

        if (checkingOnlyRouteEnabledId != null) {
            onlyRouteEnabledId = checkingOnlyRouteEnabledId;
        }
        else {
            onlyRouteEnabledId = null;
        }
    }

    function emptyString(key as String, value) as String
    {
        return parseStringRaw(key, value, "");
    }
    
    function defaultNumberParser(key as String, value) as Number
    {
        return parseNumberRaw(key, value, 0);
    }

    function defaultFalse(key as String, value) as Boolean
    {
        if (value instanceof Boolean)
        {
            return value;
        }

        return false;
    }

    function defaultColourParser(key as String, value) as Number
    {
        return parseColourRaw(key, value, Graphics.COLOR_RED);
    }

   function onSettingsChanged() as Void {
        System.println("onSettingsChanged: Setting Changed, loading");
        var oldRoutes = routes;
        var oldTileUrl = tileUrl;
        var oldTileSize = tileSize;
        var oldTileCacheSize = tileCacheSize;
        var oldMapEnabled = mapEnabled;
        loadSettings();
        updateCachedValues();
        // route settins do not work because garmins setting spage cannot edit them
        // when any property is modified, so we have to explain to users not to touch the settings, but we cannot because it looks 
        // like garmmins settings are not rendering desciptions anymore :(
        for (var i=0; i<oldRoutes.size(); ++i)
        {
            var oldRouteEntry = oldRoutes[i];
            var oldRouteId = oldRouteEntry["routeId"];

            var routeIndex = getRouteIndexById(oldRouteId);
            if (routeIndex != null)
            {
                // we have the same route
                continue;
            }

            // clear the route
            clearRouteFromContext(oldRouteId);
        }

        // run any tile cache clearing that we need to when map features change
        if (!oldTileUrl.equals(tileUrl))
        {
            setTileUrl(tileUrl);
        }
        if (oldTileSize != tileSize)
        {
            setTileSize(tileSize);
        }
        if (oldTileCacheSize != tileCacheSize)
        {
            setTileCacheSize(tileCacheSize);
        }
        if (oldMapEnabled != mapEnabled)
        {
            setMapEnabled(mapEnabled);
        }
    }
}