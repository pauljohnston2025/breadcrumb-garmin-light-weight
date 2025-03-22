import Toybox.Lang;
import Toybox.Graphics;

const TILE_SIZE = 128;
const TILE_PADDING = 0;

class MapRenderer {
    // single dim array might be better performance? 
    // Could do multidim array to make calling code slightly easier
    var _bitmaps as Array = [];
    // todo: get screen size and factor in some amount of padding
    var _screenSize as Float = 360f;
    var _tileCountXY as Number = Math.ceil(_screenSize/TILE_SIZE + 2 * TILE_PADDING).toNumber();
    function initialize() {
        // todo persist to storage and load from storage in init
        for (var i=0; i<_tileCountXY*_tileCountXY; ++i)
        {
            _bitmaps.add(newBitmap());
        }

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

    function newBitmap() as BufferedBitmap
    {
        var options = {
			:width => TILE_SIZE,
			:height => TILE_SIZE,
		};

        return Graphics.createBufferedBitmap(options).get();
    }

    function setTileData(tileX as Number ,tileY as Number, arr as Array)
    {
        System.println("setting map tile " + tileX + " " + tileY);
        var tile = tileX * _tileCountXY + tileY;
        if (tile >= _bitmaps.size())
        {
            return;
        }

        if (arr.size() != TILE_SIZE*TILE_SIZE)
        {
            // we could load tile partially, but that would require checking each itteration of the for loop, 
            // want to avoid any extra work for perf
            return;
        }

        System.println("processing tile data, first colour is: " + arr[0]);

        var bitmapDc = _bitmaps[tile].getDc();
        var it = 0;
        for (var i=0; i<TILE_SIZE; ++i)
        {
            for (var j=0; j<TILE_SIZE; ++j)
            {
                var colour = arr[it];
                it++;
                bitmapDc.setColor(colour, colour);
                bitmapDc.drawPoint(i, j);
            }
        }
    }

    function renderMap(
        dc as Dc,
        centerPosition as RectangularPoint,
        rotationRad as Float) as Void
    {
        var it = 0;
        var xyOffset = (_tileCountXY * TILE_SIZE - _screenSize) / 2.0f;
        var halfXY = _screenSize / 2.0f;
        var halfTile = TILE_SIZE / 2.0f;
        for (var x=0; x<_tileCountXY; ++x)
        {
            for (var y=0; y<_tileCountXY; ++y)
            {
                var xPos = -xyOffset + x * TILE_SIZE; 
                var yPos = -xyOffset + y * TILE_SIZE;
                var xTranslate = halfXY - (xPos + halfTile);
                var yTranslate = halfXY - (yPos + halfTile);
                var transform = new AffineTransform();
                transform.translate(xTranslate, yTranslate); // move to center
                transform.rotate(rotationRad); // rotate
                transform.translate(-xTranslate, -yTranslate); // move back to position

                var bitmap = _bitmaps[it];
                it++;
                dc.drawBitmap2(
                    xPos,
                    yPos,
                    bitmap,
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
    }
}

    