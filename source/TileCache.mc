import Toybox.Lang;
import Toybox.Graphics;
import Toybox.WatchUi;
import Toybox.PersistedContent;
using Toybox.Graphics;
using Toybox.Lang;
using Toybox.Math;
using Toybox.System;
using Toybox.Communications;
using Toybox.Application.Storage;
using Toybox.Time;

// trying to improve perf of lookups
// string might be slow to create and compare
// though string compares are likely done natively
class TileKey {
    var x as Number;
    var y as Number;
    var z as Number;

    function initialize(x as Number, y as Number, z as Number) {
        self.x = x;
        self.y = y;
        self.z = z;
    }

    function toString() as String {
        return Lang.format("$1$-$2$-$3$", [x, y, z]);
    }

    function hashCode() as Number {
        return x + y + z;
    }

    function equals(other as Object or Null) as Boolean {
        if (!(other instanceof TileKey))
        {
            return false;
        }

        return x == other.x && y == other.y && z == other.z ;
    }

    // Serialize the Tile object to a Dictionary
    function serializeToDictionary() as Dictionary {
        return {
            "x" => self.x,
            "y" => self.y,
            "z" => self.z,
        };
    }

        // Deserialize a Tile object from a Dictionary
    static function deserializeFromDictionary(data as Dictionary) as TileKey or Null {
        if (!data.hasKey("x") || !data.hasKey("y") || !data.hasKey("z"))
        {
            return null;    
        }

        return new TileKey(
            data["x"] as Number, 
            data["y"] as Number, 
            data["z"] as Number
        );
    }
}

class Tile {
    var lastUsed as Number;
    var bitmap as Graphics.BufferedBitmap or WatchUi.BitmapResource or Graphics.BitmapReference or Null;
    var storageIndex as Number or Null;

    function initialize() {
        self.lastUsed = System.getTimer();
        self.bitmap = null;
        self.storageIndex = null;
    }

    function setBitmap(bitmap as Graphics.BufferedBitmap or WatchUi.BitmapResource or Graphics.BitmapReference) as Void {
        self.bitmap = bitmap;
    }

    function markUsed() as Void
    {
        lastUsed = System.getTimer();
    }

    function setStorageIndex(storageIndex as Number) as Void {
        self.storageIndex = storageIndex;
    }
}

class WebTileRequestHandler extends WebHandler {
    var _tileCache as TileCache;
    var _tileKey as TileKey;
    
    function initialize(
        tileCache as TileCache,
        tileKey as TileKey
    )
    {
        WebHandler.initialize();
        _tileCache = tileCache;
        _tileKey = tileKey;
    }

