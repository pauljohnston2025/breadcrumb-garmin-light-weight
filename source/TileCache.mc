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

function tileKeyHash(x as Number, y as Number, z as Number) as String {
    var string = x.toString() + "-" + y + "-" + z;

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
        x as Number,
        y as Number,
        z as Number,
        tileKeyStr as String,
        tileCacheVersion as Number,
        onlySeedStorage as Boolean
    ) {
        JsonWebHandler.initialize();
    }

    function handle(
        responseCode as Number,
        data as
            Dictionary or
                String or
                Iterator or
                WatchUi.BitmapResource or
                Graphics.BitmapReference or
                Null
    ) as Void {}
}

(:companionTiles)
class JsonWebTileRequestHandler extends JsonWebHandler {
    var _tileCache as TileCache;
    var _tileKeyStr as String;
    var _tileCacheVersion as Number;
    var _onlySeedStorage as Boolean;
    var _x as Number;
    var _y as Number;
    var _z as Number;

    function initialize(
        tileCache as TileCache,
        x as Number,
        y as Number,
        z as Number,
        tileKeyStr as String,
        tileCacheVersion as Number,
        onlySeedStorage as Boolean
    ) {
        JsonWebHandler.initialize();
        _tileCache = tileCache;
        _x = x;
        _y = y;
        _z = z;
        _tileKeyStr = tileKeyStr;
        _tileCacheVersion = tileCacheVersion;
        _onlySeedStorage = onlySeedStorage;
    }

    function handleErroredTile(responseCode as Number) as Void {
        _tileCache.addErroredTile(
            _tileKeyStr,
            _tileCacheVersion,
            responseCode.toString(),
            isHttpResponseCode(responseCode)
        );
    }

