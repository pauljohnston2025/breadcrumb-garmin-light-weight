import Toybox.Application;
import Toybox.Lang;
import Toybox.Graphics;
import Toybox.System;
import Toybox.Activity;

const MAX_TILES_AT_A_TIME = 50;

// An iterator that walks along a line segment, yielding one point at a time.
(:storage)
class SegmentPointIterator {
    private var _x1 as Float;
    private var _y1 as Float;
    private var _x2 as Float;
    private var _y2 as Float;
    private var _stepDistance as Float;

    // State variables
    private var _totalDistance as Float;
    private var _dirX as Float;
    private var _dirY as Float;
    private var _distanceTraveled as Float;
    private var _isFinished as Boolean;

    // Constructor
    function initialize(
        x1 as Float,
        y1 as Float,
        x2 as Float,
        y2 as Float,
        stepDistanceM as Float
    ) {
        _x1 = x1;
        _y1 = y1;
        _x2 = x2;
        _y2 = y2;
        _stepDistance = stepDistanceM;

        var dx = _x2 - _x1;
        var dy = _y2 - _y1;
        _totalDistance = Math.sqrt(dx * dx + dy * dy).toFloat();

        if (_totalDistance > 0) {
            _dirX = dx / _totalDistance;
            _dirY = dy / _totalDistance;
        } else {
            _dirX = 0f;
            _dirY = 0f;
        }

        _distanceTraveled = 0f;
        _isFinished = false;
    }

