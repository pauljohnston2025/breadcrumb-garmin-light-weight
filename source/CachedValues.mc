import Toybox.Application;
import Toybox.Lang;
import Toybox.Graphics;
import Toybox.System;
import Toybox.Activity;

// https://developer.garmin.com/connect-iq/reference-guides/monkey-c-reference/
// Monkey C is a message-passed language. When a function is called, the virtual machine searches a hierarchy at runtime in the following order to find the function:
// Instance members of the class
// Members of the superclass
// Static members of the class
// Members of the parent module, and the parent modules up to the global namespace
// Members of the superclass’s parent module up to the global namespace
class CachedValues {
    private var _settings as Settings;

    // cache some important maths to make everything faster
    // things set to -1 are updated on the first layout/calcualte call

    // updated when settings change
    var smallTilesPerScaledTile as Number;
    var smallTilesPerFullTile as Number;
    // updated when user manually pans around screen
    var fixedPosition as RectangularPoint?; // NOT SCALED - raw meters
    var scale as Float? = null; // fixed map scale, when manually zooming or panning around map
    var scaleCanInc as Boolean = true;
    var scaleCanDec as Boolean = true;

    // updated whenever we change zoom level (speed changes, zoom at pace mode etc.)
    var centerPosition as RectangularPoint = new RectangularPoint(0f, 0f, 0f); // scaled to pixels
    var currentScale as Float = 0.0; // pixels per meter so <pixel count> / _currentScale = meters  or  meters * _currentScale = pixels
    // will be changed whenever scale is adjusted, falls back to metersAroundUser when no scale
    var mapMoveDistanceM as Float;

    // updated whenever we get new activity data with a new heading
    var rotationRad as Float = 0.0; // heading in radians
    var rotateCos as Float = Math.cos(rotationRad);
    var rotateSin as Float = Math.sin(rotationRad);
    var currentSpeed as Float = -1f;
    var currentlyZoomingAroundUser as Boolean = false;

    // updated whenever onlayout changes (audit usages, these should not need to be floats, but sometimes are used to do float math)
    // default to full screen guess
    var screenWidth as Float = System.getDeviceSettings().screenWidth.toFloat();
    var screenHeight as Float = System.getDeviceSettings().screenHeight.toFloat();
    var minScreenDim as Float = minF(screenWidth, screenHeight);
    var xHalf as Float = screenWidth / 2f;
    var yHalf as Float = screenHeight / 2f;
    var rotationMatrix as AffineTransform = new AffineTransform();

    // map related fields updated whenever scale changes
    var mapDataCanBeUsed as Boolean = false;
    var earthsCircumference as Float = 40075016.686f;
    var originShift as Float = earthsCircumference / 2.0; // Half circumference of Earth
    var tileZ as Number = -1;
    var tileScaleFactor as Float = -1f;
    var tileScalePixelSize as Number = -1;
    var tileOffsetX as Number = -1;
    var tileOffsetY as Number = -1;
    var tileCountX as Number = -1;
    var tileCountY as Number = -1;
    var firstTileX as Number = -1;
    var firstTileY as Number = -1;

    var seedingZ as Number = -1; // -1 means not seeding
    var seedingRectanglarTopLeft as RectangularPoint = new RectangularPoint(0f, 0f, 0f);
    var seedingRectanglarBottomRight as RectangularPoint = new RectangularPoint(0f, 0f, 0f);
    var seedingUpToTileX as Number = 0;
    var seedingUpToTileY as Number = 0;
    var seedingTilesOnThisLayer as Number = NUMBER_MAX;
    var seedingTilesProgressForThisLayer as Number = 0;

    function atMinTileLayer() as Boolean {
        return tileZ == _settings.tileLayerMin;
    }

    function atMaxTileLayer() as Boolean {
        return tileZ == _settings.tileLayerMax;
    }

    function initialize(settings as Settings) {
        self._settings = settings;
        smallTilesPerScaledTile = Math.ceil(
            _settings.scaledTileSize / _settings.tileSize.toFloat()
        ).toNumber();
        smallTilesPerFullTile = Math.ceil(
            _settings.fullTileSize / _settings.tileSize.toFloat()
        ).toNumber();
        fixedPosition = null;
        // will be changed whenever scale is adjusted, falls back to metersAroundUser when no scale
        mapMoveDistanceM = _settings.metersAroundUser.toFloat();
    }

