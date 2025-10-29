import Toybox.ActivityRecording;
import Toybox.WatchUi;
import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;
import Toybox.Communications;

var globalExceptionCounter as Number = 0;
var sourceMustBeNativeColorFormatCounter as Number = 0;

enum /* Protocol */ {
    // PROTOCOL_ROUTE_DATA = 0, - removed in favour of PROTOCOL_ROUTE_DATA2, users must update companion app
    // PROTOCOL_MAP_TILE = 1, - removed watch has pulled tiles from phone rather than phone pushing for a while
    PROTOCOL_REQUEST_LOCATION_LOAD = 2,
    PROTOCOL_RETURN_TO_USER = 3,
    PROTOCOL_REQUEST_SETTINGS = 4,
    PROTOCOL_SAVE_SETTINGS = 5,
    /* PROTOCOL_COMPANION_APP_TILE_SERVER_CHANGED = 6, // generally because a new url has been selected on the companion app  */
    PROTOCOL_ROUTE_DATA2 = 7, // an optimised form of PROTOCOL_ROUTE_DATA, so we do not trip the watchdog
    /* PROTOCOL_CACHE_CURRENT_AREA = 8, */
}

enum /* ProtocolSend */ {
    PROTOCOL_SEND_OPEN_APP = 0,
    PROTOCOL_SEND_SETTINGS = 1,
}

class CommStatus extends Communications.ConnectionListener {
    function initialize() {
        Communications.ConnectionListener.initialize();
    }
    function onComplete() {
        logT("App start message sent");
    }

    function onError() {
        logT("App start message fail");
    }
}

class SettingsSent extends Communications.ConnectionListener {
    function initialize() {
        Communications.ConnectionListener.initialize();
    }
    function onComplete() {
        logT("Settings sent");
    }

    function onError() {
        logT("Settings send failed");
    }
}

// to get devices and their memory limits
// cd <homedir>/AppData/Roaming/Garmin/ConnectIQ/Devices/
// cat ./**/compiler.json | grep -E '"type": "datafield"|displayName' -B 1
// we currently need 128.5Kb of memory
// for supported image formats of devices
// cat ./**/compiler.json | grep -E 'imageFormats|displayName' -A 5
// looks like if it does not have a key for "imageFormats" the device only supports native formats and "Source must be native color format" if trying to use anything else.
class BreadcrumbDataFieldApp extends Application.AppBase {
    var _breadcrumbContext as BreadcrumbContext;
    var _view as BreadcrumbDataFieldView;

    var _commStatus as CommStatus = new CommStatus();

    function initialize() {
        AppBase.initialize();
        _breadcrumbContext = new BreadcrumbContext();
        _view = new BreadcrumbDataFieldView(_breadcrumbContext);
        _breadcrumbContext.setup();
    }

    function onSettingsChanged() as Void {
        try {
            _breadcrumbContext.settings.onSettingsChanged();
        } catch (e) {
            logE("failed onSettingsChange: " + e.getErrorMessage());
            ++$.globalExceptionCounter;
        }
    }

    // onStart() is called on application start up
    function onStart(state as Dictionary?) as Void {
        if (Communications has :registerForPhoneAppMessages) {
            logT("registering for phone messages");
            Communications.registerForPhoneAppMessages(method(:onPhone));
        }
    }

    // onStop() is called when your application is exiting

    function onStop(state as Dictionary?) as Void {}

    // Return the initial view of your application here
    function getInitialView() as [Views] or [Views, InputDelegates] {
        // to open settings to test the simulator has it in an obvious place
        // Settings -> Trigger App Settings (right down the bottom - almost off the screen)
        // then to go back you need to Settings -> Time Out App Settings
        return [_view, new BreadcrumbDataFieldDelegate(_breadcrumbContext)];
    }

    (:settingsView)
    function getSettingsView() as [Views] or [Views, InputDelegates] or Null {
        var settings = new $.SettingsMain();
        return [settings, new $.SettingsMainDelegate(settings)];
    }

