import Toybox.Activity;
import Toybox.Position;
import Toybox.Lang;
import Toybox.Time;
import Toybox.WatchUi;
import Toybox.Communications;
import Toybox.Graphics;

const DESIRED_SCALE_PIXEL_WIDTH as Float = 100.0f;
const DESIRED_ELEV_SCALE_PIXEL_WIDTH as Float = 50.0f;
// note sure why this has anything to do with DESIRED_SCALE_PIXEL_WIDTH, should just be whatever tile layer 0 equates to for the screen size
const MIN_SCALE as Float = DESIRED_SCALE_PIXEL_WIDTH / 1000000000.0f;

class BreadcrumbRenderer {
    // todo put into ui class
    var _clearRouteProgress as Number = 0;
    var settings as Settings;
    var _cachedValues as CachedValues;
    var _crosshair as BitmapResource;
    var _leftArrow as BitmapResource;
    var _rightArrow as BitmapResource;
    var _upArrow as BitmapResource;
    var _downArrow as BitmapResource;

    // units in meters (float/int) to label
    var SCALE_NAMES as Dictionary = {
        1 => "1m",
        5 => "5m",
        10 => "10m",
        20 => "20m",
        30 => "30m",
        40 => "40m",
        50 => "50m",
        100 => "100m",
        250 => "250m",
        500 => "500m",
        1000 => "1km",
        2000 => "2km",
        3000 => "3km",
        4000 => "4km",
        5000 => "5km",
        10000 => "10km",
        20000 => "20km",
        30000 => "30km",
        40000 => "40km",
        50000 => "50km",
        100000 => "100km",
        500000 => "500km",
        1000000 => "1000km",
        10000000 => "10000km",
    };

    var ELEVATION_SCALE_NAMES as Dictionary = {
        // some rediculously small values for level ground (highly unlikely in the wild, but common on simulator)
        0.001 => "1mm",
        0.0025 => "2.5mm",
        0.005 => "5mm",
        0.01 => "1cm",
        0.025 => "2.5cm",
        0.05 => "5cm",
        0.1 => "10cm",
        0.25 => "25cm",
        0.5 => "50cm",
        1 => "1m",
        5 => "5m",
        10 => "10m",
        20 => "20m",
        30 => "30m",
        40 => "40m",
        50 => "50m",
        100 => "100m",
        250 => "250m",
        500 => "500m",
    };

    // benchmark same track loaded (just render track no activity running) using
    // average time over 1min of benchmark
    // (just route means we always have a heap of points, and a small track does not bring the average down)
    // 13307us or 17718us - renderTrack manual code (rotateCos, rotateSin)
    // 15681us or 17338us or 11996us - renderTrack manual code (rotateCos, rotateSin)  - use local variables might be faster lookup?
    // 11162us or 18114us - rotateCos, rotateSin and hard code 180 as xhalf/yhalf
    // 22297us - renderTrack Graphics.AffineTransform

    function initialize(settings as Settings, cachedValues as CachedValues) {
        self.settings = settings;
        _cachedValues = cachedValues;
        _crosshair = WatchUi.loadResource(Rez.Drawables.Crosshair);
        _leftArrow = WatchUi.loadResource(Rez.Drawables.LeftArrow);
        _rightArrow = WatchUi.loadResource(Rez.Drawables.RightArrow);
        _upArrow = WatchUi.loadResource(Rez.Drawables.UpArrow);
        _downArrow = WatchUi.loadResource(Rez.Drawables.DownArrow);
    }

    function getScaleSize() as [Number, Number] {
        return getScaleSizeGeneric(
            _cachedValues.currentScale,
            DESIRED_SCALE_PIXEL_WIDTH,
            SCALE_NAMES
        );
    }

    function getScaleSizeGeneric(
        scale as Float,
        desiredWidth as Float,
        scaleNames as Dictionary
    ) as [Number, Number] {
        var foundDistanceM = 10;
        var foundPixelWidth = 0;
        // get the closest without going over
        // keys loads them in random order, we want the smallest first
        var keys = scaleNames.keys();
        keys.sort(null);
        for (var i = 0; i < keys.size(); ++i) {
            var distanceM = keys[i];
            var testPixelWidth = (distanceM as Float) * scale;
            if (testPixelWidth > desiredWidth) {
                break;
            }

            foundPixelWidth = testPixelWidth;
            foundDistanceM = distanceM;
        }

        return [foundPixelWidth, foundDistanceM];
    }