    function calcOuterBoundingBoxFromTrackAndRoutes(
        routes as Array<BreadcrumbTrack>,
        trackBoundingBox as [Float, Float, Float, Float]?
    ) as [Float, Float, Float, Float] {
        var scaleDivisor = currentScale;
        if (currentScale == 0f) {
            scaleDivisor = 1; // use raw coordinates
        }

        // we need to make a new object, otherwise we will modify the one thats passed in
        var outerBoundingBox = BOUNDING_BOX_DEFAULT();
        if (trackBoundingBox != null) {
            outerBoundingBox[0] = trackBoundingBox[0] / scaleDivisor;
            outerBoundingBox[1] = trackBoundingBox[1] / scaleDivisor;
            outerBoundingBox[2] = trackBoundingBox[2] / scaleDivisor;
            outerBoundingBox[3] = trackBoundingBox[3] / scaleDivisor;
        }

        for (var i = 0; i < routes.size(); ++i) {
            var route = routes[i];
            if (!_settings.routeEnabled(route.storageIndex)) {
                continue;
            }
            outerBoundingBox[0] = minF(route.boundingBox[0] / scaleDivisor, outerBoundingBox[0]);
            outerBoundingBox[1] = minF(route.boundingBox[1] / scaleDivisor, outerBoundingBox[1]);
            outerBoundingBox[2] = maxF(route.boundingBox[2] / scaleDivisor, outerBoundingBox[2]);
            outerBoundingBox[3] = maxF(route.boundingBox[3] / scaleDivisor, outerBoundingBox[3]);
        }

        return outerBoundingBox;
    }

    /** returns true if a rescale occurred */
    function updateScaleCenterAndMap() as Boolean {
        var newScale = getNewScaleAndUpdateCenter();
        var rescaleOccurred = handleNewScale(newScale);
        if (_settings.mapEnabled) {
            updateMapData();
        }
        // move half way across the screen
        if (currentScale != 0f) {
            mapMoveDistanceM = minScreenDim / 2.0 / currentScale;
        }
        return rescaleOccurred;
    }

    /** returns the new scale */
    function getNewScaleAndUpdateCenter() as Float {
        if (currentlyZoomingAroundUser) {
            var renderDistanceM = _settings.metersAroundUser;
            if (!calcCenterPoint()) {
                var lastPoint = getApp()._breadcrumbContext.track().coordinates.lastPoint();
                if (lastPoint != null) {
                    centerPosition = lastPoint;
                    return calculateScale(renderDistanceM.toFloat());
                }
                // we are zooming around the user, but we do not have a last track point
                // resort to using bounding box
                var boundingBox = calcOuterBoundingBoxFromTrackAndRoutes(
                    getApp()._breadcrumbContext.routes(),
                    null
                );
                calcCenterPointForBoundingBox(boundingBox);
                return calculateScale(renderDistanceM.toFloat());
            }

            return calculateScale(renderDistanceM.toFloat());
        }

        var boundingBox = calcOuterBoundingBoxFromTrackAndRoutes(
            getApp()._breadcrumbContext.routes(),
            _settings.zoomAtPaceMode == ZOOM_AT_PACE_MODE_SHOW_ROUTES_WITHOUT_TRACK
                ? null
                : optionalTrackBoundingBox()
        );
        calcCenterPointForBoundingBox(boundingBox);
        return getNewScaleFromBoundingBox(boundingBox);
    }

    function optionalTrackBoundingBox() as [Float, Float, Float, Float]? {
        return getApp()._breadcrumbContext.track().coordinates.lastPoint() == null
            ? null
            : getApp()._breadcrumbContext.track().boundingBox;
    }

