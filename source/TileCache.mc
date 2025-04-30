import Toybox.Lang;
import Toybox.Graphics;
import Toybox.WatchUi;
import Toybox.PersistedContent;
import Toybox.StringUtil;
using Toybox.Graphics;
using Toybox.Lang;
using Toybox.Math;
using Toybox.System;
using Toybox.Communications;
using Toybox.Application.Storage;
using Toybox.Time;

enum /*TileDataType*/ {
    TILE_DATA_TYPE_64_COLOUR = 0,
    TILE_DATA_TYPE_BASE64_FULL_COLOUR = 1,
    TILE_DATA_TYPE_BLACK_AND_WHITE = 2,
}

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
        // was getting charArrayToString called which takes 193us per call
        return x.toString() + "-" + y + "-" + z;
    }

    function hashCode() as Number {
        return x + y + z;
    }

    function equals(other as Object?) as Boolean {
        if (!(other instanceof TileKey)) {
            return false;
        }

        return x == other.x && y == other.y && z == other.z;
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
    static function deserializeFromDictionary(data as Dictionary) as TileKey? {
        if (!data.hasKey("x") || !data.hasKey("y") || !data.hasKey("z")) {
            return null;
        }

        return new TileKey(data["x"] as Number, data["y"] as Number, data["z"] as Number);
    }
}

class Tile {
    var lastUsed as Number;
    var bitmap as Graphics.BufferedBitmap or WatchUi.BitmapResource or Null;
    var storageIndex as Number?;

    function initialize() {
        self.lastUsed = System.getTimer();
        self.bitmap = null;
        self.storageIndex = null;
    }

    function setBitmap(bitmap as Graphics.BufferedBitmap or WatchUi.BitmapResource) as Void {
        self.bitmap = bitmap;
    }

    function markUsed() as Void {
        lastUsed = System.getTimer();
    }

    function setStorageIndex(storageIndex as Number) as Void {
        self.storageIndex = storageIndex;
    }
}

class JsonWebTileRequestHandler extends JsonWebHandler {
    var _tileCache as TileCache;
    var _tileKey as TileKey;
    var _tileCacheVersion as Number;

    function initialize(tileCache as TileCache, tileKey as TileKey, tileCacheVersion as Number) {
        JsonWebHandler.initialize();
        _tileCache = tileCache;
        _tileKey = tileKey;
        _tileCacheVersion = tileCacheVersion;
    }

    function handle(
        responseCode as Number,
        data as Dictionary or String or Iterator or Null
    ) as Void {
        if (responseCode != 200) {
            // see error codes such as Communications.NETWORK_REQUEST_TIMED_OUT
            System.println("failed with: " + responseCode);
            return;
        }

        if (!(data instanceof Dictionary)) {
            System.println("wrong data type, not dict: " + data);
            return;
        }

        // System.print("data: " + data);
        var mapTile = data["data"];
        if (!(mapTile instanceof String)) {
            System.println("wrong data type, not string");
            return;
        }

        var type = data.get("type");
        if (type == null || !(type instanceof Number)) {
            // back compat
            System.println("bad type for type: falling back: " + type);
            handle64ColourDataString(mapTile);
            return;
        }

        if (type == TILE_DATA_TYPE_64_COLOUR) {
            handle64ColourDataString(mapTile);
            return;
        } else if (type == TILE_DATA_TYPE_BASE64_FULL_COLOUR) {
            handleBase64FullColourDataString(mapTile);
            return;
        } else if (type == TILE_DATA_TYPE_BLACK_AND_WHITE) {
            handleBlackAndWhiteDataString(mapTile);
            return;
        }
    }

    function handle64ColourDataString(mapTile as String) as Void {
        var tile = new Tile();
        // System.println("got tile string of length: " + mapTile.length());
        var bitmap = _tileCache.tileDataToBitmap64ColourString(mapTile.toCharArray());
        if (bitmap == null) {
            System.println("failed to parse bitmap");
            return;
        }

        tile.setBitmap(bitmap);
        _tileCache.addTile(_tileKey, _tileCacheVersion, tile);
    }

