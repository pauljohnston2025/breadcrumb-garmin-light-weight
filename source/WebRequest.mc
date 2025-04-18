import Toybox.Lang;
import Toybox.Graphics;
import Toybox.WatchUi;
import Toybox.PersistedContent;
import Toybox.System;
import Toybox.Communications;
import Toybox.Application;

class JsonWebHandler {
    // see error codes such as Communications.NETWORK_REQUEST_TIMED_OUT
    function handle(
        responseCode as Number,
        data as Dictionary or String or Iterator or Null
    ) as Void;
}

class ImageWebHandler {
    // see error codes such as Communications.NETWORK_REQUEST_TIMED_OUT
    function handle(
        responseCode as Number,
        data as WatchUi.BitmapResource or Graphics.BitmapReference or Null
    ) as Void;
}

class WebRequest {
    var url as String;
    var params as Dictionary<Object, Object>;
    // unique id for this request, if two requests have the same hash the second one will be dropped if the first is pending
    var hash as String;

    function initialize(_hash as String, _url as String, _params as Dictionary<Object, Object>) {
        hash = _hash;
        url = _url;
        params = _params;
    }
}

class JsonRequest extends WebRequest {
    var handler as JsonWebHandler;
    function initialize(
        _hash as String,
        _url as String,
        _params as Dictionary<Object, Object>,
        _handler as JsonWebHandler
    ) {
        WebRequest.initialize(_hash, _url, _params);
        handler = _handler;
    }
}

class ImageRequest extends WebRequest {
    var handler as ImageWebHandler;
    function initialize(
        _hash as String,
        _url as String,
        _params as Dictionary<Object, Object>,
        _handler as ImageWebHandler
    ) {
        WebRequest.initialize(_hash, _url, _params);
        handler = _handler;
    }
}

class WebRequestHandleWrapper {
    var webHandler as WebRequestHandler;
    var handler as JsonWebHandler or ImageWebHandler;

    function initialize(
        _webHandler as WebRequestHandler,
        _handler as JsonWebHandler or ImageWebHandler
    ) {
        webHandler = _webHandler;
        handler = _handler;
    }

    function handle(
        responseCode as Number,
        data as
            Dictionary or
                String or
                Iterator or
                WatchUi.BitmapResource or
                Graphics.BitmapReference or
                Null
    ) as Void {
        handler.handle(responseCode, data);

        if (responseCode != 200 && webHandler._settings.tileUrl.equals(COMPANION_APP_TILE_URL)) {
            // todo only send this on certain errors, and only probbaly only after some limit?
            webHandler.transmit([PROTOCOL_SEND_OPEN_APP], {}, getApp()._commStatus);
        }

        // got some stack overflows, as handle can be called inline if it knows it will fail (eg. BLE_CONNECTION_UNAVAILABLE)
        // also saw alot of NETWORK_REQUEST_TIMED_OUT in the logs, but thnk it was when the BLE_CONNECTION_UNAVAILABLE happened
        // as that was the last log, and it makes sense that it can short circuit
        // so launch the next task in a timer
        // var timer = new Timer.Timer();
        // timer.start(webHandler.method(:startNext), 1, false);
        // or at least I would do this if the timer task was available to datafields :(
        // so we might have to call 'startNext' every time the compute method runs :(
        // new Timer.Timer(); Error: Permission Required ; Details: Module 'Toybox.Timer' not available to 'Data Field'
        webHandler.decrementOutstanding();

        if (responseCode == 200) {
            webHandler._successCount++;
        } else {
            // System.println("got web error: " + responseCode);
            webHandler._errorCount++;
        }
        webHandler._lastResult = responseCode;
    }
}

class ConnectionListenerWrapper extends Communications.ConnectionListener {
    var webHandler as WebRequestHandler;
    var handler as Communications.ConnectionListener;
    var alreadyDecedWebHandler = false;

    function initialize(
        _webHandler as WebRequestHandler,
        _handler as Communications.ConnectionListener
    ) {
        Communications.ConnectionListener.initialize();
        webHandler = _webHandler;
        handler = _handler;
    }

    function onComplete() {
        decOutstanding();
        handler.onComplete();
    }

    function onError() {
        decOutstanding();
        handler.onError();
    }

    function decOutstanding() as Void {
        if (alreadyDecedWebHandler) {
            return;
        }

        alreadyDecedWebHandler = true;
        webHandler.decrementOutstanding();
    }
}