    // needs to be called whenever the screen moves to a new bounding box
    function updateMapData() {
        if (currentScale == 0f || smallTilesPerScaledTile == 0) {
            // do not divide by zero my good friends
            // we do not have a scale calculated yet
            return;
        }

        var centerPositionRaw = centerPosition.rescale(1 / currentScale);

        // 2 to 15 see https://opentopomap.org/#map=2/-43.2/305.9
        var desiredResolution = 1 / currentScale;
        var z = Math.round(calculateTileLevel(desiredResolution)).toNumber();
        tileZ = minN(maxN(z, _settings.tileLayerMin), _settings.tileLayerMax); // cap to our limits

        var tileWidthM = earthsCircumference / Math.pow(2, tileZ) / smallTilesPerScaledTile;
        // var minScreenDim = minF(_screenWidth, _screenHeight);
        // var minScreenDimM = minScreenDim / currentScale;
        var screenWidthM = screenWidth / currentScale;
        var screenHeightM = screenHeight / currentScale;

        // where the screen corner starts
        var halfScreenWidthM = screenWidthM / 2f;
        var halfScreenHeightM = screenHeightM / 2f;
        var screenLeftM = centerPositionRaw.x - halfScreenWidthM;
        var screenTopM = centerPositionRaw.y + halfScreenHeightM;

        // find which tile we are closest to
        firstTileX = ((screenLeftM + originShift) / tileWidthM).toNumber();
        firstTileY = ((originShift - screenTopM) / tileWidthM).toNumber();

        // remember, lat/long is a different coordinate system (the lower we are the more negative we are)
        //  x calculations are the same - more left = more negative
        //  tile inside graph
        // 90
        //    | 0,0 1,0   tile
        //    | 0,1 1,1
        //    |____________________
        //  -180,-90              180
        var firstTileLeftM = firstTileX * tileWidthM - originShift;
        var firstTileTopM = originShift - firstTileY * tileWidthM;

        // var screenToTilePixelRatio = minScreenDim / _settings.tileSize;
        // var screenToTileMRatio = minScreenDimM / tileWidthM;
        // var scaleFactor = screenToTilePixelRatio / screenToTileMRatio; // we need to stretch or shrink the tiles by this much
        // simplification of above calculation
        tileScaleFactor = (currentScale * tileWidthM) / _settings.tileSize;
        // eg. tile = 10m screen = 10m tile = 256pixel screen = 360pixel scaleFactor = 1.4 each tile pixel needs to become 1.4 sceen pixels
        // eg. 2
        //     tile = 20m screen = 10m tile = 256pixel screen = 360pixel scaleFactor = 2.8 we only want to render half the tile, so we only have half the pixels
        //     screenToTileMRatio = 0.5 screenToTilePixelRatio = 1.4
        // eg. 3
        //     tile = 10m screen = 20m tile = 256pixel screen = 360pixel scaleFactor = 0.7 we need 2 tiles, each tile pixel needs to be squashed into screen pixels
        //     screenToTileMRatio = 2 screenToTilePixelRatio = 1.4
        //

        // how many pixels on the screen the tile should take up this can be smaller or larger than the actual tile,
        // depending on if we scale up or down
        // find the closest pixel size
        tileScalePixelSize = Math.round(_settings.tileSize * tileScaleFactor).toNumber();

        // find the closest pixel size
        tileOffsetX = Math.round((firstTileLeftM - screenLeftM) * currentScale).toNumber();
        tileOffsetY = Math.round((screenTopM - firstTileTopM) * currentScale).toNumber();

        tileCountX = Math.ceil((-tileOffsetX + screenWidth) / tileScalePixelSize).toNumber();
        tileCountY = Math.ceil((-tileOffsetY + screenHeight) / tileScalePixelSize).toNumber();
        mapDataCanBeUsed = true;
    }