    function handleBase64FullColourDataString(mapTile as String) as Void {
        var tile = new Tile();
        var mapTileBytes = StringUtil.convertEncodedString(mapTile, {
            :fromRepresentation => StringUtil.REPRESENTATION_STRING_BASE64,
            :toRepresentation => StringUtil.REPRESENTATION_BYTE_ARRAY,
        });
        // System.println("got tile string of length: " + mapTile.length());
        var bitmap = _tileCache.tileDataToBitmapFullColour(mapTileBytes);
        if (bitmap == null) {
            System.println("failed to parse bitmap");
            return;
        }

        tile.setBitmap(bitmap);
        _tileCache.addTile(_tileKey, _tileCacheVersion, tile);
    }

    function handleBlackAndWhiteDataString(mapTile as String) as Void {
        var tile = new Tile();
        // System.println("got tile string of length: " + mapTile.length());
        var bitmap = _tileCache.tileDataToBitmapBlackAndWhite(mapTile.toCharArray());
        if (bitmap == null) {
            System.println("failed to parse bitmap");
            return;
        }

        tile.setBitmap(bitmap);
        _tileCache.addTile(_tileKey, _tileCacheVersion, tile);
    }
}

class ImageWebTileRequestHandler extends ImageWebHandler {
    var _tileCache as TileCache;
    var _tileKey as TileKey;
    var _tileCacheVersion as Number;

    function initialize(tileCache as TileCache, tileKey as TileKey, tileCacheVersion as Number) {
        ImageWebHandler.initialize();
        _tileCache = tileCache;
        _tileKey = tileKey;
        _tileCacheVersion = tileCacheVersion;
    }

    function handle(
        responseCode as Number,
        data as WatchUi.BitmapResource or Graphics.BitmapReference or Null
    ) as Void {
        if (responseCode != 200) {
            // see error codes such as Communications.NETWORK_REQUEST_TIMED_OUT
            System.println("failed with: " + responseCode);
            return;
        }

        if (
            data == null ||
            (!(data instanceof WatchUi.BitmapResource) &&
                !(data instanceof Graphics.BitmapReference))
        ) {
            System.println("wrong data type not image");
            return;
        }

        if (data instanceof Graphics.BitmapReference) {
            // need to keep it in memory all the time, if we use the reference only it can be deallocated by the graphics memory pool
            // https://developer.garmin.com/connect-iq/core-topics/graphics/
            data = data.get();
        }

        var settings = getApp()._breadcrumbContext.settings();
        var cachedValues = getApp()._breadcrumbContext.cachedValues();
        // we have to downsample the tile, not recomendedd, as this mean we will have to request the same tile multiple times (cant save big tiles around anywhere)
        // also means we have to use scratch space to draw the tile and downsample it

        if (data.getWidth() != settings.tileSize || data.getHeight() != settings.tileSize) {
            // dangerous large bitmap could cause oom, buts its the only way to upscale the image and then slice it
            // we cannot downscale because we would be slicing a pixel in half
            // I guess we could just figure out which pixels to double up on?
            // anyone using an external tile server should be setting thier tileSize to 256, but perhaps some devices will run out of memory?
            // if users are using a smaller size it should be a multiple of 256.
            // if its not, we will stretch the image then downsize, if its already a multiple we will use the image as is (optimal)
            var maxDim = maxN(data.getWidth(), data.getHeight()); // should be equal (every time server i know of is 256*256), but who knows
            var pixelsPerTile = maxDim / cachedValues.smallTilesPerScaledTile.toFloat();
            var sourceBitmap = data;
            if (
                Math.ceil(pixelsPerTile) != settings.tileSize ||
                Math.floor(pixelsPerTile) != settings.tileSize
            ) {
                // we have an anoying situation - stretch/reduce the image
                var scaleUpSize = cachedValues.smallTilesPerScaledTile * settings.tileSize;
                var scaleFactor = scaleUpSize / maxDim.toFloat();
                var upscaledBitmap = newBitmap(scaleUpSize, scaleUpSize);
                var upscaledBitmapDc = upscaledBitmap.getDc();

                var scaleMatrix = new AffineTransform();
                scaleMatrix.scale(scaleFactor, scaleFactor); // scale

                try {
                    upscaledBitmapDc.drawBitmap2(0, 0, sourceBitmap, {
                        :transform => scaleMatrix,
                        // Use bilinear filtering for smoother results when rotating/scaling (less noticible tearing)
                        :filterMode => Graphics.FILTER_MODE_BILINEAR,
                    });
                } catch (e) {
                    logE("failed drawBitmap2: " + e.getErrorMessage());
                    ++$.globalExceptionCounter;
                }
                // System.println("scaled up to: " + upscaledBitmap.getWidth() + " " + upscaledBitmap.getHeight());
                // System.println("from: " + sourceBitmap.getWidth() + " " + sourceBitmap.getHeight());
                sourceBitmap = upscaledBitmap; // resume what we were doing as if it was always the larger bitmap
            }

            var croppedSection = newBitmap(settings.tileSize, settings.tileSize);
            var croppedSectionDc = croppedSection.getDc();
            var xOffset = _tileKey.x % cachedValues.smallTilesPerScaledTile;
            var yOffset = _tileKey.y % cachedValues.smallTilesPerScaledTile;
            // System.println("tile: " + _tileKey);
            // System.println("croppedSection: " + croppedSection.getWidth() + " " + croppedSection.getHeight());
            // System.println("source: " + sourceBitmap.getWidth() + " " + sourceBitmap.getHeight());
            // System.println("drawing from: " + xOffset * settings.tileSize + " " + yOffset * settings.tileSize);
            croppedSectionDc.drawBitmap(
                -xOffset * settings.tileSize,
                -yOffset * settings.tileSize,
                sourceBitmap
            );

            data = croppedSection;
        }

        var tile = new Tile();
        tile.setBitmap(data);
        _tileCache.addTile(_tileKey, _tileCacheVersion, tile);
    }
}

