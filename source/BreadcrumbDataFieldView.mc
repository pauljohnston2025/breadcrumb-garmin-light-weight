import Toybox.Activity;
import Toybox.Lang;
import Toybox.Time;
import Toybox.WatchUi;
import Toybox.Communications;
import Toybox.Graphics;

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
  var _breadcrumbContext as BreadcrumbContext;
  var _speedMPS as Float = 0.0;  // start at no speed
  var _scratchPadBitmap as BufferedBitmap;
  var settings as Settings;
  // var _renderCounter = 0;

  // Set the label of the data field here.
  function initialize(breadcrumbContext as BreadcrumbContext) {
    _breadcrumbContext = breadcrumbContext;
    _scratchPadBitmap = newBitmap(_breadcrumbContext.trackRenderer()._screenSize.toNumber(), null);
    DataField.initialize();
    settings = _breadcrumbContext.settings();
  }

  function onLayout(dc as Dc) as Void {
    // for now we render everything in the onUpdate view, and assume only 1 data
    // screen
    var textDim = dc.getTextDimensions("1234", Graphics.FONT_XTINY);
    _breadcrumbContext.mapRenderer()._screenSize = dc.getWidth() * 1.0f;
    _breadcrumbContext.trackRenderer().setScreenSize(
      dc.getWidth() * 1.0f,
      textDim[0] * 1.0f
    );
    _scratchPadBitmap = newBitmap(_breadcrumbContext.trackRenderer()._screenSize.toNumber(), null);
  }

  function onWorkoutStarted() as Void {
    _breadcrumbContext.track().onStart();
  }
  
  function onTimerStart() as Void {
    _breadcrumbContext.track().onStartResume();
  }
  
  function compute(info as Activity.Info) as Void {

    // temp hack for debugging (since it seems altitude does not work when playing activity data from gpx file)
    // var route = _breadcrumbContext.route();
    // if (route != null)
    // {
    //   var nextPoint = route.coordinates.getPoint(_breadcrumbContext.track().coordinates.pointSize());
    //   if (nextPoint != null)
    //   {
    //     info.altitude = nextPoint.altitude;
    //   }
    // }

  // this is here due to stack overflow bug when requests trigger the next request
    while(_breadcrumbContext.webRequestHandler().startNextIfWeCan())
    {

    }

    var settings = _breadcrumbContext.settings();
    var disableMapsFailureCount = settings.disableMapsFailureCount;
    if (disableMapsFailureCount != 0 && _breadcrumbContext.webRequestHandler().errorCount() > disableMapsFailureCount)
    {
      System.println("disabling maps, too many errors");
      settings.setMapEnabled(false);
    }

    _breadcrumbContext.track().onActivityInfo(info);
    _breadcrumbContext.trackRenderer().onActivityInfo(info);
    var currentSpeed = info.currentSpeed;
    if (currentSpeed != null) {
      _speedMPS = currentSpeed;
    }
  }

  function onUpdate(dc as Dc) as Void {
    renderMain(dc);

    if (_breadcrumbContext.settings().uiMode == UI_MODE_SHOW_ALL)
    {
      _breadcrumbContext.trackRenderer().renderUi(dc);
    }
  }

  function center(point as RectangularPoint) as RectangularPoint
  {
      if (settings.fixedPosition != null)
      {
        return settings.fixedPosition;
      }

      return point;
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

    dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
    dc.clear();

    var renderer = _breadcrumbContext.trackRenderer();
    var mapRenderer = _breadcrumbContext.mapRenderer();
    if (renderer.renderClearTrackUi(dc))
    {
      return;
    }

    // mode should be wtored here, but is needed for renderring the ui
    // should structure this way better, but oh well (renderer per mode etc.)
    if (settings.mode == MODE_ELEVATION)
    {
       renderElevation(dc);
       return;
    } else if (settings.mode == MODE_DEBUG)
    {
       renderDebug(dc);
       return;
    }

    var routes = _breadcrumbContext.routes();
    var track = _breadcrumbContext.track();

    var lastPoint = track.lastPoint();
    if (lastPoint == null) {
      // edge case on startup when we have not got any readings yet (also when
      // viewing in settings) just render the route if we have one
      var outerBoundingBox = calcOuterBoundingBox(routes, null);
      var centerPoint = calcCenterPointForBoundingBox(outerBoundingBox);
      if (routes.size() != 0) {
        var _center = center(centerPoint);
        mapRenderer.renderMap(dc, _scratchPadBitmap, _center, renderer.rotationRadians(), renderer._currentScale);
        renderer.updateCurrentScale(outerBoundingBox);
        for (var i = 0; i < routes.size(); ++i) {
          if (!settings.routeEnabled(i))
          {
              continue;
          }
          var route = routes[i];
          renderer.renderTrack(dc, route, settings.routeColour(route.storageIndex), _center);
        }
        renderer.renderCurrentScale(dc);
      }

      return;
    }

    // if we are moving at some pace check the mode we are in to determine if we
    // zoom in or out
    if (_speedMPS > settings.zoomAtPaceSpeedMPS) {
      if (settings.zoomAtPaceMode == ZOOM_AT_PACE_MODE_PACE) {
        renderCloseAroundCurrentPosition(dc, mapRenderer, renderer, lastPoint, routes, track);
        return;
      }

      renderZoomedOut(dc, mapRenderer, renderer, lastPoint, routes, track);
      return;
    }

    // we are not at speed, so invert logic (this allows us to zoom in when
    // stopped, and zoom out when running) mostly useful for cheking close route
    // whilst stopped but also allows quick zoom in before setting manual zoom
    // (rather than having to manually zoom in from the outer level) once zoomed
    // in we lock onto the user position anyway
    if (settings.zoomAtPaceMode == ZOOM_AT_PACE_MODE_PACE) {
      renderZoomedOut(dc, mapRenderer, renderer, lastPoint, routes, track);
      return;
    }

    renderCloseAroundCurrentPosition(dc, mapRenderer, renderer, lastPoint, routes, track);
  }

  function calcOuterBoundingBox(routes as Array<BreadcrumbTrack>, trackBoundingBox as [Float, Float, Float, Float] or Null) as [Float, Float, Float, Float]
  {
    // we need to make a new object, otherwise we will modify the one thats passed in
    var outerBoundingBox = BOUNDING_BOX_DEFAULT();
    if (trackBoundingBox != null)
    {
      outerBoundingBox[0] = trackBoundingBox[0];
      outerBoundingBox[1] = trackBoundingBox[1];
      outerBoundingBox[2] = trackBoundingBox[2];
      outerBoundingBox[3] = trackBoundingBox[3];
    }

    for (var i = 0; i < routes.size(); ++i) {
      if (!settings.routeEnabled(i))
      {
          continue;
      }
      var route = routes[i];
      outerBoundingBox[0] = minF(route.boundingBox[0], outerBoundingBox[0]);
      outerBoundingBox[1] = minF(route.boundingBox[1], outerBoundingBox[1]);
      outerBoundingBox[2] = maxF(route.boundingBox[2], outerBoundingBox[2]);
      outerBoundingBox[3] = maxF(route.boundingBox[3], outerBoundingBox[3]);
    }

    return outerBoundingBox;
  }

  function calcCenterPointForBoundingBox(boundingBox as [Float, Float, Float, Float]) as RectangularPoint
  {
      return new RectangularPoint(
          boundingBox[0] + (boundingBox[2] - boundingBox[0]) / 2.0,
          boundingBox[1] + (boundingBox[3] - boundingBox[1]) / 2.0,
          0.0f
      );
  }

  function renderZoomedOut(
      dc as Dc, 
      mapRenderer as MapRenderer,
      renderer as BreadcrumbRenderer, 
      lastPoint as RectangularPoint,
      routes as Array<BreadcrumbTrack>, 
      track as BreadcrumbTrack) as Void {
    // when the scale is locked, we need to be where the user is, otherwise we
    // could see a blank part of the map, when we are zoomed in and have no
    // context
    var useUserLocation = _breadcrumbContext.settings().scale != null;

    // we are in 'full render mode', so do the entire extent
    if (routes.size() != 0) {
      // render the whole track and route if we stop
      var outerBoundingBox = calcOuterBoundingBox(routes, track.boundingBox);
      var centerPoint = calcCenterPointForBoundingBox(outerBoundingBox);

      if (useUserLocation) {
          centerPoint = lastPoint;
      }

      centerPoint = center(centerPoint);

      mapRenderer.renderMap(dc, _scratchPadBitmap, centerPoint, renderer.rotationRadians(), renderer._currentScale);
      renderer.updateCurrentScale(outerBoundingBox);
      for (var i = 0; i < routes.size(); ++i) {
        if (!settings.routeEnabled(i))
        {
            continue;
        }
        var route = routes[i];
        renderer.renderTrack(dc, route, settings.routeColour(route.storageIndex), centerPoint);
      }
      renderer.renderTrack(dc, track, _breadcrumbContext.settings().trackColour, centerPoint);
      renderer.renderUser(dc, centerPoint, lastPoint);
      renderer.renderCurrentScale(dc);
      return;
    }

    var centerPoint = track.boundingBoxCenter;
    if (useUserLocation) {
      centerPoint = lastPoint;
    }

    centerPoint = center(centerPoint);

    renderer.updateCurrentScale(track.boundingBox);
    renderer.renderUser(dc, centerPoint, lastPoint);
    renderer.renderTrack(dc, track, _breadcrumbContext.settings().trackColour, centerPoint);
    renderer.renderCurrentScale(dc);
  }

  function renderCloseAroundCurrentPosition(
      dc as Dc, 
      mapRenderer as MapRenderer,
      renderer as BreadcrumbRenderer, lastPoint as RectangularPoint,
      routes as Array<BreadcrumbTrack>, track as BreadcrumbTrack) as Void {
    var renderDistanceM = _breadcrumbContext.settings().metersAroundUser;
    var outerBoundingBox = [
      lastPoint.x - renderDistanceM,
      lastPoint.y - renderDistanceM,
      lastPoint.x + renderDistanceM,
      lastPoint.y + renderDistanceM,
    ];

    var centerPoint = center(lastPoint);

    mapRenderer.renderMap(dc, _scratchPadBitmap, centerPoint, renderer.rotationRadians(),  renderer._currentScale);
    renderer.updateCurrentScale(outerBoundingBox);

    if (routes.size() != 0) {
      for (var i = 0; i < routes.size(); ++i) {
        if (!settings.routeEnabled(i))
        {
            continue;
        }
        var route = routes[i];
        renderer.renderTrack(dc, route, settings.routeColour(route.storageIndex), centerPoint);
      }
    }
    renderer.renderTrack(dc, track, settings.trackColour, centerPoint);
    renderer.renderUser(dc, centerPoint, lastPoint);
    renderer.renderCurrentScale(dc);
  }

  function renderDebug(dc as Dc) as Void {
    dc.setColor(settings.debugColour, Graphics.COLOR_BLACK);
    dc.clear();
    // its only a debug menu that should probbaly be optimised out in release, hard code to venu2s screen coordinates
    // it is actually pretty nice info, best guess on string sizes down the screen
    var fieldCount = 7;
    var y = 30;
    var spacing = (_breadcrumbContext.trackRenderer()._screenSize - y) / fieldCount;
    var x = _breadcrumbContext.trackRenderer()._xHalf;
    dc.drawText(x, y, Graphics.FONT_XTINY, "pending web: " + _breadcrumbContext.webRequestHandler().pendingCount(), Graphics.TEXT_JUSTIFY_CENTER);
    y+=spacing;
    var combined = "last web res: " + _breadcrumbContext.webRequestHandler().lastResult() + 
                   "  tiles: " + _breadcrumbContext.tileCache().tileCount();
    dc.drawText(x, y, Graphics.FONT_XTINY, combined, Graphics.TEXT_JUSTIFY_CENTER);
    y+=spacing;
    // could do as a ratio for a single field
    dc.drawText(x, y, Graphics.FONT_XTINY, "hits: " + _breadcrumbContext.tileCache().hits(), Graphics.TEXT_JUSTIFY_CENTER);
    y+=spacing;
    dc.drawText(x, y, Graphics.FONT_XTINY, "misses: " + _breadcrumbContext.tileCache().misses(), Graphics.TEXT_JUSTIFY_CENTER);
    y+=spacing;
    // could do as a ratio for a single field
    dc.drawText(x, y, Graphics.FONT_XTINY, "web err: " + _breadcrumbContext.webRequestHandler().errorCount(), Graphics.TEXT_JUSTIFY_CENTER);
    y+=spacing;
    dc.drawText(x, y, Graphics.FONT_XTINY, "web ok: " + _breadcrumbContext.webRequestHandler().successCount(), Graphics.TEXT_JUSTIFY_CENTER);
  }

  function renderElevation(dc as Dc) as Void {
    var routes = _breadcrumbContext.routes();
    var track = _breadcrumbContext.track();   
    var renderer = _breadcrumbContext.trackRenderer();

    var elevationScale = renderer.getElevationScale(track, routes);
    var hScale = elevationScale[0];
    var vScale = elevationScale[1];
    var startAt = elevationScale[2];

    renderer.renderElevationChart(dc, hScale, vScale, startAt, track.distanceTotal);
    if (routes.size() != 0) {
      for (var i = 0; i < routes.size(); ++i) {
        if (!settings.routeEnabled(i))
        {
            continue;
        }
        var route = routes[i];
        renderer.renderTrackElevation(dc, route, settings.routeColour(route.storageIndex), hScale, vScale, startAt);
      }
    }
    renderer.renderTrackElevation(dc, track, settings.trackColour, hScale, vScale, startAt);
  }
}