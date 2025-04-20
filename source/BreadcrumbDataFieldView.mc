import Toybox.Activity;
import Toybox.Lang;
import Toybox.Time;
import Toybox.WatchUi;
import Toybox.Communications;
import Toybox.Graphics;
import Toybox.Attention;

class OffTrackAlert extends WatchUi.DataFieldAlert {
    function initialize() {
        WatchUi.DataFieldAlert.initialize();
    }

    function onUpdate(dc as Dc) as Void {
        var halfHeight = dc.getHeight() / 2;
        dc.setColor(Graphics.COLOR_RED, Graphics.COLOR_TRANSPARENT);
        dc.drawText(
            halfHeight,
            halfHeight,
            Graphics.FONT_SYSTEM_MEDIUM,
            "OFF TRACK",
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER
        );
    }
}

// note to get this to work on the simulator need to modify simulator.json and
// add isTouchable this is already on edgo devices with touch, but not the
// venu2s, even though I tested and it worked on the actual device
// AppData\Roaming\Garmin\ConnectIQ\Devices\venu2s\simulator.json
// "datafields": {
// 				"isTouchable": true,
//                 "datafields": [
// note: this only allows taps, cannot handle swipes/holds etc. (need to test on
// real device)
class BreadcrumbDataFieldView extends WatchUi.DataField {
    var offTrackInfo as OffTrackInfo = new OffTrackInfo(true, null);
    var _breadcrumbContext as BreadcrumbContext;
    var _scratchPadBitmap as BufferedBitmap?;
    var settings as Settings;
    var _cachedValues as CachedValues;
    var lastOffTrackAlertCalculated = 0;
    var _computeCounter as Number = 0;
    var _lastFullRenderTime as Number = 0;
    var _lastFullRenderScale as Float = 0f;
    var FULL_RENDER_INTERVAL_S as Number = 5;

    // Set the label of the data field here.
    function initialize(breadcrumbContext as BreadcrumbContext) {
        _breadcrumbContext = breadcrumbContext;
        _scratchPadBitmap = null;
        DataField.initialize();
        settings = _breadcrumbContext.settings();
        _cachedValues = _breadcrumbContext.cachedValues();
    }

    function rescale(scaleFactor as Float) as Void {
        if (offTrackInfo.pointWeLeftTrack != null) {
            offTrackInfo.pointWeLeftTrack.rescaleInPlace(scaleFactor);
        }
    }

    // see onUpdate explaqination for when each is called
    function onLayout(dc as Dc) as Void {
        try {
            actualOnLayout(dc);
        } catch (e) {
            logE("failed onLayout: " + e);
        }
    }

    function actualOnLayout(dc as Dc) as Void {
        // logD("onLayout");
        _cachedValues.setScreenSize(dc.getWidth(), dc.getHeight());
        var textDim = dc.getTextDimensions("1234", Graphics.FONT_XTINY);
        _breadcrumbContext.trackRenderer().setElevationAndUiData(textDim[0] * 1.0f);
        updateScratchPadBitmap();
    }

    function onWorkoutStarted() as Void {
        _breadcrumbContext.track().onStart();
    }

    function onTimerStart() as Void {
        _breadcrumbContext.track().onStartResume();
    }

    function compute(info as Activity.Info) as Void {
        try {
            actualCompute(info);
        } catch (e) {
            logE("failed compute: " + e);
        }
    }