class TileCache {
    var _internalCache as Dictionary<TileKey, Tile>;
    var _webRequestHandler as WebRequestHandler;
    var _palette as Array<Number>;
    var _settings as Settings;
    var _cachedValues as CachedValues;
    var _hits as Number = 0;
    var _misses as Number = 0;
    // Ignore any tile adds that do not have this version (allows outstanding web requests to be ignored once they are handled)
    var _tileCacheVersion as Number = 0;

    function initialize(
        webRequestHandler as WebRequestHandler,
        settings as Settings,
        cachedValues as CachedValues
    ) {
        _settings = settings;
        _cachedValues = cachedValues;
        _webRequestHandler = webRequestHandler;
        _internalCache = {};

        // note: these need to match whats in the app
        // would like tho use the bitmaps colour pallet, but we cannot :( because it erros with
        // Exception: Source must not use a color palette
        _palette = [
            // Greens (Emphasis) - 22 colors
            Graphics.createColor(255, 61, 179, 61), // Vibrant Green
            Graphics.createColor(255, 102, 179, 102), // Medium Green
            Graphics.createColor(255, 153, 204, 153), // Light Green
            Graphics.createColor(255, 0, 102, 0), // Dark Green
            Graphics.createColor(255, 128, 179, 77), // Slightly Yellowish Green
            Graphics.createColor(255, 77, 179, 128), // Slightly Bluish Green
            Graphics.createColor(255, 179, 179, 179), // Pale Green
            Graphics.createColor(255, 92, 128, 77), // Olive Green
            Graphics.createColor(255, 148, 209, 23),
            Graphics.createColor(255, 107, 142, 35), // OliveDrab
            Graphics.createColor(255, 179, 230, 0), // Lime Green
            Graphics.createColor(255, 102, 179, 0), // Spring Green
            Graphics.createColor(255, 77, 204, 77), // Bright Green
            Graphics.createColor(255, 128, 153, 128), // Grayish Green
            Graphics.createColor(255, 153, 204, 153), // Soft Green
            Graphics.createColor(255, 0, 128, 0), // Forest Green
            Graphics.createColor(255, 34, 139, 34), // ForestGreen
            Graphics.createColor(255, 50, 205, 50), // LimeGreen
            Graphics.createColor(255, 144, 238, 144), // LightGreen
            Graphics.createColor(255, 0, 100, 0), // DarkGreen
            Graphics.createColor(255, 60, 179, 113), // Medium Sea Green
            Graphics.createColor(255, 46, 139, 87), // SeaGreen

            // Reds - 8 colors
            Graphics.createColor(255, 230, 0, 0), // Bright Red
            Graphics.createColor(255, 204, 102, 102), // Light Red (Pink)
            Graphics.createColor(255, 153, 0, 0), // Dark Red
            Graphics.createColor(255, 230, 92, 77), // Coral Red
            Graphics.createColor(255, 179, 0, 38), // Crimson
            Graphics.createColor(255, 204, 102, 102), // Rose
            Graphics.createColor(255, 255, 0, 0), // Pure Red
            Graphics.createColor(255, 255, 69, 0), // RedOrange

            // Blues - 8 colors
            Graphics.createColor(255, 0, 0, 230), // Bright Blue
            Graphics.createColor(255, 102, 102, 204), // Light Blue
            Graphics.createColor(255, 0, 0, 153), // Dark Blue
            Graphics.createColor(255, 102, 153, 230), // Sky Blue
            Graphics.createColor(255, 38, 0, 179), // Indigo
            Graphics.createColor(255, 77, 128, 179), // Steel Blue
            Graphics.createColor(255, 0, 0, 255), // Pure Blue
            Graphics.createColor(255, 0, 191, 255), // DeepSkyBlue
            Graphics.createColor(255, 151, 210, 227), // ocean blue

            // Yellows - 6 colors
            Graphics.createColor(255, 230, 230, 0), // Bright Yellow
            Graphics.createColor(255, 204, 204, 102), // Light Yellow
            Graphics.createColor(255, 153, 153, 0), // Dark Yellow (Gold)
            Graphics.createColor(255, 179, 153, 77), // Mustard Yellow
            Graphics.createColor(255, 255, 255, 0), // Pure Yellow
            Graphics.createColor(255, 255, 215, 0), // Gold

            // Oranges - 6 colors
            Graphics.createColor(255, 230, 115, 0), // Bright Orange
            Graphics.createColor(255, 204, 153, 102), // Light Orange
            Graphics.createColor(255, 153, 77, 0), // Dark Orange
            Graphics.createColor(255, 179, 51, 0), // Burnt Orange
            Graphics.createColor(255, 255, 165, 0), // Orange
            Graphics.createColor(255, 255, 140, 0), // DarkOrange

            // Purples - 6 colors
            Graphics.createColor(255, 230, 0, 230), // Bright Purple
            Graphics.createColor(255, 204, 102, 204), // Light Purple
            Graphics.createColor(255, 153, 0, 153), // Dark Purple
            Graphics.createColor(255, 230, 153, 230), // Lavender
            Graphics.createColor(255, 128, 0, 128), // Purple
            Graphics.createColor(255, 75, 0, 130), // Indigo

            // Neutral/Grayscale - 4 colors
            Graphics.createColor(255, 242, 242, 242), // White
            // Graphics.createColor(255, 179, 179, 179),       // Light Gray
            Graphics.createColor(255, 77, 77, 77), // Dark Gray
            Graphics.createColor(255, 0, 0, 0), // Black

            // manually picked to match map tiles
            Graphics.createColor(255, 246, 230, 98), // road colours (yellow)
            Graphics.createColor(255, 194, 185, 108), // slightly darker yellow road
            Graphics.createColor(255, 214, 215, 216), // some mountains (light grey)
            Graphics.createColor(255, 213, 237, 168), // some greenery that was not a nice colour
        ];

        if (_palette.size() != 64) {
            System.println("colour pallet has only: " + _palette.size() + "elements");
        }

        // loadPersistedTiles();
    }