    /** returns true if a rescale occurred */
    function onActivityInfo(activityInfo as Activity.Info) as Boolean {
        // System.println(
        //     "store heading, current speed etc. so we can know how to render the "
        //     + "map");
        var currentHeading = activityInfo.currentHeading;
        if (currentHeading != null) {
            rotationRad = currentHeading;
            rotateCos = Math.cos(rotationRad);
            rotateSin = Math.sin(rotationRad);
        }
        var _currentSpeed = activityInfo.currentSpeed;
        if (_currentSpeed != null) {
            currentSpeed = _currentSpeed;
        }

        updateRotationMatrix();

        // we are either in 2 cases
        // if we are moving at some pace check the mode we are in to determine if we
        // zoom in or out
        // or we are not at speed, so invert logic (this allows us to zoom in when
        // stopped, and zoom out when running) mostly useful for cheking close route
        // whilst stopped but also allows quick zoom in before setting manual zoom
        // (rather than having to manually zoom in from the outer level) once zoomed
        // in we lock onto the user position anyway
        var weShouldZoomAroundUser =
            (scale != null &&
                _settings.zoomAtPaceMode != ZOOM_AT_PACE_MODE_SHOW_ROUTES_WITHOUT_TRACK) ||
            (currentSpeed > _settings.zoomAtPaceSpeedMPS &&
                _settings.zoomAtPaceMode == ZOOM_AT_PACE_MODE_PACE) ||
            (currentSpeed <= _settings.zoomAtPaceSpeedMPS &&
                _settings.zoomAtPaceMode == ZOOM_AT_PACE_MODE_STOPPED) ||
            _settings.zoomAtPaceMode == ZOOM_AT_PACE_MODE_ALWAYS_ZOOM;
        if (currentlyZoomingAroundUser != weShouldZoomAroundUser) {
            currentlyZoomingAroundUser = weShouldZoomAroundUser;
            return updateScaleCenterAndMap();
            _settings.clearPendingWebRequests();
            if (getApp()._view != null) {
                getApp()._view.resetRenderTime();
            }
        }

        return false;
    }

    function setScreenSize(width as Number, height as Number) as Void {
        screenWidth = width.toFloat();
        screenHeight = height.toFloat();
        minScreenDim = minF(screenWidth, screenHeight);
        xHalf = width / 2.0f;
        yHalf = height / 2.0f;

        updateRotationMatrix();
        updateScaleCenterAndMap();
    }

    function updateRotationMatrix() as Void {
        rotationMatrix = new AffineTransform();
        rotationMatrix.translate(xHalf, yHalf); // move to center
        rotationMatrix.rotate(-rotationRad); // rotate
        rotationMatrix.translate(-xHalf, -yHalf); // move back to position
    }

    (:scaledbitmap)
    function calculateScale(maxDistanceM as Float) as Float {
        if (_settings.scaleRestrictedToTileLayers && _settings.mapEnabled) {
            return tileLayerScale(maxDistanceM);
        }
        return calculateScaleStandard(maxDistanceM);
    }

    // todo inline
    function calculateScaleStandard(maxDistanceM as Float) as Float {
        if (scale != null) {
            return scale;
        }

        // we want the whole map to be show on the screen, we have 360 pixels on the
        // venu 2s
        // but this would only work for sqaures, so 0.75 fudge factor for circle
        // watch face
        return (minScreenDim / maxDistanceM) * 0.75;
    }

    function nextTileLayerScale(direction as Number) as Float {
        if (smallTilesPerFullTile == 0 || scale == null || scale == 0f) {
            return 0f;
        }

        var currentZF = calculateTileLevel(1 / scale);
        var currentZ = Math.round(currentZF).toNumber();
        currentZ = minN(maxN(currentZ, _settings.tileLayerMin), _settings.tileLayerMax); // cap to our limits, otherwise we can decreent/increment outside the range if we are already at a bad scale
        var nextZ = currentZ + direction;

        nextZ = minN(maxN(nextZ, _settings.tileLayerMin), _settings.tileLayerMax); // cap to our limits
        var tileWidthM2 = earthsCircumference / Math.pow(2, nextZ) / smallTilesPerFullTile;
        var ret = (_settings.tileSize / tileWidthM2).toFloat();
        // atMinTileLayer = ret == _settings.tileLayerMin;
        // atMaxTileLayer = ret == _settings.tileLayerMax;
        return ret;
    }