class WebRequestHandler {
    // see https://forums.garmin.com/developer/connect-iq/f/discussion/209443/watchface-working-in-simulator-failing-webrequest-on-device-with-http-response--101
    // only 3 web requests are allowed in parallel, so we need to buffer them up and make new requests when we get responses
    // using 2 arrays so we get FIFO
    // also dictionary seemed to make the code 2X slower, think because we had to serch all the keys for a string several times
    var pendingTransmit as
    Array<[Application.PersistableType, Dictionary?, Communications.ConnectionListener]> = [];
    var pending as Array<JsonRequest or ImageRequest> = [];
    var pendingHashes as Array<String> = [];
    var _outstandingCount as Number = 0;
    var _settings as Settings;
    var _errorCount as Number = 0;
    var _successCount as Number = 0;
    var _lastResult as Number = 0;

    function initialize(settings as Settings) {
        _settings = settings;
    }

    function clearValues() as Void {
        pending = [];
        pendingHashes = [];
    }

    // Communications.trnsmit can fail if web requests are pending, 'Communications transmit queue full'
    // so we will have to queue it up to the web server as 'high priority', or just have a transmit queue that is always high priority
    function transmit(
        content as Application.PersistableType,
        options as Dictionary?,
        listener as Communications.ConnectionListener
    ) {
        pendingTransmit.add([content, options, listener]);
    }

    function add(jsonOrImageReq as JsonRequest or ImageRequest) as Void {
        // todo remove old requests if we get too many (slow network and requests too often mean the internal array grows and we OOM)
        // hard to know if there is one outstanding though, also need to startNext() on a timer if we have not seen any requests in a while
        if (pending.size() > _settings.maxPendingWebRequests) {
            // we have too many, don't try and get the tile
            // we should try and dedupe - as its making a request for the same tile twice (2 renders cause 2 requests)
            // logE("Too many pending requests dropping: " + jsonReq.hash);
            return;
        }

        var hash = jsonOrImageReq.hash;
        if (pendingHashes.indexOf(hash) > -1) {
            // log("Dropping req for: " + hash);
            // note: we cannot attempt to run the request, as i've gotten stack over flows on real devices
            // all web requests will be started from the top level compute loop
            // stack overflow comes when it completes immediately, and calls into handle
            // see report at end of TileCache.mc
            // startNextIfWeCan(); // start any other ones whilst we are in a different function
            return;
        }

        pending.add(jsonOrImageReq);
        pendingHashes.add(hash);
        // for now just start one at a time, simpler to track
        // At most 3 outstanding can occur, todo query this limit
        // https://forums.garmin.com/developer/connect-iq/f/discussion/204298/ble-queue-full
        // otherwise you will get BLE_QUEUE_FULL (-101)
        // note: we cannot attempt to run the request, as i've gotten stack over flows on real devices
        // all web requests will be started from the top level compute loop
        // stack overflow comes when it completes immediately, and calls into handle
        // see report at end of TileCache.mc
        // startNextIfWeCan();
    }

    function startNextIfWeCan() as Boolean {
        if (pending.size() == 0 && pendingTransmit.size() == 0) {
            return false;
        }

        if (_outstandingCount < 3) {
            // we could get real crazy and start some tile requests through makeWebRequest
            // and some others through pushing tiles from the companion app
            // seems really hard to maintain though, and ble connection probably already saturated
            start();
            return true;
        }

        return false;
    }

    function decrementOutstanding() as Void {
        --_outstandingCount;
    }

