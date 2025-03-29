import Toybox.Lang;
import Toybox.Graphics;
import Toybox.WatchUi;
import Toybox.PersistedContent;
import Toybox.System;
import Toybox.Communications;

class WebHandler {
    // see error codes such as Communications.NETWORK_REQUEST_TIMED_OUT
    function handle(responseCode as Number, data as Dictionary or String or Iterator or WatchUi.BitmapResource or Graphics.BitmapReference or Null) as Void;
}

class WebRequest {
    var url as String;
    var params as Dictionary<Object, Object>;
    var handler as WebHandler;
    // unique id for this request, if two requests have the same hash the second one will be dropped if the first is pending
    var hash as String;

    function initialize(
        _hash as String,
        _url as String,
        _params as Dictionary<Object, Object>, 
        _handler as WebHandler)
    {
        hash = _hash;
        url = _url;
        params = _params;
        handler = _handler;
    }
}

class JsonRequest extends WebRequest {
    function initialize(
        _hash as String,
        _url as String,
        _params as Dictionary<Object, Object>, 
        _handler as WebHandler)
    {
        WebRequest.initialize(_hash, _url, _params, _handler);
    }
}

class ImageRequest extends WebRequest {
    function initialize(
        _hash as String,
        _url as String,
        _params as Dictionary<Object, Object>, 
        _handler as WebHandler)
    {
       WebRequest.initialize(_hash, _url, _params, _handler);
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

    function handle(responseCode as Number, data as Dictionary or String or Iterator or WatchUi.BitmapResource or Graphics.BitmapReference or Null) as Void
    {
        handler.handle(responseCode, data);

        if (responseCode != 200 && webHandler._settings.tileUrl.equals(COMPANION_APP_TILE_URL))
        {
            // todo only send this on certain errors, and only probbaly only after some limit?
            Communications.transmit("startserice", {}, getApp()._commStatus);
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
    }
}

class WebRequestHandler
{
    // see https://forums.garmin.com/developer/connect-iq/f/discussion/209443/watchface-working-in-simulator-failing-webrequest-on-device-with-http-response--101
    // only 3 web requests are allowed in parallel, so we need to buffer them up and make new requests when we get responses
    // using 2 arrays so we get FIFO
    // also dictionary seemed to make the code 2X slower, think because we had to serch all the keys for a string several times
    var pending as Array<JsonRequest or ImageRequest> = [];
    var pendingHashes as Array<String> = [];
    var _outstandingCount as Number = 0;
    var _settings as Settings;

    function initialize(settings as Settings) {
        _settings = settings;
    }

    function clearValues() as Void
    {
        pending = [];
        pendingHashes = [];
    }

    function add(jsonOrImageReq as JsonRequest or ImageRequest) as Void 
    {
        // todo remove old requests if we get too many (slow network and requests too often mean the internal array grows and we OOM)
        // hard to know if there is one outstanding though, also need to startNext() on a timer if we have not seen any requests in a while
        if (pending.size() > _settings.maxPendingWebRequests)
        {
            // we have too many, don't try and get the tile
            // we should try and dedupe - as its making a request for the same tile twice (2 renders cause 2 requests)
            // logE("Too many pending requests dropping: " + jsonReq.hash);
            return;
        }

        var hash = jsonOrImageReq.hash;
        if (pendingHashes.indexOf(hash) > -1)
        {
            // log("Dropping req for: " + hash);
            startNextIfWeCan(); // start any other ones whilst we are in a different function
            return;
        }

        pending.add(jsonOrImageReq);
        pendingHashes.add(hash);
        // for now just start one at a time, simpler to track
        // At most 3 outstanding can occur, todo query this limit
        // https://forums.garmin.com/developer/connect-iq/f/discussion/204298/ble-queue-full
        // otherwise you will get BLE_QUEUE_FULL (-101)
        startNextIfWeCan();
    }

    function startNextIfWeCan() as Boolean
    {
        if (pending.size() == 0)
        {
            return false;
        }

        if (_outstandingCount < 3)
        {
            // we could get real crazy and start some tile requests through makeWebRequest 
            // and some others through pushing tiles from the companion app
            // seems really hard to maintain though, and ble connection probably already saturated
            start();
            return true;
        }

        return false;
    }

    function decrementOutstanding() as Void 
    {
        --_outstandingCount; 
    }
    
    function start() as Void 
    {
        ++_outstandingCount;
        var jsonOrImageReq = pending[0];
        pending.remove(jsonOrImageReq);
        // trust that the keys are in the same order as the hash
        pendingHashes.remove(jsonOrImageReq.hash);
        if (pending.size() != pendingHashes.size())
        {
            logE("size mismatch: " + pending.size() + " " + pendingHashes.size());
            pending = [];
            pendingHashes = [];
        }

        // System.println("url: "  + jsonOrImageReq.url);
        // System.println("params: "  + jsonOrImageReq.params);

        if (jsonOrImageReq instanceof ImageRequest)
        {
            // System.println("sending image request");
            var callback = (new WebRequestHandle(me, jsonOrImageReq.handler)).method(:handle) as Method(responseCode as Lang.Number, data as WatchUi.BitmapResource or Graphics.BitmapReference or Null) as Void;
            Communications.makeImageRequest(
                jsonOrImageReq.url,
                jsonOrImageReq.params,
                {}, // options
                // see https://forums.garmin.com/developer/connect-iq/f/discussion/2289/documentation-clarification-object-method-and-lang-method
                callback
            );
            return;
        }

        // System.println("sending json request");
        var callback = (new WebRequestHandle(me, jsonOrImageReq.handler)).method(:handle) as Method(responseCode as Lang.Number, data as Lang.Dictionary or Lang.String or PersistedContent.Iterator or Null) as Void or Method(responseCode as Lang.Number, data as Lang.Dictionary or Lang.String or PersistedContent.Iterator or Null, context as Lang.Object) as Void;
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
}