    function tileLayerScale(maxDistanceM as Float) as Float {
        var perfectScale = calculateScaleStandard(maxDistanceM);

        if (perfectScale == 0f || smallTilesPerFullTile == 0) {
            return perfectScale; // do not divide by 0
        }

        // only allow map tile scale levels so that we can render the tiles without any gaps, and at the correct size
        // todo cache these calcs, it is for the slower devices after all
        var desiredResolution = 1 / perfectScale;
        var z = Math.round(calculateTileLevel(desiredResolution)).toNumber();
        z = minN(maxN(z, _settings.tileLayerMin), _settings.tileLayerMax); // cap to our limits

        // we want these ratios to be the same
        // var minScreenDimM = _minScreenDim / currentScale;
        // var screenToTileMRatio = minScreenDimM / tileWidthM;
        // var screenToTilePixelRatio = minScreenDim / _settings.tileSize;
        var tileWidthM2 = earthsCircumference / Math.pow(2, z) / smallTilesPerFullTile;
        //  var screenToTilePixelRatio = _minScreenDim / settings.tileSize;

        // note: this gets as close as it can to the zoom level, some route clipping might occur
        // we have to go to the largertile sizes so that we can see the whole route
        return (_settings.tileSize / tileWidthM2).toFloat();
    }

    (:noscaledbitmap)
    function calculateScale(maxDistanceM as Float) as Float {
        // note: this can come from user intervention, and settings the sclae overload, we will get a close as we can
        var perfectScale = calculateScaleStandard(maxDistanceM);

        return perfectScale;
    }

    /** returns the new scale */
    function getNewScaleFromBoundingBox(outerBoundingBox as [Float, Float, Float, Float]) as Float {
        var xDistanceM = outerBoundingBox[2] - outerBoundingBox[0];
        var yDistanceM = outerBoundingBox[3] - outerBoundingBox[1];

        var maxDistanceM = maxF(xDistanceM, yDistanceM);

        if (maxDistanceM == 0) {
            // show 1m of space to avaoid division by 0
            maxDistanceM = 1;
        }

        return calculateScale(maxDistanceM);
    }

    /** returns true if the scale changed */
    function handleNewScale(newScale as Float) as Boolean {
        if (abs(currentScale - newScale) < 0.000001) {
            // ignore any minor scale changes, esp if the scale is the same but float == does not work
            return false;
        }

        if (newScale == 0f) {
            return false; // dont allow silly scales
        }

        var scaleFactor = newScale;
        if (currentScale != null && currentScale != 0f) {
            // adjsut by old scale
            scaleFactor = newScale / currentScale;
        }

        var routes = getApp()._breadcrumbContext.routes();
        for (var i = 0; i < routes.size(); ++i) {
            var route = routes[i];
            route.rescale(scaleFactor); // rescale all routes, even if they are not enabled
        }
        getApp()._breadcrumbContext.track().rescale(scaleFactor);
        if (getApp()._view != null) {
            getApp()._view.rescale(scaleFactor);
        }
        centerPosition.rescaleInPlace(scaleFactor);

        currentScale = newScale;
        return true;
    }

    function recalculateAll() as Void {
        System.println("recalculating all cached values from settings/routes change");
        smallTilesPerScaledTile = Math.ceil(
            _settings.scaledTileSize / _settings.tileSize.toFloat()
        ).toNumber();
        smallTilesPerFullTile = Math.ceil(
            _settings.fullTileSize / _settings.tileSize.toFloat()
        ).toNumber();
        updateFixedPositionFromSettings();
        updateScaleCenterAndMap();
    }

    function updateFixedPositionFromSettings() as Void {
        var fixedLatitude = _settings.fixedLatitude;
        var fixedLongitude = _settings.fixedLongitude;
        if (fixedLatitude == null || fixedLongitude == null) {
            fixedPosition = null;
        } else {
            fixedPosition = RectangularPoint.latLon2xy(fixedLatitude, fixedLongitude, 0f);
        }
    }

    // Desired resolution (meters per pixel)
    function calculateTileLevel(desiredResolution as Float) as Float {
        return Math.log(
            earthsCircumference / (_settings.tileSize * desiredResolution) / smallTilesPerFullTile,
            2
        );
    }

    function moveLatLong(
        xMoveUnrotated as Float,
        yMoveUnrotated as Float,
        xMoveRotated as Float,
        yMoveRotated as Float
    ) as [Float, Float]? {
        if (
            _settings.renderMode == RENDER_MODE_UNBUFFERED_NO_ROTATION ||
            _settings.renderMode == RENDER_MODE_BUFFERED_NO_ROTATION
        ) {
            return RectangularPoint.xyToLatLon(
                fixedPosition.x + xMoveUnrotated,
                fixedPosition.y + yMoveUnrotated
            );
        }

        return RectangularPoint.xyToLatLon(
            fixedPosition.x + xMoveRotated,
            fixedPosition.y + yMoveRotated
        );
    }