    function start() as Void {
        ++_outstandingCount;
        if (pendingTransmit.size() != 0) {
            // prioritize the  transmits ofver tile/web loads
            var transmitEntry = pendingTransmit[0];
            pendingTransmit.remove(transmitEntry);
            Communications.transmit(
                transmitEntry[0],
                transmitEntry[1],
                new ConnectionListenerWrapper(me, transmitEntry[2])
            );
            return;
        }

        var jsonOrImageReq = pending[0];
        pending.remove(jsonOrImageReq);
        // trust that the keys are in the same order as the hash
        pendingHashes.remove(jsonOrImageReq.hash);
        if (pending.size() != pendingHashes.size()) {
            logE("size mismatch: " + pending.size() + " " + pendingHashes.size());
            pending = [];
            pendingHashes = [];
        }

        System.println("url: "  + jsonOrImageReq.url);
        // System.println("params: "  + jsonOrImageReq.params);

        if (jsonOrImageReq instanceof ImageRequest) {
            // System.println("sending image request");
            var callback =
                (new WebRequestHandleWrapper(me, jsonOrImageReq.handler)).method(:handle) as
                (Method
                    (
                        responseCode as Lang.Number,
                        data as WatchUi.BitmapResource or Graphics.BitmapReference or Null
                    ) as Void
                );
            // we only use image requests for exeternal servers
            var requiresScaling = _settings.tileSize != 256;
            Communications.makeImageRequest(
                jsonOrImageReq.url,
                jsonOrImageReq.params,
                {
                    // needs to be png or we will get
                    // Error: Unhandled Exception
                    // Exception: Source must not use a color palette if we try and draw it to another bufferredBitmap
                    // it appears PACKING_FORMAT_DEFAULT is the culprit
                    // PACKING_FORMAT_YUV, PACKING_FORMAT_PNG, PACKING_FORMAT_JPG are also fine
                    // docs say png is slow to load, yuv is fast and jpg is reasonably fast
                    // PACKING_FORMAT_YUV has weird issues in the physical device (its just tinting the image, not preserving pixel data)
                    // looks like PACKING_FORMAT_PNG does work, but its really slow -> we shold only fallback to this if we really need it
                    // PACKING_FORMAT_JPG does weird things
                    // (we have to scale the image - at this point im thinking i should just override the users setting to 256 if the tile server is not the companion app)
                    // so we must use PACKING_FORMAT_PNG if they really want a slow response and smaller tiles cache
                    // so tried it again, ang PNG did the same colour issue as JPG/YUV :( AHHHHHHHHHHHH
                    :packingFormat => requiresScaling
                        ? Communications.PACKING_FORMAT_PNG
                        : Communications.PACKING_FORMAT_DEFAULT,
                    // from android code
                    // val osName = "Garmin"
                    // val osVersion = Build.VERSION.RELEASE ?: "Unknown"
                    // val deviceModel = "${Build.MANUFACTURER} ${Build.MODEL}"
                    // required by openstreetmaps, not sure how to get this to work
                    // https://operations.osmfoundation.org/policies/tiles/
                    // https://help.openstreetmap.org/questions/29938/in-my-app-problem-downloading-maptile-000-http-response-http11-403-forbidden
                    // header("User-Agent", "Breadcrumb/1.0 ($osName $osVersion $deviceModel)")
                    // but unfortunetly the makeImageRequest does not support headers
                    // https://forums.garmin.com/developer/connect-iq/f/discussion/303994/makeimagerequest-additional-headers-and-svgs
                    // so no openstreet maps for us :(
                }, // options
                // see https://forums.garmin.com/developer/connect-iq/f/discussion/2289/documentation-clarification-object-method-and-lang-method
                callback
            );
            return;
        }

        // System.println("sending json request");
        var callback =
            (new WebRequestHandleWrapper(me, jsonOrImageReq.handler)).method(:handle) as
            (Method
                (
                    responseCode as Lang.Number,
                    data as Lang.Dictionary or Lang.String or PersistedContent.Iterator or Null
                ) as Void
            ) or
                (Method
                (
                    responseCode as Lang.Number,
                    data as Lang.Dictionary or Lang.String or PersistedContent.Iterator or Null,
                    context as Lang.Object
                ) as Void
            );
        // note: even though docs say that this could be sent over wifi it seems it never is, and requires the blueotth connection
        // also i tried several ways to force wifi, inclusding calls to checkWifiConnection - which does ocnnect wifi but the request still seems
        // to go through the bluetooth bridge
        // https://forums.garmin.com/developer/connect-iq/f/discussion/5230/web-requests-without-mobile-connect
        // it seems like edge devices in the simulator do not support this, the callback is just never called (could be a simulator bug)
        // routes still work though, so allowing them to still be used
        Communications.makeWebRequest(
            jsonOrImageReq.url,
            jsonOrImageReq.params,
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
            callback
        );
    }

    function pendingCount() as Number {
        return pending.size();
    }

    function pendingTransmitCount() as Number {
        return pendingTransmit.size();
    }

    function errorCount() as Number {
        return _errorCount;
    }

    function successCount() as Number {
        return _successCount;
    }

    function lastResult() as Number {
        return _lastResult;
    }

    function clearStats() as Void {
        _errorCount = 0;
        _successCount = 0;
        _lastResult = 0;
    }
}
