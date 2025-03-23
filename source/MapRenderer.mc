import Toybox.Lang;
import Toybox.Graphics;
import Toybox.WatchUi;
import Toybox.PersistedContent;

const DATA_TILE_SIZE = 50;
const PIXEL_SIZE = 1;
const TILE_SIZE = DATA_TILE_SIZE * PIXEL_SIZE;
const TILE_PADDING = 0;

class WebTileRequestHandler extends WebHandler {
    var _mapRenderer as MapRenderer;
    var _x as Number;
    var _y as Number;

    function initialize(
        mapRenderer as MapRenderer,
        x as Number, 
        y as Number)
    {
        WebHandler.initialize();
        _mapRenderer = mapRenderer;
        _x = x;
        _y = y;
    }

    function handle(responseCode as Number, data as Dictionary or String or Iterator or Null) as Void
    {
        if (responseCode != 200)
        {
            // see error codes such as Communications.NETWORK_REQUEST_TIMED_OUT
            System.println("failed with: " + responseCode);
            return;
        }

        if (!(data instanceof Dictionary))
        {
            System.println("wrong data type, not dict");
            return;
        }

        // System.print("data: " + data);
        var mapTile = data["data"];
        _mapRenderer.setTileData(_x, _y, mapTile as Array<Number>);
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

        var bitmap = Graphics.createBufferedBitmap(options).get();
        if (!(bitmap instanceof BufferedBitmap))
        {
            System.println("Could not allocate buffered bitmap");
            throw new Exception();
        }

        return bitmap;
    }

    function setTileData(tileX as Number, tileY as Number, arr as Array<Number>) as Void
    {
        // System.println("setting map tile " + tileX + " " + tileY);
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

        // System.println("processing tile data, first colour is: " + arr[0]);

        var localBitmap = newBitmap(TILE_SIZE);
        var localDc = localBitmap.getDc();
        var it = 0;
        for (var i=0; i<DATA_TILE_SIZE; ++i)
        {
            for (var j=0; j<DATA_TILE_SIZE; ++j)
            {
                var colour = arr[it];
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
        var xyOffset = (_tileCountXY * TILE_SIZE) / 2.0f;
        
        var transform = new AffineTransform();
        transform.translate(xyOffset, xyOffset); // move to center
        transform.rotate(rotationRad); // rotate
        transform.translate(-xyOffset, -xyOffset); // move back to position

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

    