    // Returns the next point [x, y] on the segment, or null if finished.
    function next() as [Float, Float]? {
        if (_isFinished) {
            return null;
        }

        var point;
        if (_distanceTraveled >= _totalDistance) {
            // We have reached or passed the end. Return the exact end point.
            point = [_x2, _y2];
            _isFinished = true;
        } else {
            // Calculate the current point based on distance traveled.
            var currentX = _x1 + _distanceTraveled * _dirX;
            var currentY = _y1 + _distanceTraveled * _dirY;
            point = [currentX, currentY];

            // Advance our state for the next call.
            _distanceTraveled += _stepDistance;
        }

        return point;
    }
}

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
    // things set to -1 are updated on the first layout/calculate call

    // updated when user manually pans around screen
    var fixedPosition as RectangularPoint?; // NOT SCALED - raw meters
    var scale as Float? = null; // fixed map scale, when manually zooming or panning around map
    var scaleCanInc as Boolean = true;
    var scaleCanDec as Boolean = true;

    // updated whenever we change zoom level (speed changes, zoom at pace mode etc.)
    var centerPosition as RectangularPoint = new RectangularPoint(0f, 0f, 0f); // scaled to pixels
    var currentScale as Float = 0.0; // pixels per meter so <pixel count> / _currentScale = meters  or  meters * _currentScale = pixels
    // will be changed whenever scale is adjusted, falls back to metersAroundUser when no scale
    var mapMoveDistanceM as Float = -1f;

    // updated whenever we get new activity data with a new heading
    var rotationRad as Float = 0.0f; // heading in radians
    var rotateCos as Float = Math.cos(rotationRad).toFloat() as Float;
    var rotateSin as Float = Math.sin(rotationRad).toFloat() as Float;
    var currentSpeed as Float = -1f;
    var elapsedDistanceM as Float = 0f;
    var currentlyZoomingAroundUser as Boolean = false;

    // updated whenever onlayout changes (audit usages, these should not need to be floats, but sometimes are used to do float math)
    // default to full screen guess
    var physicalScreenWidth as Float = System.getDeviceSettings().screenWidth.toFloat() as Float;
    var physicalScreenHeight as Float = System.getDeviceSettings().screenHeight.toFloat() as Float;
    var minPhysicalScreenDim as Float = -1f;
    var maxPhysicalScreenDim as Float = -1f;
    var xHalfPhysical as Float = physicalScreenWidth / 2f;
    var yHalfPhysical as Float = physicalScreenHeight / 2f;
    var virtualScreenWidth as Float = System.getDeviceSettings().screenWidth.toFloat() as Float;
    var virtualScreenHeight as Float = System.getDeviceSettings().screenHeight.toFloat() as Float;
    var minVirtualScreenDim as Float = -1f;
    var maxVirtualScreenDim as Float = -1f;
    var bufferedBitmapOffsetX as Float = -1f;
    var bufferedBitmapOffsetY as Float = 0f; // only need for buffered rotation mode, with user offset values less than 0.5
    var rotateAroundScreenX as Float = physicalScreenWidth / 2f;
    var rotateAroundScreenY as Float = physicalScreenHeight / 2f;
    var rotateAroundScreenXOffsetFactoredIn as Float = rotateAroundScreenX - bufferedBitmapOffsetX;
    var rotateAroundScreenYOffsetFactoredIn as Float = rotateAroundScreenY;
    var rotateAroundMinScreenDim as Float = -1f;
    var rotateAroundMaxScreenDim as Float = -1f;
    var rotationMatrix as AffineTransform = new AffineTransform();

    function initialize(settings as Settings) {
        self._settings = settings;
        // initialised in constructor so they can be inlined
        minPhysicalScreenDim = minF(physicalScreenWidth, physicalScreenHeight);
        maxPhysicalScreenDim = maxF(physicalScreenWidth, physicalScreenHeight);
        minVirtualScreenDim = minF(virtualScreenWidth, virtualScreenHeight);
        maxVirtualScreenDim = maxF(virtualScreenWidth, virtualScreenHeight);
        bufferedBitmapOffsetX = -(maxVirtualScreenDim - physicalScreenWidth) / 2f;
        rotateAroundMinScreenDim = minPhysicalScreenDim;
        rotateAroundMaxScreenDim = maxPhysicalScreenDim;
    }

    function setup() as Void {
        fixedPosition = null;
        // will be changed whenever scale is adjusted, falls back to metersAroundUser when no scale
        mapMoveDistanceM = _settings.metersAroundUser.toFloat() * _settings.mapMoveScreenSize;
        recalculateAll();
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

            // tmp vars so we can inline the function and remove it
            var outerBoundingBox0Tmp = outerBoundingBox[0] as Float;
            var outerBoundingBox1Tmp = outerBoundingBox[1] as Float;
            var outerBoundingBox2Tmp = outerBoundingBox[2] as Float;
            var outerBoundingBox3Tmp = outerBoundingBox[3] as Float;

            var routeBoundingBox0Tmp = route.boundingBox[0] as Float;
            var routeBoundingBox1Tmp = route.boundingBox[1] as Float;
            var routeBoundingBox2Tmp = route.boundingBox[2] as Float;
            var routeBoundingBox3Tmp = route.boundingBox[3] as Float;

            outerBoundingBox0Tmp = minF(routeBoundingBox0Tmp / scaleDivisor, outerBoundingBox0Tmp);
            outerBoundingBox1Tmp = minF(routeBoundingBox1Tmp / scaleDivisor, outerBoundingBox1Tmp);
            outerBoundingBox2Tmp = maxF(routeBoundingBox2Tmp / scaleDivisor, outerBoundingBox2Tmp);
            outerBoundingBox3Tmp = maxF(routeBoundingBox3Tmp / scaleDivisor, outerBoundingBox3Tmp);

            outerBoundingBox[0] = outerBoundingBox0Tmp;
            outerBoundingBox[1] = outerBoundingBox1Tmp;
            outerBoundingBox[2] = outerBoundingBox2Tmp;
            outerBoundingBox[3] = outerBoundingBox3Tmp;
        }

        return outerBoundingBox;
    }

    /** returns true if a rescale occurred */
    function updateScaleCenter() as Boolean {
        var newScale = getNewScaleAndUpdateCenter();
        var rescaleOccurred = handleNewScale(newScale);
        return rescaleOccurred;
    }

    /** returns the new scale */
    function getNewScaleAndUpdateCenter() as Float {
        if (currentlyZoomingAroundUser) {
            var renderDistanceM = _settings.metersAroundUser;
            if (!calcCenterPoint()) {
                var lastPoint = getApp()._breadcrumbContext.track.coordinates.lastPoint();
                if (lastPoint != null) {
                    centerPosition = lastPoint;
                    return calculateScale(renderDistanceM.toFloat());
                }
                // we are zooming around the user, but we do not have a last track point
                // resort to using bounding box
                var boundingBox = calcOuterBoundingBoxFromTrackAndRoutes(
                    getApp()._breadcrumbContext.routes,
                    null
                );
                calcCenterPointForBoundingBox(boundingBox);
                return calculateScale(renderDistanceM.toFloat());
            }

            return calculateScale(renderDistanceM.toFloat());
        }

        var boundingBox = calcOuterBoundingBoxFromTrackAndRoutes(
            getApp()._breadcrumbContext.routes,
            // if no roues we will try and render the track instead
            _settings.zoomAtPaceMode == ZOOM_AT_PACE_MODE_SHOW_ROUTES_WITHOUT_TRACK &&
                getApp()._breadcrumbContext.routes.size() != 0
                ? null
                : optionalTrackBoundingBox()
        );
        calcCenterPointForBoundingBox(boundingBox);
        return getNewScaleFromBoundingBox(boundingBox);
    }

    function optionalTrackBoundingBox() as [Float, Float, Float, Float]? {
        return getApp()._breadcrumbContext.track.coordinates.lastPoint() == null
            ? null
            : getApp()._breadcrumbContext.track.boundingBox;
    }

    /** returns true if a rescale occurred */
    function onActivityInfo(activityInfo as Activity.Info) as Boolean {
        // logT(
        //     "store heading, current speed etc. so we can know how to render the "
        //     + "map");
        // garmin might already do this for us? the docs say
        // track:
        // The current track in radians.
        // Track is the direction of travel in radians based on GPS movement. If supported by the device, this provides compass orientation when stopped.
        // currentHeading :
        // The true north referenced heading in radians.
        // This provides compass orientation if it is supported by the device.
        // based on some of the posts here, its better to use currentHeading if we want our compas to work whilst not moving, and track is only supported on some devices
        // https://forums.garmin.com/developer/connect-iq/f/discussion/258978/currentheading
        var currentHeading = activityInfo.currentHeading;
        if (activityInfo has :track) {
            var track = activityInfo.track;
            if (currentHeading == null && track != null) {
                currentHeading = track;
            }
        }

        if (currentHeading != null) {
            rotationRad = currentHeading;
            rotateCos = Math.cos(rotationRad).toFloat();
            rotateSin = Math.sin(rotationRad).toFloat();
        }
        var _currentSpeed = activityInfo.currentSpeed;
        if (_currentSpeed != null) {
            currentSpeed = _currentSpeed;
        }

        updateRotationMatrix();

        var _elapsedDistance = activityInfo.elapsedDistance;
        if (_elapsedDistance != null) {
            elapsedDistanceM = _elapsedDistance;
        }

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
            updateUserRotationElements(getCenterUserOffsetY());
            var ret = updateScaleCenter();
            getApp()._view.resetRenderTime();
            return ret;
        }

        return false;
    }

    function setScreenSize(width as Number, height as Number) as Void {
        physicalScreenWidth = width.toFloat();
        physicalScreenHeight = height.toFloat();
        minPhysicalScreenDim = minF(physicalScreenWidth, physicalScreenHeight);
        maxPhysicalScreenDim = maxF(physicalScreenWidth, physicalScreenHeight);
        xHalfPhysical = physicalScreenWidth / 2f;
        yHalfPhysical = physicalScreenHeight / 2f;

        updateVirtualScreenSize();
        updateScaleCenter();
    }

    (:inline)
    function getCenterUserOffsetY() as Float {
        var centerUserOffsetY = _settings.centerUserOffsetY;
        // we do not want to be offset from the center of the screen, when we are viewing a position or panning around the map use the center of the screen,
        // not the offset center that we want when following our location (to see more of the map ahead)
        return fixedPosition != null ? 0.5f : centerUserOffsetY;
    }

    function updateVirtualScreenSize() as Void {
        var centerUserOffsetY = getCenterUserOffsetY();

        virtualScreenWidth = physicalScreenWidth; // always the same, just using naming for consistency
        if (_settings.renderMode == RENDER_MODE_UNBUFFERED_ROTATING) {
            if (centerUserOffsetY >= 0.5) {
                virtualScreenHeight = physicalScreenHeight * centerUserOffsetY * 2;
            } else {
                virtualScreenHeight =
                    (physicalScreenHeight - physicalScreenHeight * centerUserOffsetY) * 2;
            }
        } else {
            virtualScreenHeight = physicalScreenHeight;
        }

        minVirtualScreenDim = minF(virtualScreenWidth, virtualScreenHeight);
        maxVirtualScreenDim = maxF(virtualScreenWidth, virtualScreenHeight);

        updateUserRotationElements(centerUserOffsetY);
    }

    function updateUserRotationElements(centerUserOffsetY as Float) as Void {
        if (currentlyZoomingAroundUser) {
            rotateAroundScreenX = virtualScreenWidth / 2f;
            rotateAroundScreenY = physicalScreenHeight * centerUserOffsetY;
            rotateAroundMinScreenDim = minVirtualScreenDim;
            rotateAroundMaxScreenDim = maxVirtualScreenDim;
        } else {
            rotateAroundScreenX = xHalfPhysical;
            rotateAroundScreenY = yHalfPhysical;
            rotateAroundMinScreenDim = minPhysicalScreenDim;
            rotateAroundMaxScreenDim = maxPhysicalScreenDim;
        }

        if (_settings.renderMode == RENDER_MODE_UNBUFFERED_ROTATING) {
            // unbuffered mode -> draws straight to dc
            rotateAroundScreenXOffsetFactoredIn = rotateAroundScreenX;
            rotateAroundScreenYOffsetFactoredIn = rotateAroundScreenY;
            bufferedBitmapOffsetX = rotateAroundScreenX;
            bufferedBitmapOffsetY = rotateAroundScreenY;

            if (currentlyZoomingAroundUser) {
                bufferedBitmapOffsetX = -(rotateAroundMaxScreenDim - physicalScreenWidth) / 2f;
                bufferedBitmapOffsetY = -(rotateAroundMaxScreenDim - physicalScreenHeight);
                // dirty hacks, using bufferedBitmapOffsetX for map renderer to do the tile offsets
                // if we use just mapBitmapOffsetX/mapBitmapOffsetY we get clipping
                bufferedBitmapOffsetX = rotateAroundScreenX - bufferedBitmapOffsetX;
                bufferedBitmapOffsetY = rotateAroundScreenY - bufferedBitmapOffsetY;

                if (centerUserOffsetY >= 0.5) {
                    bufferedBitmapOffsetY = rotateAroundScreenY;
                }
            }
        } else {
            // RENDER_MODE_UNBUFFERED_NO_ROTATION
            // unbuffered mode -> draws straight to dc
            rotateAroundScreenXOffsetFactoredIn = rotateAroundScreenX;
            rotateAroundScreenYOffsetFactoredIn = rotateAroundScreenY;
        }

        updateRotationMatrix();
    }

    function updateRotationMatrix() as Void {
        rotationMatrix = new AffineTransform();
        rotationMatrix.translate(rotateAroundScreenX, rotateAroundScreenY); // move to center
        rotationMatrix.rotate(-rotationRad); // rotate
        rotationMatrix.translate(
            -rotateAroundScreenXOffsetFactoredIn,
            -rotateAroundScreenYOffsetFactoredIn
        ); // move back to position
    }

    function calculateScale(maxDistanceM as Float) as Float {
        if (scale != null) {
            return scale;
        }

        return calcScaleForScreenMeters(maxDistanceM);
    }

    function calcScaleForScreenMeters(maxDistanceM as Float) as Float {
        // we want the whole map to be show on the screen, we have 360 pixels on the
        // venu 2s
        // but this would only work for squares, so 0.75 fudge factor for circle
        // watch face
        return (rotateAroundMinScreenDim / maxDistanceM) * 0.75;
    }

    /** returns the new scale */
    function getNewScaleFromBoundingBox(outerBoundingBox as [Float, Float, Float, Float]) as Float {
        var xDistanceM = outerBoundingBox[2] - outerBoundingBox[0];
        var yDistanceM = outerBoundingBox[3] - outerBoundingBox[1];

        var maxDistanceM = maxF(xDistanceM, yDistanceM);

        if (maxDistanceM == 0f) {
            // show 1m of space to avaoid division by 0
            maxDistanceM = 1f;
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
            return false; // don't allow silly scales
        }

        var scaleFactor = newScale;
        if (currentScale != null && currentScale != 0f) {
            // adjust by old scale
            scaleFactor = newScale / currentScale;
        }

        var routes = getApp()._breadcrumbContext.routes;
        for (var i = 0; i < routes.size(); ++i) {
            var route = routes[i];
            route.rescale(scaleFactor); // rescale all routes, even if they are not enabled
        }
        getApp()._breadcrumbContext.track.rescale(scaleFactor);
        getApp()._view.rescale(scaleFactor);
        centerPosition.rescaleInPlace(scaleFactor);

        currentScale = newScale;
        return true;
    }

    function recalculateAll() as Void {
        logT("recalculating all cached values from settings/routes change");
        updateFixedPositionFromSettings();
        updateVirtualScreenSize();
        updateScaleCenter();
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

    function moveLatLong(
        xMoveUnrotated as Float,
        yMoveUnrotated as Float,
        xMoveRotated as Float,
        yMoveRotated as Float
    ) as Void {
        setPositionAndScaleIfNotSet();
        var latlong = getNewLatLong(xMoveUnrotated, yMoveUnrotated, xMoveRotated, yMoveRotated);

        if (latlong != null) {
            _settings.setFixedPositionRaw(latlong[0], latlong[1]);
        }
        updateFixedPositionFromSettings();
        updateScaleCenter();
        getApp()._view.resetRenderTime();
    }

    function getNewLatLong(
        xMoveUnrotated as Float,
        yMoveUnrotated as Float,
        xMoveRotated as Float,
        yMoveRotated as Float
    ) as [Float, Float]? {
        var fixedPositionL = fixedPosition;
        if (fixedPositionL == null) {
            // never happens, but appease the compiler
            logE("unreachable, fixedPositionL is null");
            return null;
        }
        if (_settings.renderMode == RENDER_MODE_UNBUFFERED_NO_ROTATION) {
            return RectangularPoint.xyToLatLon(
                fixedPositionL.x + xMoveUnrotated,
                fixedPositionL.y + yMoveUnrotated
            );
        }

        return RectangularPoint.xyToLatLon(
            fixedPositionL.x + xMoveRotated,
            fixedPositionL.y + yMoveRotated
        );
    }

    function moveFixedPositionUp() as Void {
        moveLatLong(
            0f,
            mapMoveDistanceM,
            rotateSin * mapMoveDistanceM,
            rotateCos * mapMoveDistanceM
        );
    }

    function moveFixedPositionDown() as Void {
        moveLatLong(
            0f,
            -mapMoveDistanceM,
            -rotateSin * mapMoveDistanceM,
            -rotateCos * mapMoveDistanceM
        );
    }

    function moveFixedPositionLeft() as Void {
        moveLatLong(
            -mapMoveDistanceM,
            0f,
            -rotateCos * mapMoveDistanceM,
            rotateSin * mapMoveDistanceM
        );
    }

    function moveFixedPositionRight() as Void {
        moveLatLong(
            mapMoveDistanceM,
            0f,
            rotateCos * mapMoveDistanceM,
            -rotateSin * mapMoveDistanceM
        );
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
            var lastPoint = getApp()._breadcrumbContext.track.coordinates.lastPoint();
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
        // we need to set a fixed scale so that a user moving does not change the zoom level randomly whilst they are viewing a map and panning
        if (scale == null) {
            var scaleToSet = currentScale;
            if (currentScale == 0f) {
                scaleToSet = calculateScale(_settings.metersAroundUser.toFloat());
            }
            setScale(scaleToSet);
        }

        if (fixedPosition != null) {
            // we are already good to go
            return;
        }

        var center = getScreenCenter();

        // the current center can have an offset applied, we want the current middle of the screen to become our new fixed position location
        var offsetXPx = xHalfPhysical - rotateAroundScreenX;
        var offsetYPx = yHalfPhysical - rotateAroundScreenY;

        var unrotatedOffsetXPx = offsetXPx * rotateCos - offsetYPx * rotateSin;
        var unrotatedOffsetYPx = offsetXPx * rotateSin + offsetYPx * rotateCos;

        if (currentScale == 0f) {
            // hmm how did this happen?
            logE("currentScale not set when it should be");
            fixedPosition = center;
            updateVirtualScreenSize();
            return;
        }

        var xAddM = unrotatedOffsetXPx / currentScale;
        // The Y-axis is inverted between screen (down is +) and map (up is +),
        // so we must subtract the Y offset to correctly move North/South.
        var yAddM = -(unrotatedOffsetYPx / currentScale);
        fixedPosition = new RectangularPoint(center.x + xAddM, center.y + yAddM, 0f);

        // logT("new fixed pos: " + fixedPosition);
        // all code paths that call into here also call
        // updateScaleCenter so we will avoid calling it here
        // but we must update the screen size, and tell the view about it
        updateVirtualScreenSize();
    }

    function getScreenCenter() as RectangularPoint {
        var divisor = currentScale;
        if (divisor == 0f) {
            // we should always have a current scale at this point, since we manually set scale (or we are caching map tiles)
            logE("Warning: current scale was somehow not set");
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
        var center = RectangularPoint.latLon2xy(fixedLatitude, fixedLongitude, 0f);
        if (center != null) {
            return center;
        }

        return new RectangularPoint(0f, 0f, 0f); // highly unlikely code path
    }

    function returnToUser() as Void {
        // set fixed position recalculates all on us
        _settings.setFixedPosition(null, null);
        setScale(null);
    }

    function setScale(_scale as Float?) as Void {
        scale = _scale;
        // be very careful about putting null into properties, it breaks everything
        if (scale == null) {
            updateScaleCenter();
            // this is not the best guess, but will only require the user to tap zoom once to see that it cannot zoom
            // getScaleDecIncAmount() only works when the scale is not null. We could update it to use the currentScale if scale is null?
            // they are not actually in a user scale in this case though, so makes sense to show that we are tracking the users desired zoom instead of ours
            scaleCanInc = true;
            scaleCanDec = true;
            getApp()._view.resetRenderTime();
            return;
        }

        updateScaleCenter();
        getApp()._view.resetRenderTime();
    }
}