    function handle(responseCode as Number, data as Dictionary or String or Iterator or WatchUi.BitmapResource or Graphics.BitmapReference or Null) as Void
    {
        if (responseCode != 200)
        {
            // see error codes such as Communications.NETWORK_REQUEST_TIMED_OUT
            System.println("failed with: " + responseCode);
            return;
        }

        if (data instanceof WatchUi.BitmapResource || data instanceof Graphics.BitmapReference)
        {
            var settings = getApp()._breadcrumbContext.settings();
            // we have to downsample the tile, not recomendedd, as this mean we will have to request the same tile multiple times (cant save big tiles around anywhere)
            // also means we have to use scratch space to draw the tile and downsample it
            
            if (data.getWidth() != settings.tileSize || data.getHeight() != settings.tileSize)
            {
                // dangerous large bitmap could cause oom, buts its the only way to upscale the image and then slice it
                // we cannot downscale because we would be slicing a pixel in half
                // I guess we could just figure out which pixels to double up on?
                // anyone using an external tile server should be setting thier tileSize to 256, but perhaps some devices will run out of memory?
                // if users are using a smaller size it should be a multiple of 256.
                // if its not, we will stretch the image then downsize, if its already a multiple we will use the image as is (optimal)
                var maxDim = maxN(data.getWidth(), data.getHeight()); // should be equal (every time server i know of is 256*256), but who knows
                var pixelsPerTile = maxDim / settings.smallTilesPerBigTile.toFloat();
                var sourceBitmap = data;
                if (Math.ceil(pixelsPerTile) != pixelsPerTile)
                {
                    // we have an aloying situation - stretch the image
                    var scaleUpSize = settings.smallTilesPerBigTile * settings.tileSize;
                    var upscaledBitmap = newBitmap(scaleUpSize, null);
                    var upscaledBitmapDc = upscaledBitmap.getDc();
                    upscaledBitmapDc.drawScaledBitmap(0, 0, scaleUpSize, scaleUpSize, sourceBitmap);
                    System.println("scaled up to: " + upscaledBitmap.getWidth() + " " + upscaledBitmap.getHeight());
                    System.println("from: " + sourceBitmap.getWidth() + " " + sourceBitmap.getHeight());
                    sourceBitmap = upscaledBitmap; // resume what we were doing as if it was always the larger bitmap
                }

                var croppedSection = newBitmap(settings.tileSize, null);
                var croppedSectionDc = croppedSection.getDc();
                var xOffset = _tileKey.x % settings.smallTilesPerBigTile;
                var yOffset = _tileKey.y % settings.smallTilesPerBigTile;
                System.println("tile: " + _tileKey);
                System.println("croppedSection: " + croppedSection.getWidth() + " " + croppedSection.getHeight());
                System.println("source: " + sourceBitmap.getWidth() + " " + sourceBitmap.getHeight());
                System.println("drawing from: " + xOffset * settings.tileSize + " " + yOffset * settings.tileSize);
                croppedSectionDc.drawBitmap2(
                    0,
                    0,
                    sourceBitmap,
                    {
                        // if this results in hitting the edge of the bitmap nothing is drawn
                        // so even though x=192 with width=64 should be drawn it is not
                        // it results in an empty image
                        // ie. it should be 0-64, 65-128, 128-192, 192-256 ie. half-open range [begin, end)
                        // but it look like they are using closed ranges?
                        // I cannot get this to work on a phsical device, see isues in Webrequest around Communications.makeImageRequest( and packing format
                        // the simulator also does the weird becaviour as listed above only first tile crop works
                        // I think the math and usage is correct, its possiby my venu2s just does not support it, even though its listed as supported in the docs
                        // it is API Level 4.2.1 so I would not be surprised if thats it
                        :bitmapX => xOffset * settings.tileSize,
                        :bitmapY => yOffset * settings.tileSize,
                        :bitmapWidth => settings.tileSize,
                        :bitmapHeight => settings.tileSize,
                        // :filterMode => Graphics.FILTER_MODE_BILINEAR,
                        // :dithering => Communications.IMAGE_DITHERING_NONE,
                    }
                );

                data = croppedSection;
            }

            var tile = new Tile();
            tile.setBitmap(data);
            _tileCache.addTile(_tileKey, tile);
            return;
        }

        if (!(data instanceof Dictionary))
        {
            System.println("wrong data type, not dict: " + data);
            return;
        }

        // System.print("data: " + data);
        var mapTile = data["data"];
        if (!(mapTile instanceof String))
        {
            System.println("wrong data type, not string");
            return;
        }
        var tile = new Tile();
        var mapTileStr = mapTile as String;
        // System.println("got tile string of length: " + mapTileStr.length());
        var bitmap = _tileCache.tileDataToBitmap(mapTileStr.toUtf8Array());
        if (bitmap == null)
        {
            System.println("failed to parse bitmap");
            return;
        }

        tile.setBitmap(bitmap);
        _tileCache.addTile(_tileKey, tile);
    }
}

class TileCache {
    var _internalCache as Dictionary<TileKey, Tile>;
    var _webRequestHandler as WebRequestHandler;
    var _palette as Array<Number>;
    var _settings as Settings;
    var _hits as Number = 0;
    var _misses as Number = 0;

    function initialize(
        webRequestHandler as WebRequestHandler,
        settings as Settings
    ) 
    {
        _settings = settings;
        _webRequestHandler = webRequestHandler;
        _internalCache = {};

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
            Graphics.createColor(255, 151, 210, 227), // ocean blue


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
            // Graphics.createColor(255, 179, 179, 179),       // Light Gray
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

        // loadPersistedTiles();
    }

    public function clearValues() as Void
    {
        _internalCache = {};
    }

    // loads a tile into the cache
    function seedTile(tileKey as TileKey) as Void {
        if (haveTile(tileKey))
        {
            return;
        }

        // System.println("starting load tile: " + x + " " + y + " " + z);

        if (!_settings.tileUrl.equals(COMPANION_APP_TILE_URL))
        {
            var x = tileKey.x / _settings.smallTilesPerBigTile;
            var y = tileKey.y / _settings.smallTilesPerBigTile;
            _webRequestHandler.add(
                new ImageRequest(
                    "tileimage" + new TileKey( x, y, tileKey.z),
                    stringReplaceFirst(
                        stringReplaceFirst(
                            stringReplaceFirst(_settings.tileUrl, "{x}", x.toString()), 
                            "{y}", 
                            y.toString()
                        ),
                        "{z}", 
                        tileKey.z.toString()
                    ),
                    {},
                    new WebTileRequestHandler(me, tileKey)
                )
            );
            return;
        }

        _webRequestHandler.add(
            new JsonRequest(
                "/loadtile" + tileKey,
                _settings.tileUrl + "/loadtile",
                {
                    "x" => tileKey.x,
                    "y" => tileKey.y,
                    "z" => tileKey.z,
                    "tileSize" => getApp()._breadcrumbContext.settings().tileSize,
                },
                new WebTileRequestHandler(me, tileKey)
            )
        );
    }