    // see onUpdate explaqination for when each is called
    function actualCompute(info as Activity.Info) as Void {
        // logD("compute");
        // temp hack for debugging in simulator (since it seems altitude does not work when playing activity data from gpx file)
        // var route = _breadcrumbContext.routes()[0];
        // var nextPoint = route.coordinates.getPoint(_breadcrumbContext.track().coordinates.pointSize());
        // if (nextPoint != null)
        // {
        //     info.altitude = nextPoint.altitude;
        // }

        // store rotations and speed every time
        var rescaleOccurred = _cachedValues.onActivityInfo(info);
        if (rescaleOccurred) {
            // rescaling is an expensive operatioj, f we have multiple large routes rescale and then try and recalculate off track alerts (or anything else expensive)
            // we could hit watchdog errors. Best to not attempt anything else.
            logD("rescale occurred, skipping remaining calculate");
            return;
        }
        // this is here due to stack overflow bug when requests trigger the next request
        while (_breadcrumbContext.webRequestHandler().startNextIfWeCan()) {}

        // System.println("computing data field");
        _computeCounter++;
        // slow down the calls to onActivityInfo as its a heavy operation checking
        // the distance we don't really need data much faster than this anyway
        if (_computeCounter != settings.recalculateItervalS) {
            return;
        }

        // perf only seed tiles when we need to (zoom level changes or user moves)
        _breadcrumbContext.mapRenderer().seedTiles(); // could possibly be moved into cached values when map data changes - though map data may not change but we nuked the pending web requests - safer here
        // or we have to do multiple seeds if pending web requests is low

        _computeCounter = 0;

        var settings = _breadcrumbContext.settings();
        var disableMapsFailureCount = settings.disableMapsFailureCount;
        if (
            disableMapsFailureCount != 0 &&
            _breadcrumbContext.webRequestHandler().errorCount() > disableMapsFailureCount
        ) {
            System.println("disabling maps, too many errors");
            settings.setMapEnabled(false);
        }

        var newPoint = _breadcrumbContext.track().pointFromActivityInfo(info);
        if (newPoint != null) {
            if (_cachedValues.currentScale != 0f) {
                newPoint.rescaleInPlace(_cachedValues.currentScale);
            }
            if (_breadcrumbContext.track().onActivityInfo(newPoint)) {
                // todo: PERF only update this if the new point added changed the bounding box
                // its pretty good atm though, only recalculates once every few seconds, and only
                // if a point is added
                _cachedValues.updateScaleCenterAndMap();
                var lastPoint = _breadcrumbContext.track().lastPoint();
                if (
                    lastPoint != null &&
                    (settings.enableOffTrackAlerts || settings.drawLineToClosestPoint)
                ) {
                    handleOffTrackAlerts(lastPoint);
                }
            }
        }
    }

    // new point is already pre scaled
    function handleOffTrackAlerts(newPoint as RectangularPoint) as Void {
        var epoch = Time.now().value();
        if (epoch - settings.offTrackAlertsMaxReportIntervalS < lastOffTrackAlertCalculated) {
            return;
        }

        // Do not check again for hits long, prevents alerts retrigerring, as well as stopping the expensive off track calculation running constantly whilst we are on track.
        lastOffTrackAlertCalculated = epoch;

        var atLeastOneEnabled = false;
        for (var i = 0; i < _breadcrumbContext.routes().size(); ++i) {
            var route = _breadcrumbContext.routes()[i];
            if (!settings.routeEnabled(route.storageIndex)) {
                continue;
            }
            atLeastOneEnabled = true;
            var routeOffTrackInfo = route.checkOffTrack(
                newPoint,
                settings.offTrackAlertsDistanceM * _cachedValues.currentScale
            );

            if (routeOffTrackInfo.onTrack) {
                offTrackInfo = routeOffTrackInfo.clone(); // never store the point we got or rescales could occur twice on the same object
                return;
            }

            if (
                offTrackInfo.pointWeLeftTrack == null ||
                offTrackInfo.pointWeLeftTrack.distanceTo(newPoint) >
                    routeOffTrackInfo.pointWeLeftTrack.distanceTo(newPoint)
            ) {
                offTrackInfo = routeOffTrackInfo.clone(); // never store the point we got or rescales could occur twice on the same object
            }
        }

        if (!atLeastOneEnabled) {
            // no routes are enabled - pretend we are ontrack
            offTrackInfo.onTrack = true;
            return;
        }

        offTrackInfo.onTrack = false; // use the last pointWeLeftTrack from when we were on track

        if (settings.enableOffTrackAlerts) {
            try {
                logD("trying to trigger alert");
                if (settings.alertType == ALERT_TYPE_ALERT) {
                    // allerts are really annoying bevcause users have to remember to enable them
                    // and then some times ive noticed that they do not seem to work, or they are disabled and still lock out the screen
                    // this is why we default to toasts, the virration will still occur, and maybe should be a seperate setting?
                    showAlert(new OffTrackAlert());
                } else {
                    WatchUi.showToast("OFF TRACK", {});
                }

                if (Attention has :vibrate) {
                    var vibeData = [
                        new Attention.VibeProfile(100, 500),
                        new Attention.VibeProfile(0, 150),
                        new Attention.VibeProfile(100, 500),
                        new Attention.VibeProfile(0, 150),
                        new Attention.VibeProfile(100, 500),
                    ];
                    Attention.vibrate(vibeData);
                }

                lastOffTrackAlertCalculated = epoch;
            } catch (e) {
                // not sure there is a way to check that we can display or not, so just catch errors
                System.println("failed to show alert: " + e);
            }
        }
    }

