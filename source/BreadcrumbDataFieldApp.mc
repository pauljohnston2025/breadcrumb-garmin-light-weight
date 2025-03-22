import Toybox.ActivityRecording;
import Toybox.WatchUi;
import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;
import Toybox.Communications;

enum Protocol {
  PROTOCOL_ROUTE_DATA = 0,
  PROTOCOL_MAP_TILE = 1,
  PROTOCOL_REQUEST_TILE_LOAD = 2,
}

class BreadcrumbDataFieldApp extends Application.AppBase {
  var _view as BreadcrumbDataFieldView;
  var _breadcrumbContext as BreadcrumbContext;

  function initialize() {
    AppBase.initialize();
    _breadcrumbContext = new BreadcrumbContext();
    _view = new BreadcrumbDataFieldView(_breadcrumbContext);
  }

  // onStart() is called on application start up
    function onStart(state as Dictionary?) as Void {
      if (Communications has : registerForPhoneAppMessages) {
        System.println("registering for phone messages");
        Communications.registerForPhoneAppMessages(method( : onPhone));
      }
    }

    // onStop() is called when your application is exiting
    function onStop(state as Dictionary?) as Void {
    }

    // Return the initial view of your application here
    function getInitialView() as[Views] or
        [Views, InputDelegates] {
          return [ _view, new BreadcrumbDataFieldDelegate(_breadcrumbContext) ];
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
        if (rawData.size() < 3) {
          System.println("Failed to parse map tile, bad length: " + rawData.size());
          return;
        }

        var tileDataStr = rawData[2] as String;
        var tileData = tileDataStr.toUtf8Array();
        if (tileData.size() != DATA_TILE_SIZE*DATA_TILE_SIZE)
        {
          System.println("Failed to parse map tile, bad tile length: " + tileData.size());
          return;
        }

        var x = rawData[0] as Number;
        var y = rawData[1] as Number;
        _breadcrumbContext.mapRenderer().setTileData(x, y, tileData as Array<Number>);
        return;
      }
      else if (type == PROTOCOL_REQUEST_TILE_LOAD) {
        _breadcrumbContext.mapRenderer().loadMapTilesForPosition(0f, 0f, _breadcrumbContext.trackRenderer()._currentScale);
        return;
      }

      System.println("Unknown message type: " + data[0]);
    }
}

function getApp() as BreadcrumbDataFieldApp {
  return Application.getApp() as BreadcrumbDataFieldApp;
}