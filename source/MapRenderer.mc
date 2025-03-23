import Toybox.Lang;
import Toybox.Graphics;
import Toybox.WatchUi;
import Toybox.PersistedContent;

const DATA_TILE_SIZE = 50;
const PIXEL_SIZE = 1;
const TILE_SIZE = DATA_TILE_SIZE * PIXEL_SIZE;
const TILE_PADDING = 0;

const TILE_PALLET_MODE_OPTIMISED_STRING = 1;
const TILE_PALLET_MODE_LIST = 2;
const TILE_PALLET_MODE_OPTIMISED_STRING_WITH_PALLET = 3;
const TILE_PALLET_MODE = TILE_PALLET_MODE_OPTIMISED_STRING_WITH_PALLET;

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
        if (TILE_PALLET_MODE == TILE_PALLET_MODE_OPTIMISED_STRING || TILE_PALLET_MODE == TILE_PALLET_MODE_OPTIMISED_STRING_WITH_PALLET)
        {
            var mapTile = data["data"];
            if (!(mapTile instanceof String))
            {
                System.println("wrong data type, not string");
                return;
            }
            _mapRenderer.setTileData(_x, _y, mapTile.toUtf8Array());
        }
        else if (TILE_PALLET_MODE == TILE_PALLET_MODE_LIST) 
        {
            var mapTile = data["data"];
            _mapRenderer.setTileData(_x, _y, mapTile as Array<Number>);
        }
        else
        {
            System.println("unrecognised tile mode: " + TILE_PALLET_MODE);
            return;
        }
    }
}