    function onSettingsChanged() as Void {
        // they could have turned off off track alerts, changed the distance of anything, so let it all recalculate
        // or modified routes
        lastOffTrackAlertCalculated = 0;
        offTrackInfo = new OffTrackInfo(true, null);
        // render mode could have changed
        updateScratchPadBitmap();
        resetRenderTime();
    }

    function resetRenderTime() as Void {
        _lastFullRenderTime = 0; // map panning needs to redraw map immediately
    }

    function updateScratchPadBitmap() as Void {
        if (
            settings.renderMode == RENDER_MODE_BUFFERED_ROTATING ||
            settings.renderMode == RENDER_MODE_BUFFERED_NO_ROTATION
        ) {
            // make sure we are at the correct size (settings/layout change at any point)
            // could optimise this to be done in cached values rather than every render
            var width = _cachedValues.screenWidth.toNumber();
            var height = _cachedValues.screenHeight.toNumber();
            if (
                _scratchPadBitmap == null ||
                _scratchPadBitmap.getWidth() != width ||
                _scratchPadBitmap.getHeight() != height
            ) {
                _scratchPadBitmap = null; // null out the old one first, otherwise we have 2 bit bitmaps allocated at the same time
                // assuming garbage collection will run immediately, or when trying to allocate the next it will clean up the old one
                _scratchPadBitmap = newBitmap(width, height, null);
            }
        } else {
            _scratchPadBitmap = null; // settigns have disabled it - clean up after ourselves on next render
        }
    }