    public function clearValues() as Void {
        _internalCache = {};
        _tileCacheVersion++;
    }

    // loads a tile into the cache
    function seedTile(tileKey as TileKey) as Void {
        if (haveTile(tileKey)) {
            return;
        }
        startSeedTile(tileKey);
    }

    private function startSeedTile(tileKey as TileKey) as Void {
        // System.println("starting load tile: " + x + " " + y + " " + z);

        if (!_settings.tileUrl.equals(COMPANION_APP_TILE_URL)) {
            // logD("small tile: " + tileKey + " scaledTileSize: " + _settings.scaledTileSize + " tileSize: " + _settings.tileSize);
            var x = tileKey.x / _cachedValues.smallTilesPerScaledTile;
            var y = tileKey.y / _cachedValues.smallTilesPerScaledTile;
            // logD("large tile: " + x + ", " + y + ", " + tileKey.z);
            _webRequestHandler.add(
                new ImageRequest(
                    "tileimage" + tileKey + "-" + _tileCacheVersion, // the hash is for the small tile request, not the big one (they will send the same physical request out, but again use 256 tilSize if your using external sources)
                    stringReplaceFirst(
                        stringReplaceFirst(
                            stringReplaceFirst(
                                stringReplaceFirst(_settings.tileUrl, "{x}", x.toString()),
                                "{y}",
                                y.toString()
                            ),
                            "{z}",
                            tileKey.z.toString()
                        ),
                        "{authToken}",
                        _settings.authToken
                    ),
                    {},
                    new ImageWebTileRequestHandler(me, tileKey, _tileCacheVersion)
                )
            );
            return;
        }

        // logD("small tile (companion): " + tileKey + " scaledTileSize: " + _settings.scaledTileSize + " tileSize: " + _settings.tileSize);
        _webRequestHandler.add(
            new JsonRequest(
                "/loadtile" + tileKey + "-" + _tileCacheVersion,
                _settings.tileUrl + "/loadtile",
                {
                    "x" => tileKey.x,
                    "y" => tileKey.y,
                    "z" => tileKey.z,
                    "scaledTileSize" => _settings.scaledTileSize,
                    "tileSize" => _settings.tileSize,
                },
                new JsonWebTileRequestHandler(me, tileKey, _tileCacheVersion)
            )
        );
    }