class MapRenderer {
    // single dim array might be better performance? 
    // Could do multidim array to make calling code slightly easier
    var _bitmap as BufferedBitmap;
    // todo: get screen size and factor in some amount of padding
    var _screenSize as Float = 360f;
    var _tileCountXY as Number = Math.ceil(_screenSize/TILE_SIZE + 2 * TILE_PADDING).toNumber();
    var _webRequestHandler as WebRequestHandler = new WebRequestHandler(me);
    var _palette as Array<Number>;
    function initialize() {
        // todo persist to storage and load from storage in init
        _bitmap = newBitmap(_tileCountXY * TILE_SIZE);

        // note: these need to match whats in the app
        // would like tho use the bitmaps colour pallet, but we cannot :( because it erros with
        // Exception: Source must not use a color palette
        _palette = [
            // Greens (Emphasis) - 22 colors
            Graphics.createColor(255, 61, 179, 61),       // Vibrant Green
            Graphics.createColor(255, 102, 179, 102),      // Medium Green
            Graphics.createColor(255, 153, 204, 153),      // Light Green
            Graphics.createColor(255, 0, 102, 0),         // Dark Green
            Graphics.createColor(255, 128, 179, 77),      // Slightly Yellowish Green
            Graphics.createColor(255, 77, 179, 128),      // Slightly Bluish Green
            Graphics.createColor(255, 179, 179, 179),       // Pale Green
            Graphics.createColor(255, 92, 128, 77),      // Olive Green
            Graphics.createColor(255, 148, 209, 23),
            Graphics.createColor(255, 107, 142, 35),  // OliveDrab
            Graphics.createColor(255, 179, 230, 0),        // Lime Green
            Graphics.createColor(255, 102, 179, 0),        // Spring Green
            Graphics.createColor(255, 77, 204, 77),      // Bright Green
            Graphics.createColor(255, 128, 153, 128),      // Grayish Green
            Graphics.createColor(255, 153, 204, 153),      // Soft Green
            Graphics.createColor(255, 0, 128, 0),         // Forest Green
            Graphics.createColor(255, 34, 139, 34),    // ForestGreen
            Graphics.createColor(255, 50, 205, 50),    // LimeGreen
            Graphics.createColor(255, 144, 238, 144),  // LightGreen
            Graphics.createColor(255, 0, 100, 0),       // DarkGreen
            Graphics.createColor(255, 60, 179, 113),     // Medium Sea Green
            Graphics.createColor(255, 46, 139, 87),      // SeaGreen

            // Reds - 8 colors
            Graphics.createColor(255, 230, 0, 0),         // Bright Red
            Graphics.createColor(255, 204, 102, 102),      // Light Red (Pink)
            Graphics.createColor(255, 153, 0, 0),         // Dark Red
            Graphics.createColor(255, 230, 92, 77),      // Coral Red
            Graphics.createColor(255, 179, 0, 38),         // Crimson
            Graphics.createColor(255, 204, 102, 102),      // Rose
            Graphics.createColor(255, 255, 0, 0),     // Pure Red
            Graphics.createColor(255, 255, 69, 0),    // RedOrange

            // Blues - 8 colors
            Graphics.createColor(255, 0, 0, 230),         // Bright Blue
            Graphics.createColor(255, 102, 102, 204),      // Light Blue
            Graphics.createColor(255, 0, 0, 153),         // Dark Blue
            Graphics.createColor(255, 102, 153, 230),      // Sky Blue
            Graphics.createColor(255, 38, 0, 179),         // Indigo
            Graphics.createColor(255, 77, 128, 179),      // Steel Blue
            Graphics.createColor(255, 0, 0, 255),       // Pure Blue
            Graphics.createColor(255, 0, 191, 255),      // DeepSkyBlue

            // Yellows - 6 colors
            Graphics.createColor(255, 230, 230, 0),        // Bright Yellow
            Graphics.createColor(255, 204, 204, 102),      // Light Yellow
            Graphics.createColor(255, 153, 153, 0),        // Dark Yellow (Gold)
            Graphics.createColor(255, 179, 153, 77),      // Mustard Yellow
            Graphics.createColor(255, 255, 255, 0),   // Pure Yellow
            Graphics.createColor(255, 255, 215, 0),   // Gold

            // Oranges - 6 colors
            Graphics.createColor(255, 230, 115, 0),        // Bright Orange
            Graphics.createColor(255, 204, 153, 102),      // Light Orange
            Graphics.createColor(255, 153, 77, 0),         // Dark Orange
            Graphics.createColor(255, 179, 51, 0),         // Burnt Orange
            Graphics.createColor(255, 255, 165, 0),    // Orange
            Graphics.createColor(255, 255, 140, 0),    // DarkOrange

            // Purples - 6 colors
            Graphics.createColor(255, 230, 0, 230),        // Bright Purple
            Graphics.createColor(255, 204, 102, 204),      // Light Purple
            Graphics.createColor(255, 153, 0, 153),        // Dark Purple
            Graphics.createColor(255, 230, 153, 230),      // Lavender
            Graphics.createColor(255, 128, 0, 128),   // Purple
            Graphics.createColor(255, 75, 0, 130),   // Indigo

            // Neutral/Grayscale - 4 colors
            Graphics.createColor(255, 242, 242, 242),      // White
            Graphics.createColor(255, 179, 179, 179),       // Light Gray
            Graphics.createColor(255, 77, 77, 77),         // Dark Gray
            Graphics.createColor(255, 0, 0, 0),         // Black

            // manually picked to match map tiles
            Graphics.createColor(255, 246, 230, 98), // road colours (yellow)
            Graphics.createColor(255, 194, 185, 108), // slightly darker yellow road
            Graphics.createColor(255, 214, 215, 216), // some mountains (light grey)
            Graphics.createColor(255, 213, 237, 168), // some greenery that was not a nice colour
        ];

        if (_palette.size() != 64)
        {
            System.println("colour pallet has only: " + _palette.size() + "elements");
        }
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

        // System.println("tile data " + arr);

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
                var colour = null;
                if (TILE_PALLET_MODE == TILE_PALLET_MODE_OPTIMISED_STRING)
                {
                    var byteColour = arr[it] as Number;
                    // System.println("processing colour" + byteColour);
                    // 2 bits per colour (todo set up colour pallete instead)
                    var red = ((byteColour & 0x030) >> 4) * 255 / 3;
                    var green = ((byteColour & 0x0C) >> 2) * 255 / 3;
                    var blue = (byteColour & 0x03) * 255 / 3;
                    colour = (red << 16) | (green << 8) | blue;
                }
                else if (TILE_PALLET_MODE == TILE_PALLET_MODE_OPTIMISED_STRING_WITH_PALLET)
                {
                    var byteColour = arr[it] as Number;
                    colour = _palette[byteColour & 0x3F];
                }
                else if (TILE_PALLET_MODE == TILE_PALLET_MODE_LIST) 
                {
                    colour = arr[it] as Number;
                }
                else
                {
                    System.println("unrecognised tile mode: " + TILE_PALLET_MODE);
                    return;
                }
                
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

    