    // did some testing on real device
    // looks like when we are not on the data page onUpdate is not called, but compute is (as expected)
    // when we are on the data page and it is visible, onUpdate can be called many more times then compute (not just once a second)
    // in some other cases onUpdate is called interleaved with onCompute once a second each (think this might be when its the active screen but not currently renderring)
    // so we need to do all or heavy scaling code in compute, and make onUpdate just handle drawing, and possibly rotation (pre storing rotation could be slow/hard)
    function onUpdate(dc as Dc) as Void {
        try {
            actualOnUpdate(dc);
        } catch (e) {
            logE("failed onUpdate: " + e);
        }
    }
    function actualOnUpdate(dc as Dc) as Void {
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();

        // logD("onUpdate");
        var renderer = _breadcrumbContext.trackRenderer();
        if (renderer.renderClearTrackUi(dc)) {
            return;
        }

        // mode should be wtored here, but is needed for renderring the ui
        // should structure this way better, but oh well (renderer per mode etc.)
        if (settings.mode == MODE_ELEVATION) {
            renderElevation(dc);
            if (_breadcrumbContext.settings().uiMode == UI_MODE_SHOW_ALL) {
                renderer.renderUi(dc);
            }
            return;
        } else if (settings.mode == MODE_DEBUG) {
            renderDebug(dc);
            if (_breadcrumbContext.settings().uiMode == UI_MODE_SHOW_ALL) {
                renderer.renderUi(dc);
            }
            return;
        }

        renderMain(dc);

        var routes = _breadcrumbContext.routes();

        if (settings.displayRouteNames) {
            for (var i = 0; i < routes.size(); ++i) {
                var route = routes[i];
                if (!settings.routeEnabled(route.storageIndex)) {
                    continue;
                }
                if (
                    settings.renderMode == RENDER_MODE_BUFFERED_ROTATING ||
                    settings.renderMode == RENDER_MODE_UNBUFFERED_ROTATING
                ) {
                    renderer.renderTrackName(dc, route, settings.routeColour(route.storageIndex));
                } else {
                    renderer.renderTrackNameUnrotated(
                        dc,
                        route,
                        settings.routeColour(route.storageIndex)
                    );
                }
            }
        }

        var lastPoint = _breadcrumbContext.track().lastPoint();
        if (lastPoint != null) {
            renderer.renderUser(dc, lastPoint);

            // only ever not null if feature enabled
            if (!offTrackInfo.onTrack && offTrackInfo.pointWeLeftTrack != null) {
                // points need to be scaled and rotated :(
                renderer.renderLineFromLastPointToRoute(
                    dc,
                    lastPoint,
                    offTrackInfo.pointWeLeftTrack
                );
            }
        }

        // move based on the last scale we drew
        if (_breadcrumbContext.settings().uiMode == UI_MODE_SHOW_ALL) {
            renderer.renderUi(dc);
        }

        renderer.renderCurrentScale(dc);

        if (settings.mapEnabled) {
            var attrib = settings.getAttribution();
            if (attrib != null) {
                try {
                    dc.drawBitmap2(
                        _cachedValues.xHalf - attrib.getWidth() / 2,
                        _cachedValues.screenHeight - 20,
                        attrib,
                        {
                            :tintColor => settings.uiColour,
                        }
                    );
                } catch (e) {
                    logE("failed drawBitmap2: " + e);
                }
            }
        }
    }

    function renderMain(dc as Dc) as Void {
        // _renderCounter++;
        // // slow down the calls to onUpdate as its a heavy operation, we will only render every second time (effectively 2 seconds)
        // // this should save some battery, and hopefully the screen stays as the old renderred value
        // // this will mean that we will need to wait this long for the inital render too
        // // perhaps we could base it on speed or 'user is looking at watch'
        // // and have a touch override?
        // if (_renderCounter != 2) {
        //   View.onUpdate(dc);
        //   return;
        // }

        // _renderCounter = 0;
        // looks like view must do a render (not doing a render causes flashes), perhaps we can store our rendered state to a buffer to load from?

        var routes = _breadcrumbContext.routes();
        var track = _breadcrumbContext.track();

        if (
            settings.renderMode == RENDER_MODE_BUFFERED_ROTATING ||
            settings.renderMode == RENDER_MODE_BUFFERED_NO_ROTATION
        ) {
            // only render once to buffer then back off for a bit
            // need to force rerender on scale change
            var epoch = Time.now().value();
            if (
                epoch - _lastFullRenderTime > settings.recalculateItervalS ||
                _lastFullRenderScale != _cachedValues.currentScale
            ) {
                // FULL_RENDER_INTERVAL_S is only to take into accout user moving (which we are also backing off)
                // if they stop and scale changes we will redraw immediately
                // if they rotate we will draw rotations stright away
                _lastFullRenderTime = epoch;
                _lastFullRenderScale = _cachedValues.currentScale;
                var scratchPadBitmapDc = _scratchPadBitmap.getDc();
                rederUnrotated(scratchPadBitmapDc, routes, track);
            }

            try {
                if (settings.renderMode == RENDER_MODE_BUFFERED_ROTATING) {
                    dc.drawBitmap2(0, 0, _scratchPadBitmap, {
                        // :bitmapX =>
                        // :bitmapY =>
                        // :bitmapWidth =>
                        // :bitmapHeight =>
                        // :tintColor =>
                        // :filterMode =>
                        :transform => _cachedValues.rotationMatrix,
                    });
                } else {
                    dc.drawBitmap(0, 0, _scratchPadBitmap);
                }
            } catch (e) {
                logE("failed drawBitmap2 or drawBitmap: " + e);
            }
            return;
        }

        if (settings.renderMode == RENDER_MODE_UNBUFFERED_ROTATING) {
            var mapRenderer = _breadcrumbContext.mapRenderer();
            var renderer = _breadcrumbContext.trackRenderer();
            dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
            dc.clear();
            mapRenderer.renderMap(dc);
            for (var i = 0; i < routes.size(); ++i) {
                var route = routes[i];
                if (!settings.routeEnabled(route.storageIndex)) {
                    continue;
                }
                renderer.renderTrack(dc, route, settings.routeColour(route.storageIndex));
            }
            renderer.renderTrack(dc, track, settings.trackColour);
            return;
        }

        // RENDER_MODE_UNBUFFERED_NO_ROTATION
        rederUnrotated(dc, routes, track);
    }

