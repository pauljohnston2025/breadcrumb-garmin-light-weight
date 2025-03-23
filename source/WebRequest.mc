import Toybox.Lang;
import Toybox.Graphics;
import Toybox.WatchUi;
import Toybox.PersistedContent;
import Toybox.System;
import Toybox.Communications;

class WebHandler {
    // see error codes such as Communications.NETWORK_REQUEST_TIMED_OUT
    function handle(responseCode as Number, data as Dictionary or String or Iterator or Null) as Void;
}

class JsonRequest {
    var method as String;
    var params as Dictionary<Object, Object>;
    var handler as WebHandler;

    function initialize(
        _method as String,
        _params as Dictionary<Object, Object>, 
        _handler as WebHandler)
    {
        method = _method;
        params = _params;
        handler = _handler;
    }
}

class WebRequestHandle {
    var webHandler as WebRequestHandler;
    var handler as WebHandler;

    function initialize(
        _webHandler as WebRequestHandler,
        _handler as WebHandler)
    {
        webHandler = _webHandler;
        handler = _handler;
    }

    function handle(responseCode as Number, data as Dictionary or String or Iterator or Null) as Void
    {
        handler.handle(responseCode, data);
        var updateErrors = [Communications.BLE_HOST_TIMEOUT, Communications.NETWORK_REQUEST_TIMED_OUT];
        if (updateErrors.indexOf(responseCode) > -1)
        {
            webHandler.updateUrlPrefix();
        }
        webHandler.startNext();
    }
}

class WebRequestHandler
{
    // see https://forums.garmin.com/developer/connect-iq/f/discussion/209443/watchface-working-in-simulator-failing-webrequest-on-device-with-http-response--101
    // only 3 web requests are allowed in parallel, so we need to buffer them up and make new requests when we get responses
    var pending as Array<JsonRequest> = [];
    var noOutstanding as Boolean = true;
    var _urlPrefix as String;
    var _ipsToTry as Array<String>;
    var _ipsToTryIndex as Number;
    var _mapRenderer as MapRenderer;

    function initialize(mapRenderer as MapRenderer) {
        _mapRenderer = mapRenderer;
        // todo: expose this through settings
        // we want to allow 
        // local connections through bluetooth bridge (slow but doess work): http://127.0.0.1:8080
        // connections where the watch is on a wifi network (this will be very rare, since it would be an activity 
        // thats always in range of the network, but good for testing): http://<android ip on same network>:8080
        // connections where the watch is tethered to the android phone (fater than bluetooth): http://<android teather host ip>:8080
        // note: depending on the network the watch is on, only 1 of these will work at any point
        // could auto detect, but seems complicated (maybe have a list to try in settings, and on failed web requests try the next url)
        // to make this work on the emulator you ned to run 
        // adb forward tcp:8080 tcp:8080
        // eg.
        // _urlPrefix = "http://127.0.0.1:8080"; // localhost (bluetooth bridge)
        // _urlPrefix = "http://192.168.1.103:8080/"; // android phone ip on wlan
        // _urlPrefix = "http://192.168.79.82:8080/"; // androids hotspot ip (the default gateway ip from the connected devices)
        // if (isSimulator())
        // {
        //     _urlPrefix = "http://192.168.1.101:81";
        // }

        // todo load from settings
        // to make this work on the emulator you ned to run 
        // adb forward tcp:8080 tcp:8080
        _urlPrefix = "http://127.0.0.1:8080";
        _ipsToTry = ["127.0.0.1", "192.168.1.103", "192.168.79.82"];
        _ipsToTryIndex = 0;
    }

    // function connectionStatusCallback(result as { :wifiAvailable as Lang.Boolean, :errorCode as Communications.WifiConnectionStatus }) as Void
    // {
    //     System.println("wifi status: " + result[:wifiAvailable] + " " + result[:errorCode]);
    //     // think if we start a request whilst wifi is active it will keep it active for us (with any hope)
    //     realStartNext();
    // }

    function updateUrlPrefix() as Void
    {
        // keeping since we way experiment with wifi again at some point, but it appear there is no way to force a connection to use wifi .
        // I never saw a single request pass, even if bluetooth was disabled, seems like wifi can only be used for a sync (but we want it always in for the lifetime of our activity)
        // it would probbaly use too much power anyway, so falling back to slower bluetooth and smaller colour pallete images
        // this does rotate the url fine though

        // to make this work on the emulator you ned to run 
        // adb forward tcp:8080 tcp:8080
        _urlPrefix = "http://127.0.0.1:8080";
        return;

        // System.println("updating url");
        // if (_ipsToTry.size() == 0)
        // {
        //     _urlPrefix = "http://127.0.0.1:8080";
        //     System.println("url changed to " + _urlPrefix);
        //     return;
        // }

        // _ipsToTryIndex++;
        // if (_ipsToTryIndex >= _ipsToTry.size())
        // {
        //     _ipsToTryIndex = 0;
        // }

        // _urlPrefix = "http://" + _ipsToTry[_ipsToTryIndex] + ":8080";
        // System.println("url changed to " + _urlPrefix);
    }

    function add(jsonReq as JsonRequest) as Void 
    {
        // todo remove old requests if we get too many (slow network and requests too often mean the internal array grows and we OOM)
        // hard to know if there is one outstanding though, also need to startNext() on a timer if we have not seen any requests in a while
        pending.add(jsonReq);
        // for now just start one at a time, simpler to track
        if (noOutstanding)
        {
            startNext();
        }
    }

    // function startNext() as Void 
    // {
    //     Communications.checkWifiConnection(method(:connectionStatusCallback));
    // }

    function startNext() as Void 
    {
        // todo: may need to handle race where one completes and one is added at the same time?
        // think its all single threaded, so should not matter
        if (pending.size() == 0)
        {
            noOutstanding = true;
            return;
        }

        noOutstanding = false;
        var jsonReq = pending[0];
        pending.remove(jsonReq); // might be better to slice?
        Communications.makeWebRequest(
            _urlPrefix + jsonReq.method,
            jsonReq.params,
            {
                :method => Communications.HTTP_REQUEST_METHOD_GET,
                :headers => {
                    // docs say you can do this (or ommit it), but i found its not sent, or is sent as application/x-www-form-urlencoded when using HTTP_RESPONSE_CONTENT_TYPE_JSON
                    // "Content-Type" => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON,
                    // my local server does not like content type being supplied when its a get or post
                    // the android server does not seem to get 
                    // "Content-Type" => "application/json",

                },
                :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON,
            }, // options
            // see https://forums.garmin.com/developer/connect-iq/f/discussion/2289/documentation-clarification-object-method-and-lang-method
            (new WebRequestHandle(me, jsonReq.handler)).method(:handle)
        );
    }
}
