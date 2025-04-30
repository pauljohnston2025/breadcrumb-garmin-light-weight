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
        cachedValues as CachedValues
    ) {
        // todo persist to storage and load from storage in init
        _tileCache = tileCache;
        _settings = settings;
        _cachedValues = cachedValues;
    }

    function seedTiles() as Void {
        var cachedValues = _cachedValues; // local lookup faster
        if (!_cachedValues.mapDataCanBeUsed) {
            // do not divide by zero my good friends
            // we do not have a scale calculated yet
            return;
        }

        if (!_settings.mapEnabled) {
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

        for (
            var x = -_settings.tileCachePadding;
            x < tileCountX + _settings.tileCachePadding;
            ++x
        ) {
            for (
                var y = -_settings.tileCachePadding;
                y < tileCountY + _settings.tileCachePadding;
                ++y
            ) {
                var tileKey = new TileKey(firstTileX + x, firstTileY + y, tileZ);
                _tileCache.seedTile(tileKey); // seed it for the next render
            }
        }
    }

    function renderMapUnrotated(dc as Dc) as Void {
        var cachedValues = _cachedValues; // local lookup faster
        if (!_cachedValues.mapDataCanBeUsed) {
            // do not divide by zero my good friends
            // we do not have a scale calculated yet
            return;
        }

        if (!_settings.mapEnabled) {
            return;
        }

        if (_settings.authMissing()) {
            dc.setColor(Graphics.COLOR_RED, Graphics.COLOR_BLACK);
            dc.clear();    
            dc.drawText(
                _cachedValues.xHalf,
                _cachedValues.yHalf,
                Graphics.FONT_SYSTEM_MEDIUM,
                "AUTH TOKEN\nMISSING",
                Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER
            );
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

        for (var x = 0; x < tileCountX; ++x) {
            for (var y = 0; y < tileCountY; ++y) {
                var tileKey = new TileKey(firstTileX + x, firstTileY + y, tileZ);
                var tileFromCache = _tileCache.getTile(tileKey); // seed it for the next render
                if (tileFromCache == null || tileFromCache.bitmap == null) {
                    continue;
                }

                // Its best to have a 'scratch space' bitmap that we use for draws then rotate the whole thing
                // cant rotate individual tiles as you can see the seams between tiles
                // one large one then rotate looks much better, and is possibly faster
                // we must scale as the tile we picked is only close to the resolution we need
                $.drawScaledBitmapHelper(
                    dc,
                    tileOffsetX + x * tileScalePixelSize,
                    tileOffsetY + y * tileScalePixelSize,
                    tileScalePixelSize,
                    tileScalePixelSize,
                    tileFromCache.bitmap
                );
            }
        }
    }

    function renderMap(dc as Dc) as Void {
        var cachedValues = _cachedValues; // local lookup faster
        if (!_cachedValues.mapDataCanBeUsed) {
            // do not divide by zero my good friends
            // we do not have a scale calculated yet
            return;
        }

        if (!_settings.mapEnabled) {
            return;
        }
        
        if (_settings.authMissing()) {
            dc.setColor(Graphics.COLOR_RED, Graphics.COLOR_BLACK);
            dc.clear();    
            dc.drawText(
                _cachedValues.xHalf,
                _cachedValues.yHalf,
                Graphics.FONT_SYSTEM_MEDIUM,
                "AUTH TOKEN\nMISSING",
                Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER
            );
            return;
        }

        // for debug its purple so we can see any issues, otherwise it should be black
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();

        var tileScalePixelSize = cachedValues.tileScalePixelSize; // local lookup faster
        var tileScaleFactor = cachedValues.tileScaleFactor; // local lookup faster
        var tileOffsetX = cachedValues.tileOffsetX; // local lookup faster
        var tileOffsetY = cachedValues.tileOffsetY; // local lookup faster
        var tileCountX = cachedValues.tileCountX; // local lookup faster
        var tileCountY = cachedValues.tileCountY; // local lookup faster
        var firstTileX = cachedValues.firstTileX; // local lookup faster
        var firstTileY = cachedValues.firstTileY; // local lookup faster
        var tileZ = cachedValues.tileZ; // local lookup faster

        for (var x = 0; x < tileCountX; ++x) {
            for (var y = 0; y < tileCountY; ++y) {
                var tileKey = new TileKey(firstTileX + x, firstTileY + y, tileZ);
                var tileFromCache = _tileCache.getTile(tileKey); // seed it for the next render
                if (tileFromCache == null || tileFromCache.bitmap == null) {
                    continue;
                }

                // Its best to have a 'scratch space' bitmap that we use for draws then rotate the whole thing
                // cant rotate individual tiles as you can see the seams between tiles
                // one large one then rotate looks much better, and is possibly faster
                // we must scale as the tile we picked is only close to the resolution we need
                var xPos = (tileOffsetX + x * tileScalePixelSize).toFloat();
                var yPos = (tileOffsetY + y * tileScalePixelSize).toFloat();
                var xTranslate = cachedValues.xHalf - xPos;
                var yTranslate = cachedValues.yHalf - yPos;
                var rotationMatrix = new AffineTransform();
                // Apply transformations in REVERSE order of visual effect:
                rotationMatrix.translate(xTranslate, yTranslate); // move to center
                rotationMatrix.rotate(-cachedValues.rotationRad); // rotate
                rotationMatrix.translate(-xTranslate, -yTranslate); // move back to position
                rotationMatrix.scale(tileScaleFactor, tileScaleFactor); // scale

                // Error: Unhandled Exception
                // Time: 2025-04-19T13:31:58Z
                // Part-Number: 006-B3704-00
                // Firmware-Version: '19.05'
                // Language-Code: eng
                // ConnectIQ-Version: 5.1.1
                // Filename: BreadcrumbDataField
                // Appname: BreadcrumbDataField
                // Stack:
                //   - pc: 0x1000c98a
                //     File: 'BreadcrumbDataField\source\MapRenderer.mc'
                //     Line: 160
                //     Function: renderMap
                //   - pc: 0x1000ad04
                //     File: 'BreadcrumbDataField\source\BreadcrumbDataFieldView.mc'
                //     Line: 410
                //     Function: renderMain
                //   - pc: 0x1000b7f0
                //     File: 'BreadcrumbDataField\source\BreadcrumbDataFieldView.mc'
                //     Line: 293
                //     Function: onUpdate
                try {
                    dc.drawBitmap2(xPos, yPos, tileFromCache.bitmap, {
                        // :bitmapX =>
                        // :bitmapY =>
                        // :bitmapWidth =>
                        // :bitmapHeight =>
                        // :tintColor =>
                        :transform => rotationMatrix,
                        // Use bilinear filtering for smoother results when rotating/scaling (less noticible tearing)
                        :filterMode => Graphics.FILTER_MODE_BILINEAR,
                    });
                } catch (e) {
                    // not sure what this exception was see above
                    // simultor keeps getting InvalidValueException: Source must not use a color palette but I never use a colour pallete for this very reason
                    // seems to only be in render modes that render directly to dc, and not through the scratchpad
                    // also worked fine with vivoactive 5 (that always renders the bitmaps through drawBitmap2), but failed with the venu2s (my normal test device).
                    // purged the tmp dir AppData\Local\Temp\com.garmin.connectiq
                    // it seems to be wehn loading from an external tile server - so Communications.PACKING_FORMAT_DEFAULT in makeImageRequest must be the culprit (possibly vivoactive is always a png?).
                    // changing it to 
                    // tileFromCache.bitmap.isCached() + " "
                    //  + " " + tileFromCache.bitmap
                    logE("failed drawBitmap2: " + e.getErrorMessage());
                    ++$.globalExceptionCounter;
                }
            }
            
        }
    }
}