    function rederUnrotated(
        dc as Dc,
        routes as Array<BreadcrumbTrack>,
        track as BreadcrumbTrack
    ) as Void {
        var renderer = _breadcrumbContext.trackRenderer();
        var mapRenderer = _breadcrumbContext.mapRenderer();

        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();
        mapRenderer.renderMapUnrotated(dc);
        for (var i = 0; i < routes.size(); ++i) {
            var route = routes[i];
            if (!settings.routeEnabled(route.storageIndex)) {
                continue;
            }
            renderer.renderTrackUnrotated(dc, route, settings.routeColour(route.storageIndex));
        }
        renderer.renderTrackUnrotated(dc, track, settings.trackColour);
    }

    function renderDebug(dc as Dc) as Void {
        var epoch = Time.now().value();
        dc.setColor(settings.debugColour, Graphics.COLOR_BLACK);
        dc.clear();
        // its only a debug menu that should probbaly be optimised out in release, hard code to venu2s screen coordinates
        // it is actually pretty nice info, best guess on string sizes down the screen
        var fieldCount = 9;
        var y = 30;
        var spacing = (dc.getHeight() - y).toFloat() / fieldCount;
        var x = _cachedValues.xHalf;
        dc.drawText(
            x,
            y,
            Graphics.FONT_XTINY,
            "pending web: " + _breadcrumbContext.webRequestHandler().pendingCount(),
            Graphics.TEXT_JUSTIFY_CENTER
        );
        y += spacing;
        dc.drawText(
            x,
            y,
            Graphics.FONT_XTINY,
            "pending transmit: " + _breadcrumbContext.webRequestHandler().pendingTransmitCount(),
            Graphics.TEXT_JUSTIFY_CENTER
        );
        y += spacing;
        dc.drawText(
            x,
            y,
            Graphics.FONT_XTINY,
            "outstanding: " + _breadcrumbContext.webRequestHandler().outstandingCount() + " web: " + _breadcrumbContext.webRequestHandler().outstandingHashesCount(),
            Graphics.TEXT_JUSTIFY_CENTER
        );
        y += spacing;
        var combined =
            "last web res: " +
            _breadcrumbContext.webRequestHandler().lastResult() +
            "  tiles: " +
            _breadcrumbContext.tileCache().tileCount();
        dc.drawText(x, y, Graphics.FONT_XTINY, combined, Graphics.TEXT_JUSTIFY_CENTER);
        y += spacing;
        dc.drawText(
            x,
            y,
            Graphics.FONT_XTINY,
            "last alert: " + (epoch - lastOffTrackAlertCalculated) + "s",
            Graphics.TEXT_JUSTIFY_CENTER
        );
        y += spacing;
        // could do as a ratio for a single field
        dc.drawText(
            x,
            y,
            Graphics.FONT_XTINY,
            "web err: " + _breadcrumbContext.webRequestHandler().errorCount() + " web ok: " + _breadcrumbContext.webRequestHandler().successCount(),
            Graphics.TEXT_JUSTIFY_CENTER
        );
        y += spacing;
        dc.drawText(
            x,
            y,
            Graphics.FONT_XTINY,
            "hits: " + _breadcrumbContext.tileCache().hits(),
            Graphics.TEXT_JUSTIFY_CENTER
        );
        y += spacing;
        dc.drawText(
            x,
            y,
            Graphics.FONT_XTINY,
            "misses: " + _breadcrumbContext.tileCache().misses(),
            Graphics.TEXT_JUSTIFY_CENTER
        );
        y += spacing;
        // _lastFullRenderTime only updates when rendering the track (debug screen does not use it, so it just counts up whilst on the debug page)
        // dc.drawText(x, y, Graphics.FONT_XTINY, "last buff render: " + (epoch - _lastFullRenderTime) + "s", Graphics.TEXT_JUSTIFY_CENTER);
        // y+=spacing;
        // could do as a ratio for a single field
        // auto
        if (_cachedValues.scale != null) {
            dc.drawText(
                x,
                y,
                Graphics.FONT_XTINY,
                "scale: " + _cachedValues.scale.format("%.2f"),
                Graphics.TEXT_JUSTIFY_CENTER
            );
        } else {
            dc.drawText(x, y, Graphics.FONT_XTINY, "scale: Auto", Graphics.TEXT_JUSTIFY_CENTER);
        }
        
    }

