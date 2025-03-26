import Toybox.Lang;
import Toybox.Graphics;
import Toybox.WatchUi;
import Toybox.PersistedContent;

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
    var _tileCache as TileCache;
    var _settings as Settings;

    function initialize(
        tileCache as TileCache,
        settings as Settings) {
        // todo persist to storage and load from storage in init
        _tileCache = tileCache;
        _settings = settings;
    }
    
    function epsg3857ToTile(xIn as Float, yIn as Float, z as Number) as TileCoordinates {
        // System.println("converting point to tile: " + xIn + " " + yIn + " " + z);

        var originShift = 2 * Math.PI * 6378137 / 2.0; // Half circumference

        var x = (xIn + originShift) / (2 * originShift) * Math.pow(2, z);
        var y = (originShift - yIn) / (2 * originShift) * Math.pow(2, z);

        var tileX = Math.floor(x * _settings.smallTilesPerBigTile).toNumber();
        var tileY = Math.floor(y * _settings.smallTilesPerBigTile).toNumber();

        // var tileXStandard = Math.floor(x).toNumber();
        // var tileYStandard = Math.floor(y).toNumber();
        // System.println("tile url should be: https://a.tile.opentopomap.org/" + z + "/" + tileXStandard + "/" + tileYStandard + ".png");

        return new TileCoordinates(tileX, tileY, z);
    }

    function renderMap(
        dc as Dc,
        scratchPad as BufferedBitmap,
        centerPosition as RectangularPoint,
        rotationRad as Float) as Void
    {
        if (!_settings.mapEnabled)
        {
            return;
        }

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
        var tileSize = _settings.tileSize;
        var tileCount = _screenSize / tileSize;

        // 2 to 15 see https://opentopomap.org/#map=2/-43.2/305.9
        var z = 15;
        var originShift = 2 * Math.PI * 6378137 / 2.0; // Half circumference
        var bigTileWidthM = (2 * originShift) / Math.pow(2, z);
        // smaller since we only have 64*64 tiles, so its /4
        var tileWidthMPartTile = bigTileWidthM/_settings.smallTilesPerBigTile;
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

                var tileKey = new TileKey(tile.x, tile.y, tile.z);
                _tileCache.seedTile(tileKey); // seed it for the next render
                var tileFromCache = _tileCache.getTile(tileKey);
                if (tileFromCache == null || tileFromCache.bitmap == null)
                {
                    continue;
                }

                scratchPadDc.drawBitmap(x * tileSize, y * tileSize, tileFromCache.bitmap);
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

    