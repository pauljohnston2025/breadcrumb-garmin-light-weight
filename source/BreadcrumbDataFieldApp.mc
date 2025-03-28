import Toybox.ActivityRecording;
import Toybox.WatchUi;
import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;
import Toybox.Communications;

enum Protocol {
  PROTOCOL_ROUTE_DATA = 0,
  PROTOCOL_MAP_TILE = 1,
  PROTOCOL_REQUEST_LOCATION_LOAD = 2,
  PROTOCOL_CANCEL_LOCATION_REQUEST = 3,
}

class CommStatus extends Communications.ConnectionListener {
    function initialize() {
      Communications.ConnectionListener.initialize();
    }
    function onComplete() {
        System.println("App start message sent");
    }

    function onError() {
        System.println("App start message fail");
    }
}

class BreadcrumbDataFieldApp extends Application.AppBase {
  var _view as BreadcrumbDataFieldView;
  var _breadcrumbContext as BreadcrumbContext;
  var _commStatus as CommStatus = new CommStatus();

  function initialize() {
    AppBase.initialize();
    _breadcrumbContext = new BreadcrumbContext();
    _view = new BreadcrumbDataFieldView(_breadcrumbContext);
  }

  function onSettingsChanged() as Void
  {
    _breadcrumbContext.settings().onSettingsChanged();
  }

  // onStart() is called on application start up
    function onStart(state as Dictionary?) as Void {
      if (Communications has : registerForPhoneAppMessages) {
        System.println("registering for phone messages");
        Communications.registerForPhoneAppMessages(method( : onPhone));
      }

      // this would be nice to have (so the user is pormpted to open the app), but appears it does not work
      // System.println("opening app");
      // opens browser only if valid url
      // Communications.openWebPage("http://open.breadcrumb.app.example.com", null, null);
      //  does not work on real device if its not a valid url
      // Communications.openWebPage("open the app please", null, null);
      // https://forums.garmin.com/developer/connect-iq/f/discussion/4339/start-an-android-service-from-watch?pifragment-1298=2#pifragment-1298=2
      // describes how to handle it on android
      Communications.transmit("startserice", {}, _commStatus);
    }

    // onStop() is called when your application is exiting
    function onStop(state as Dictionary?) as Void {
    }

    // Return the initial view of your application here
    function getInitialView() as [Views] or [Views, InputDelegates] {
        return [ _view, new BreadcrumbDataFieldDelegate(_breadcrumbContext, false) ];
        // uncomment to test settings in simulator, also need to change manifest to be 'watch app'
        // return [ new SettingsView(_breadcrumbContext)];
    }

    function getSettingsView() as [Views] or [Views, InputDelegates] or Null {
        return [ new SettingsView(_breadcrumbContext)];
    }

    function onPhone(msg as Communications.PhoneAppMessage) as Void {
      var data = msg.data as Array<Number> or Null;
      if (data == null || data.size() < 1) {
        System.println("Bad message: " + data);
        return;
      }

      var type = data[0];
      var rawData = data.slice(1, null);

      if (type == PROTOCOL_ROUTE_DATA) {
        // protocol:
        //  RawData... [x, y, z]...  // latitude <float> and longitude <float>
        //  in degrees, altitude <float> too

        if (rawData.size() % 3 == 0) {
          var route = _breadcrumbContext.newRoute();
          for (var i = 0; i < rawData.size(); i += 3) {
            route.addLatLongRaw(rawData[i].toFloat(), rawData[i + 1].toFloat(),
                              rawData[i + 2].toFloat());
          }

          route.writeToDisk(ROUTE_KEY);
          return;
        }

        System.println("Failed to parse route data, bad length: " +
                       rawData.size() + " remainder: " + rawData.size() % 3);
        return;
      }
      else if (type == PROTOCOL_MAP_TILE) {
        // note: this route is depdrecated since its really to send through messages
        // instead you should send through PROTOCOL_REQUEST_TILE_LOAD and serve the correct tiles 
        // with the phone companion app
        if (rawData.size() < 4) {
          System.println("Failed to parse map tile, bad length: " + rawData.size());
          return;
        }

        var tileDataStr = rawData[3] as String;
        var tileData = tileDataStr.toUtf8Array();
        if (tileData.size() != _breadcrumbContext.settings().tileSize * _breadcrumbContext.settings().tileSize)
        {
          System.println("Failed to parse map tile, bad tile length: " + tileData.size());
          return;
        }

        var x = rawData[0] as Number;
        var y = rawData[1] as Number;
        var z = rawData[2] as Number;
        var tileKey = new TileKey(x,  y, z);
        var tile = new Tile();
        var _tileCache = _breadcrumbContext.mapRenderer()._tileCache;
        var bitmap = _tileCache.tileDataToBitmap(tileData);
        if (bitmap == null)
        {
            System.println("failed to parse bitmap on set tile data");
            return;
        }

        tile.setBitmap(bitmap);
        _tileCache.addTile(tileKey, tile);
        return;
      }
      else if (type == PROTOCOL_REQUEST_LOCATION_LOAD) {
        if (rawData.size() < 2) {
          System.println("Failed to parse request load tile, bad length: " + rawData.size());
          return;
        }

        System.println("parsing req location: " + rawData);
        var lat = rawData[0] as Float;
        var long = rawData[1] as Float;
        _breadcrumbContext.settings().setFixedPosition(lat, long);
        return;
      }
      else if (type == PROTOCOL_CANCEL_LOCATION_REQUEST) {
        System.println("got cancel location req req: " + rawData);
        _breadcrumbContext.settings().setFixedPosition(null, null);
        return;
      }

      System.println("Unknown message type: " + data[0]);
    }
}

function getApp() as BreadcrumbDataFieldApp {
  return Application.getApp() as BreadcrumbDataFieldApp;
}