    function moveFixedPositionUp() as Void {
        setPositionAndScaleIfNotSet();

        var latlong = moveLatLong(
            0f,
            mapMoveDistanceM,
            rotateSin * mapMoveDistanceM,
            rotateCos * mapMoveDistanceM
        );
        if (latlong != null) {
            _settings.setFixedPositionRaw(latlong[0], latlong[1]);
        }
        updateFixedPositionFromSettings();
        updateScaleCenterAndMap();
        if (getApp()._view != null) {
            getApp()._view.resetRenderTime();
        }
    }

    function moveFixedPositionDown() as Void {
        setPositionAndScaleIfNotSet();
        var latlong = moveLatLong(
            0f,
            -mapMoveDistanceM,
            -rotateSin * mapMoveDistanceM,
            -rotateCos * mapMoveDistanceM
        );
        if (latlong != null) {
            _settings.setFixedPositionRaw(latlong[0], latlong[1]);
        }
        updateFixedPositionFromSettings();
        updateScaleCenterAndMap();
        if (getApp()._view != null) {
            getApp()._view.resetRenderTime();
        }
    }

    function moveFixedPositionLeft() as Void {
        setPositionAndScaleIfNotSet();
        var latlong = moveLatLong(
            -mapMoveDistanceM,
            0f,
            -rotateCos * mapMoveDistanceM,
            rotateSin * mapMoveDistanceM
        );
        if (latlong != null) {
            _settings.setFixedPositionRaw(latlong[0], latlong[1]);
        }
        updateFixedPositionFromSettings();
        updateScaleCenterAndMap();
        if (getApp()._view != null) {
            getApp()._view.resetRenderTime();
        }
    }

    function moveFixedPositionRight() as Void {
        setPositionAndScaleIfNotSet();
        var latlong = moveLatLong(
            mapMoveDistanceM,
            0f,
            rotateCos * mapMoveDistanceM,
            -rotateSin * mapMoveDistanceM
        );
        if (latlong != null) {
            _settings.setFixedPositionRaw(latlong[0], latlong[1]);
        }
        updateFixedPositionFromSettings();
        updateScaleCenterAndMap();
        if (getApp()._view != null) {
            getApp()._view.resetRenderTime();
        }
    }

    function calcCenterPoint() as Boolean {
        if (fixedPosition != null) {
            if (currentScale == 0f) {
                centerPosition = fixedPosition.clone();
            } else {
                centerPosition = fixedPosition.rescale(currentScale);
            }

            return true;
        }

        // when the scale is locked, we need to be where the user is, otherwise we
        // could see a blank part of the map, when we are zoomed in and have no
        // context
        if (
            scale != null &&
            _settings.zoomAtPaceMode != ZOOM_AT_PACE_MODE_SHOW_ROUTES_WITHOUT_TRACK
        ) {
            // the hacks begin
            var lastPoint = getApp()._breadcrumbContext.track().coordinates.lastPoint();
            if (lastPoint != null) {
                centerPosition = lastPoint;
                return true;
            }
        }

        return false;
    }

    function calcCenterPointForBoundingBox(boundingBox as [Float, Float, Float, Float]) as Void {
        if (calcCenterPoint()) {
            return;
        }

        centerPosition = new RectangularPoint(
            boundingBox[0] + (boundingBox[2] - boundingBox[0]) / 2.0,
            boundingBox[1] + (boundingBox[3] - boundingBox[1]) / 2.0,
            0.0f
        );

        if (currentScale != 0f) {
            centerPosition.rescaleInPlace(currentScale);
        }
    }

    function setPositionAndScaleIfNotSet() as Void {
        fixedPosition = getScreenCenter();
        // System.println("new fixed pos: " + fixedPosition);
    }

