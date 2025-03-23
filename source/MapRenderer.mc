import Toybox.Lang;
import Toybox.Graphics;
import Toybox.WatchUi;
import Toybox.PersistedContent;

const DATA_TILE_SIZE = 50;
const PIXEL_SIZE = 1;
const TILE_SIZE = DATA_TILE_SIZE * PIXEL_SIZE;
const TILE_PADDING = 0;

class WebHandler {
    function handle(responseCode as Number, data as Dictionary or String or Iterator or Null) as Void;
}

class WebTileRequestHandler extends WebHandler {
    var _mapRenderer as MapRenderer;
    var _x as Number;
    var _y as Number;

    function initialize(
        mapRenderer as MapRenderer,
        x as Number, 
        y as Number)
    {
        _mapRenderer = mapRenderer;
        _x = x;
        _y = y;
    }

    function handle(responseCode as Number, data as Dictionary or String or Iterator or Null) as Void
    {
        if (responseCode != 200)
        {
            System.println("failed with: " + responseCode);
            return;
        }

        // todo check type is dictionary (json response)
        _mapRenderer.setTileData(_x, _y, (data["data"] as String).toUtf8Array());
    }
}

class JsonRequest {
    var method as String;
    var params as Dictionary;
    var handler as WebHandler;

    function initialize(
        _method as String,
        _params as Dictionary, 
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

    function add(jsonReq as JsonRequest) {
        pending.add(jsonReq);
        // for now just start one at a time, simpler to track
        if (noOutstanding)
        {
            startNext();
        }
    }

    function startNext()
    {
        // todo: may need to handle race where one completes and one is added at the same time?
        // think its all single threaded, so should not matter
        if (pending.size() == 0)
        {
            noOutstanding = true;
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

class MapRenderer {
    // single dim array might be better performance? 
    // Could do multidim array to make calling code slightly easier
    var _bitmap as BufferedBitmap;
    // todo: get screen size and factor in some amount of padding
    var _screenSize as Float = 360f;
    var _tileCountXY as Number = Math.ceil(_screenSize/TILE_SIZE + 2 * TILE_PADDING).toNumber();
    var _webRequestHandler as WebRequestHandler = new WebRequestHandler();
    function initialize() {
        // todo persist to storage and load from storage in init
        _bitmap = newBitmap(_tileCountXY * TILE_SIZE);
        // to make this work on the emulator you ned to run 
        // adb forward tcp:8080 tcp:8080
        // test code
        // var red = [];
        // var green = [];
        // var blue = [];
        // for (var i=0 ; i<TILE_SIZE*TILE_SIZE; ++i)
        // {
        //     red.add(Graphics.COLOR_RED);
        //     green.add(Graphics.COLOR_GREEN);
        //     blue.add(Graphics.COLOR_BLUE);
        // }
        // setTileData(0, 0, red);
        // setTileData(1, 1, green);
        // setTileData(2, 2, blue);
        // setTileData(3, 3, red);
        // setTileData(4, 4, green);
        // setTileData(5, 5, blue);
        // setTileData(6, 6, red);
        // setTileData(7, 7, green);
        // setTileData(8, 8, blue);
        // setTileData(9, 9, red);
        // setTileData(10, 10, green);
        // setTileData(11, 11, blue);
    }

    function newBitmap(size as Number) as BufferedBitmap
    {
        var options = {
			:width => size,
			:height => size,
		};

        return Graphics.createBufferedBitmap(options).get();
    }

    function setTileData(tileX as Number, tileY as Number, arr as Array)
    {
        System.println("setting map tile " + tileX + " " + tileY);
        var tile = tileX * _tileCountXY + tileY;
        if (tile >= _tileCountXY * _tileCountXY)
        {
            System.println("bad tile position: " + tileX + " " + tileY);
            return;
        }

        if (arr.size() < DATA_TILE_SIZE*DATA_TILE_SIZE)
        {
            System.println("tile length too short: " + arr.size());
            return;
        }

        if (arr.size() != DATA_TILE_SIZE*DATA_TILE_SIZE)
        {
            // we could load tile partially, but that would require checking each itteration of the for loop, 
            // want to avoid any extra work for perf
            System.println("bad tile length: " + arr.size() + " best effort load");
        }

        System.println("processing tile data, first colour is: " + arr[0]);

        var localBitmap = newBitmap(TILE_SIZE);
        var localDc = localBitmap.getDc();
        var it = 0;
        for (var i=0; i<DATA_TILE_SIZE; ++i)
        {
            for (var j=0; j<DATA_TILE_SIZE; ++j)
            {
                var byteColour = arr[it];
                // System.println("processing colour" + byteColour);
                // 2 bits per colour (todo set up colour pallete instead)
                var red = ((byteColour & 0x030) >> 4) * 255 / 3;
                var green = ((byteColour & 0x0C) >> 2) * 255 / 3;
                var blue = (byteColour & 0x03) * 255 / 3;
                var colour = (red << 16) | (green << 8) | blue;
                it++;
                localDc.setColor(colour, colour);
                if (PIXEL_SIZE == 1)
                {
                    localDc.drawPoint(i, j);
                }
                else {
                    localDc.fillRectangle(i * PIXEL_SIZE, j * PIXEL_SIZE, PIXEL_SIZE, PIXEL_SIZE);
                }
            }
        }

        // might be faster to calculate x/y and render to larger tile, rather than 2 renders?
        // would sure be bettter for memory
        var globalDc = _bitmap.getDc();

        globalDc.drawBitmap(tileX * TILE_SIZE, tileY * TILE_SIZE, localBitmap);
    }

    function loadMapTilesForPosition(
        lat as Float, 
        long as Float, 
        scale as Float) as Void
    {
        // todo only call this when we have moved far enough, should cache a large distance around us
        // only when we move off the edge of the map do we need to get the next tiles
        // and we could move a bunch of them across ourselves, and only get the ones needed off the edge
        for (var x=0 ; x<_tileCountXY; ++x)
        {
            for (var y=0 ; y<_tileCountXY; ++y)
            {
                _webRequestHandler.add(
                    new JsonRequest(
                        "/loadtile",
                        {
                            "lat" => lat,
                            "long" => long,
                            "tileX" => x,
                            "tileY" => y,
                            "scale" => scale,
                            "tileSize" => DATA_TILE_SIZE,
                            "tileCountXY" => _tileCountXY,
                        },
                        new WebTileRequestHandler(me, x, y)
                    )
                );
            }
        }
    }

    function renderMap(
        dc as Dc,
        centerPosition as RectangularPoint,
        rotationRad as Float) as Void
    {
        var it = 0;
        var xyOffset = (_tileCountXY * TILE_SIZE) / 2.0f;
        
        var transform = new AffineTransform();
        // transform.translate(xyOffset, xyOffset); // move to center
        // transform.rotate(rotationRad); // rotate
        // transform.translate(-xyOffset, -xyOffset); // move back to position

        dc.drawBitmap2(
            0,
            0,
            _bitmap,
            {
                // :bitmapX =>
                // :bitmapY =>
                // :bitmapWidth =>
                // :bitmapHeight =>
                // :tintColor =>
                // :filterMode =>
                :transform => transform
            }
        );
    }
}

    