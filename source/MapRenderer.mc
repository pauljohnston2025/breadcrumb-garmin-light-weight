import Toybox.Lang;
import Toybox.Graphics;
import Toybox.WatchUi;
import Toybox.PersistedContent;

class MapRenderer {
    // single dim array might be better performance? 
    // Could do multidim array to make calling code slightly easier
    // todo: get screen size and factor in some amount of padding
    var _tileCache as TileCache;
    var _settings as Settings;
    var _cachedValues as CachedValues;
    
    function initialize(
        tileCache as TileCache,
        settings as Settings,
        cachedValues as CachedValues) {
        // todo persist to storage and load from storage in init
        _tileCache = tileCache;
        _settings = settings;
        _cachedValues = cachedValues;
    }

    function seedTiles() as Void
    {
        var cachedValues = _cachedValues; // local lookup faster
        if (!_cachedValues.mapDataCanBeUsed)
        {
            // do not divide by zero my good friends
            // we do not have a scale calculated yet
            return;
        }

        if (!_settings.mapEnabled)
        {
            return;
        }

        var tileScalePixelSize = cachedValues.tileScalePixelSize; // local lookup faster
        var tileOffsetX = cachedValues.tileOffsetX; // local lookup faster
        var tileOffsetY = cachedValues.tileOffsetY; // local lookup faster
        var tileCountX = cachedValues.tileCountX; // local lookup faster
        var tileCountY = cachedValues.tileCountY; // local lookup faster
        var firstTileX = cachedValues.firstTileX; // local lookup faster
        var firstTileY = cachedValues.firstTileY; // local lookup faster
        var tileZ = cachedValues.tileZ; // local lookup faster
        
        for (var x=-_settings.tileCachePadding ; x<tileCountX + _settings.tileCachePadding; ++x)
        {
            for (var y=-_settings.tileCachePadding ; y<tileCountY + _settings.tileCachePadding; ++y)
            {
                var tileKey = new TileKey(firstTileX + x, firstTileY + y, tileZ);
                _tileCache.seedTile(tileKey); // seed it for the next render
            }
        }
    }
    
    function renderMapUnrotated(dc as Dc) as Void
    {
        var cachedValues = _cachedValues; // local lookup faster
        if (!_cachedValues.mapDataCanBeUsed)
        {
            // do not divide by zero my good friends
            // we do not have a scale calculated yet
            return;
        }

        if (!_settings.mapEnabled)
        {
            return;
        }

        // for debug its purple so we can see any issues, otherwise it should be black
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();

        var tileScalePixelSize = cachedValues.tileScalePixelSize; // local lookup faster
        var tileOffsetX = cachedValues.tileOffsetX; // local lookup faster
        var tileOffsetY = cachedValues.tileOffsetY; // local lookup faster
        var tileCountX = cachedValues.tileCountX; // local lookup faster
        var tileCountY = cachedValues.tileCountY; // local lookup faster
        var firstTileX = cachedValues.firstTileX; // local lookup faster
        var firstTileY = cachedValues.firstTileY; // local lookup faster
        var tileZ = cachedValues.tileZ; // local lookup faster
        
        for (var x=0 ; x<tileCountX; ++x)
        {
            for (var y=0 ; y<tileCountY; ++y)
            {
                var tileKey = new TileKey(firstTileX + x, firstTileY + y, tileZ);
                var tileFromCache = _tileCache.getTile(tileKey); // seed it for the next render
                if (tileFromCache == null || tileFromCache.bitmap == null)
                {
                    continue;
                }

                // Its best to have a 'scratch space' bitmap that we use for draws then rotate the whole thing
                // cant rotate individual tiles as you can see the seams between tiles
                // one large one then rotate looks much better, and is possibly faster
                // we must scale as the tile we picked is only close to the resolution we need
                $.drawScaledBitmapHelper(dc, tileOffsetX + x * tileScalePixelSize, tileOffsetY + y * tileScalePixelSize, tileScalePixelSize, tileScalePixelSize, tileFromCache.bitmap);
            }
        }
    }
    
    function renderMap(dc as Dc) as Void
    {
        var cachedValues = _cachedValues; // local lookup faster
        if (!_cachedValues.mapDataCanBeUsed)
        {
            // do not divide by zero my good friends
            // we do not have a scale calculated yet
            return;
        }

        if (!_settings.mapEnabled)
        {
            return;
        }

        // for debug its purple so we can see any issues, otherwise it should be black
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();

        var tileScalePixelSize = cachedValues.tileScalePixelSize; // local lookup faster
        var tileOffsetX = cachedValues.tileOffsetX; // local lookup faster
        var tileOffsetY = cachedValues.tileOffsetY; // local lookup faster
        var tileCountX = cachedValues.tileCountX; // local lookup faster
        var tileCountY = cachedValues.tileCountY; // local lookup faster
        var firstTileX = cachedValues.firstTileX; // local lookup faster
        var firstTileY = cachedValues.firstTileY; // local lookup faster
        var tileZ = cachedValues.tileZ; // local lookup faster

        // we need to scale it down first, then draw the scaled tile rotated to the larger dc
        var bitmap = newBitmap(tileScalePixelSize, tileScalePixelSize, null);
        var bitmapDc = bitmap.getDc();
        
        for (var x=0 ; x<tileCountX; ++x)
        {
            for (var y=0 ; y<tileCountY; ++y)
            {
                var tileKey = new TileKey(firstTileX + x, firstTileY + y, tileZ);
                var tileFromCache = _tileCache.getTile(tileKey); // seed it for the next render
                if (tileFromCache == null || tileFromCache.bitmap == null)
                {
                    continue;
                }

                // Its best to have a 'scratch space' bitmap that we use for draws then rotate the whole thing
                // cant rotate individual tiles as you can see the seams between tiles
                // one large one then rotate looks much better, and is possibly faster
                // we must scale as the tile we picked is only close to the resolution we need
                $.drawScaledBitmapHelper(bitmapDc, 0, 0, tileScalePixelSize, tileScalePixelSize, tileFromCache.bitmap);
                var xPos = (tileOffsetX + x * tileScalePixelSize).toFloat();
                var yPos = (tileOffsetY + y * tileScalePixelSize).toFloat();
                var halfTile = tileScalePixelSize / 2f;
                var xTranslate = cachedValues.xHalf - (xPos + halfTile);
                var yTranslate = cachedValues.yHalf - (yPos + halfTile);
                var rotationMatrix = new AffineTransform();
                rotationMatrix.translate(xTranslate, yTranslate); // move to center
                rotationMatrix.rotate(-cachedValues.rotationRad); // rotate
                rotationMatrix.translate(-xTranslate, -yTranslate); // move back to position
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
                        :transform => rotationMatrix
                    }
                );
            }
        }
    }
}

    