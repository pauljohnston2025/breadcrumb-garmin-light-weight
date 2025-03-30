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
    var earthRadius = 6378137; // Earth radius in meters
    var originShift = 2 * Math.PI * earthRadius / 2.0; // Half circumference of Earth
    var originShiftTime2 = originShift * 2;

    function initialize(
        tileCache as TileCache,
        settings as Settings) {
        // todo persist to storage and load from storage in init
        _tileCache = tileCache;
        _settings = settings;
    }
    
    function epsg3857ToTile(xIn as Float, yIn as Float, z as Number) as TileCoordinates {
        // System.println("converting point to tile: " + xIn + " " + yIn + " " + z);
        var x = (xIn + originShift) / originShiftTime2 * Math.pow(2, z);
        var y = (originShift - yIn) / originShiftTime2 * Math.pow(2, z);

        var tileX = Math.floor(x * _settings.smallTilesPerBigTile).toNumber();
        var tileY = Math.floor(y * _settings.smallTilesPerBigTile).toNumber();

        // var tileXStandard = Math.floor(x).toNumber();
        // var tileYStandard = Math.floor(y).toNumber();
        // System.println("tile url should be: https://a.tile.opentopomap.org/" + z + "/" + tileXStandard + "/" + tileYStandard + ".png");

        return new TileCoordinates(tileX, tileY, z);
    }

    // Desired resolution (meters per pixel)
    function calculateTileLevel(desiredResolution as Float) as Number {
        var earthRadius = 6378137; // Earth radius in meters
        var originShift = 2 * Math.PI * earthRadius / 2.0; // Half circumference of Earth

        // Tile width in meters at zoom level 0
        var tileWidthAtZoom0 = (2 * originShift) / 1;

        // Pixel resolution (meters per pixel) at zoom level 0
        var resolutionAtZoom0 = tileWidthAtZoom0 / 256; // 256 is standard tile size

        // Calculate the tile level (Z)
        var tileLevel = Math.ln(resolutionAtZoom0 / desiredResolution) / Math.ln(2);

        // Round to the nearest integer zoom level
        return Math.round(tileLevel);
    }

    function renderMap(
        dc as Dc,
        scratchPad as BufferedBitmap,
        centerPosition as RectangularPoint,
        rotationRad as Float,
        currentScale as Float) as Void
    {
        if (currentScale == 0)
        {
            // do not divide by zero my good friends
            // we do not have a scale calculated yet
            return;
        }

        if (!_settings.mapEnabled)
        {
            return;
        }

        var scratchPadDc = scratchPad.getDc();
        // for debug its purple so we can see any issues, otherwise it should be black
        scratchPadDc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        scratchPadDc.clear();
        
        // 2 to 15 see https://opentopomap.org/#map=2/-43.2/305.9
        var desiredResolution = 1 / currentScale;
        var z = calculateTileLevel(desiredResolution);
        z = minN(maxN(z, _settings.tileLayerMin), _settings.tileLayerMax); // cap to our limits

        // smaller since we only have 64*64 tiles, so its /4
        var bigTileWidthM = (2 * originShift) / Math.pow(2, z);
        // this needs to factor in the 
        var smallTileWidthM = bigTileWidthM/_settings.smallTilesPerBigTile;

        var screenWidthM = _screenSize / currentScale;
        var screenToTileMRatio = screenWidthM / smallTileWidthM;
        var screenToTilePixelRatio = _screenSize / _settings.tileSize;
        var scaleFactor = screenToTilePixelRatio/screenToTileMRatio; // we need to stretch or shrink the tiles by this much

        var scaleSize = Math.ceil(_settings.tileSize * scaleFactor);
        var tileCount = Math.ceil(_screenSize / scaleSize).toNumber();
        var tileOffset = ((tileCount * scaleSize) - _screenSize) / 2f;

        var halfTileCountM = (tileCount / 2f) * smallTileWidthM;
        var tilesLoadFromX = centerPosition.x - halfTileCountM;
        var tilesLoadFromY = centerPosition.y + halfTileCountM;

        for (var x=0 ; x<tileCount; ++x)
        {
            for (var y=0 ; y<tileCount; ++y)
            {
                // todo calculate zoom base off scale
                // calculate a different tile for each x/y coordintate
                // add a cache for the tiles loaded
                // todo figure out actual meters per tile size based of scale
                var tile = epsg3857ToTile(
                    tilesLoadFromX + x * smallTileWidthM, 
                    tilesLoadFromY - y * smallTileWidthM, 
                    z
                );

                var tileKey = new TileKey(tile.x, tile.y, tile.z);
                _tileCache.seedTile(tileKey); // seed it for the next render
                var tileFromCache = _tileCache.getTile(tileKey);
                if (tileFromCache == null || tileFromCache.bitmap == null)
                {
                    continue;
                }

                // Its best to have a 'scratch space' bitmap that we use for draws then rotate the whole thing
                // cant rotate individual tiles as you can see the seams between tiles
                // one large one then rotate looks much better, and is possibly faster
                // we must scale as the tile we picked is only close to the resolution we need
                scratchPadDc.drawScaledBitmap(-tileOffset + x * scaleSize, -tileOffset + y * scaleSize, scaleSize, scaleSize, tileFromCache.bitmap);
                // no scaling incase issues
                // scratchPadDc.drawBitmap(-tileOffset + x * scaleSize, -tileOffset + y * scaleSize, tileFromCache.bitmap);
            }
        }

        
        var xyOffset = _screenSize / 2.0f;
        
        var transform = new AffineTransform();
        if (_settings.enableRotation)
        {
            transform.translate(xyOffset, xyOffset); // move to center
            transform.rotate(rotationRad); // rotate
            transform.translate(-xyOffset, -xyOffset); // move back to position
        }

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

    