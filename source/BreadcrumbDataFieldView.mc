import Toybox.Activity;
import Toybox.Lang;
import Toybox.Time;
import Toybox.WatchUi;
import Toybox.Communications;
import Toybox.Graphics;
import Toybox.Attention;

class OffTrackAlert extends WatchUi.DataFieldAlert {
  function initialize()
  {
    WatchUi.DataFieldAlert.initialize();
  }

  function onUpdate(dc as Dc) as Void {
    if (Attention has :vibrate)
    {
      var vibeData = [
        new Attention.VibeProfile(100, 500),
        new Attention.VibeProfile(0, 150),
        new Attention.VibeProfile(100, 500),
        new Attention.VibeProfile(0, 150),
        new Attention.VibeProfile(100, 500),
      ];
      Attention.vibrate(vibeData);
    }

      var halfHeight = dc.getHeight()/2;
      dc.setColor(Graphics.COLOR_RED, Graphics.COLOR_TRANSPARENT);    
      dc.drawText(halfHeight, halfHeight, Graphics.FONT_SYSTEM_MEDIUM, "OFF TRACK", Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
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
  var offTrackPoint as RectangularPoint or Null = null;
  var _breadcrumbContext as BreadcrumbContext;
  var _scratchPadBitmap as BufferedBitmap;
  var settings as Settings;
  var _cachedValues as CachedValues;
  var lastOffTrackAlertSent = 0;
  var currentScaleOfoffTrackPoint as Float or Null = null;
  // var _renderCounter = 0;

  // Set the label of the data field here.
  function initialize(breadcrumbContext as BreadcrumbContext) {
    _breadcrumbContext = breadcrumbContext;
    _scratchPadBitmap = newBitmap(360, 360, null);
    DataField.initialize();
    settings = _breadcrumbContext.settings();
    _cachedValues = _breadcrumbContext.cachedValues();
  }

  function rescale(newScale as Float) as Void
  {
      if (newScale == 0f)
      {
        return; // dont allow silly scales
      }

      var scaleFactor = newScale;
      if (currentScaleOfoffTrackPoint != null && currentScaleOfoffTrackPoint != 0)
      {
        // adjsut by old scale
        scaleFactor = newScale / currentScaleOfoffTrackPoint;
      }

      if (offTrackPoint != null)
      {
        offTrackPoint = offTrackPoint.rescale(scaleFactor);
      }

      currentScaleOfoffTrackPoint = newScale;
  }

// see onUpdate explaqination for when each is called
  function onLayout(dc as Dc) as Void {
    // logD("onLayout");
    _cachedValues.setScreenSize(dc.getWidth(),  dc.getHeight());
    var textDim = dc.getTextDimensions("1234", Graphics.FONT_XTINY);
    _breadcrumbContext.trackRenderer().setElevationAndUiData(textDim[0] * 1.0f);
    _scratchPadBitmap = newBitmap(dc.getWidth(),  dc.getHeight(), null);
  }

  function onWorkoutStarted() as Void {
    _breadcrumbContext.track().onStart();
  }
  
  function onTimerStart() as Void {
    _breadcrumbContext.track().onStartResume();
  }
  
  // see onUpdate explaqination for when each is called
  function compute(info as Activity.Info) as Void {
    // logD("compute");
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

    // store rotations and speed every time
    _cachedValues.onActivityInfo(info);

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

    var newPoint = _breadcrumbContext.track().pointFromActivityInfo(info);
    if (newPoint != null)
    {
      if (_breadcrumbContext.track().onActivityInfo(newPoint))
      {
        // todo: PERF only update this if the new point added changed the bounding box
        // its pretty good atm though, only recalculates once every few seconds, and only 
        // if a point is added
        _cachedValues.updateBoundingBox(); 
        var lastPoint = _breadcrumbContext.track().lastPoint();
        if (lastPoint != null && (settings.enableOffTrackAlerts || settings.drawLineToClosestPoint))
        {
          handleOffTrackAlerts(lastPoint);
        }
      }
    }
  }

  // new point is already pre scaled
  function handleOffTrackAlerts(newPoint as RectangularPoint) as Void
  {
    var epoch = Time.now().value();
    if (epoch - settings.offTrackAlertsMaxReportIntervalS < lastOffTrackAlertSent)
    {
      return;
    }

    var onlyEnabledRouteId = settings.getOnlyEnabledRouteId();
    for (var i=0; i< _breadcrumbContext.routes().size(); ++i)
    {
      var route = _breadcrumbContext.routes()[i];
      if (route.storageIndex == onlyEnabledRouteId)
      {
        var offTrackInfo = route.checkOffTrack(newPoint, settings.offTrackAlertsDistanceM * _cachedValues.currentScale);
        if (!offTrackInfo.onTrack)
        {
          if (settings.drawLineToClosestPoint)
          {
              currentScaleOfoffTrackPoint = route.currentScale; // all tracks and routes really have to have the same scale, or the calculcation of distance will be wrong
              offTrackPoint = offTrackInfo.pointWeLeftTrack;
          }

          if (settings.enableOffTrackAlerts)
          {
              try {
                showAlert(new OffTrackAlert());
                lastOffTrackAlertSent = epoch;
              } catch (e) {
                // not sure there is a way to check that we can display or not, so just catch errors
              }
          }
        }
        else {
          offTrackPoint = null;
        }
        break;
      }
    }
  }

  // did some testing on real device
  // looks like when we are not on the data page onUpdate is not called, but compute is (as expected)
  // when we are on the data page and it is visible, onUpdate can be called many more times then compute (not just once a second)
  // in some other cases onUpdate is called interleaved with onCompute once a second each (think this might be when its the active screen but not currently renderring)
  // so we need to do all or heavy scaling code in compute, and make onUpdate just handle drawing, and possibly rotation (pre storing rotation could be slow/hard)
  function onUpdate(dc as Dc) as Void {
    // logD("onUpdate");
    renderMain(dc);

    // move based on the last scale we drew
    var renderer = _breadcrumbContext.trackRenderer();
    if (_breadcrumbContext.settings().uiMode == UI_MODE_SHOW_ALL)
    {
      _breadcrumbContext.trackRenderer().renderUi(dc);
    }

    // only ever not null if feature enabled
    if (offTrackPoint != null)
    {
      var lastPoint = _breadcrumbContext.track().lastPoint();
      if (lastPoint != null)
      {
        // points need to be scaled and rotated :(
        _breadcrumbContext.trackRenderer().renderLineFromLastPointToRoute(dc, lastPoint, offTrackPoint);
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

    mapRenderer.renderMap(dc, _scratchPadBitmap);
    for (var i = 0; i < routes.size(); ++i) {
      if (!settings.routeEnabled(i))
      {
          continue;
      }
      var route = routes[i];
      renderer.renderTrack(dc, route, settings.routeColour(route.storageIndex));
    }
    renderer.renderCurrentScale(dc);

    renderer.renderTrack(dc, track, settings.trackColour);

    var lastPoint = track.lastPoint();
    if (lastPoint != null) {
      renderer.renderUser(dc, lastPoint);
    }
  }

  function renderDebug(dc as Dc) as Void {
    var epoch = Time.now().value();
    dc.setColor(settings.debugColour, Graphics.COLOR_BLACK);
    dc.clear();
    // its only a debug menu that should probbaly be optimised out in release, hard code to venu2s screen coordinates
    // it is actually pretty nice info, best guess on string sizes down the screen
    var fieldCount = 7;
    var y = 30;
    var spacing = (dc.getHeight() - y).toFloat() / fieldCount;
    var x = _cachedValues.xHalf;
    dc.drawText(x, y, Graphics.FONT_XTINY, "pending web: " + _breadcrumbContext.webRequestHandler().pendingCount(), Graphics.TEXT_JUSTIFY_CENTER);
    y+=spacing;
    var combined = "last web res: " + _breadcrumbContext.webRequestHandler().lastResult() + 
                   "  tiles: " + _breadcrumbContext.tileCache().tileCount();
    dc.drawText(x, y, Graphics.FONT_XTINY, combined, Graphics.TEXT_JUSTIFY_CENTER);
    y+=spacing;
    dc.drawText(x, y, Graphics.FONT_XTINY, "last alert: " + (epoch - lastOffTrackAlertSent) + "s", Graphics.TEXT_JUSTIFY_CENTER);
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