    function getScreenCenter() as RectangularPoint {
        // we need to set a fixed scale so that a user moving does not change the zoom level randomly whilst they are viewing a map and panning
        if (scale == null) {
            var scaleToSet = currentScale;
            if (currentScale == 0f) {
                scaleToSet = calculateScale(_settings.metersAroundUser.toFloat());
            }
            setScale(scaleToSet);
        }

        var divisor = currentScale;
        if (divisor == 0f) {
            // we should always have a current scale at this point, since we manually set scale
            System.println("Warning: current scale was somehow not set");
            divisor = 1f;
        }

        var lastRenderedLatLongCenter = null;
        lastRenderedLatLongCenter = RectangularPoint.xyToLatLon(
            centerPosition.x / divisor,
            centerPosition.y / divisor
        );

        var fixedLatitude = _settings.fixedLatitude;
        var fixedLongitude = _settings.fixedLongitude;
        if (fixedLatitude == null) {
            fixedLatitude = lastRenderedLatLongCenter == null ? 0f : lastRenderedLatLongCenter[0];
        }

        if (fixedLongitude == null) {
            fixedLongitude = lastRenderedLatLongCenter == null ? 0f : lastRenderedLatLongCenter[1];
        }
        return RectangularPoint.latLon2xy(fixedLatitude, fixedLongitude, 0f);
    }

    function setScale(_scale as Float?) as Void {
        scale = _scale;
        // be very careful about putting null into properties, it breaks everything
        if (scale == null) {
            _settings.clearPendingWebRequests(); // we want the new position to render faster, that might be the same position, which is fine they queue up pretty quick
            updateScaleCenterAndMap();
            // this is not the best guess, but will onyl require the user to tap zoom once to see that it cannot zoom
            // getScaleDecIncAmount() only works when the scale is not null. We could update it to use the currentScale if scale is null?
            // they are not acutally in a user scale in this case though, so makes sense to show that we are tracking the users desired zoom instead of ours
            scaleCanInc = true;
            scaleCanDec = true;
            if (getApp()._view != null) {
                getApp()._view.resetRenderTime();
            }
            return;
        }

        _settings.clearPendingWebRequests(); // we want the new position to render faster, that might be the same position, which is fine they queue up pretty quick
        updateScaleCenterAndMap();
        if (getApp()._view != null) {
            getApp()._view.resetRenderTime();
        }
    }

    function cancelCacheCurrentMapArea() as Void {
        seedingZ = -1;
        seedingRectanglarTopLeft = new RectangularPoint(0f, 0f, 0f);
        seedingRectanglarBottomRight = new RectangularPoint(0f, 0f, 0f);
        seedingUpToTileX = 0;
        seedingUpToTileY = 0;
        seedingTilesOnThisLayer = NUMBER_MAX;
        seedingTilesProgressForThisLayer = 0;
    }

    function startCacheCurrentMapArea() as Void {
        if (!_settings.mapEnabled) {
            return;
        }

        var tileCache = getApp()._breadcrumbContext.tileCache();
        // If we do not clear the in memory tile cache the image tiles sometimes cause us to crash.
        // Think its because the graphics pool runs out of memory, and makeImageRequest fails with
        // Error: System Error
        // Details: failed inside handle_image_callback
        tileCache.clearValuesWithoutStorage();

        var centerRectangular = getScreenCenter();
        seedingRectanglarTopLeft = new RectangularPoint(
            centerRectangular.x - mapMoveDistanceM,
            centerRectangular.y + mapMoveDistanceM,
            0f
        );
        seedingRectanglarBottomRight = new RectangularPoint(
            centerRectangular.x + mapMoveDistanceM,
            centerRectangular.y - mapMoveDistanceM,
            0f
        );
        // start at max, and move towards min.
        // It's slower to do the lower layers first, but means if we run out of storage the higher layers will still be cached, so we will get a better experiece.
        // Rather than having all the fine details, but no overview, we at least get the overview tiles. Users can set tileLayerMin and tileLayerMax if they would prefer to cache only a single layer.
        seedingZ = _settings.tileLayerMax;
        // todo store current x and y for the for loop, also need to store the max/min tile coords
        // seedingX = ...
        // seedingY = ...
    }

    function seeding() as Boolean {
        return seedingZ >= 0;
    }

    function stepCacheCurrentMapArea() as Boolean {
        if (seedingZ == -1) {
            return false;
        }

        if (seedNextTilesToStorage()) {
            seedingZ--;
            seedingUpToTileX = 0;
            seedingUpToTileY = 0;
        }

        if (seedingZ < _settings.tileLayerMin) {
            // no more seeding
            cancelCacheCurrentMapArea();
            return false;
        }

        return true;
    }