    function onPhone(msg as Communications.PhoneAppMessage) as Void {
        try {
            var data = msg.data as Array?;
            if (data == null || !(data instanceof Array) || data.size() < 1) {
                logE("Bad message: " + data);
                mustUpdate();
                return;
            }

            var type = data[0] as Number;
            var rawData = data.slice(1, null);

            if (type == PROTOCOL_ROUTE_DATA2) {
                logT("Parsing route data 2");
                // protocol:
                //  name
                //  [x, y, z]...  // latitude <float> and longitude <float> in rectangular coordinates, altitude <float> - pre calculated by the app
                //  [x, y, angle, index] // direction data - pre calculated all floats
                if (rawData.size() < 2) {
                    logT("Failed to parse route 2 data, bad length: " + rawData.size());
                    mustUpdate();
                    return;
                }

                var name = rawData[0] as String;
                var routeData = rawData[1] as Array<Float>;
                var directions = [] as Array<Number>; // back compat empty array
                if (rawData.size() > 2) {
                    directions = rawData[2] as Array<Number>;
                }
                if (routeData.size() % ARRAY_POINT_SIZE == 0) {
                    var route = _breadcrumbContext.newRoute(name);
                    if (route == null) {
                        logE("Failed to add route");
                        mustUpdate();
                        return;
                    }
                    var routeWrote = route.handleRouteV2(
                        routeData,
                        directions,
                        _breadcrumbContext.cachedValues
                    );
                    logT("Parsing route data 2 complete, wrote to storage: " + routeWrote);
                    if (!routeWrote) {
                        _breadcrumbContext.clearRoute(route.storageIndex);
                    }
                    return;
                }

                logE(
                    "Failed to parse route2 data, bad length: " +
                        rawData.size() +
                        " remainder: " +
                        (rawData.size() % 3)
                );
                mustUpdate();
                return;
            } else if (type == PROTOCOL_REQUEST_LOCATION_LOAD) {
                // logT("parsing req location: " + rawData);
                if (rawData.size() < 2) {
                    logE("Failed to parse request load tile, bad length: " + rawData.size());
                    return;
                }

                var lat = rawData[0] as Float;
                var long = rawData[1] as Float;
                _breadcrumbContext.settings.setFixedPosition(lat, long);

                if (rawData.size() >= 3) {
                    // also sets the scale, since user has providedd how many meters they want to see
                    // note this ignores the 'restrict to tile layers' functionality
                    var scale = _breadcrumbContext.cachedValues.calcScaleForScreenMeters(
                        rawData[2] as Float
                    );
                    _breadcrumbContext.cachedValues.setScale(scale);
                }
                return;
            } else if (type == PROTOCOL_RETURN_TO_USER) {
                logT("got return to user req: " + rawData);
                _breadcrumbContext.cachedValues.returnToUser();
                return;
            } else if (type == PROTOCOL_REQUEST_SETTINGS) {
                logT("got send settings req: " + rawData);
                var settings = _breadcrumbContext.settings.asDict();
                // logT("sending settings"+ settings);
                Communications.transmit(
                    [PROTOCOL_SEND_SETTINGS, settings],
                    {},
                    new SettingsSent()
                );
                return;
            } else if (type == PROTOCOL_SAVE_SETTINGS) {
                logT("got save settings req: " + rawData);
                if (rawData.size() < 1) {
                    logE("Failed to parse save settings request, bad length: " + rawData.size());
                    return;
                }
                _breadcrumbContext.settings.saveSettings(
                    rawData[0] as Dictionary<String, PropertyValueType>
                );
                _breadcrumbContext.settings.onSettingsChanged(); // reload anything that has changed
                return;
            } 

            logE("Unknown message type: " + type);
            mustUpdate();
        } catch (e) {
            logE("failed onPhone: " + e.getErrorMessage());
            mustUpdate();
            ++$.globalExceptionCounter;
        }
    }
}

function getApp() as BreadcrumbDataFieldApp {
    return Application.getApp() as BreadcrumbDataFieldApp;
}
