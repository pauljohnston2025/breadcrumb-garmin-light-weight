import Toybox.Lang;
import Toybox.Graphics;
import Toybox.WatchUi;
import Toybox.PersistedContent;

const PIXEL_SIZE = 1;
const TILE_SIZE = DATA_TILE_SIZE * PIXEL_SIZE;
const TILE_PADDING = 0;

class TileCoordinates
{
    var x as Number;
    var y as Number;
    var z as Number;

    function initialize(
        _x as Number, 
        _y as Number,
        _z as Number)
    {
        x = _x;
        y = _y;
        z = _z;
    }

}

class MapRenderer {
    // single dim array might be better performance? 
    // Could do multidim array to make calling code slightly easier
    // todo: get screen size and factor in some amount of padding
    var _screenSize as Float = 360f;
    var _tileCountXY as Number = Math.ceil(_screenSize/TILE_SIZE + 2 * TILE_PADDING).toNumber();
    var _tileCache as TileCache;
    var smallTilesPerBigTile = Math.ceil(256f/DATA_TILE_SIZE);

    function initialize(tileCache as TileCache) {
        // todo persist to storage and load from storage in init
        _tileCache = tileCache;
    }
    
    function epsg3857ToTile(xIn as Float, yIn as Float, z as Number) as TileCoordinates {
        // System.println("converting point to tile: " + xIn + " " + yIn + " " + z);

        var originShift = 2 * Math.PI * 6378137 / 2.0; // Half circumference

        var x = (xIn + originShift) / (2 * originShift) * Math.pow(2, z);
        var y = (originShift - yIn) / (2 * originShift) * Math.pow(2, z);

        var tileX = Math.floor(x * smallTilesPerBigTile).toNumber();
        var tileY = Math.floor(y * smallTilesPerBigTile).toNumber();

        var tileXStandard = Math.floor(x).toNumber();
        var tileYStandard = Math.floor(y).toNumber();
        // System.println("tile url should be: https://a.tile.opentopomap.org/" + z + "/" + tileXStandard + "/" + tileYStandard + ".png");

        return new TileCoordinates(tileX, tileY, z);
    }

    // function loadMapTilesForPosition(
    //     point as RectangularPoint,
    //     scale as Float) as Void
    // {
    //     // todo only call this when we have moved far enough, should cache a large distance around us
    //     // only when we move off the edge of the map do we need to get the next tiles
    //     // and we could move a bunch of them across ourselves, and only get the ones needed off the edge
    //     var z = 10;
    //     var originShift = 2 * Math.PI * 6378137 / 2.0; // Half circumference
    //     var bigTileWidthM = (2 * originShift) / Math.pow(2, z);
    //     // smaller since we only have 64*64 tiles, so its /4
    //     var tileWidthMPartTile = bigTileWidthM/smallTilesPerBigTile;
    //     for (var x=0 ; x<_tileCountXY; ++x)
    //     {
    //         for (var y=0 ; y<_tileCountXY; ++y)
    //         {
    //             // todo calculate zoom base off scale
    //             // calculate a different tile for each x/y coordintate
    //             // add a cache for the tiles loaded
    //             // todo figure out actual meters per tile size based of scale
    //             var tile = epsg3857ToTile(
    //                 point.x + x * tileWidthMPartTile, 
    //                 point.y - y * tileWidthMPartTile, 
    //                 z
    //             );

    //             _tileCache.seedTile(tile.x, tile.y, tile.z);
    //         }
    //     }
    // }

    function renderMap(
        dc as Dc,
        scratchPad as BufferedBitmap,
        centerPosition as RectangularPoint,
        rotationRad as Float) as Void
    {
        var scratchPadDc = scratchPad.getDc();
        // for debug its purple so we can see any issues, otherwise it should be black
        scratchPadDc.setColor(Graphics.COLOR_PURPLE, Graphics.COLOR_PURPLE);
        scratchPadDc.clear();
        
        // todo
        // maybe skip tile cache a few times and just use the larger one
        // we could store 2 sets of the tiles if we do this
        // think its best to have a 'scratch space' bitmap though that we use for draws then rotates
        // cant rotate individual tiels as you can see the seams between tiles
        // one large one then rotate looks much better, andis possibly faster

        // tilecount will change at zoom levels (we have to scale the tiles up or down)
        var tileCount = _screenSize / TILE_SIZE;

        // 2 to 15 see https://opentopomap.org/#map=2/-43.2/305.9
        var z = 15;
        var originShift = 2 * Math.PI * 6378137 / 2.0; // Half circumference
        var bigTileWidthM = (2 * originShift) / Math.pow(2, z);
        // smaller since we only have 64*64 tiles, so its /4
        var tileWidthMPartTile = bigTileWidthM/smallTilesPerBigTile;
        for (var x=0 ; x<tileCount; ++x)
        {
            for (var y=0 ; y<tileCount; ++y)
            {
                // todo calculate zoom base off scale
                // calculate a different tile for each x/y coordintate
                // add a cache for the tiles loaded
                // todo figure out actual meters per tile size based of scale
                var tile = epsg3857ToTile(
                    centerPosition.x + x * tileWidthMPartTile, 
                    centerPosition.y - y * tileWidthMPartTile, 
                    z
                );

                _tileCache.seedTile(tile.x, tile.y, tile.z); // seed it for the next render
                var tileFromCache = _tileCache.getTile(tile.x, tile.y, tile.z);
                if (tileFromCache == null || tileFromCache.bitmap == null)
                {
                    continue;
                }

                scratchPadDc.drawBitmap(x * DATA_TILE_SIZE, y * DATA_TILE_SIZE, tileFromCache.bitmap);
            }
        }

        
        var xyOffset = _screenSize / 2.0f;
        
        var transform = new AffineTransform();
        transform.translate(xyOffset, xyOffset); // move to center
        transform.rotate(rotationRad); // rotate
        transform.translate(-xyOffset, -xyOffset); // move back to position

        dc.drawBitmap2(
            0,
            0,
            scratchPad,
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

    