    function renderElevation(dc as Dc) as Void {
        if (settings.elevationMode == ELEVATION_MODE_STACKED)
        {
            renderElevationStacked(dc);
            return;
        }

        renderElevationOrderedRoutes(dc);
    }

    function renderElevationStacked(dc as Dc) as Void {
        var routes = _breadcrumbContext.routes();
        var track = _breadcrumbContext.track();
        var renderer = _breadcrumbContext.trackRenderer();

        var elevationScale = renderer.getElevationScale(track, routes);
        var hScale = elevationScale[0];
        var vScale = elevationScale[1];
        var startAt = elevationScale[2];
        var hScalePPM = elevationScale[3];

        var elevationText =
            track.lastPoint() == null ? "" : track.lastPoint().altitude.format("%.0f") + "m";

        renderer.renderElevationChart(
            dc,
            hScalePPM,
            vScale,
            startAt,
            track.distanceTotal,
            elevationText
        );
        if (routes.size() != 0) {
            for (var i = 0; i < routes.size(); ++i) {
                var route = routes[i];
                if (!settings.routeEnabled(route.storageIndex)) {
                    continue;
                }
                renderer.renderTrackElevation(
                    dc,
                    renderer._xElevationStart,
                    route,
                    settings.routeColour(route.storageIndex),
                    hScale,
                    vScale,
                    startAt
                );
            }
        }
        renderer.renderTrackElevation(dc, renderer._xElevationStart, track, settings.trackColour, hScale, vScale, startAt);
    }
    
    function renderElevationOrderedRoutes(dc as Dc) as Void {
        var routes = _breadcrumbContext.routes();
        var track = _breadcrumbContext.track();
        var renderer = _breadcrumbContext.trackRenderer();
        
        var elevationScale = renderer.getElevationScaleOrderedRoutes(track, routes);
        var hScale = elevationScale[0];
        var vScale = elevationScale[1];
        var startAt = elevationScale[2];
        var hScalePPM = elevationScale[3];

        var elevationText =
            track.lastPoint() == null ? "" : track.lastPoint().altitude.format("%.0f") + "m";

        var elevationStartX = renderer._xElevationStart;

        renderer.renderElevationChart(
            dc,
            hScalePPM,
            vScale,
            startAt,
            track.distanceTotal,
            elevationText
        );
        if (routes.size() != 0) {
            for (var i = 0; i < routes.size(); ++i) {
                var route = routes[i];
                if (!settings.routeEnabled(route.storageIndex)) {
                    continue;
                }
                elevationStartX = renderer.renderTrackElevation(
                    dc,
                    elevationStartX,
                    route,
                    settings.routeColour(route.storageIndex),
                    hScale,
                    vScale,
                    startAt
                );
            }
        }
        renderer.renderTrackElevation(dc, renderer._xElevationStart, track, settings.trackColour, hScale, vScale, startAt);
    }
}