    // puts a tile into the cache
    function addTile(tileKey as TileKey, tile as Tile) as Void {
        if (_internalCache.size() == getApp()._breadcrumbContext.settings().tileCacheSize)
        {
            evictLeastRecentlyUsedTile();
        }

        _internalCache[tileKey] = tile;
    }
    
    // gets a tile that was stored by seedTile
    function getTile(tileKey as TileKey) as Tile or Null {
        var tile = _internalCache[tileKey] as Tile or Null;
        if (tile != null)
        {
            // System.println("cache hit: " + x  + " " + y + " " + z);
            _hits++;
            tile.markUsed();
            return tile;
        }

        // System.println("cache miss: " + x  + " " + y + " " + z);
        // System.println("have tiles: " + _internalCache.keys());
        _misses++;
        return null;
    }
    
    function haveTile(tileKey as TileKey) as Boolean {
        return _internalCache.hasKey(tileKey);
    }

    function tileCount() as Number {
        return _internalCache.size();
    }
    
    function hits() as Number {
        return _hits;
    }

    function misses() as Number {
        return _misses;
    }

    function evictLeastRecentlyUsedTile() as Void {
        // todo put older tiles into disk, and store what tiles are on disk (storage class)
        // it will be faster to load them from there than bluetooth
        var oldestTime = null;
        var oldestKey = null;

        var keys = _internalCache.keys();
        for (var i = 0; i < keys.size(); i++) {
            var key = keys[i];
            var tile = self._internalCache[key];
            if (oldestTime == null || oldestTime > tile.lastUsed) {
                oldestTime = tile.lastUsed;
                oldestKey = key;
            }
        }

        if (oldestKey != null) {
            _internalCache.remove(oldestKey);
            // System.println("Evicted tile " + oldestKey + " from internal cache");
        }
    }

    function tileDataToBitmap(arr as Array<Number>) as Graphics.BufferedBitmap or Null
    {
        // System.println("tile data " + arr);

        if (arr.size() < _settings.tileSize*_settings.tileSize)
        {
            System.println("tile length too short: " + arr.size());
            return null;
        }

        if (arr.size() != _settings.tileSize*_settings.tileSize)
        {
            // we could load tile partially, but that would require checking each itteration of the for loop, 
            // want to avoid any extra work for perf
            System.println("bad tile length: " + arr.size() + " best effort load");
        }

        // System.println("processing tile data, first colour is: " + arr[0]);

        // todo check if setting the pallet actually reduces memory
        var tileSize = _settings.tileSize;
        var localBitmap = newBitmap(tileSize, _palette);
        var localDc = localBitmap.getDc();
        var it = 0;
        for (var i=0; i<tileSize; ++i)
        {
            for (var j=0; j<tileSize; ++j)
            {
                var byteColour = arr[it] as Number;
                var colour = _palette[byteColour & 0x3F];
                it++;
                localDc.setColor(colour, colour);
                localDc.drawPoint(i, j);
            }
        }

        return localBitmap;
    }

    function clearStats() as Void
    {
        _hits = 0;
        _misses = 0;
    }
}


// stack i encountered
// Error: Stack Overflow Error
// Details: 'Failed invoking <symbol>'
// Time: 2025-03-30T05:04:34Z
// Part-Number: 006-B3704-00
// Firmware-Version: '19.05'
// Language-Code: eng
// ConnectIQ-Version: 5.1.0
// Filename: BreadcrumbDataField
// Appname: BreadcrumbDataField
// Stack: 
//   - pc: 0x3000017c
//   - pc: 0x10009850
//     File: 'BreadcrumbDataField\source\TileCache.mc'
//     Line: 112
//     Function: handle
//   - pc: 0x10007b61
//     File: 'BreadcrumbDataField\source\WebRequest.mc'
//     Line: 69
//     Function: handle
//   - pc: 0x300003b6
//   - pc: 0x10002f4f
//     File: 'BreadcrumbDataField\source\WebRequest.mc'
//     Line: 198
//     Function: start
//   - pc: 0x1000300f
//     File: 'BreadcrumbDataField\source\WebRequest.mc'
//     Line: 165
//     Function: startNextIfWeCan
//   - pc: 0x10002e3f
//     File: 'BreadcrumbDataField\source\WebRequest.mc'
//     Line: 150
//     Function: add
//   - pc: 0x1000526e
//     File: 'BreadcrumbDataField\source\TileCache.mc'
//     Line: 339
//     Function: seedTile
//   - pc: 0x10009635
//     File: 'BreadcrumbDataField\source\MapRenderer.mc'
//     Line: 106
//     Function: renderMap
//   - pc: 0x100082c7
//     File: 'BreadcrumbDataField\source\BreadcrumbDataFieldView.mc'
//     Line: 154
//     Function: renderMain
//   - pc: 0x1000877f
//     File: 'BreadcrumbDataField\source\BreadcrumbDataFieldView.mc'
//     Line: 87
//     Function: onUpdate