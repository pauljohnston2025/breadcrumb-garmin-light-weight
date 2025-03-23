import Toybox.Lang;
import Toybox.Graphics;
import Toybox.WatchUi;
import Toybox.PersistedContent;

class WebHandler {
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

    function initialize() {
        _urlPrefix = "http://127.0.0.1:8080";
        // if (isSimulator())
        // {
        //     _urlPrefix = "http://192.168.1.101:81";
        // }
    }

    function add(jsonReq as JsonRequest) as Void 
    {
        pending.add(jsonReq);
        // for now just start one at a time, simpler to track
        if (noOutstanding)
        {
            startNext();
        }
    }

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