    // puts a tile into the cache
    function addTile(tileKey as TileKey, tileCacheVersion as Number, tile as Tile) as Void {
        if (tileCacheVersion != _tileCacheVersion) {
            return;
        }

        if (_internalCache.size() == getApp()._breadcrumbContext.settings().tileCacheSize) {
            evictLeastRecentlyUsedTile();
        }

        _internalCache[tileKey] = tile;
    }

    // gets a tile that was stored by seedTile
    function getTile(tileKey as TileKey) as Tile? {
        var tile = _internalCache[tileKey] as Tile?;
        if (tile != null) {
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

    function getOrSeedTile(tileKey as TileKey) as Tile? {
        var tile = getTile(tileKey);
        if (tile != null) {
            return tile;
        }

        startSeedTile(tileKey);
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

    function tileDataToBitmap64ColourString(charArr as Array<Char>) as Graphics.BufferedBitmap? {
        // System.println("tile data " + arr);
        var tileSize = _settings.tileSize;
        var requiredSize = tileSize * tileSize;
        // got a heap of
        // Error: Unexpected Type Error
        // Details: 'Failed invoking <symbol>'
        // even though the only calling coe checks it's a string, then calls .toUtf8Array()
        // Stack:
        // - pc: 0x1000867c
        //     File: 'BreadcrumbDataField\source\TileCache.mc'
        //     Line: 479
        //     Function: tileDataToBitmap64ColourString
        // - pc: 0x1000158c
        //     File: 'BreadcrumbDataField\source\TileCache.mc'
        //     Line: 121
        //     Function: handle
        // - pc: 0x10004e8d
        //     File: 'BreadcrumbDataField\source\WebRequest.mc'
        //     Line: 86
        //     Function: handle
        if (!(charArr instanceof Array)) {
            // managed to get this in the sim, it was a null (when using .toUtf8Array())
            // docs do not say that it can ever be null though
            // perhaps the colour string im sending is no good?
            // seems to be random though. And it seems to get through on the next pass, might be memory related?
            // it even occurs on a simple string (no special characters)
            // resorting to using the string directly
            // the toCharArray method im using now seems to throw OOM errors instead of returning null
            // not sure which is better, we are at our memory limits regardless, so
            // optimisation level seems to effect it (think it must garbage collect faster or inline things where it can)
            // slow optimisations are always good for relase, but make debugging harder when variables are optimised away (which is why i was running no optimisations).
            System.println("got a bad type somehow? 64colour: " + charArr);
            return null;
        }

        if (charArr.size() < requiredSize) {
            System.println("tile length too short 64colour: " + charArr.size());
            return null;
        }

        if (charArr.size() != requiredSize) {
            // we could load tile partially, but that would require checking each itteration of the for loop,
            // want to avoid any extra work for perf
            System.println("bad tile length 64colour: " + charArr.size() + " best effort load");
        }

        // System.println("processing tile data, first colour is: " + arr[0]);

        // todo check if setting the pallet actually reduces memory
        var localBitmap = newBitmap(tileSize, tileSize);
        var localDc = localBitmap.getDc();
        var it = 0;
        for (var i = 0; i < tileSize; ++i) {
            for (var j = 0; j < tileSize; ++j) {
                var colour = _palette[charArr[it].toNumber() & 0x3f]; // charArr[it] as Char the toNumber is The UTF-32 representation of the Char interpreted as a Number
                it++;
                localDc.setColor(colour, colour);
                localDc.drawPoint(i, j);
            }
        }

        return localBitmap;
    }

    function tileDataToBitmapBlackAndWhite(charArr as Array<Char>) as Graphics.BufferedBitmap? {
        // System.println("tile data " + arr);
        var tileSize = _settings.tileSize;
        var requiredSize = Math.ceil((tileSize * tileSize) / 6f).toNumber(); // 6 bits of colour per byte
        if (!(charArr instanceof Array)) {
            // managed to get this in the sim, it was a null (when using .toUtf8Array())
            // docs do not say that it can ever be null though
            // perhaps the colour string im sending is no good?
            // seems to be random though. And it seems to get through on the next pass, might be memory related?
            // it even occurs on a simple string (no special characters)
            // resorting to using the string directly
            // the toCharArray method im using now seems to throw OOM errors instead of returning null
            // not sure which is better, we are at our memory limits regardless, so
            // optimisation level seems to effect it (think it must garbage collect faster or inline things where it can)
            // slow optimisations are always good for relase, but make debugging harder when variables are optimised away (which is why i was running no optimisations).
            System.println("got a bad type somehow? b&w: " + charArr);
            return null;
        }

        if (charArr.size() < requiredSize) {
            System.println("tile length too short b&w: " + charArr.size());
            return null;
        }

        if (charArr.size() != requiredSize) {
            // we could load tile partially, but that would require checking each itteration of the for loop,
            // want to avoid any extra work for perf
            System.println("bad tile length b&w: " + charArr.size() + " best effort load");
        }

        // System.println("processing tile data, first colour is: " + arr[0]);

        // todo check if setting the pallet actually reduces memory
        var localBitmap = newBitmap(tileSize, tileSize);
        var localDc = localBitmap.getDc();
        var bit = 0;
        var byte = 0;
        for (var i = 0; i < tileSize; ++i) {
            for (var j = 0; j < tileSize; ++j) {
                var colour = (charArr[byte].toNumber() >> bit) & 0x01;
                bit++;
                if (bit >= 6) {
                    bit = 0;
                    byte++;
                }

                if (colour == 1) {
                    localDc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_WHITE);
                } else {
                    localDc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
                }

                localDc.drawPoint(i, j);
            }
        }

        return localBitmap;
    }

    function tileDataToBitmapFullColour(mapTileBytes as ByteArray) as Graphics.BufferedBitmap? {
        // System.println("tile data " + arr);
        var tileSize = _settings.tileSize;
        var requiredSize = tileSize * tileSize * 3;

        if (!(mapTileBytes instanceof ByteArray)) {
            // managed to get this in the sim, it was a null (when using .toUtf8Array())
            // docs do not say that it can ever be null though
            // perhaps the colour string im sending is no good?
            // seems to be random though. And it seems to get through on the next pass, might be memory related?
            // it even occurs on a simple string (no special characters)
            // resorting to using the string directly
            // the toCharArray method im using now seems to throw OOM errors instead of returning null
            // not sure which is better, we are at our memory limits regardless, so
            // optimisation level seems to effect it (think it must garbage collect faster or inline things where it can)
            // slow optimisations are always good for relase, but make debugging harder when variables are optimised away (which is why i was running no optimisations).
            System.println("got a bad full colour type somehow?: " + mapTileBytes);
            return null;
        }

        if (mapTileBytes.size() < requiredSize) {
            System.println("tile length too short full colour: " + mapTileBytes.size());
            return null;
        }

        if (mapTileBytes.size() != requiredSize) {
            // we could load tile partially, but that would require checking each itteration of the for loop,
            // want to avoid any extra work for perf
            System.println("bad tile length full colour: " + mapTileBytes.size() + " best effort load");
        }

        mapTileBytes.add(0x00); // add a byte to the end so the last 24bit colour we parse still has 32 bits of data

        // System.println("processing tile data, first colour is: " + arr[0]);

        // todo check if setting the pallet actually reduces memory
        var localBitmap = newBitmap(tileSize, tileSize);
        var localDc = localBitmap.getDc();
        var offset = 0;
        for (var i = 0; i < tileSize; ++i) {
            for (var j = 0; j < tileSize; ++j) {
                // probbaly a faster way to do this
                var colour = mapTileBytes.decodeNumber(Lang.NUMBER_FORMAT_UINT32, {
                    :offset => offset,
                    :endianness => Lang.ENDIAN_BIG,
                });
                colour = (colour >> 8) & 0x00FFFFFF; // 24 bit colour only
                offset += 3;
                // tried setFill and setStroke, neither seemed to work, so we can only support 24bit colour
                localDc.setColor(colour, colour);
                localDc.drawPoint(i, j);
            }
        }

        return localBitmap;
    }

    function clearStats() as Void {
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