    function handle(
        responseCode as Number,
        data as
            Dictionary or
                String or
                Iterator or
                WatchUi.BitmapResource or
                Graphics.BitmapReference or
                Null
    ) as Void {
        // do not store tiles in storage if the tile cache version does not match
        if (_tileCacheVersion != _tileCache._tileCacheVersion) {
            return;
        }

        var settings = getApp()._breadcrumbContext.settings;
        var cachedValues = getApp()._breadcrumbContext.cachedValues;

        if (responseCode != 200) {
            // see error codes such as Communications.NETWORK_REQUEST_TIMED_OUT
            logE("failed with: " + responseCode);
            if (settings.cacheTilesInStorage || cachedValues.seeding()) {
                _tileCache._storageTileCache.addErroredTile(_x, _y, _z, _tileKeyStr, responseCode);
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
        data as
            Dictionary or
                String or
                Iterator or
                WatchUi.BitmapResource or
                Graphics.BitmapReference or
                Null,
        addToCache as Boolean
    ) as Void {
        var settings = getApp()._breadcrumbContext.settings;
        var cachedValues = getApp()._breadcrumbContext.cachedValues;

        if (!(data instanceof Dictionary)) {
            logE("wrong data type, not dict: " + data);
            if (addToCache) {
                if (settings.cacheTilesInStorage || cachedValues.seeding()) {
                    _tileCache._storageTileCache.addWrongDataTile(_x, _y, _z, _tileKeyStr);
                }
            }
            if (_onlySeedStorage) {
                return;
            }
            _tileCache.addErroredTile(_tileKeyStr, _tileCacheVersion, "WD", false);
            return;
        }

        if (addToCache) {
            if (settings.cacheTilesInStorage || cachedValues.seeding()) {
                _tileCache._storageTileCache.addJsonData(
                    _x,
                    _y,
                    _z,
                    _tileKeyStr,
                    data as Dictionary<PropertyKeyType, PropertyValueType>
                );
            }
        }

        if (_onlySeedStorage) {
            return;
        }

        // logT("data: " + data);
        var mapTile = data["data"];
        if (!(mapTile instanceof String)) {
            logE("wrong data type, not string");
            _tileCache.addErroredTile(_tileKeyStr, _tileCacheVersion, "WD", false);
            return;
        }

        var type = data.get("type");
        if (type == null || !(type instanceof Number)) {
            // back compat
            logE("bad type for type: falling back: " + type);
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

        _tileCache.addErroredTile(_tileKeyStr, _tileCacheVersion, "UT", false);
    }

    function handle64ColourDataString(mapTile as String) as Void {
        // logT("got tile string of length: " + mapTile.length());
        var bitmap = _tileCache.tileDataToBitmap64ColourString(mapTile.toCharArray());
        if (bitmap == null) {
            logE("failed to parse bitmap");
            _tileCache.addErroredTile(_tileKeyStr, _tileCacheVersion, "FP", false);
            return;
        }

        var tile = new Tile(bitmap);
        _tileCache.addTile(_tileKeyStr, _tileCacheVersion, tile);
    }

    function handleBase64FullColourDataString(mapTile as String) as Void {
        var mapTileBytes =
            StringUtil.convertEncodedString(mapTile, {
                :fromRepresentation => StringUtil.REPRESENTATION_STRING_BASE64,
                :toRepresentation => StringUtil.REPRESENTATION_BYTE_ARRAY,
            }) as ByteArray;
        // logT("got tile string of length: " + mapTile.length());
        var bitmap = _tileCache.tileDataToBitmapFullColour(mapTileBytes);
        if (bitmap == null) {
            logE("failed to parse bitmap");
            _tileCache.addErroredTile(_tileKeyStr, _tileCacheVersion, "FP", false);
            return;
        }

        var tile = new Tile(bitmap);
        _tileCache.addTile(_tileKeyStr, _tileCacheVersion, tile);
    }

    function handleBlackAndWhiteDataString(mapTile as String) as Void {
        // logT("got tile string of length: " + mapTile.length());
        var bitmap = _tileCache.tileDataToBitmapBlackAndWhite(mapTile.toCharArray());
        if (bitmap == null) {
            logE("failed to parse bitmap");
            _tileCache.addErroredTile(_tileKeyStr, _tileCacheVersion, "FP", false);
            return;
        }

        var tile = new Tile(bitmap);
        _tileCache.addTile(_tileKeyStr, _tileCacheVersion, tile);
    }
}

(:noImageTiles)
class ImageWebTileRequestHandler extends ImageWebHandler {
    function initialize(
        tileCache as TileCache,
        x as Number,
        y as Number,
        z as Number,
        tileKeyStr as String,
        fullTileKeyStr as String,
        tileCacheVersion as Number,
        onlySeedStorage as Boolean
    ) {
        ImageWebHandler.initialize();
    }

    function handle(
        responseCode as Number,
        data as WatchUi.BitmapResource or Graphics.BitmapReference or Null
    ) as Void {}
}
(:imageTiles)
class ImageWebTileRequestHandler extends ImageWebHandler {
    var _tileCache as TileCache;
    var _tileKeyStr as String;
    var _fullTileKeyStr as String;
    var _tileCacheVersion as Number;
    var _onlySeedStorage as Boolean;
    var _x as Number;
    var _y as Number;
    var _z as Number;

    function initialize(
        tileCache as TileCache,
        x as Number,
        y as Number,
        z as Number,
        tileKeyStr as String,
        fullTileKeyStr as String,
        tileCacheVersion as Number,
        onlySeedStorage as Boolean
    ) {
        ImageWebHandler.initialize();
        _tileCache = tileCache;
        _x = x;
        _y = y;
        _z = z;
        _tileKeyStr = tileKeyStr;
        _fullTileKeyStr = fullTileKeyStr;
        _tileCacheVersion = tileCacheVersion;
        _onlySeedStorage = onlySeedStorage;
    }

    function handleErroredTile(responseCode as Number) as Void {
        _tileCache.addErroredTile(
            _tileKeyStr,
            _tileCacheVersion,
            responseCode.toString(),
            isHttpResponseCode(responseCode)
        );
    }

    function handle(
        responseCode as Number,
        data as
            Dictionary or
                String or
                Iterator or
                WatchUi.BitmapResource or
                Graphics.BitmapReference or
                Null
    ) as Void {
        // do not store tiles in storage if the tile cache version does not match
        if (_tileCacheVersion != _tileCache._tileCacheVersion) {
            return;
        }

        var settings = getApp()._breadcrumbContext.settings;
        var cachedValues = getApp()._breadcrumbContext.cachedValues;

        if (responseCode != 200) {
            // see error codes such as Communications.NETWORK_REQUEST_TIMED_OUT
            logE("failed with: " + responseCode);
            if (settings.cacheTilesInStorage || cachedValues.seeding()) {
                _tileCache._storageTileCache.addErroredTile(
                    _x,
                    _y,
                    _z,
                    _fullTileKeyStr,
                    responseCode
                );
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
        data as
            Dictionary or
                String or
                Iterator or
                WatchUi.BitmapResource or
                Graphics.BitmapReference or
                Null,
        addToCache as Boolean
    ) as Void {
        var settings = getApp()._breadcrumbContext.settings;
        var cachedValues = getApp()._breadcrumbContext.cachedValues;

        if (
            data == null ||
            (!(data instanceof WatchUi.BitmapResource) &&
                !(data instanceof Graphics.BitmapReference))
        ) {
            logE("wrong data type not image");
            if (addToCache) {
                if (settings.cacheTilesInStorage || cachedValues.seeding()) {
                    _tileCache._storageTileCache.addWrongDataTile(_x, _y, _z, _tileKeyStr);
                }
            }
            if (_onlySeedStorage) {
                return;
            }
            _tileCache.addErroredTile(_tileKeyStr, _tileCacheVersion, "WD", false);
            return;
        }

        if (data instanceof Graphics.BitmapReference) {
            // need to keep it in memory all the time, if we use the reference only it can be deallocated by the graphics memory pool
            // https://developer.garmin.com/connect-iq/core-topics/graphics/
            data = data.get();
        }

        if (data == null || !(data instanceof WatchUi.BitmapResource)) {
            logE("data bitmap was null or not a bitmap");
            if (addToCache) {
                if (settings.cacheTilesInStorage || cachedValues.seeding()) {
                    _tileCache._storageTileCache.addWrongDataTile(_x, _y, _z, _tileKeyStr);
                }
            }
            if (_onlySeedStorage) {
                return;
            }
            _tileCache.addErroredTile(_tileKeyStr, _tileCacheVersion, "WD", false);
            return;
        }

        if (addToCache) {
            if (settings.cacheTilesInStorage || cachedValues.seeding()) {
                _tileCache._storageTileCache.addBitmap(_x, _y, _z, _fullTileKeyStr, data);
            }
        }

        if (_onlySeedStorage) {
            return;
        }

        // we have to downsample the tile, not recomendedd, as this mean we will have to request the same tile multiple times (cant save big tiles around anywhere)
        // also means we have to use scratch space to draw the tile and downsample it

        // if (data.getWidth() != settings.tileSize || data.getHeight() != settings.tileSize) {
        //     // dangerous large bitmap could cause oom, buts its the only way to upscale the image and then slice it
        //     // we cannot downscale because we would be slicing a pixel in half
        //     // I guess we could just figure out which pixels to double up on?
        //     // anyone using an external tile server should be setting thier tileSize to 256, but perhaps some devices will run out of memory?
        //     // if users are using a smaller size it should be a multiple of 256.
        //     // if its not, we will stretch the image then downsize, if its already a multiple we will use the image as is (optimal)
        //     var maxDim = maxN(data.getWidth(), data.getHeight()); // should be equal (every time server i know of is 256*256), but who knows
        //     var pixelsPerTile = maxDim / cachedValues.smallTilesPerScaledTile.toFloat();
        //     var sourceBitmap = data;
        //     if (
        //         Math.ceil(pixelsPerTile) != settings.tileSize ||
        //         Math.floor(pixelsPerTile) != settings.tileSize
        //     ) {
        //         // we have an anoying situation - stretch/reduce the image
        //         var scaleUpSize = cachedValues.smallTilesPerScaledTile * settings.tileSize;
        //         var scaleFactor = scaleUpSize / maxDim.toFloat();
        //         var upscaledBitmap = newBitmap(scaleUpSize, scaleUpSize);
        //         var upscaledBitmapDc = upscaledBitmap.getDc();

        //         var scaleMatrix = new AffineTransform();
        //         scaleMatrix.scale(scaleFactor, scaleFactor); // scale

        //         try {
        //             upscaledBitmapDc.drawBitmap2(0, 0, sourceBitmap, {
        //                 :transform => scaleMatrix,
        //                 // Use bilinear filtering for smoother results when rotating/scaling (less noticible tearing)
        //                 :filterMode => Graphics.FILTER_MODE_BILINEAR,
        //             });
        //         } catch (e) {
        // var message = e.getErrorMessage();
        // logE("failed drawBitmap2 (handleSuccessfulTile): " + message);
        // ++$.globalExceptionCounter;
        // incNativeColourFormatErrorIfMessageMatches(message);
        //         }
        //         // logT("scaled up to: " + upscaledBitmap.getWidth() + " " + upscaledBitmap.getHeight());
        //         // logT("from: " + sourceBitmap.getWidth() + " " + sourceBitmap.getHeight());
        //         sourceBitmap = upscaledBitmap; // resume what we were doing as if it was always the larger bitmap
        //     }

        //     var croppedSection = newBitmap(settings.tileSize, settings.tileSize);
        //     var croppedSectionDc = croppedSection.getDc();
        //     var xOffset = _tileKeyStr.x % cachedValues.smallTilesPerScaledTile;
        //     var yOffset = _tileKeyStr.y % cachedValues.smallTilesPerScaledTile;
        //     // logT("tile: " + _tileKeyStr);
        //     // logT("croppedSection: " + croppedSection.getWidth() + " " + croppedSection.getHeight());
        //     // logT("source: " + sourceBitmap.getWidth() + " " + sourceBitmap.getHeight());
        //     // logT("drawing from: " + xOffset * settings.tileSize + " " + yOffset * settings.tileSize);
        //     croppedSectionDc.drawBitmap(
        //         -xOffset * settings.tileSize,
        //         -yOffset * settings.tileSize,
        //         sourceBitmap
        //     );

        //     data = croppedSection;
        // }

        var tile = new Tile(data);
        _tileCache.addTile(_tileKeyStr, _tileCacheVersion, tile);
    }
}

const TILES_KEY = "tileKeys";
const TILES_VERSION_KEY = "tilesVersion";
const TILES_STORAGE_VERSION = 4; // update this every time the tile format on disk changes, so we can purge of the old tiles on startup
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
    function initialize(settings as Settings) {}
    function setup() as Void {}

    function get(
        x as Number,
        y as Number,
        z as Number,
        tileKeyStr as String
    ) as StorageTileDataType? {
        return null;
    }
    function haveTile(x as Number, y as Number, z as Number, tileKeyStr as String) as Boolean {
        return false;
    }
    function addErroredTile(
        x as Number,
        y as Number,
        z as Number,
        tileKeyStr as String,
        responseCode as Number
    ) as Void {}
    function addWrongDataTile(
        x as Number,
        y as Number,
        z as Number,
        tileKeyStr as String
    ) as Void {}
    function addJsonData(
        x as Number,
        y as Number,
        z as Number,
        tileKeyStr as String,
        data as Dictionary<PropertyKeyType, PropertyValueType>
    ) as Void {}
    function addBitmap(
        x as Number,
        y as Number,
        z as Number,
        tileKeyStr as String,
        bitmap as WatchUi.BitmapResource
    ) as Void {}
    function clearValues(oldPageCount as Number) as Void {}
}

(:storage)
class StorageTileCache {
    // The Storage module does not allow querying the current keys, so we would have to query every possible tile to get the oldest and be able to remove it.
    // To manage memory, we will store what tiles we know exist in pages, and be able to purge them ourselves.
    var _settings as Settings;

    // we store the tiles into pages based on the tile keys hash, this is so we only have to load small chunks of known keys at a time (if we try and store all the keys we quickly run out of memory)
    // 1 page is the most cpu efficient for reading, but limits the max number of tiles we can store
    var _pageCount as Number = 1;
    var _totalTileCount as Number = 0;
    var _currentPageIndex as Number = -1; // -1 indicates no page is loaded
    var _currentPageKeys as Array<String> = [];
    var _pageSizes as Array<Number>;
    private var _lastEvictedPageIndex as Number = 0;
    private var _maxPageSize as Number;

    function initialize(settings as Settings) {
        var tilesVersion = Storage.getValue(TILES_VERSION_KEY);
        if (tilesVersion != null && (tilesVersion as Number) != TILES_STORAGE_VERSION) {
            Storage.clearValues(); // we have to purge all storage (even our routes, since we have no way of cleanly removing the old storage keys (without having back compat for each format))
        }
        Storage.setValue(TILES_VERSION_KEY, TILES_STORAGE_VERSION);

        _settings = settings;
        _pageCount = _settings.storageTileCachePageCount;
        pageCountUpdated();

        // Instead of loading all keys, we load the total count of tiles across all pages.
        var totalCount = Storage.getValue("totalTileCount");
        if (totalCount != null) {
            _totalTileCount = totalCount as Number;
        } else {
            _totalTileCount = 0;
        }
    }

    private function pageCountUpdated() as Void {
        if (_pageCount <= 0) {
            _pageCount = 1;
        }
        _pageSizes = new [_pageCount] as Array<Number>;
        for (var i = 0; i < _pageCount; i++) {
            _pageSizes[i] = 0;
        }

        // Calculate the maximum allowed size for a single page to prevent memory issues.
        var idealPageSize = _settings.storageTileCacheSize / _pageCount;
        _maxPageSize = (idealPageSize * 1.1).toNumber();
    }

    function setup() as Void {
        populateInitialPageSizes();
        if (_settings.storageTileCacheSize < _totalTileCount) {
            // Purge excess tiles if the cache size has been reduced.
            var numberToEvict = _totalTileCount - _settings.storageTileCacheSize;
            for (var i = 0; i < numberToEvict; ++i) {
                evictLeastRecentlyUsedTile();
            }
        }
    }

    private function populateInitialPageSizes() as Void {
        for (var i = 0; i < _pageCount; i++) {
            loadPage(i);
            _pageSizes[i] = _currentPageKeys.size();
        }
    }

    private function pageStorageKey(pageIndex as Number) as String {
        return TILES_KEY + "_" + pageIndex;
    }

    private function loadPage(pageIndex as Number) as Void {
        if (_currentPageIndex == pageIndex) {
            return; // Page is already loaded.
        }

        // logT("Loading storage page: " + pageIndex);

        // Release memory of the old page's keys before loading the new one.
        _currentPageKeys = [];
        var page = Storage.getValue(pageStorageKey(pageIndex));

        if (page instanceof Array) {
            _currentPageKeys = page as Array<String>;
        }
        // No else needed, _currentPageKeys is already an empty array.
        _currentPageIndex = pageIndex;
    }

    private function saveCurrentPage() as Void {
        if (_currentPageIndex != -1) {
            var pageKey = pageStorageKey(_currentPageIndex);
            Storage.setValue(pageKey, _currentPageKeys);
        }
    }

    // Determines which page a tile key belongs to using a spatial hash.
    // This new algorithm groups tiles that are geographically close onto the same page,
    // which dramatically reduces page loading when panning the map.
    private function getPageIndexForKey(x as Number, y as Number, z as Number) as Number {
        if (_pageCount <= 1) {
            // optimise for single page
            return 0;
        }

        // This spatial hash groups tiles into 4x4 blocks. All tiles in a block
        // at the same zoom level will be on the same page.
        // Integer division (x / 4) effectively creates a grid.
        var gridX = x / 4;
        var gridY = y / 4;

        // Combine the grid coordinates and zoom level to get a consistent hash value.
        // The prime numbers help in distributing the pages more evenly across zoom levels.
        var spatialHash = gridX * 31 + gridY * 61 + z * 97;

        var res = absN(spatialHash % _pageCount);
        // logT("tile: " + x + "-" + y + "-" + z + " page: " + res);
        return res;
    }

    private function metaKey(tileKeyStr as String) as String {
        return TILES_META_PREFIX + tileKeyStr;
    }

    private function tileKey(tileKeyStr as String) as String {
        return TILES_TILE_PREFIX + tileKeyStr;
    }

    function get(
        x as Number,
        y as Number,
        z as Number,
        tileKeyStr as String
    ) as StorageTileDataType? {
        var pageIndex = getPageIndexForKey(x, y, z);
        loadPage(pageIndex);

        if (_currentPageKeys.indexOf(tileKeyStr) < 0) {
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

    function haveTile(x as Number, y as Number, z as Number, tileKeyStr as String) as Boolean {
        // need to check for expired tiles
        // we could call get, but that also loads the tile data, and increments the "lastUsed" time
        var pageIndex = getPageIndexForKey(x, y, z);
        loadPage(pageIndex);

        if (_currentPageKeys.indexOf(tileKeyStr) < 0) {
            // we do not have the tile key
            return false;
        }

        var metaKeyStr = metaKey(tileKeyStr);
        var tileMeta = Storage.getValue(metaKeyStr);
        if (tileMeta == null || !(tileMeta instanceof Array) || tileMeta.size() < 3) {
            logE("bad tile metadata in storage" + tileMeta);
            return false;
        }

        var epoch = Time.now().value();
        var expiresAt = tileMeta[2] as Number;
        if (expired(expiresAt, epoch)) {
            logE("tile expired" + tileMeta);
            return false;
        }

        return true;
    }

    function addErroredTile(
        x as Number,
        y as Number,
        z as Number,
        tileKeyStr as String,
        responseCode as Number
    ) as Void {
        var epoch = Time.now().value();
        var settings = getApp()._breadcrumbContext.settings;
        var expiresAt =
            epoch +
            (isHttpResponseCode(responseCode)
                ? settings.httpErrorTileTTLS
                : settings.errorTileTTLS);
        addMetaData(x, y, z, tileKeyStr, [
            epoch,
            STORAGE_TILE_TYPE_ERRORED,
            expiresAt,
            responseCode,
        ]);
    }

    function addWrongDataTile(x as Number, y as Number, z as Number, tileKeyStr as String) as Void {
        var epoch = Time.now().value();
        var settings = getApp()._breadcrumbContext.settings;
        var expiresAt = epoch + settings.errorTileTTLS;
        addMetaData(x, y, z, tileKeyStr, [
            epoch,
            STORAGE_TILE_TYPE_ERRORED,
            expiresAt,
            WRONG_DATA_TILE,
        ]);
    }

    function addJsonData(
        x as Number,
        y as Number,
        z as Number,
        tileKeyStr as String,
        data as Dictionary<PropertyKeyType, PropertyValueType>
    ) as Void {
        if (
            addMetaData(x, y, z, tileKeyStr, [
                Time.now().value(),
                STORAGE_TILE_TYPE_DICT,
                NO_EXPIRY,
            ])
        ) {
            safeAdd(tileKey(tileKeyStr), data);
        }
    }

    (:inline)
    private function loadBitmap(
        tileKeyStr as String,
        tileCount as Number,
        tileWidth as Number,
        tileHeight as Number
    ) as WatchUi.BitmapResource? {
        // bitmap has to just load as a single image, but it could be over the 32Kb limit
        return Storage.getValue(tileKey(tileKeyStr)) as WatchUi.BitmapResource?;
    }

    (:inline)
    private function deleteBitmap(tileKeyStr as String, tileCount as Number) as Void {
        // for (var i = 0; i < tileCount; ++i) {
        //     var key = tileKey(tileKeyStr) +;
        //     Storage.deleteValue(key);
        // }
        // bitmap has to just load as a single image, but it could be over the 32Kb limit
        Storage.deleteValue(tileKey(tileKeyStr));
    }

    function addBitmap(
        x as Number,
        y as Number,
        z as Number,
        tileKeyStr as String,
        bitmap as WatchUi.BitmapResource
    ) as Void {
        if (
            addMetaData(x, y, z, tileKeyStr, [
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

    private function addMetaData(
        x as Number,
        y as Number,
        z as Number,
        tileKeyStr as String,
        metaData as Array<PropertyValueType>
    ) as Boolean {
        var pageIndex = getPageIndexForKey(x, y, z);
        loadPage(pageIndex);

        // This is a new tile.
        _currentPageKeys.add(tileKeyStr);
        _pageSizes[pageIndex]++;
        _totalTileCount++;
        // If keyIndex is not -1, it's an existing tile being updated.
        // We still proceed to save its new metadata below.

        try {
            // update our tracking first, we do not want to loose tiles because we stored them, but could then not update the tracking
            // Save metadata and the updated page list first.
            saveCurrentPage();
            Storage.setValue(metaKey(tileKeyStr), metaData);
            Storage.setValue("totalTileCount", _totalTileCount);
        } catch (e) {
            if (e instanceof Lang.StorageFullException) {
                // we expect storage to get full at some point, but there seems to be no way to get the size of the storage,
                // or how much is remaining programmatically
                // we could allow the user to specify 'maxTileCache storage' but we will just fill it up until there is no more space
                // note: This means routes need to be loaded first, or there will be no space left for new routes

                logE("tile storage full: " + e.getErrorMessage());
                // this page might have been too big, or we might just be full, so evict 2 tiles to  be safe
                evictOldestTileFromPage();
                evictLeastRecentlyUsedTile();
                return false;
            }

            logE("failed tile storage add: " + e.getErrorMessage());
            ++$.globalExceptionCounter;
        }

        // Check if this page is getting too large, and evict its oldest tile.
        if (_pageSizes[pageIndex] >= _maxPageSize) {
            evictOldestTileFromPage();
        }

        if (_totalTileCount > _settings.storageTileCacheSize) {
            // Does this ever need to do more than one pass? Saw it in the sim early on where it was higher than storage cache size, but never again.
            // do not want to do a while loop, since it could go for a long time and trigger watchdog
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
                // or how much is remaining programmatically
                // we could allow the user to specify 'maxTileCache storage' but we will just fill it up until there is no more space
                // note: This means routes need to be loaded first, or there will be no space left for new routes

                logE("tile storage full: " + e.getErrorMessage());
                evictLeastRecentlyUsedTile();
                return false;
            }

            logE("failed tile storage add: " + e.getErrorMessage());
            ++$.globalExceptionCounter;
        }
        return true;
    }

    private function evictOldestTileFromPage() as Void {
        if (_currentPageIndex < 0 || _currentPageIndex >= _pageSizes.size()) {
            logE("evicting from page thats not loaded");
            return;
        }

        if (_currentPageKeys.size() == 0) {
            return; // Nothing to evict.
        }

        var oldestTime = null;
        var oldestKey = null;
        var epoch = Time.now().value();

        // Find the oldest tile ON THE CURRENT PAGE.
        for (var i = 0; i < _currentPageKeys.size(); i++) {
            var key = _currentPageKeys[i];
            var tileMetaData = Storage.getValue(metaKey(key));

            if (tileMetaData instanceof Array && tileMetaData.size() >= 3) {
                var expiresAt = tileMetaData[2] as Number;
                if (expired(expiresAt, epoch)) {
                    oldestKey = key; // Found an expired tile, evict immediately.
                    break;
                }

                var lastUsed = tileMetaData[0] as Number;
                if (oldestTime == null || oldestTime > lastUsed) {
                    oldestTime = lastUsed;
                    oldestKey = key;
                }
            } else {
                // Corrupted/dangling entry, evict immediately.
                oldestKey = key;
                break;
            }
        }

        if (oldestKey != null) {
            deleteByMetaData(oldestKey);
            _currentPageKeys.remove(oldestKey);
            _pageSizes[_currentPageIndex]--;
            _totalTileCount--;
            // The calling function is responsible for saving the page and total count.
            logT("Evicted tile " + oldestKey + " from page " + _currentPageIndex);
        }
    }

    private function evictLeastRecentlyUsedTile() as Void {
        // so that we do not read every page and every tile we just evict from the next page in the list
        // this may not actually remove a tile if the page is empty
        // the tiles are meant to be spread out evenly across pages though, if they are not, none of the assumptions in the class help
        _lastEvictedPageIndex = (_lastEvictedPageIndex + 1) % _pageCount;
        loadPage(_lastEvictedPageIndex);

        // single shot try to get a non-empty page (incredibly rare case)
        if (_currentPageKeys.size() == 0) {
            _lastEvictedPageIndex = (_lastEvictedPageIndex + 1) % _pageCount;
            loadPage(_lastEvictedPageIndex);
        }

        evictOldestTileFromPage();
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

    // if this setting is changed whist the app is not running it will leave tile dangling in storage, and we have no way to know they are there, so guess thats up to the user to clear the storage
    // or we could try every page on startup?
    function setNewPageCount(newPageCount as Number) as Void {
        if (newPageCount == _pageCount) {
            return;
        }

        // we need to purge everything, otherwise we will look in the wrong page for a tile
        clearValues();

        // set ourselves up for the enw partition strategy
        _pageCount = newPageCount;
        pageCountUpdated();
    }
    function clearValues() as Void {
        for (var i = 0; i < _pageCount; i++) {
            loadPage(i);
            var keys = _currentPageKeys;
            for (var j = 0; j < keys.size(); j++) {
                deleteByMetaData(keys[j]);
            }
            Storage.deleteValue(pageStorageKey(i));
        }
        _currentPageKeys = [];
        _currentPageIndex = -1;
        _totalTileCount = 0;
        Storage.deleteValue("totalTileCount");
        for (var i = 0; i < _pageCount; i++) {
            _pageSizes[i] = 0;
        }
    }
}

class TileCache {
    var _internalCache as Dictionary<String, Tile>;
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
        _internalCache = ({}) as Dictionary<String, Tile>;
        _storageTileCache = new StorageTileCache(_settings);

        // note: these need to match whats in the app
        // would like to use the bitmaps colour pallet, but we cannot :( because it errors with
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
            logE("colour pallet has only: " + _palette.size() + "elements");
        }

        // loadPersistedTiles();
    }

    function setup() as Void {
        _storageTileCache.setup();
    }

    public function clearValues() as Void {
        clearValuesWithoutStorage();
        // whenever we purge the tile cache it is usually because the tile server properties have changed, safest to nuke the storage cache too
        // though sme times its when the in memory tile cache size changes
        // users should not be modifying the tile settings in any way, otherwise the storage will also be out of date (eg. when tile size or tile url changes)
        _storageTileCache.clearValues();
    }

    public function clearValuesWithoutStorage() as Void {
        _internalCache = ({}) as Dictionary<String, Tile>;
        _errorBitmaps = ({}) as Dictionary<String, WeakReference<Graphics.BufferedBitmap> >;
        _tileCacheVersion++;
    }

    // loads a tile into the cache
    // returns true if seed should stop and wait for next calculate (to prevent watchdog errors)
    function seedTile(x as Number, y as Number, z as Number) as Boolean {
        var tileKeyStr = tileKeyHash(x, y, z);
        var tile = _internalCache[tileKeyStr] as Tile?;
        if (tile != null) {
            var epoch = Time.now().value();
            if (!tile.expiredAlready(epoch)) {
                return false;
            }
        }
        return startSeedTile(tileKeyStr, x, y, z, false);
    }

    // seedTile puts the tile into memory, either by pulling from storage, or by runnung a web request
    // seedTileToStorage only puts the tile into storage
    // returns true if a tile seed was started, flase if we already have the tile
    function seedTileToStorage(
        tileKeyStr as String,
        x as Number,
        y as Number,
        z as Number
    ) as Boolean {
        if (_storageTileCache.haveTile(x, y, z, tileKeyStr)) {
            // we already have the tile (and it is not expired)
            return false;
        }

        startSeedTile(tileKeyStr, x, y, z, true);
        return true;
    }

    // returns true if seed should stop and wait for next calculate (to prevent watchdog errors)
    private function startSeedTile(
        tileKeyStr as String,
        x as Number,
        y as Number,
        z as Number,
        onlySeedStorage as Boolean
    ) as Boolean {
        // logT("starting load tile: " + x + " " + y + " " + z);

        if (!_settings.tileUrl.equals(COMPANION_APP_TILE_URL)) {
            return seedImageTile(tileKeyStr, x, y, z, onlySeedStorage);
        }

        return seedCompanionAppTile(tileKeyStr, x, y, z, onlySeedStorage);
    }

    (:noImageTiles)
    function seedImageTile(
        tileKeyStr as String,
        x as Number,
        y as Number,
        z as Number,
        onlySeedStorage as Boolean
    ) as Boolean {
        return false;
    }
    (:imageTiles)
    function seedImageTile(
        tileKeyStr as String,
        _x as Number,
        _y as Number,
        _z as Number,
        onlySeedStorage as Boolean
    ) as Boolean {
        // logD("small tile: " + tileKey + " scaledTileSize: " + _settings.scaledTileSize + " tileSize: " + _settings.tileSize);
        var x = _x / _cachedValues.smallTilesPerScaledTile;
        var y = _y / _cachedValues.smallTilesPerScaledTile;
        var fullSizeTileStr = tileKeyHash(x, y, _z);
        // logD("fullSizeTile tile: " + fullSizeTile);
        var imageReqHandler = new ImageWebTileRequestHandler(
            me,
            x,
            y,
            _z,
            tileKeyStr,
            fullSizeTileStr,
            _tileCacheVersion,
            onlySeedStorage
        );
        var tileFromStorage = _storageTileCache.get(x, y, _z, fullSizeTileStr);
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
            addErroredTile(tileKeyStr, _tileCacheVersion, "S404", true);
            return true; // this could be a complicated op if we are getting all these tiles from storage
        }
        _webRequestHandler.add(
            new ImageRequest(
                "im" + tileKeyStr + "-" + _tileCacheVersion, // the hash is for the small tile request, not the big one (they will send the same physical request out, but again use 256 tilSize if your using external sources)
                stringReplaceFirst(
                    stringReplaceFirst(
                        stringReplaceFirst(
                            stringReplaceFirst(_settings.tileUrl, "{x}", x.toString()),
                            "{y}",
                            y.toString()
                        ),
                        "{z}",
                        _z.toString()
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

    (:noCompanionTiles)
    function seedCompanionAppTile(
        tileKeyStr as String,
        _x as Number,
        _y as Number,
        _z as Number,
        onlySeedStorage as Boolean
    ) as Boolean {
        return false;
    }

    (:companionTiles)
    function seedCompanionAppTile(
        tileKeyStr as String,
        _x as Number,
        _y as Number,
        _z as Number,
        onlySeedStorage as Boolean
    ) as Boolean {
        // logD("small tile (companion): " + tileKey + " scaledTileSize: " + _settings.scaledTileSize + " tileSize: " + _settings.tileSize);
        var jsonWebHandler = new JsonWebTileRequestHandler(
            me,
            _x,
            _y,
            _z,
            tileKeyStr,
            _tileCacheVersion,
            onlySeedStorage
        );
        var tileFromStorage = _storageTileCache.get(_x, _y, _z, tileKeyStr);
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
            addErroredTile(tileKeyStr, _tileCacheVersion, "S404", true);
            return true; // this could be a complicated op if we are getting all these tiles from storage
        }
        _webRequestHandler.add(
            new JsonRequest(
                "json" + tileKeyStr + "-" + _tileCacheVersion,
                _settings.tileUrl + "/loadtile",
                {
                    "x" => _x,
                    "y" => _y,
                    "z" => _z,
                    "scaledTileSize" => _settings.scaledTileSize,
                    "tileSize" => _settings.tileSize,
                },
                jsonWebHandler
            )
        );
        return false;
    }

    // puts a tile into the cache
    function addTile(tileKeyStr as String, tileCacheVersion as Number, tile as Tile) as Void {
        if (tileCacheVersion != _tileCacheVersion) {
            return;
        }

        tile.setExpiresAt(NO_EXPIRY); // be explicit that there is no expiry

        if (_internalCache.size() == _settings.tileCacheSize) {
            evictLeastRecentlyUsedTile();
        }

        _internalCache[tileKeyStr] = tile;
    }

    function addErroredTile(
        tileKeyStr as String,
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
                _internalCache[tileKeyStr] = tile;
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
        _internalCache[tileKeyStr] = tile;
    }

    // gets a tile that was stored by seedTile
    function getTile(x as Number, y as Number, z as Number) as Tile? {
        var tileKeyStr = tileKeyHash(x, y, z);
        var tile = _internalCache[tileKeyStr] as Tile?;
        if (tile != null) {
            // logT("cache hit: " + x  + " " + y + " " + z);
            _hits++;
            tile.markUsed();
            return tile;
        }

        // logT("cache miss: " + x  + " " + y + " " + z);
        // logT("have tiles: " + _internalCache.keys());
        _misses++;
        return null;
    }

    function haveTile(tileKeyStr as String) as Boolean {
        return _internalCache.hasKey(tileKeyStr);
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
            // logT("Evicted tile " + oldestKey + " from internal cache");
        }
    }

    (:noCompanionTiles)
    function tileDataToBitmap64ColourString(charArr as Array<Char>?) as Graphics.BufferedBitmap? {
        return null;
    }
    (:companionTiles)
    function tileDataToBitmap64ColourString(charArr as Array<Char>?) as Graphics.BufferedBitmap? {
        // logT("tile data " + arr);
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
            logE("got a bad type somehow? 64colour: " + charArr);
            return null;
        }

        if (charArr.size() < requiredSize) {
            logE("tile length too short 64colour: " + charArr.size());
            return null;
        }

        if (charArr.size() != requiredSize) {
            // we could load tile partially, but that would require checking each itteration of the for loop,
            // want to avoid any extra work for perf
            logE("bad tile length 64colour: " + charArr.size() + " best effort load");
        }

        // logT("processing tile data, first colour is: " + arr[0]);

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
        // logT("tile data " + arr);
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
            logE("got a bad type somehow? b&w: " + charArr);
            return null;
        }

        if (charArr.size() < requiredSize) {
            logT("tile length too short b&w: " + charArr.size());
            return null;
        }

        if (charArr.size() != requiredSize) {
            // we could load tile partially, but that would require checking each itteration of the for loop,
            // want to avoid any extra work for perf
            logE("bad tile length b&w: " + charArr.size() + " best effort load");
        }

        // logT("processing tile data, first colour is: " + arr[0]);

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
        // logT("tile data " + arr);
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
            logE("got a bad full colour type somehow?: " + mapTileBytes);
            return null;
        }

        if (mapTileBytes.size() < requiredSize) {
            logE("tile length too short full colour: " + mapTileBytes.size());
            return null;
        }

        if (mapTileBytes.size() != requiredSize) {
            // we could load tile partially, but that would require checking each itteration of the for loop,
            // want to avoid any extra work for perf
            logE("bad tile length full colour: " + mapTileBytes.size() + " best effort load");
        }

        mapTileBytes.add(0x00); // add a byte to the end so the last 24bit colour we parse still has 32 bits of data

        // logT("processing tile data, first colour is: " + arr[0]);

        // todo check if setting the pallet actually reduces memory
        var localBitmap = newBitmap(tileSize, tileSize);
        var localDc = localBitmap.getDc();
        var offset = 0;
        for (var i = 0; i < tileSize; ++i) {
            for (var j = 0; j < tileSize; ++j) {
                // probably a faster way to do this
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
