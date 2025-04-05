import Toybox.Lang;
import Toybox.Graphics;
import Toybox.WatchUi;
import Toybox.PersistedContent;

class MapRenderer {
    // single dim array might be better performance? 
    // Could do multidim array to make calling code slightly easier
    // todo: get screen size and factor in some amount of padding
    var _screenWidth as Float = 360f;
    var _screenHeight as Float = 360f;
    var _tileCache as TileCache;
    var _settings as Settings;
    var earthsCircumference as Float = 40075016.686f;
    var originShift as Float = earthsCircumference / 2.0; // Half circumference of Earth
    
    function initialize(
        tileCache as TileCache,
        settings as Settings) {
        // todo persist to storage and load from storage in init
        _tileCache = tileCache;
        _settings = settings;
    }

    // Desired resolution (meters per pixel)
    function calculateTileLevel(desiredResolution as Float) as Float {
        // Tile width in meters at zoom level 0
        // var tileWidthAtZoom0 = earthsCircumference;

        // Pixel resolution (meters per pixel) at zoom level 0
        var resolutionAtZoom0 = earthsCircumference / 256f; // big tile coordinates

        // Calculate the tile level (Z)
        var tileLevel = Math.ln(resolutionAtZoom0 / desiredResolution) / Math.ln(2);

        // Round to the nearest integer zoom level
        return tileLevel.toFloat();
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
        var z = Math.round(calculateTileLevel(desiredResolution)).toNumber();
        z = minN(maxN(z, _settings.tileLayerMin), _settings.tileLayerMax); // cap to our limits

        var tileWidthM = (earthsCircumference / Math.pow(2, z)) / _settings.smallTilesPerBigTile;
        // var minScreenDim = minF(_screenWidth, _screenHeight);
        // var minScreenDimM = minScreenDim / currentScale;
        var screenWidthM = _screenWidth / currentScale;
        var screenHeightM = _screenHeight / currentScale;
        
        // where the screen corner starts
        var halfScreenWidthM = screenWidthM / 2f;
        var halfScreenHeightM = screenHeightM / 2f;
        var screenLeftM = centerPosition.x - halfScreenWidthM;
        var screenTopM = centerPosition.y + halfScreenHeightM;

        // find which tile we are closest to
        var firstTileX = ((screenLeftM + originShift) / tileWidthM).toNumber();
        var firstTileY = ((originShift - screenTopM) / tileWidthM).toNumber();

        // remember, lat/long is a different coordinate system (the lower we are the more negative we are)
        //  x calculations are the same - more left = more negative
        //  tile inside graph
        // 90
        //    | 0,0 1,0   tile 
        //    | 0,1 1,1
        //    |____________________
        //  -180,-90              180
        var firstTileLeftM = firstTileX * tileWidthM - originShift;
        var firstTileTopM = originShift - firstTileY * tileWidthM;

        // var screenToTilePixelRatio = minScreenDim / _settings.tileSize;
        // var screenToTileMRatio = minScreenDimM / tileWidthM;
        // var scaleFactor = screenToTilePixelRatio / screenToTileMRatio; // we need to stretch or shrink the tiles by this much
        // simplification of above calculation
        var scaleFactor = (currentScale * tileWidthM)/ _settings.tileSize;
        // eg. tile = 10m screen = 10m tile = 256pixel screen = 360pixel scaleFactor = 1.4 each tile pixel needs to become 1.4 sceen pixels
        // eg. 2
        //     tile = 20m screen = 10m tile = 256pixel screen = 360pixel scaleFactor = 2.8 we only want to render half the tile, so we only have half the pixels
        //     screenToTileMRatio = 0.5 screenToTilePixelRatio = 1.4 
        // eg. 3
        //     tile = 10m screen = 20m tile = 256pixel screen = 360pixel scaleFactor = 0.7 we need 2 tiles, each tile pixel needs to be squashed into screen pixels
        //     screenToTileMRatio = 2 screenToTilePixelRatio = 1.4 
        // 

        // how many pixels on the screen the tile should take up this can be smaller or larger than the actual tile, 
        // depending on if we scale up or down
        // find the closest pixel size
        var scalePixelSize = Math.round(_settings.tileSize * scaleFactor);

        // find the closest pixel size
        var offsetX = Math.round(((firstTileLeftM - screenLeftM) * currentScale));
        var offsetY = Math.round((screenTopM - firstTileTopM) * currentScale);

        var tileCountX = Math.ceil((-offsetX + _screenWidth) / scalePixelSize);
        var tileCountY = Math.ceil((-offsetY + _screenHeight) / scalePixelSize);
        for (var x=0 ; x<tileCountX; ++x)
        {
            for (var y=0 ; y<tileCountY; ++y)
            {
                var tileKey = new TileKey(firstTileX + x, firstTileY + y, z);
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
                $.drawScaledBitmapHelper(scratchPadDc, offsetX + x * scalePixelSize, offsetY + y * scalePixelSize, scalePixelSize, scalePixelSize, tileFromCache.bitmap);
            }
        }

        
        var xOffset = _screenWidth / 2.0f;
        var yOffset = _screenHeight / 2.0f;
        
        var transform = new AffineTransform();
        if (_settings.enableRotation)
        {
            transform.translate(xOffset, yOffset); // move to center
            transform.rotate(-rotationRad); // rotate
            transform.translate(-xOffset, -yOffset); // move back to position
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

    