    function seedNextTilesToStorage() as Boolean {
        var tileWidthM = earthsCircumference / Math.pow(2, seedingZ) / smallTilesPerScaledTile;

        // find which tile we are closest to
        var firstTileX = ((seedingRectanglarTopLeft.x + originShift) / tileWidthM).toNumber();
        var firstTileY = ((originShift - seedingRectanglarTopLeft.y) / tileWidthM).toNumber();
        // last tile is open ended range (+1)
        var lastTileX =
            ((seedingRectanglarBottomRight.x + originShift) / tileWidthM).toNumber() + 1;
        var lastTileY =
            ((originShift - seedingRectanglarBottomRight.y) / tileWidthM).toNumber() + 1;
        var origFirstTileY = firstTileY;

        var tilesPerXRow = lastTileX - firstTileX;
        seedingTilesOnThisLayer = tilesPerXRow * (lastTileY - firstTileY);

        // firstTileX = maxN(firstTileX, seedingUpToTileX); firstTileX cannot be capped, since it needs to start fresh on each row
        firstTileY = maxN(firstTileY, seedingUpToTileY);

        updateSeedingProgress(firstTileX, firstTileY, lastTileX, lastTileY);
        if (seedingUpToTileX == lastTileX - 1 && seedingUpToTileY == lastTileY - 1) {
            return true;
        }

        // our progress might have changed
        firstTileY = maxN(firstTileY, seedingUpToTileY);

        seedingTilesProgressForThisLayer =
            tilesPerXRow * (firstTileY - origFirstTileY) +
            tilesPerXRow -
            (lastTileX - maxN(firstTileX, seedingUpToTileX));

        var tileCache = getApp()._breadcrumbContext.tileCache();

        // we do not want to get a massive for loop that we then get killed by the watchdog
        // we also might not even fetch a tile, we need to wait until the previous set have responded
        // the we can move onto fetching the next set of tiles
        // the storage could also be very small, so we need to keep this number small
        // otherwsie we will
        // * try and download 10 tile to storage
        // * only fit the last 9 tiles in storage
        // * then we do not have all 10, so we will start again
        // ideally we would progress the storage seed based on the web handler responding with a tile
        var maxTilesAtATime = 10;
        maxTilesAtATime = minN(maxTilesAtATime, _settings.storageTileCacheSize);

        var tileStarted = 0;
        for (var y = firstTileY; y < lastTileY; ++y) {
            for (
                var x = y == firstTileY ? maxN(firstTileX, seedingUpToTileX) : firstTileX;
                x < lastTileX;
                ++x
            ) {
                ++tileStarted;
                var tileKey = new TileKey(x, y, seedingZ);
                if (!tileCache._storageTileCache.haveTile(tileKey)) {
                    // should we check if this tile is a 404/403 response?
                    // problem is we will keep trying to get it even if its a new tile that we just got
                    // we should probably store a 'downloadedAt' time on each tile in the cache so we can calculate a TTL
                    // logD("seeding storage tile: " + tileKey);
                    tileCache.seedTileToStorage(tileKey);
                }

                if (tileStarted >= maxTilesAtATime) {
                    return false;
                }
            }
        }

        return false;
    }

    function updateSeedingProgress(
        firstTileX as Number,
        firstTileY as Number,
        lastTileX as Number,
        lastTileY as Number
    ) {
        var tileCache = getApp()._breadcrumbContext.tileCache();

        for (var y = firstTileY; y < lastTileY; ++y) {
            for (
                var x = y == firstTileY ? maxN(firstTileX, seedingUpToTileX) : firstTileX;
                x < lastTileX;
                ++x
            ) {
                var tileKey = new TileKey(x, y, seedingZ);
                if (!tileCache._storageTileCache.haveTile(tileKey)) {
                    // we need to seed some more
                    return;
                }

                // we have the tile (may be a bad response, but we have attempted it in the past), move our progress forward
                // users should remove tile cache and start from scratch if they want to retry failed tiles
                seedingUpToTileX = x;
                seedingUpToTileY = y;
            }
        }
    }
}
