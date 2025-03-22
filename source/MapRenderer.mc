import Toybox.Lang;
import Toybox.Graphics;
import Toybox.WatchUi;
import Toybox.PersistedContent;

const DATA_TILE_SIZE = 50;
const PIXEL_SIZE = 4;
const TILE_SIZE = DATA_TILE_SIZE * PIXEL_SIZE;
const TILE_PADDING = 0;

class MapRenderer {
    // single dim array might be better performance? 
    // Could do multidim array to make calling code slightly easier
    var _bitmap as BufferedBitmap;
    // todo: get screen size and factor in some amount of padding
    var _screenSize as Float = 360f;
    var _tileCountXY as Number = Math.ceil(_screenSize/TILE_SIZE + 2 * TILE_PADDING).toNumber();
    function initialize() {
        // todo persist to storage and load from storage in init
        _bitmap = newBitmap(_tileCountXY * TILE_SIZE);
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

    function setTileData(tileX as Number ,tileY as Number, arr as Array)
    {
        System.println("setting map tile " + tileX + " " + tileY);
        var tile = tileX * _tileCountXY + tileY;
        if (tile >= _tileCountXY * _tileCountXY)
        {
            System.println("bad tile position: " + tileX + " " + tileY);
            return;
        }

        if (arr.size() != DATA_TILE_SIZE*DATA_TILE_SIZE)
        {
            // we could load tile partially, but that would require checking each itteration of the for loop, 
            // want to avoid any extra work for perf
            System.println("bad tile length: " + arr.size());
            // return;
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
                // localDc.drawPoint(i, j);
                localDc.fillRectangle(i * PIXEL_SIZE, j * PIXEL_SIZE, PIXEL_SIZE, PIXEL_SIZE);
            }
        }

        // might be faster to calculate x/y and render to larger tile, rather than 2 renders?
        // would sure be bettter for memory
        var globalDc = _bitmap.getDc();
        // Communications.makeImageRequest(
        //     "https://www.shutterstock.com/image-vector/pixel-image-super-mario-260nw-2391997417.jpg", 
        //     null, 
        //     {}, 
        //     method( :responseCallback)
        // );
        Communications.makeWebRequest(
            "http://127.0.0.1:8080/",
            null, // paramaters
            {
                :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_TEXT_PLAIN
            }, // options
            method(:makeWebRequestResponseCallback)
        );
        globalDc.drawBitmap(tileX * TILE_SIZE, tileY * TILE_SIZE, localBitmap);
    }

    function responseCallback(responseCode as Number, image as BitmapResource or BitmapReference or Null) as Void
    {
        var globalDc = _bitmap.getDc();
        globalDc.drawBitmap(0, 0, image);
    }
    
    function makeWebRequestResponseCallback(responseCode as Number, data as Dictionary or String or Iterator or Null) as Void
    {
        if (responseCode != 200)
        {
            System.println("failed with: " + responseCode);
            return;
        }

        setTileData(0, 0, (data as String).toUtf8Array());
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

    