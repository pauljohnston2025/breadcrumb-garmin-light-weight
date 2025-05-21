import Toybox.Lang;
import Toybox.Graphics;
import Toybox.WatchUi;
import Toybox.PersistedContent;
import Toybox.StringUtil;
import Toybox.Application;
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

    function optimisedHashKey() as String {
        var string = toString();

        // we can base64 encode and get a shorter unique string
        // toString() contains '-' characters, and base64 does not have hyphens
        if (string.length() <= 12) {
            return string;
        }

        var byteArr = new [9]b;
        byteArr.encodeNumber(x, Lang.NUMBER_FORMAT_SINT32, {
            :offset => 0,
            :endianness => Lang.ENDIAN_BIG,
        });
        byteArr.encodeNumber(y, Lang.NUMBER_FORMAT_SINT32, {
            :offset => 4,
            :endianness => Lang.ENDIAN_BIG,
        });
        byteArr.encodeNumber(z, Lang.NUMBER_FORMAT_UINT8, {
            :offset => 8,
            :endianness => Lang.ENDIAN_BIG,
        });
        return (
            StringUtil.convertEncodedString(byteArr, {
                :fromRepresentation => StringUtil.REPRESENTATION_BYTE_ARRAY,
                :toRepresentation => StringUtil.REPRESENTATION_STRING_BASE64,
                :encoding => StringUtil.CHAR_ENCODING_UTF8,
            }) as String
        );
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

const NO_EXPIRY = -1;
const WRONG_DATA_TILE = -6000;
function expired(expiresAt as Number, now as Number) as Boolean {
    return expiresAt != NO_EXPIRY && expiresAt < now;
}

class Tile {
    var lastUsed as Number;
    var expiresAt as Number = NO_EXPIRY;
    var bitmap as Graphics.BufferedBitmap or WatchUi.BitmapResource;

    function initialize(_bitmap as Graphics.BufferedBitmap or WatchUi.BitmapResource) {
        self.lastUsed = Time.now().value();
        self.bitmap = _bitmap;
    }

    function setExpiresAt(expiresAt as Number) as Void {
        self.expiresAt = expiresAt;
    }

    function expiredAlready(now as Number) as Boolean {
        return expired(self.expiresAt, now);
    }

    function markUsed() as Void {
        lastUsed = Time.now().value();
    }
}

(:noCompanionTiles)
class JsonWebTileRequestHandler extends JsonWebHandler {
    function initialize(
        tileCache as TileCache,
        tileKey as TileKey,
        tileCacheVersion as Number,
        onlySeedStorage as Boolean
    ) {
        JsonWebHandler.initialize();
    }

    function handle(
        responseCode as Number,
        data as Dictionary or String or Iterator or Null
    ) as Void {}
}

(:companionTiles)
class JsonWebTileRequestHandler extends JsonWebHandler {
    var _tileCache as TileCache;
    var _tileKey as TileKey;
    var _tileCacheVersion as Number;
    var _onlySeedStorage as Boolean;

    function initialize(
        tileCache as TileCache,
        tileKey as TileKey,
        tileCacheVersion as Number,
        onlySeedStorage as Boolean
    ) {
        JsonWebHandler.initialize();
        _tileCache = tileCache;
        _tileKey = tileKey;
        _tileCacheVersion = tileCacheVersion;
        _onlySeedStorage = onlySeedStorage;
    }

    function handleErroredTile(responseCode as Number) as Void {
        _tileCache.addErroredTile(
            _tileKey,
            _tileCacheVersion,
            responseCode.toString(),
            isHttpResponseCode(responseCode)
        );
    }

    function handle(
        responseCode as Number,
        data as Dictionary or String or Iterator or Null
    ) as Void {
        // do not store tiles in storage if the tile cache version does not match
        if (_tileCacheVersion != _tileCache._tileCacheVersion) {
            return;
        }

        var settings = getApp()._breadcrumbContext.settings;
        var cachedValues = getApp()._breadcrumbContext.cachedValues;

        if (responseCode != 200) {
            // see error codes such as Communications.NETWORK_REQUEST_TIMED_OUT
            System.println("failed with: " + responseCode);
            if (settings.cacheTilesInStorage || cachedValues.seeding()) {
                _tileCache._storageTileCache.addErroredTile(_tileKey, responseCode);
            }
            if (_onlySeedStorage) {
                return;
            }
            handleErroredTile(responseCode);
            return;
        }

        handleSuccessfulTile(data, true);
    }

    function handleSuccessfulTile(
        data as Dictionary or String or Iterator or Null,
        addToCache as Boolean
    ) as Void {
        var settings = getApp()._breadcrumbContext.settings;
        var cachedValues = getApp()._breadcrumbContext.cachedValues;

        if (!(data instanceof Dictionary)) {
            System.println("wrong data type, not dict: " + data);
            if (addToCache) {
                if (settings.cacheTilesInStorage || cachedValues.seeding()) {
                    _tileCache._storageTileCache.addWrongDataTile(_tileKey);
                }
            }
            if (_onlySeedStorage) {
                return;
            }
            _tileCache.addErroredTile(_tileKey, _tileCacheVersion, "WD", false);
            return;
        }

        if (addToCache) {
            if (settings.cacheTilesInStorage || cachedValues.seeding()) {
                _tileCache._storageTileCache.addJsonData(
                    _tileKey,
                    data as Dictionary<PropertyKeyType, PropertyValueType>
                );
            }
        }

        if (_onlySeedStorage) {
            return;
        }

        // System.print("data: " + data);
        var mapTile = data["data"];
        if (!(mapTile instanceof String)) {
            System.println("wrong data type, not string");
            _tileCache.addErroredTile(_tileKey, _tileCacheVersion, "WD", false);
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

        _tileCache.addErroredTile(_tileKey, _tileCacheVersion, "UT", false);
    }

    function handle64ColourDataString(mapTile as String) as Void {
        // System.println("got tile string of length: " + mapTile.length());
        var bitmap = _tileCache.tileDataToBitmap64ColourString(mapTile.toCharArray());
        if (bitmap == null) {
            System.println("failed to parse bitmap");
            _tileCache.addErroredTile(_tileKey, _tileCacheVersion, "FP", false);
            return;
        }

        var tile = new Tile(bitmap);
        _tileCache.addTile(_tileKey, _tileCacheVersion, tile);
    }

    function handleBase64FullColourDataString(mapTile as String) as Void {
        var mapTileBytes =
            StringUtil.convertEncodedString(mapTile, {
                :fromRepresentation => StringUtil.REPRESENTATION_STRING_BASE64,
                :toRepresentation => StringUtil.REPRESENTATION_BYTE_ARRAY,
            }) as ByteArray;
        // System.println("got tile string of length: " + mapTile.length());
        var bitmap = _tileCache.tileDataToBitmapFullColour(mapTileBytes);
        if (bitmap == null) {
            System.println("failed to parse bitmap");
            _tileCache.addErroredTile(_tileKey, _tileCacheVersion, "FP", false);
            return;
        }

        var tile = new Tile(bitmap);
        _tileCache.addTile(_tileKey, _tileCacheVersion, tile);
    }

    function handleBlackAndWhiteDataString(mapTile as String) as Void {
        // System.println("got tile string of length: " + mapTile.length());
        var bitmap = _tileCache.tileDataToBitmapBlackAndWhite(mapTile.toCharArray());
        if (bitmap == null) {
            System.println("failed to parse bitmap");
            _tileCache.addErroredTile(_tileKey, _tileCacheVersion, "FP", false);
            return;
        }

        var tile = new Tile(bitmap);
        _tileCache.addTile(_tileKey, _tileCacheVersion, tile);
    }
}

class ImageWebTileRequestHandler extends ImageWebHandler {
    var _tileCache as TileCache;
    var _tileKey as TileKey;
    var _fullSizeTile as TileKey;
    var _tileCacheVersion as Number;
    var _onlySeedStorage as Boolean;

    function initialize(
        tileCache as TileCache,
        tileKey as TileKey,
        fullSizeTile as TileKey,
        tileCacheVersion as Number,
        onlySeedStorage as Boolean
    ) {
        ImageWebHandler.initialize();
        _tileCache = tileCache;
        _tileKey = tileKey;
        _fullSizeTile = fullSizeTile;
        _tileCacheVersion = tileCacheVersion;
        _onlySeedStorage = onlySeedStorage;
    }

    function handleErroredTile(responseCode as Number) as Void {
        _tileCache.addErroredTile(
            _tileKey,
            _tileCacheVersion,
            responseCode.toString(),
            isHttpResponseCode(responseCode)
        );
    }

    function handle(
        responseCode as Number,
        data as WatchUi.BitmapResource or Graphics.BitmapReference or Null
    ) as Void {
        // do not store tiles in storage if the tile cache version does not match
        if (_tileCacheVersion != _tileCache._tileCacheVersion) {
            return;
        }

        var settings = getApp()._breadcrumbContext.settings;
        var cachedValues = getApp()._breadcrumbContext.cachedValues;

        if (responseCode != 200) {
            // see error codes such as Communications.NETWORK_REQUEST_TIMED_OUT
            System.println("failed with: " + responseCode);
            if (settings.cacheTilesInStorage || cachedValues.seeding()) {
                _tileCache._storageTileCache.addErroredTile(_fullSizeTile, responseCode);
            }
            if (_onlySeedStorage) {
                return;
            }
            handleErroredTile(responseCode);
            return;
        }

        handleSuccessfulTile(data, true);
    }

    function handleSuccessfulTile(
        data as WatchUi.BitmapResource or Graphics.BitmapReference or Null,
        addToCache as Boolean
    ) as Void {
        var settings = getApp()._breadcrumbContext.settings;
        var cachedValues = getApp()._breadcrumbContext.cachedValues;

        if (
            data == null ||
            (!(data instanceof WatchUi.BitmapResource) &&
                !(data instanceof Graphics.BitmapReference))
        ) {
            System.println("wrong data type not image");
            if (addToCache) {
                if (settings.cacheTilesInStorage || cachedValues.seeding()) {
                    _tileCache._storageTileCache.addWrongDataTile(_tileKey);
                }
            }
            if (_onlySeedStorage) {
                return;
            }
            _tileCache.addErroredTile(_tileKey, _tileCacheVersion, "WD", false);
            return;
        }

        if (data instanceof Graphics.BitmapReference) {
            // need to keep it in memory all the time, if we use the reference only it can be deallocated by the graphics memory pool
            // https://developer.garmin.com/connect-iq/core-topics/graphics/
            data = data.get();
        }

        if (data == null || !(data instanceof WatchUi.BitmapResource)) {
            System.println("data bitmap was null or not a bitmap");
            if (addToCache) {
                if (settings.cacheTilesInStorage || cachedValues.seeding()) {
                    _tileCache._storageTileCache.addWrongDataTile(_tileKey);
                }
            }
            if (_onlySeedStorage) {
                return;
            }
            _tileCache.addErroredTile(_tileKey, _tileCacheVersion, "WD", false);
            return;
        }

        if (addToCache) {
            if (settings.cacheTilesInStorage || cachedValues.seeding()) {
                _tileCache._storageTileCache.addBitmap(_fullSizeTile, data);
            }
        }

        if (_onlySeedStorage) {
            return;
        }

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
                    logE("failed drawBitmap2 (handleSuccessfulTile): " + e.getErrorMessage());
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

        var tile = new Tile(data);
        _tileCache.addTile(_tileKey, _tileCacheVersion, tile);
    }
}

const TILES_KEY = "tileKeys";
const TILES_VERION_KEY = "tilesVersion";
const TILES_STORAGE_VERSION = 3; // udate this every time the tile format on disk changes, so we can purge of the old tiles on startup
const TILES_TILE_PREFIX = "tileData";
const TILES_META_PREFIX = "tileMeta";

enum /* StorageTileType */ {
    STORAGE_TILE_TYPE_DICT = 0,
    STORAGE_TILE_TYPE_BITMAP = 1,
    STORAGE_TILE_TYPE_ERRORED = 2,
}

// tiles are stored as
// TILES_KEY => list of all known tile keys in storage, this is kept in memory so we can do quick lookups and know what to delete
// <TILES_TILE_PREFIX><TILEKEY> => the raw tile data
// <TILES_META_PREFIX><TILEKEY> => [<lastUsed>, <tileType>, <expiresAt>, <type specific data>] only used when fetching tile, or when trying to find out which tile to remove based on lastUsed

// <type specific data> for
// STORAGE_TILE_TYPE_DICT -> nothing
// STORAGE_TILE_TYPE_BITMAP -> <tileCount>, <tileWidth>, <tileHeight> (we have to split the bitmap up into multiple images sometimes)
// STORAGE_TILE_TYPE_ERRORED -> the error code

// tile format returned is [<httpresponseCode>, <tileData>]
typedef StorageTileDataType as [Number, Dictionary or WatchUi.BitmapResource or Null];

// raw we request tiles stored directly on the watch for future use

(:noStorage)
class StorageTileCache {
    var _tilesInStorage as Array<String> = [];

    function initialize(settings as Settings) {}

    function get(tileKey as TileKey) as StorageTileDataType? {
        return null;
    }
    function haveTile(tileKey as TileKey) as Boolean {
        return false;
    }
    function addErroredTile(tileKey as TileKey, responseCode as Number) as Void {}
    function addWrongDataTile(tileKey as TileKey) as Void {}
    function addJsonData(
        tileKey as TileKey,
        data as Dictionary<PropertyKeyType, PropertyValueType>
    ) as Void {}
    function addBitmap(tileKey as TileKey, bitmap as WatchUi.BitmapResource) as Void {}
    function clearValues() as Void {}
}

(:storage)
class StorageTileCache {
    // the Storage module does not allow  querying the current keys, so we would have to query every possible tile to get the oldest an be able to remove
    // so we will store what tiles we know exist, and be able to purge them ourselves
    // we have to optimise this to just contain a list of tile keys, otherwise it takes up too much memory
    // all the metadata about a tile is stored in the tile key
    var _settings as Settings;
    var _tilesInStorage as Array<String> = [];

    function initialize(settings as Settings) {
        var tilesVersion = Storage.getValue(TILES_VERION_KEY);
        if (tilesVersion != null && (tilesVersion as Number) != TILES_STORAGE_VERSION) {
            Storage.clearValues(); // we have to purge all storage (even our routes, since we have no way of cleanly removing the old storage keys (without having back comapt for each format))
        }
        Storage.setValue(TILES_VERION_KEY, TILES_STORAGE_VERSION);

        // test storage does not cache values in memory
        // var newKey = "newkey";
        // Storage.setValue(newKey, { "test" => "value" });
        // var val1 = Storage.getValue(newKey);
        // Storage.setValue(newKey, { "test" => "value2" });
        // var val2 = Storage.getValue(newKey);
        // if (val2 instanceof Dictionary) {
        //     System.println("val was dict");
        //     val2["test"] = "val2mod";
        //     val2["test2"] = "val2test"; // new keys should be created
        // }
        // var val3 = Storage.getValue(newKey);

        // System.println("val1: " + val1);
        // System.println("val2: " + val2);
        // System.println("val3: " + val3);
        // System.println("val3 test bad dict key access: " + (val3 as Dictionary)["badkey"]);

        _settings = settings;
        var tiles = Storage.getValue(TILES_KEY);
        if (tiles != null && tiles instanceof Array) {
            // todo validate its an array of strings?
            _tilesInStorage = tiles as Array<String>;
        }
    }

    private function metaKey(tileKeyStr as String) as String {
        return TILES_META_PREFIX + tileKeyStr;
    }

    private function tileKey(tileKeyStr as String) as String {
        return TILES_TILE_PREFIX + tileKeyStr;
    }

    function get(tileKey as TileKey) as StorageTileDataType? {
        var tileKeyStr = tileKey.optimisedHashKey();

        if (_tilesInStorage.indexOf(tileKeyStr) < 0) {
            // we do not have the tile key
            return null;
        }

        var metaKeyStr = metaKey(tileKeyStr);
        var tileMeta = Storage.getValue(metaKeyStr);
        if (tileMeta == null || !(tileMeta instanceof Array) || tileMeta.size() < 3) {
            logE("bad tile metadata in storage" + tileMeta);
            return null;
        }
        tileMeta[0] = Time.now().value();
        Storage.setValue(metaKeyStr, tileMeta);

        var epoch = Time.now().value();
        var expiresAt = tileMeta[2] as Number;
        if (expired(expiresAt, epoch)) {
            logE("tile expired" + tileMeta);
            // todo should we evict the tile now?
            return null;
        }

        switch (tileMeta[1] as Number) {
            case STORAGE_TILE_TYPE_DICT:
                // no need to check type of the getValue call, handling code checks it
                return [200, Storage.getValue(tileKey(tileKeyStr)) as Dictionary]; // should always fit into the 32Kb size
            case STORAGE_TILE_TYPE_BITMAP:
                if (tileMeta.size() < 6) {
                    logE("bad tile metadata in storage for bitmap tile" + tileMeta);
                    return null;
                }
                // no need to check type of loadBitmap, handling code checks it
                return [
                    200,
                    loadBitmap(
                        tileKeyStr,
                        tileMeta[3] as Number,
                        tileMeta[4] as Number,
                        tileMeta[5] as Number
                    ),
                ];
            case STORAGE_TILE_TYPE_ERRORED:
                if (tileMeta.size() < 4) {
                    logE("bad tile metadata in storage for error tile" + tileMeta);
                    return null;
                }
                var responseCode = tileMeta[3] as Number;
                if (responseCode == WRONG_DATA_TILE) {
                    return [200, null]; // they normally come from 200 responses, with null data
                }
                return [responseCode, null];
        }

        return null;
    }

    function haveTile(tileKey as TileKey) as Boolean {
        return _tilesInStorage.indexOf(tileKey.optimisedHashKey()) >= 0;
    }

    function addErroredTile(tileKey as TileKey, responseCode as Number) as Void {
        var tileKeyStr = tileKey.optimisedHashKey();
        var epoch = Time.now().value();
        var settings = getApp()._breadcrumbContext.settings;
        var expiresAt =
            epoch +
            (isHttpResponseCode(responseCode)
                ? settings.httpErrorTileTTLS
                : settings.errorTileTTLS);
        addMetaData(tileKeyStr, [epoch, STORAGE_TILE_TYPE_ERRORED, expiresAt, responseCode]);
    }

    function addWrongDataTile(tileKey as TileKey) as Void {
        var tileKeyStr = tileKey.optimisedHashKey();
        var epoch = Time.now().value();
        var settings = getApp()._breadcrumbContext.settings;
        var expiresAt = epoch + settings.errorTileTTLS;
        addMetaData(tileKeyStr, [epoch, STORAGE_TILE_TYPE_ERRORED, expiresAt, WRONG_DATA_TILE]);
    }

    function addJsonData(
        tileKey as TileKey,
        data as Dictionary<PropertyKeyType, PropertyValueType>
    ) as Void {
        var tileKeyStr = tileKey.optimisedHashKey();
        if (addMetaData(tileKeyStr, [Time.now().value(), STORAGE_TILE_TYPE_DICT, NO_EXPIRY])) {
            safeAdd(tileKey(tileKeyStr), data);
        }
    }

    private function loadBitmap(
        tileKeyStr as String,
        tileCount as Number,
        tileWidth as Number,
        tileHeight as Number
    ) as WatchUi.BitmapResource? {
        // bitmap has to just load as a single image, but it could be over the 32Kb limit
        return Storage.getValue(tileKey(tileKeyStr)) as WatchUi.BitmapResource?;
    }

    private function deleteBitmap(tileKeyStr as String, tileCount as Number) as Void {
        // for (var i = 0; i < tileCount; ++i) {
        //     var key = tileKey(tileKeyStr) +;
        //     Storage.deleteValue(key);
        // }
        // bitmap has to just load as a single image, but it could be over the 32Kb limit
        Storage.deleteValue(tileKey(tileKeyStr));
    }

    function addBitmap(tileKey as TileKey, bitmap as WatchUi.BitmapResource) as Void {
        var tileKeyStr = tileKey.optimisedHashKey();
        if (
            addMetaData(tileKeyStr, [
                Time.now().value(),
                STORAGE_TILE_TYPE_BITMAP,
                NO_EXPIRY,
                1,
                bitmap.getWidth(),
                bitmap.getHeight(),
            ])
        ) {
            // bitmaps can be larger than the allowed 32kb limit, we must store it as 4 smaller bitmaps
            // todo slice the bitmap into small chunks (4 should always be enough, hard code for now)
            // this is not currently possible, since we can only draw to a bufferred bitmap, but cannot save the buffered bitmap to storage
            // so we have to hope the tile size fits into storage
            logD("storing tile " + tileKey(tileKeyStr));
            safeAdd(tileKey(tileKeyStr), bitmap);
        }
    }

    private function addMetaData(tileKeyStr as String, metaData as Array<Number>) as Boolean {
        try {
            // update our tracking first, we do not want to loose tiles because we stored them, but could then not update the tracking
            _tilesInStorage.add(tileKeyStr);
            Storage.setValue(TILES_KEY, _tilesInStorage as Array<PropertyValueType>);
            Storage.setValue(metaKey(tileKeyStr), metaData as Array<PropertyValueType>);
        } catch (e) {
            if (e instanceof Lang.StorageFullException) {
                // we expect storage to get full at some point, but there seems to be no way to get the size of the storage,
                // or how much is remaining programatically
                // we could allow the user to specify 'maxTileCache storage' but we will just fill it up untill there is no more space
                // note: This means routes need to be loaded first, or there will be no space left for new routes

                // todo: clear the oldest tile from storage and try again
                logE("tile storage full: " + e.getErrorMessage());
                evictLeastRecentlyUsedTile();
                return false;
            }

            logE("failed tile storage add: " + e.getErrorMessage());
            ++$.globalExceptionCounter;
        }
        if (_tilesInStorage.size() > _settings.storageTileCacheSize) {
            // Does this ever need to do more than one pass? Saw it in the sim early on where it was higher than storage cache size, but never again.
            // do not wat to do a while loop, since it could go for a long time and trigger watchdog
            evictLeastRecentlyUsedTile();
        }

        return true;
    }

    private function safeAdd(key as String, data as PropertyValueType) as Boolean {
        try {
            Storage.setValue(key, data);
        } catch (e) {
            if (e instanceof Lang.StorageFullException) {
                // we expect storage to get full at some point, but there seems to be no way to get the size of the storage,
                // or how much is remaining programatically
                // we could allow the user to specify 'maxTileCache storage' but we will just fill it up untill there is no more space
                // note: This means routes need to be loaded first, or there will be no space left for new routes

                // todo: clear the oldest tile from storage and try again
                logE("tile storage full: " + e.getErrorMessage());
                evictLeastRecentlyUsedTile();
                return false;
            }

            logE("failed tile storage add: " + e.getErrorMessage());
            ++$.globalExceptionCounter;
        }
        return true;
    }

    private function evictLeastRecentlyUsedTile() as Void {
        // todo put older tiles into disk, and store what tiles are on disk (storage class)
        // it will be faster to load them from there than bluetooth
        var oldestTime = null;
        var oldestKey = null;

        var epoch = Time.now().value();

        var keys = _tilesInStorage;
        for (var i = 0; i < keys.size(); i++) {
            var key = keys[i];
            // this is not ideal that we have to load all tiles in order to check when they were last used,
            // but its better than keeping the last used time in memory and causing OOM (when we have lots of tiles in storage).
            // this is slower, but better for memory.
            // we could have another key where we store the array of last used times, but that is harder to manage.
            var metaKeyStr = metaKey(key);
            var tileMetaData = Storage.getValue(metaKeyStr);
            if (
                tileMetaData == null ||
                !(tileMetaData instanceof Array) ||
                tileMetaData.size() < 3
            ) {
                // we do not have it in storage anymore somehow, remove this tile
                oldestKey = key;
                break;
            }

            var expiresAt = tileMetaData[2] as Number;
            if (expired(expiresAt, epoch)) {
                oldestKey = key;
                break;
            }

            var lastUsed = tileMetaData[0] as Number;
            if (oldestTime == null || oldestTime > lastUsed) {
                oldestTime = lastUsed;
                oldestKey = key;
            }
        }

        if (oldestKey != null) {
            deleteByMetaData(oldestKey);
            _tilesInStorage.remove(oldestKey);
            System.println("Evicted tile " + oldestKey + " from storage cache");
        }

        Storage.setValue(TILES_KEY, _tilesInStorage as Array<PropertyValueType>);
    }

    private function deleteByMetaData(key as String) as Void {
        var metaKeyStr = metaKey(key);
        var metaData = Storage.getValue(metaKeyStr);
        Storage.deleteValue(metaKeyStr);

        if (metaData == null || !(metaData instanceof Array) || metaData.size() < 2) {
            return;
        }

        switch (metaData[1] as Number) {
            case STORAGE_TILE_TYPE_DICT:
                Storage.deleteValue(tileKey(key));
                break;
            case STORAGE_TILE_TYPE_BITMAP:
                if (metaData.size() < 4) {
                    logE("bad tile metadata in storage for bitmap tile remove" + metaData);
                    break;
                }
                deleteBitmap(key, metaData[3] as Number);
                break;
            case STORAGE_TILE_TYPE_ERRORED:
                // noop its just the meta key
                break;
        }
    }

    function clearValues() as Void {
        var keys = _tilesInStorage;
        for (var i = 0; i < keys.size(); ++i) {
            var key = keys[i];
            deleteByMetaData(key);
        }
        _tilesInStorage = [];
        Storage.setValue(TILES_KEY, _tilesInStorage);
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
    var _storageTileCache as StorageTileCache;
    var _errorBitmaps as Dictionary<String, WeakReference<Graphics.BufferedBitmap> > =
        ({}) as Dictionary<String, WeakReference<Graphics.BufferedBitmap> >;

    function initialize(
        webRequestHandler as WebRequestHandler,
        settings as Settings,
        cachedValues as CachedValues
    ) {
        _settings = settings;
        _cachedValues = cachedValues;
        _webRequestHandler = webRequestHandler;
        _internalCache = ({}) as Dictionary<TileKey, Tile>;
        _storageTileCache = new StorageTileCache(_settings);

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
        clearValuesWithoutStorage();
        // whenever we purge the tile cache it is usually because the tile server properties have changed, safest to nuke the storage cache too
        // though sme times its when the in memory tile cache size changes
        // users should not be modifiying the tile settings in any way, otherwise the storage will also be out of date (eg. when tile size or tile url changes)
        _storageTileCache.clearValues();
    }

    public function clearValuesWithoutStorage() as Void {
        _internalCache = ({}) as Dictionary<TileKey, Tile>;
        _errorBitmaps = ({}) as Dictionary<String, WeakReference<Graphics.BufferedBitmap> >;
        _tileCacheVersion++;
    }

    // loads a tile into the cache
    // reurns true if seed should stop and wait for next calculate (to prevent watchdog errors)
    function seedTile(tileKey as TileKey) as Boolean {
        var tile = _internalCache[tileKey] as Tile?;
        if (tile != null) {
            var epoch = Time.now().value();
            if (!tile.expiredAlready(epoch)) {
                return false;
            }
        }
        return startSeedTile(tileKey, false);
    }

    // seedTile puts the tile into memory, either by pulling from storage, or by runnung a web request
    // seedTileToStorage only puts the tile into storage
    function seedTileToStorage(tileKey as TileKey) as Void {
        if (_storageTileCache.haveTile(tileKey)) {
            // we already have the tile (it might be errored, but we have it)
            return;
        }

        startSeedTile(tileKey, true);
    }

    // reurns true if seed should stop and wait for next calculate (to prevent watchdog errors)
    private function startSeedTile(tileKey as TileKey, onlySeedStorage as Boolean) as Boolean {
        // System.println("starting load tile: " + x + " " + y + " " + z);

        if (!_settings.tileUrl.equals(COMPANION_APP_TILE_URL)) {
            // logD("small tile: " + tileKey + " scaledTileSize: " + _settings.scaledTileSize + " tileSize: " + _settings.tileSize);
            var x = tileKey.x / _cachedValues.smallTilesPerScaledTile;
            var y = tileKey.y / _cachedValues.smallTilesPerScaledTile;
            var fullSizeTile = new TileKey(x, y, tileKey.z);
            // logD("fullSizeTile tile: " + fullSizeTile);
            var imageReqHandler = new ImageWebTileRequestHandler(
                me,
                tileKey,
                fullSizeTile,
                _tileCacheVersion,
                onlySeedStorage
            );
            var tileFromStorage = _storageTileCache.get(fullSizeTile);
            if (tileFromStorage != null) {
                var responseCode = tileFromStorage[0];
                // logD("image tile loaded from storage: " + tileKey + " with result: " + responseCode);
                if (responseCode != 200) {
                    imageReqHandler.handleErroredTile(responseCode);
                    return true;
                }
                // only handle successful tiles for now, maybe we should handle some other errors (404, 403 etc)
                imageReqHandler.handleSuccessfulTile(tileFromStorage[1] as BitmapResource?, false);
                return true;
            }
            if (_settings.storageMapTilesOnly && !_cachedValues.seeding()) {
                // we are running in storage only mode, but the tile is not in the cache
                addErroredTile(tileKey, _tileCacheVersion, "S404", true);
                return false;
            }
            _webRequestHandler.add(
                new ImageRequest(
                    "im" + tileKey.optimisedHashKey() + "-" + _tileCacheVersion, // the hash is for the small tile request, not the big one (they will send the same physical request out, but again use 256 tilSize if your using external sources)
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
                    imageReqHandler
                )
            );
            return false;
        }

        return seedCompanionAppTile(tileKey, onlySeedStorage);
    }

    (:noCompanionTiles)
    function seedCompanionAppTile(tileKey as TileKey, onlySeedStorage as Boolean) as Boolean {
        return false;
    }

    (:companionTiles)
    function seedCompanionAppTile(tileKey as TileKey, onlySeedStorage as Boolean) as Boolean {
        // logD("small tile (companion): " + tileKey + " scaledTileSize: " + _settings.scaledTileSize + " tileSize: " + _settings.tileSize);
        var jsonWebHandler = new JsonWebTileRequestHandler(
            me,
            tileKey,
            _tileCacheVersion,
            onlySeedStorage
        );
        var tileFromStorage = _storageTileCache.get(tileKey);
        if (tileFromStorage != null) {
            var responseCode = tileFromStorage[0];
            // logD("image tile loaded from storage: " + tileKey + " with result: " + responseCode);
            if (responseCode != 200) {
                jsonWebHandler.handleErroredTile(responseCode);
                return true;
            }
            // only handle successful tiles for now, maybe we should handle some other errors (404, 403 etc)
            jsonWebHandler.handleSuccessfulTile(tileFromStorage[1] as Dictionary?, false);
            return true;
        }
        if (_settings.storageMapTilesOnly && !_cachedValues.seeding()) {
            // we are running in storage only mode, but the tile is not in the cache
            addErroredTile(tileKey, _tileCacheVersion, "S404", true);
            return false;
        }
        _webRequestHandler.add(
            new JsonRequest(
                "json" + tileKey.optimisedHashKey() + "-" + _tileCacheVersion,
                _settings.tileUrl + "/loadtile",
                {
                    "x" => tileKey.x,
                    "y" => tileKey.y,
                    "z" => tileKey.z,
                    "scaledTileSize" => _settings.scaledTileSize,
                    "tileSize" => _settings.tileSize,
                },
                jsonWebHandler
            )
        );
        return false;
    }

    // puts a tile into the cache
    function addTile(tileKey as TileKey, tileCacheVersion as Number, tile as Tile) as Void {
        if (tileCacheVersion != _tileCacheVersion) {
            return;
        }

        tile.setExpiresAt(NO_EXPIRY); // be explicit that there is no expiry

        if (_internalCache.size() == _settings.tileCacheSize) {
            evictLeastRecentlyUsedTile();
        }

        _internalCache[tileKey] = tile;
    }

    function addErroredTile(
        tileKey as TileKey,
        tileCacheVersion as Number,
        msg as String,
        isHttpResponseCode as Boolean
    ) as Void {
        if (tileCacheVersion != _tileCacheVersion) {
            return;
        }

        if (_internalCache.size() == _settings.tileCacheSize) {
            evictLeastRecentlyUsedTile();
        }

        var epoch = Time.now().value();
        var expiresAt =
            epoch + (isHttpResponseCode ? _settings.httpErrorTileTTLS : _settings.errorTileTTLS);

        var weakRefToErrorBitmap = _errorBitmaps[msg];
        if (weakRefToErrorBitmap != null) {
            var errorBitmap = weakRefToErrorBitmap.get() as Graphics.BufferedBitmap?;
            if (errorBitmap != null) {
                var tile = new Tile(errorBitmap);
                tile.setExpiresAt(expiresAt);
                _internalCache[tileKey] = tile;
                return;
            }
        }

        var tileSize = _settings.tileSize;
        // todo perf: only draw each message once, and cache the result (since they are generally 404,403 etc.), still need the tile object though to track last used
        // this is especially important for larger tiles (image tiles are usually compressed and do not take up the full tile size in pixels)
        var bitmap = newBitmap(tileSize, tileSize);
        var dc = bitmap.getDc();
        var halfHeight = tileSize / 2;
        dc.setColor(Graphics.COLOR_RED, _settings.tileErrorColour);
        dc.clear();
        // cache the tile as errored, but do not show the error message
        if (_settings.showErrorTileMessages) {
            // could get text width and see which one covers more of the tile
            if (tileSize < 100) {
                dc.drawText(
                    halfHeight,
                    halfHeight,
                    Graphics.FONT_XTINY,
                    msg,
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER
                );
            } else {
                var textHight = dc.getFontHeight(Graphics.FONT_LARGE);
                dc.drawText(0, 0, Graphics.FONT_LARGE, msg, Graphics.TEXT_JUSTIFY_LEFT);
                dc.drawText(tileSize, 0, Graphics.FONT_LARGE, msg, Graphics.TEXT_JUSTIFY_RIGHT);
                dc.drawText(
                    halfHeight,
                    halfHeight,
                    Graphics.FONT_LARGE,
                    msg,
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER
                );
                dc.drawText(
                    0,
                    tileSize - textHight,
                    Graphics.FONT_LARGE,
                    msg,
                    Graphics.TEXT_JUSTIFY_LEFT
                );
                dc.drawText(
                    tileSize,
                    tileSize - textHight,
                    Graphics.FONT_LARGE,
                    msg,
                    Graphics.TEXT_JUSTIFY_RIGHT
                );
            }
        }

        _errorBitmaps[msg] = bitmap.weak(); // store in our cache for later use
        var tile = new Tile(bitmap);
        tile.setExpiresAt(expiresAt);
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

    function haveTile(tileKey as TileKey) as Boolean {
        return _internalCache.hasKey(tileKey);
    }

    function evictLeastRecentlyUsedTile() as Void {
        // todo put older tiles into disk, and store what tiles are on disk (storage class)
        // it will be faster to load them from there than bluetooth
        var oldestTime = null;
        var oldestKey = null;

        var epoch = Time.now().value();

        var keys = _internalCache.keys();
        for (var i = 0; i < keys.size(); i++) {
            var key = keys[i];
            var tile = self._internalCache[key] as Tile;
            if (tile.expiredAlready(epoch)) {
                oldestKey = key;
                break;
            }

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

    (:noCompanionTiles)
    function tileDataToBitmap64ColourString(charArr as Array<Char>?) as Graphics.BufferedBitmap? {
        return null;
    }
    (:companionTiles)
    function tileDataToBitmap64ColourString(charArr as Array<Char>?) as Graphics.BufferedBitmap? {
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
                // _palette should have all values that are possible, not checking size for perf reasons
                var colour = _palette[charArr[it].toNumber() & 0x3f]; // charArr[it] as Char the toNumber is The UTF-32 representation of the Char interpreted as a Number
                it++;
                localDc.setColor(colour, colour);
                localDc.drawPoint(i, j);
            }
        }

        return localBitmap;
    }

    (:noCompanionTiles)
    function tileDataToBitmapBlackAndWhite(charArr as Array<Char>?) as Graphics.BufferedBitmap? {
        return null;
    }
    (:companionTiles)
    function tileDataToBitmapBlackAndWhite(charArr as Array<Char>?) as Graphics.BufferedBitmap? {
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

    (:noCompanionTiles)
    function tileDataToBitmapFullColour(mapTileBytes as ByteArray?) as Graphics.BufferedBitmap? {
        return null;
    }
    (:companionTiles)
    function tileDataToBitmapFullColour(mapTileBytes as ByteArray?) as Graphics.BufferedBitmap? {
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
            System.println(
                "bad tile length full colour: " + mapTileBytes.size() + " best effort load"
            );
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
                var colour =
                    mapTileBytes.decodeNumber(Lang.NUMBER_FORMAT_UINT32, {
                        :offset => offset,
                        :endianness => Lang.ENDIAN_BIG,
                    }) as Number;
                colour = (colour >> 8) & 0x00ffffff; // 24 bit colour only
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