    function renderCurrentScale(dc as Dc) {
        var scaleData = getScaleSize();
        var pixelWidth = scaleData[0];
        var distanceM = scaleData[1];
        if (pixelWidth == 0) {
            return;
        }

        var foundName = SCALE_NAMES[distanceM];

        var y = _cachedValues.screenHeight - 20;
        dc.setColor(settings.normalModeColour, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(4);
        dc.drawLine(
            _cachedValues.xHalf - pixelWidth / 2.0f,
            y,
            _cachedValues.xHalf + pixelWidth / 2.0f,
            y
        );
        dc.drawText(
            _cachedValues.xHalf,
            y - 30,
            Graphics.FONT_XTINY,
            foundName,
            Graphics.TEXT_JUSTIFY_CENTER
        );
    }

    // points should already be scaled
    function renderLineFromLastPointToRoute(
        dc as Dc,
        lastPoint as RectangularPoint,
        offTrackPoint as RectangularPoint
    ) as Void {
        // todo make this use the buffered rendering mode
        // its only when off track, so not a huge issue
        if (settings.mode != MODE_NORMAL && settings.mode != MODE_MAP_MOVE) {
            // its very confusing seeing the routes disappear when scrolling
            // and it makes sense to want to sroll around the route too
            return;
        }

        var centerPosition = _cachedValues.centerPosition; // local lookup faster
        var rotateCos = _cachedValues.rotateCos; // local lookup faster
        var rotateSin = _cachedValues.rotateSin; // local lookup faster
        var xHalf = _cachedValues.xHalf; // local lookup faster
        var yHalf = _cachedValues.yHalf; // local lookup faster

        var lastPointUnrotatedX = lastPoint.x - centerPosition.x;
        var lastPointUnrotatedY = lastPoint.y - centerPosition.y;

        var lastPointRotatedX = xHalf + lastPointUnrotatedX;
        var lastPointRotatedY = yHalf - lastPointUnrotatedY;
        if (
            settings.renderMode == RENDER_MODE_BUFFERED_ROTATING ||
            settings.renderMode == RENDER_MODE_UNBUFFERED_ROTATING
        ) {
            lastPointRotatedX =
                xHalf + rotateCos * lastPointUnrotatedX - rotateSin * lastPointUnrotatedY;
            lastPointRotatedY =
                yHalf - (rotateSin * lastPointUnrotatedX + rotateCos * lastPointUnrotatedY);
        }

        var offTrackPointUnrotatedX = offTrackPoint.x - centerPosition.x;
        var offTrackPointUnrotatedY = offTrackPoint.y - centerPosition.y;

        var offTrackPointRotatedX = xHalf + offTrackPointUnrotatedX;
        var offTrackPointRotatedY = yHalf - offTrackPointUnrotatedY;
        if (
            settings.renderMode == RENDER_MODE_BUFFERED_ROTATING ||
            settings.renderMode == RENDER_MODE_UNBUFFERED_ROTATING
        ) {
            offTrackPointRotatedX =
                xHalf + rotateCos * offTrackPointUnrotatedX - rotateSin * offTrackPointUnrotatedY;
            offTrackPointRotatedY =
                yHalf - (rotateSin * offTrackPointUnrotatedX + rotateCos * offTrackPointUnrotatedY);
        }

        dc.setPenWidth(4);
        dc.setColor(Graphics.COLOR_RED, Graphics.COLOR_BLACK);
        dc.drawLine(
            lastPointRotatedX,
            lastPointRotatedY,
            offTrackPointRotatedX,
            offTrackPointRotatedY
        );
    }

    // last location should already be scaled
    function renderUser(dc as Dc, usersLastLocation as RectangularPoint) as Void {
        var centerPosition = _cachedValues.centerPosition; // local lookup faster
        var rotateCos = _cachedValues.rotateCos; // local lookup faster
        var rotateSin = _cachedValues.rotateSin; // local lookup faster
        var xHalf = _cachedValues.xHalf; // local lookup faster
        var yHalf = _cachedValues.yHalf; // local lookup faster

        var userPosUnrotatedX = usersLastLocation.x - centerPosition.x;
        var userPosUnrotatedY = usersLastLocation.y - centerPosition.y;

        var userPosRotatedX = xHalf + userPosUnrotatedX;
        var userPosRotatedY = yHalf - userPosUnrotatedY;
        if (
            settings.renderMode == RENDER_MODE_BUFFERED_ROTATING ||
            settings.renderMode == RENDER_MODE_UNBUFFERED_ROTATING
        ) {
            userPosRotatedX = xHalf + rotateCos * userPosUnrotatedX - rotateSin * userPosUnrotatedY;
            userPosRotatedY =
                yHalf - (rotateSin * userPosUnrotatedX + rotateCos * userPosUnrotatedY);
        }

        var triangleSizeY = 10;
        var triangleSizeX = 4;
        var triangleTopX = userPosRotatedX;
        var triangleTopY = userPosRotatedY - triangleSizeY;

        var triangleLeftX = triangleTopX - triangleSizeX;
        var triangleLeftY = userPosRotatedY + triangleSizeY;

        var triangleRightX = triangleTopX + triangleSizeX;
        var triangleRightY = triangleLeftY;

        var triangleCenterX = userPosRotatedX;
        var triangleCenterY = userPosRotatedY;

        if (
            settings.renderMode != RENDER_MODE_BUFFERED_ROTATING &&
            settings.renderMode != RENDER_MODE_UNBUFFERED_ROTATING
        ) {
            // todo: load user arrow from bitmap and draw rotated instead
            // we normally rotate the track, but we now need to rotate the user
            var triangleTopXRot =
                triangleCenterX +
                rotateCos * (triangleTopX - triangleCenterX) -
                rotateSin * (triangleTopY - triangleCenterY);
            // yes + and not -, we are in pixel coordinates, the rest are in latitude which is negative at the bottom of the page
            triangleTopY =
                triangleCenterY +
                (rotateSin * (triangleTopX - triangleCenterX) +
                    rotateCos * (triangleTopY - triangleCenterY));
            triangleTopX = triangleTopXRot;

            var triangleLeftXRot =
                triangleCenterX +
                rotateCos * (triangleLeftX - triangleCenterX) -
                rotateSin * (triangleLeftY - triangleCenterY);
            // yes + and not -, we are in pixel coordinates, the rest are in latitude which is negative at the bottom of the page
            triangleLeftY =
                triangleCenterY +
                (rotateSin * (triangleLeftX - triangleCenterX) +
                    rotateCos * (triangleLeftY - triangleCenterY));
            triangleLeftX = triangleLeftXRot;

            var triangleRightXRot =
                triangleCenterX +
                rotateCos * (triangleRightX - triangleCenterX) -
                rotateSin * (triangleRightY - triangleCenterY);
            // yes + and not -, we are in pixel coordinates, the rest are in latitude which is negative at the bottom of the page
            triangleRightY =
                triangleCenterY +
                (rotateSin * (triangleRightX - triangleCenterX) +
                    rotateCos * (triangleRightY - triangleCenterY));
            triangleRightX = triangleRightXRot;
        }

        dc.setColor(settings.userColour, Graphics.COLOR_BLACK);
        dc.setPenWidth(6);
        dc.drawLine(triangleTopX, triangleTopY, triangleRightX, triangleRightY);
        dc.drawLine(triangleRightX, triangleRightY, triangleLeftX, triangleLeftY);
        dc.drawLine(triangleLeftX, triangleLeftY, triangleTopX, triangleTopY);
    }

    function renderTrackUnrotated(
        dc as Dc,
        breadcrumb as BreadcrumbTrack,
        colour as Graphics.ColorType
    ) as Void {
        var centerPosition = _cachedValues.centerPosition; // local lookup faster
        var xHalf = _cachedValues.xHalf; // local lookup faster
        var yHalf = _cachedValues.yHalf; // local lookup faster

        if (settings.mode != MODE_NORMAL && settings.mode != MODE_MAP_MOVE) {
            // its very cofusing seeing the routes disappear when scrolling
            // and it makes sense to want to sroll around the route too
            return;
        }

        dc.setColor(colour, Graphics.COLOR_BLACK);
        dc.setPenWidth(4);

        var size = breadcrumb.coordinates.size();
        var coordinatesRaw = breadcrumb.coordinates._internalArrayBuffer;

        // note: size is using the overload of points array (the reduced pointarray size)
        // but we draw from the raw points
        if (size >= ARRAY_POINT_SIZE * 2) {
            var firstXScaledAtCenter = coordinatesRaw[0] - centerPosition.x;
            var firstYScaledAtCenter = coordinatesRaw[1] - centerPosition.y;
            var lastX = xHalf + firstXScaledAtCenter;
            var lastY = yHalf - firstYScaledAtCenter;

            for (var i = ARRAY_POINT_SIZE; i < size; i += ARRAY_POINT_SIZE) {
                var nextX = xHalf + (coordinatesRaw[i] - centerPosition.x);
                var nextY = yHalf - (coordinatesRaw[i + 1] - centerPosition.y);

                dc.drawLine(lastX, lastY, nextX, nextY);

                lastX = nextX;
                lastY = nextY;
            }
        }
    }

    function renderTrackName(
        dc as Dc,
        breadcrumb as BreadcrumbTrack,
        colour as Graphics.ColorType
    ) as Void {
        dc.setColor(colour, Graphics.COLOR_BLACK);
        dc.setPenWidth(4);
        var centerPosition = _cachedValues.centerPosition; // local lookup faster
        var xHalf = _cachedValues.xHalf; // local lookup faster
        var yHalf = _cachedValues.yHalf; // local lookup faster
        var rotateCos = _cachedValues.rotateCos; // local lookup faster
        var rotateSin = _cachedValues.rotateSin; // local lookup faster

        var xScaledAtCenter = breadcrumb.boundingBoxCenter.x - centerPosition.x;
        var yScaledAtCenter = breadcrumb.boundingBoxCenter.y - centerPosition.y;

        var x = xHalf + rotateCos * xScaledAtCenter - rotateSin * yScaledAtCenter;
        var y = yHalf - (rotateSin * xScaledAtCenter + rotateCos * yScaledAtCenter);
        dc.drawText(
            x,
            y,
            Graphics.FONT_XTINY,
            settings.routeName(breadcrumb.storageIndex),
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER
        );
    }

    function renderTrackNameUnrotated(
        dc as Dc,
        breadcrumb as BreadcrumbTrack,
        colour as Graphics.ColorType
    ) as Void {
        dc.setColor(colour, Graphics.COLOR_BLACK);
        dc.setPenWidth(4);
        var centerPosition = _cachedValues.centerPosition; // local lookup faster
        var xHalf = _cachedValues.xHalf; // local lookup faster
        var yHalf = _cachedValues.yHalf; // local lookup faster

        var xScaledAtCenter = breadcrumb.boundingBoxCenter.x - centerPosition.x;
        var yScaledAtCenter = breadcrumb.boundingBoxCenter.y - centerPosition.y;

        var x = xHalf + xScaledAtCenter;
        var y = yHalf - yScaledAtCenter;

        dc.drawText(
            x,
            y,
            Graphics.FONT_XTINY,
            settings.routeName(breadcrumb.storageIndex),
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER
        );
    }

    function renderTrack(
        dc as Dc,
        breadcrumb as BreadcrumbTrack,
        colour as Graphics.ColorType
    ) as Void {
        var centerPosition = _cachedValues.centerPosition; // local lookup faster
        var rotateCos = _cachedValues.rotateCos; // local lookup faster
        var rotateSin = _cachedValues.rotateSin; // local lookup faster
        var xHalf = _cachedValues.xHalf; // local lookup faster
        var yHalf = _cachedValues.yHalf; // local lookup faster

        if (settings.mode != MODE_NORMAL && settings.mode != MODE_MAP_MOVE) {
            // its very cofusing seeing the routes disappear when scrolling
            // and it makes sense to want to sroll around the route too
            return;
        }

        dc.setColor(colour, Graphics.COLOR_BLACK);
        dc.setPenWidth(4);

        var size = breadcrumb.coordinates.size();
        var coordinatesRaw = breadcrumb.coordinates._internalArrayBuffer;

        // note: size is using the overload of points array (the reduced pointarray size)
        // but we draw from the raw points
        if (size >= ARRAY_POINT_SIZE * 2) {
            var firstXScaledAtCenter = coordinatesRaw[0] - centerPosition.x;
            var firstYScaledAtCenter = coordinatesRaw[1] - centerPosition.y;
            var lastXRotated =
                xHalf + rotateCos * firstXScaledAtCenter - rotateSin * firstYScaledAtCenter;
            var lastYRotated =
                yHalf - (rotateSin * firstXScaledAtCenter + rotateCos * firstYScaledAtCenter);

            for (var i = ARRAY_POINT_SIZE; i < size; i += ARRAY_POINT_SIZE) {
                var nextX = coordinatesRaw[i];
                var nextY = coordinatesRaw[i + 1];

                var nextXScaledAtCenter = nextX - centerPosition.x;
                var nextYScaledAtCenter = nextY - centerPosition.y;

                var nextXRotated =
                    xHalf + rotateCos * nextXScaledAtCenter - rotateSin * nextYScaledAtCenter;
                var nextYRotated =
                    yHalf - (rotateSin * nextXScaledAtCenter + rotateCos * nextYScaledAtCenter);

                dc.drawLine(lastXRotated, lastYRotated, nextXRotated, nextYRotated);

                lastXRotated = nextXRotated;
                lastYRotated = nextYRotated;
            }
        }
    }

    function renderClearTrackUi(dc as Dc) as Boolean {
        var xHalf = _cachedValues.xHalf; // local lookup faster
        var yHalf = _cachedValues.yHalf; // local lookup faster
        var screenHeight = _cachedValues.screenHeight; // local lookup faster

        // should be using Toybox.WatchUi.Confirmation and Toybox.WatchUi.ConfirmationDelegate for questions
        var padding = xHalf / 2.0f;
        var topText = yHalf / 2.0f;
        switch (_clearRouteProgress) {
            case 0:
                break;
            case 1:
            case 3: {
                // press right to confirm, left cancels
                dc.setColor(Graphics.COLOR_RED, Graphics.COLOR_RED);
                dc.fillRectangle(0, 0, xHalf, screenHeight);
                dc.setColor(Graphics.COLOR_GREEN, Graphics.COLOR_GREEN);
                dc.fillRectangle(xHalf, 0, xHalf, screenHeight);
                dc.setColor(settings.uiColour, Graphics.COLOR_TRANSPARENT);
                dc.drawText(
                    xHalf - padding,
                    yHalf,
                    Graphics.FONT_XTINY,
                    "N",
                    Graphics.TEXT_JUSTIFY_CENTER
                );
                dc.drawText(
                    xHalf + padding,
                    yHalf,
                    Graphics.FONT_XTINY,
                    "Y",
                    Graphics.TEXT_JUSTIFY_CENTER
                );
                var text =
                    _clearRouteProgress == 1
                        ? "Clearing all routes, are you sure?"
                        : "Clearing all routes, LAST CHANCE!!!";
                dc.drawText(
                    xHalf,
                    topText,
                    Graphics.FONT_XTINY,
                    text,
                    Graphics.TEXT_JUSTIFY_CENTER
                );
                return true;
            }
            case 2: {
                // press left to confirm, right cancels
                dc.setColor(Graphics.COLOR_GREEN, Graphics.COLOR_GREEN);
                dc.fillRectangle(0, 0, xHalf, screenHeight);
                dc.setColor(Graphics.COLOR_RED, Graphics.COLOR_RED);
                dc.fillRectangle(xHalf, 0, xHalf, screenHeight);
                dc.setColor(settings.uiColour, Graphics.COLOR_TRANSPARENT);
                dc.drawText(
                    xHalf - padding,
                    yHalf,
                    Graphics.FONT_XTINY,
                    "Y",
                    Graphics.TEXT_JUSTIFY_CENTER
                );
                dc.drawText(
                    xHalf + padding,
                    yHalf,
                    Graphics.FONT_XTINY,
                    "N",
                    Graphics.TEXT_JUSTIFY_CENTER
                );
                var text = "Confirm route clear";
                dc.drawText(
                    xHalf,
                    topText,
                    Graphics.FONT_XTINY,
                    text,
                    Graphics.TEXT_JUSTIFY_CENTER
                );
                return true;
            }
        }

        return false;
    }

    function renderUi(dc as Dc) as Void {
        dc.setColor(settings.uiColour, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(1);

        var currentScale = _cachedValues.currentScale; // local lookup faster
        var centerPosition = _cachedValues.centerPosition; // local lookup faster
        var screenWidth = _cachedValues.screenWidth; // local lookup faster
        var screenHeight = _cachedValues.screenHeight; // local lookup faster
        var xHalf = _cachedValues.xHalf; // local lookup faster
        var yHalf = _cachedValues.yHalf; // local lookup faster

        // current mode displayed
        var modeLetter = "T";
        switch (settings.mode) {
            case MODE_NORMAL:
                modeLetter = "T";
                break;
            case MODE_ELEVATION:
                modeLetter = "E";
                break;
            case MODE_MAP_MOVE:
                modeLetter = "M";
                break;
            case MODE_DEBUG:
                modeLetter = "D";
                break;
        }

        dc.drawText(
            modeSelectX,
            modeSelectY,
            Graphics.FONT_XTINY,
            modeLetter,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER
        );

        if (settings.mode == MODE_DEBUG) {
            // mode button is the only thing to show
            return;
        }

        // clear routes
        dc.drawText(
            clearRouteX,
            clearRouteY,
            Graphics.FONT_XTINY,
            "C",
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER
        );

        if (settings.mode == MODE_ELEVATION) {
            return;
        }

        if (settings.mode != MODE_MAP_MOVE) {
            // do not allow disabling maps from mapmove mode
            var mapletter = "Y";
            if (!settings.mapEnabled) {
                mapletter = "N";
            }
            dc.drawText(
                mapEnabledX,
                mapEnabledY,
                Graphics.FONT_XTINY,
                mapletter,
                Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER
            );
        }

        // make this a const
        var halfLineLength = 10;
        var lineFromEdge = 10;
        var textHeight = 15; // guestimate
        var scaleFromEdge = 75; // guestimate

        if (_cachedValues.fixedPosition != null || _cachedValues.scale != null) {
            try {
                dc.drawBitmap2(
                    returnToUserX - _crosshair.getWidth() / 2,
                    returnToUserY - _crosshair.getHeight() / 2,
                    _crosshair,
                    {
                        :tintColor => settings.uiColour,
                    }
                );
            } catch (e) {
                // not sure what this exception was see above
                logE("failed drawBitmap2: " + e);
            }
        }

        if (settings.displayLatLong) {
            if (
                _cachedValues.fixedPosition != null &&
                settings.fixedLatitude != null &&
                settings.fixedLongitude != null
            ) {
                var txt =
                    settings.fixedLatitude.format("%.3f") +
                    ", " +
                    settings.fixedLongitude.format("%.3f");
                dc.drawText(
                    xHalf,
                    screenHeight - scaleFromEdge,
                    Graphics.FONT_XTINY,
                    txt,
                    Graphics.TEXT_JUSTIFY_CENTER
                );
            } else if (currentScale != 0f) {
                var latLong = RectangularPoint.xyToLatLon(
                    centerPosition.x / currentScale,
                    centerPosition.y / currentScale
                );
                if (latLong != null) {
                    var txt = latLong[0].format("%.3f") + ", " + latLong[1].format("%.3f");
                    dc.drawText(
                        xHalf,
                        screenHeight - scaleFromEdge,
                        Graphics.FONT_XTINY,
                        txt,
                        Graphics.TEXT_JUSTIFY_CENTER
                    );
                }
            }
        }

        if (settings.mode == MODE_MAP_MOVE) {
            try {
                dc.drawBitmap2(0, yHalf - _leftArrow.getHeight() / 2, _leftArrow, {
                    :tintColor => settings.uiColour,
                });
                dc.drawBitmap2(
                    screenWidth - _rightArrow.getWidth(),
                    yHalf - _rightArrow.getHeight() / 2,
                    _rightArrow,
                    {
                        :tintColor => settings.uiColour,
                    }
                );
                dc.drawBitmap2(xHalf - _upArrow.getWidth() / 2, 0, _upArrow, {
                    :tintColor => settings.uiColour,
                });
                if (settings.getAttribution() == null) {
                    dc.drawBitmap2(
                        xHalf - _downArrow.getWidth() / 2,
                        screenHeight - _downArrow.getHeight(),
                        _downArrow,
                        {
                            :tintColor => settings.uiColour,
                        }
                    );
                }
            } catch (e) {
                // not sure what this exception was see above
                logE("failed drawBitmap2: " + e);
            }
            return;
        }

        // plus at the top of screen
        dc.drawLine(xHalf - halfLineLength, lineFromEdge, xHalf + halfLineLength, lineFromEdge);
        dc.drawLine(xHalf, lineFromEdge - halfLineLength, xHalf, lineFromEdge + halfLineLength);

        if (settings.getAttribution() == null) {
            // minus at the bottom
            dc.drawLine(
                xHalf - halfLineLength,
                dc.getHeight() - lineFromEdge,
                xHalf + halfLineLength,
                dc.getHeight() - lineFromEdge
            );
        }

        // M - default, moving is zoomed view, stopped if full view
        // S - stopped is zoomed view, moving is entire view
        var fvText = "M";
        // dirty hack, should pass the bool in another way
        // ui should be its own class, as should states
        if (settings.zoomAtPaceMode == ZOOM_AT_PACE_MODE_STOPPED) {
            // zoom view
            fvText = "S";
        }
        if (settings.zoomAtPaceMode == ZOOM_AT_PACE_MODE_ALWAYS_ZOOM) {
            // zoom view
            fvText = "A";
        }
        if (settings.zoomAtPaceMode == ZOOM_AT_PACE_MODE_NEVER_ZOOM) {
            // zoom view
            fvText = "N";
        }
        dc.drawText(lineFromEdge, yHalf, Graphics.FONT_XTINY, fvText, Graphics.TEXT_JUSTIFY_LEFT);

        // north facing N with litle cross
        // var nPosX = 295;
        // var nPosY = 85;
    }

    function getDecIncAmount(direction as Number) as Float {
        if (settings.scaleRestrictedToTileLayers && settings.mapEnabled) {
            var desiredScale = _cachedValues.nextTileLayerScale(direction);
            var toInc = desiredScale - _cachedValues.scale;
            return toInc;
        }

        var scaleData = getScaleSize();
        var iInc = direction;
        var currentDistanceM = scaleData[1];
        var keys = SCALE_NAMES.keys();
        keys.sort(null);
        for (var i = 0; i < keys.size(); ++i) {
            var distanceM = keys[i];
            if (currentDistanceM == distanceM) {
                var nextScaleIndex = i - iInc;
                if (nextScaleIndex >= keys.size()) {
                    nextScaleIndex = keys.size() - 1;
                }

                if (nextScaleIndex < 0) {
                    nextScaleIndex = 0;
                }

                // we want the result to be
                var nextDistanceM = keys[nextScaleIndex] as Float;
                // -2 since we need some fudge factor to make sure we are very close to desired length, but not past it
                var desiredScale = (DESIRED_SCALE_PIXEL_WIDTH - 2) / nextDistanceM;
                var toInc = desiredScale - _cachedValues.scale;
                return toInc;
            }
        }

        return direction * MIN_SCALE;
    }

    function incScale() as Void {
        if (settings.mode != MODE_NORMAL) {
            return;
        }

        if (_cachedValues.scale == null) {
            _cachedValues.setScale(_cachedValues.currentScale);
        }
        _cachedValues.setScale(_cachedValues.scale + getDecIncAmount(1));
    }

    function decScale() as Void {
        if (settings.mode != MODE_NORMAL) {
            return;
        }

        if (_cachedValues.scale == null) {
            _cachedValues.setScale(_cachedValues.currentScale);
        }
        _cachedValues.setScale(_cachedValues.scale + getDecIncAmount(-1));

        // prevent negative values
        // may need to go to lower scales to display larger maps (maybe like 0.05?)
        if (_cachedValues.scale < MIN_SCALE) {
            _cachedValues.setScale(MIN_SCALE);
        }
    }

    function handleClearRoute(x as Number, y as Number) as Boolean {
        var xHalf = _cachedValues.xHalf; // local lookup faster
        var yHalf = _cachedValues.yHalf; // local lookup faster

        if (
            settings.mode != MODE_NORMAL &&
            settings.mode != MODE_ELEVATION &&
            settings.mode != MODE_MAP_MOVE
        ) {
            return false; // debug and map move do not clear routes
        }

        switch (_clearRouteProgress) {
            case 0:
                // press top left to start clear route
                if (
                    y > clearRouteY - halfHitboxSize &&
                    y < clearRouteY + halfHitboxSize &&
                    x > clearRouteX - halfHitboxSize &&
                    x < clearRouteX + halfHitboxSize
                ) {
                    _clearRouteProgress = 1;
                    return true;
                }
                return false;
            case 1:
                // press right to confirm, left cancels
                if (x > xHalf) {
                    _clearRouteProgress = 2;
                    return true;
                }
                _clearRouteProgress = 0;
                return true;

            case 2:
                // press left to confirm, right cancels
                if (x < xHalf) {
                    _clearRouteProgress = 3;
                    return true;
                }
                _clearRouteProgress = 0;
                return true;
            case 3:
                // press right to confirm, left cancels
                if (x > xHalf) {
                    getApp()._breadcrumbContext.clearRoutes();
                }
                _clearRouteProgress = 0;
                return true;
        }

        return false;
    }

    function resetScale() as Void {
        if (settings.mode != MODE_NORMAL && settings.mode != MODE_MAP_MOVE) {
            return;
        }
        _cachedValues.setScale(null);
    }

    // todo move most of these into a ui class
    // and all teh elevation ones into elevation class, or cached values if they are
    // things set to -1 are set by setScreenSize()
    var _xElevationStart as Float = -1f; // think this needs to depend on dpi?
    var _xElevationEnd as Float = -1f;
    var _yElevationHeight as Float = -1f;
    var _halfYElevationHeight as Float = -1f;
    var yElevationTop as Float = -1f;
    var yElevationBottom as Float = -1f;
    var clearRouteX as Float = -1f;
    var clearRouteY as Float = -1f;
    var modeSelectX as Float = -1f;
    var modeSelectY as Float = -1f;
    var returnToUserX as Float = -1f;
    var returnToUserY as Float = -1f;
    var mapEnabledX as Float = -1f;
    var mapEnabledY as Float = -1f;
    var hitboxSize as Float = 50f;
    var halfHitboxSize as Float = hitboxSize / 2.0f;

    function setElevationAndUiData(xElevationStart as Float) as Void {
        var xHalf = _cachedValues.xHalf; // local lookup faster
        var yHalf = _cachedValues.yHalf; // local lookup faster
        var screenWidth = _cachedValues.screenWidth; // local lookup faster

        _xElevationStart = xElevationStart;
        _xElevationEnd = screenWidth - _xElevationStart;
        var xElevationFromCenter = xHalf - _xElevationStart;
        _yElevationHeight =
            Math.sqrt(xHalf * xHalf - xElevationFromCenter * xElevationFromCenter) * 2 - 40;
        _halfYElevationHeight = _yElevationHeight / 2.0f;
        yElevationTop = yHalf - _halfYElevationHeight;
        yElevationBottom = yHalf + _halfYElevationHeight;

        setCornerPositions();
    }

    (:round)
    function setCornerPositions() as Void {
        var xHalf = _cachedValues.xHalf; // local lookup faster
        var yHalf = _cachedValues.yHalf; // local lookup faster

        var offsetSize = Math.sqrt(((yHalf - halfHitboxSize) * (yHalf - halfHitboxSize)) / 2);

        // top left
        clearRouteX = xHalf - offsetSize;
        clearRouteY = yHalf - offsetSize;

        // top right
        modeSelectX = xHalf + offsetSize;
        modeSelectY = yHalf - offsetSize;

        // bottom left
        returnToUserX = xHalf - offsetSize;
        returnToUserY = yHalf + offsetSize;

        // bottom right
        mapEnabledX = xHalf + offsetSize;
        mapEnabledY = yHalf + offsetSize;
    }

    (:rectangle)
    function setCornerPositions() as Void {
        var xHalf = _cachedValues.xHalf; // local lookup faster
        var yHalf = _cachedValues.yHalf; // local lookup faster
        var screenWidth = _cachedValues.screenWidth; // local lookup faster
        var screenHeight = _cachedValues.screenHeight; // local lookup faster

        // top left
        clearRouteX = halfHitboxSize;
        clearRouteY = halfHitboxSize;

        // top right
        modeSelectX = screenWidth - halfHitboxSize;
        modeSelectY = halfHitboxSize;

        // bottom left
        returnToUserX = halfHitboxSize;
        returnToUserY = screenHeight - halfHitboxSize;

        // bottom right
        mapEnabledX = screenWidth - halfHitboxSize;
        mapEnabledY = screenHeight - halfHitboxSize;
    }

    function renderElevationChart(
        dc as Dc,
        hScalePPM as Float,
        vScale as Float,
        startAt as Float,
        distanceM as Float,
        elevationText as String
    ) as Void {
        var xHalf = _cachedValues.xHalf; // local lookup faster
        var yHalf = _cachedValues.yHalf; // local lookup faster
        var screenHeight = _cachedValues.screenHeight; // local lookup faster

        var hScaleData = getScaleSizeGeneric(hScalePPM, DESIRED_SCALE_PIXEL_WIDTH, SCALE_NAMES);
        var hPixelWidth = hScaleData[0];
        var hDistanceM = hScaleData[1];
        var vScaleData = getScaleSizeGeneric(
            vScale,
            DESIRED_ELEV_SCALE_PIXEL_WIDTH,
            ELEVATION_SCALE_NAMES
        );
        var vPixelWidth = vScaleData[0];
        var vDistanceM = vScaleData[1];
        dc.setColor(settings.uiColour, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(1);

        // vertical and horizontal lines for extreems
        dc.drawLine(_xElevationStart, yElevationTop, _xElevationStart, yElevationBottom);
        dc.drawLine(_xElevationStart, yHalf, _xElevationEnd, yHalf);
        // border (does not look great)
        // dc.drawRectangle(_xElevationStart, yHalf - _halfYElevationHeight, screenWidth - _xElevationStart * 2, _yElevationHeight);

        // horizontal lines vertical scale
        if (vPixelWidth != 0) {
            // do not want infinite for loop
            for (var i = 0; i < _halfYElevationHeight; i += vPixelWidth) {
                var yTop = yHalf - i;
                var yBottom = yHalf + i;
                dc.drawLine(_xElevationStart, yTop, _xElevationEnd, yTop);
                dc.drawLine(_xElevationStart, yBottom, _xElevationEnd, yBottom);
            }
        }

        // vertical lines horizontal scale
        if (hPixelWidth != 0) {
            // do not want infinite for loop
            for (var i = _xElevationStart; i < _xElevationEnd; i += hPixelWidth) {
                dc.drawLine(i, yElevationTop, i, yElevationBottom);
            }
        }

        dc.drawText(
            0,
            yHalf - 15,
            Graphics.FONT_XTINY,
            startAt.format("%.0f"),
            Graphics.TEXT_JUSTIFY_LEFT
        );
        if (vScale != 0) {
            // prevent division by 0
            var topScaleM = startAt + _halfYElevationHeight / vScale;
            var topText = topScaleM.format("%.0f") + "m";
            var textDim = dc.getTextDimensions(topText, Graphics.FONT_XTINY);
            dc.drawText(
                _xElevationStart,
                yHalf - _halfYElevationHeight - textDim[1],
                Graphics.FONT_XTINY,
                topText,
                Graphics.TEXT_JUSTIFY_LEFT
            );
            var bottomScaleM = startAt - _halfYElevationHeight / vScale;
            dc.drawText(
                _xElevationStart,
                yHalf + _halfYElevationHeight,
                Graphics.FONT_XTINY,
                bottomScaleM.format("%.0f") + "m",
                Graphics.TEXT_JUSTIFY_LEFT
            );
        }

        dc.setColor(settings.elevationColour, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(3);

        if (hPixelWidth != 0) {
            // if statement makes sure that we can get a SCALE_NAMES[hDistanceM]
            var hFoundName = SCALE_NAMES[hDistanceM];

            var y = screenHeight - 20;
            dc.drawLine(xHalf - hPixelWidth / 2.0f, y, xHalf + hPixelWidth / 2.0f, y);
            dc.drawText(
                xHalf,
                y - 30,
                Graphics.FONT_XTINY,
                hFoundName,
                Graphics.TEXT_JUSTIFY_CENTER
            );
        }

        if (vPixelWidth != 0) {
            // if statement makes sure that we can get a ELEVATION_SCALE_NAMES[vDistanceM]
            var vFoundName = ELEVATION_SCALE_NAMES[vDistanceM];

            var x = xHalf + DESIRED_SCALE_PIXEL_WIDTH / 2.0f;
            var y = screenHeight - 20 - 5 - vPixelWidth / 2.0f;
            dc.drawLine(x, y - vPixelWidth / 2.0f, x, y + vPixelWidth / 2.0f);
            dc.drawText(x + 5, y - 15, Graphics.FONT_XTINY, vFoundName, Graphics.TEXT_JUSTIFY_LEFT);
            // var vectorFont = Graphics.getVectorFont(
            //   {
            //     // font face from https://developer.garmin.com/connect-iq/reference-guides/devices-reference/
            //     :face=>["VeraSans"],
            //     :size=>16,
            //     // :font=>Graphics.FONT_XTINY,
            //     // :scale=>1.0f
            //   }
            // );
            // dc.drawAngledText(0, yHalf, vectorFont, vFoundName, Graphics.TEXT_JUSTIFY_LEFT, 90);
            // dc.drawRadialText(0, yHalf, vectorFont, vFoundName, Graphics.TEXT_JUSTIFY_LEFT, 90, 0, Graphics.RADIAL_TEXT_DIRECTION_COUNTER_CLOCKWISE);
            // drawAngledText and drawRadialText not available :(
        }

        var text =
            "dist: " +
            (distanceM * _cachedValues.currentScale).format("%.0f") +
            "m\n" +
            "elev: " +
            elevationText;
        dc.drawText(xHalf, 20, Graphics.FONT_XTINY, text, Graphics.TEXT_JUSTIFY_CENTER);
    }

    function getElevationScale(
        track as BreadcrumbTrack,
        routes as Array<BreadcrumbTrack>
    ) as [Float, Float, Float, Float] {
        var maxDistanceScaled = 0f;
        var minElevation = FLOAT_MAX;
        var maxElevation = FLOAT_MIN;
        if (track.coordinates.pointSize() > 2) {
            maxDistanceScaled = maxF(maxDistanceScaled, track.distanceTotal);
            minElevation = minF(minElevation, track.elevationMin);
            maxElevation = maxF(maxElevation, track.elevationMax);
        }

        for (var i = 0; i < routes.size(); ++i) {
            var route = routes[i];
            if (!settings.routeEnabled(route.storageIndex)) {
                continue;
            }
            if (route.coordinates.pointSize() > 2) {
                maxDistanceScaled = maxF(maxDistanceScaled, route.distanceTotal);
                minElevation = minF(minElevation, route.elevationMin);
                maxElevation = maxF(maxElevation, route.elevationMax);
            }
        }

        // abs really only needed until we get the first point (then max should always be more than min)
        var elevationChange = abs(maxElevation - minElevation);
        var startAt = minElevation + elevationChange / 2;
        return getElevationScaleRaw(maxDistanceScaled, elevationChange, startAt);
    }
    
    function getElevationScaleOrderedRoutes(
        track as BreadcrumbTrack,
        routes as Array<BreadcrumbTrack>
    ) as [Float, Float, Float, Float] {
        var maxTrackDistanceScaled = 0f;
        var minElevation = FLOAT_MAX;
        var maxElevation = FLOAT_MIN;
        if (track.coordinates.pointSize() > 2) {
            maxTrackDistanceScaled = maxF(maxTrackDistanceScaled, track.distanceTotal);
            minElevation = minF(minElevation, track.elevationMin);
            maxElevation = maxF(maxElevation, track.elevationMax);
        }

        var allRouteDistanceScaled = 0f;
        for (var i = 0; i < routes.size(); ++i) {
            var route = routes[i];
            if (!settings.routeEnabled(route.storageIndex)) {
                continue;
            }
            if (route.coordinates.pointSize() > 2) {
                allRouteDistanceScaled += route.distanceTotal;
                minElevation = minF(minElevation, route.elevationMin);
                maxElevation = maxF(maxElevation, route.elevationMax);
            }
        }

        // track renders ontop of the routes, so we need to get the max distance of the routes or the track
        var maxDistanceScaled = maxF(allRouteDistanceScaled, maxTrackDistanceScaled);

        // abs really only needed until we get the first point (then max should always be more than min)
        var elevationChange = abs(maxElevation - minElevation);
        var startAt = minElevation + elevationChange / 2;
        return getElevationScaleRaw(maxDistanceScaled, elevationChange, startAt);
    }

    function getElevationScaleRaw(
        distanceScaled as Float,
        elevationChange as Float,
        startAt as Float
    ) as [Float, Float, Float, Float] {
        var distanceM = distanceScaled;
        var distanceScale = _cachedValues.currentScale;
        if (distanceScale != 0f) {
            distanceM = distanceScaled / distanceScale;
        }

        // clip to a a square (since we cannot see the edges of the circle)
        var totalXDistance = _cachedValues.screenWidth - 2 * _xElevationStart;
        var totalYDistance = _yElevationHeight;

        if (distanceScaled == 0 && elevationChange == 0) {
            return [0f, 0f, startAt, 0f]; // do not divide by 0
        }

        if (distanceScaled == 0) {
            return [0f, totalYDistance / elevationChange, startAt, 0f]; // do not divide by 0
        }

        if (elevationChange == 0) {
            return [totalXDistance / distanceScaled, 0f, startAt, totalXDistance / distanceM]; // do not divide by 0
        }

        var hScalePPM = totalXDistance / distanceM; // pixels per meter
        var hScale = totalXDistance / distanceScaled; // pixels per pixel - make track renderring faster (single multiply)
        var vScale = totalYDistance / elevationChange;

        return [hScale, vScale, startAt, hScalePPM];
    }

    function renderTrackElevation(
        dc as Dc,
        xElevationStart as Float,
        track as BreadcrumbTrack,
        colour as Graphics.ColorType,
        hScale as Float,
        vScale as Float,
        startAt as Float
    ) as Float {
        var yHalf = _cachedValues.yHalf; // local lookup faster

        var sizeRaw = track.coordinates.size();
        if (sizeRaw < ARRAY_POINT_SIZE * 2) {
            return xElevationStart; // not enough points for iteration
        }

        dc.setColor(colour, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(1);

        var pointSize = track.coordinates.pointSize();

        var coordinatesRaw = track.coordinates._internalArrayBuffer;
        var prevPointX = coordinatesRaw[0];
        var prevPointY = coordinatesRaw[1];
        var prevPointAlt = coordinatesRaw[2];
        var prevChartX = xElevationStart;
        var prevChartY = yHalf + (startAt - prevPointAlt) * vScale;
        for (var i = ARRAY_POINT_SIZE; i < sizeRaw; i += ARRAY_POINT_SIZE) {
            var currPointX = coordinatesRaw[i];
            var currPointY = coordinatesRaw[i + 1];
            var currPointAlt = coordinatesRaw[i + 2];

            var xDist = prevPointX - currPointX;
            var yDist = prevPointY - currPointY;
            var xDistance = Math.sqrt(xDist * xDist + yDist * yDist);

            var yDistance = prevPointAlt - currPointAlt;

            var currChartX = prevChartX + xDistance * hScale;
            var currChartY = prevChartY + yDistance * vScale;

            dc.drawLine(prevChartX, prevChartY, currChartX, currChartY);

            prevPointX = currPointX;
            prevPointY = currPointY;
            prevPointAlt = currPointAlt;
            prevChartX = currChartX;
            prevChartY = currChartY;
        }

        return prevChartX;
    }
}
