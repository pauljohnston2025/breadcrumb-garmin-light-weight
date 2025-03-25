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

// should be a multiple of 256 (since thats how tiles are stored, though the companion app will render them scaled for you)
// we will support rounding up though. ie. if we use 50 the 256 tile will be sliced into 6 chunks on the phone, this allows us to support more pixel sizes. 
// so math.ceil should be used what figuring out how many meters a tile is.
// eg. maybe we cannot do 128 but we can do 120 (this would limit the number of tiles, but the resolution would be slightly off)
const DATA_TILE_SIZE = 64; 

// there is both a memory limit to the number of tiles we can store, as well as a storage limit
// for now this is both, though we may be abel to store more than we can in memory 
// so we could use the storage as a tile cache, and revert to loading from there, as it would be much faster than 
// fetching over bluetooth
// not sure if we can even store bitmaps into storage, it says only BitmapResource
// id have to serialise it to an array and back out (might not be too hard)
const MEMORY_CACHED_TILES = 64; // enough to render outside the screen a bit 64*64 tiles with 64 tiles gives us 512*512 worth of pixel data

const TILE_PALLET_MODE_OPTIMISED_STRING = 1;
const TILE_PALLET_MODE_LIST = 2;
const TILE_PALLET_MODE_OPTIMISED_STRING_WITH_PALLET = 3;
const TILE_PALLET_MODE = TILE_PALLET_MODE_OPTIMISED_STRING_WITH_PALLET;

function tileKey(x as Number, y as Number, z as Number) as String {
    // do not return tuple, they cannot be used to compare equality
    return Lang.format("$1$-$2$-$3$", [x, y, z]);
}

class Tile {
    var x as Number;
    var y as Number;
    var z as Number;
    var lastUsed as Time.Moment = Time.now();
    var bitmap as Graphics.BufferedBitmap or Null;
    var storageIndex as Number or Null;

    function initialize(x as Number, y as Number, z as Number) {
        self.x = x;
        self.y = y;
        self.z = z;
        self.bitmap = null;
        self.storageIndex = null;
    }

    function setBitmap(bitmap as Graphics.BufferedBitmap) as Void {
        self.bitmap = bitmap;
    }

    function markUsed() as Void
    {
        lastUsed = Time.now();
    }

    function setStorageIndex(storageIndex as Number) as Void {
        self.storageIndex = storageIndex;
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
    static function deserializeFromDictionary(data as Dictionary) as Tile or Null {
        if (!data.hasKey("x") || !data.hasKey("y") || !data.hasKey("z"))
        {
            return null;    
        }

        return new Tile(
            data["x"] as Number, 
            data["y"] as Number, 
            data["z"] as Number
        );
    }
}

class WebTileRequestHandler extends WebHandler {
    var _tileCache as TileCache;
    var _x as Number;
    var _y as Number;
    var _z as Number;

    function initialize(
        tileCache as TileCache,
        x as Number, 
        y as Number,
        z as Number)
    {
        WebHandler.initialize();
        _tileCache = tileCache;
        _x = x;
        _y = y;
        _z = z;
    }

    function handle(responseCode as Number, data as Dictionary or String or Iterator or Null) as Void
    {
        if (responseCode != 200)
        {
            // see error codes such as Communications.NETWORK_REQUEST_TIMED_OUT
            System.println("failed with: " + responseCode);
            return;
        }

        if (!(data instanceof Dictionary))
        {
            System.println("wrong data type, not dict");
            return;
        }

        // System.print("data: " + data);
        if (TILE_PALLET_MODE == TILE_PALLET_MODE_OPTIMISED_STRING || TILE_PALLET_MODE == TILE_PALLET_MODE_OPTIMISED_STRING_WITH_PALLET)
        {
            var mapTile = data["data"];
            if (!(mapTile instanceof String))
            {
                System.println("wrong data type, not string");
                return;
            }
            var tile = new Tile(_x, _y, _z);
            var mapTileStr = mapTile as String;
            // System.println("got tile string of length: " + mapTileStr.length());
            var bitmap = _tileCache.tileDataToBitmap(mapTileStr.toUtf8Array());
            if (bitmap == null)
            {
                System.println("failed to parse bitmap");
                return;
            }

            tile.setBitmap(bitmap);
            _tileCache.addTile(tile);
            return;
        }
        else if (TILE_PALLET_MODE == TILE_PALLET_MODE_LIST) 
        {
            var mapTile = data["data"];
            var tile = new Tile(_x,  _y, _z);
            var bitmap = _tileCache.tileDataToBitmap(mapTile as Array<Number>);
            if (bitmap == null)
            {
                System.println("failed to parse bitmap LIST MODE");
                return;
            }

            tile.setBitmap(bitmap);
            _tileCache.addTile(tile);
            return;
        }
        else
        {
            System.println("unrecognised tile mode: " + TILE_PALLET_MODE);
            return;
        }
    }
}

class TileCache {
    var _internalCache as Dictionary;
    var _webRequestHandler as WebRequestHandler;
    var _palette as Array<Number>;

    function initialize(webRequestHandler as WebRequestHandler) {
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

    // loads a tile into the cache
    function seedTile(x as Number, y as Number, z as Number) as Void {
        if (haveTile(x, y, z))
        {
            return;
        }

        // System.println("starting load tile: " + x + " " + y + " " + z);
        _webRequestHandler.add(
            new JsonRequest(
                "/loadtile",
                {
                    "x" => x,
                    "y" => y,
                    "z" => z,
                    "tileSize" => DATA_TILE_SIZE,
                },
                new WebTileRequestHandler(me, x, y, z)
            )
        );
    }

    // puts a tile into the cache
    function addTile(tile as Tile) as Void {
        if (_internalCache.size() == MEMORY_CACHED_TILES)
        {
            evictLeastRecentlyUsedTile();
        }

        _internalCache[tileKey(tile.x, tile.y, tile.z)] = tile;
    }
    
    // gets a tile that was stored by seedTile
    function getTile(x as Number, y as Number, z as Number) as Tile or Null {
        var key = tileKey(x, y, z);

        var tile = _internalCache[key] as Tile or Null;
        if (tile != null)
        {
            // System.println("cache hit: " + x  + " " + y + " " + z);
            tile.markUsed();
            return tile;
        }

        // System.println("cache miss: " + x  + " " + y + " " + z);
        // System.println("have tiles: " + _internalCache.keys());
        return null;
    }
    
    function haveTile(x as Number, y as Number, z as Number) as Boolean {
        var key = tileKey(x, y, z);

        return _internalCache.hasKey(key);
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
            if (oldestTime == null || oldestTime.greaterThan(tile.lastUsed)) {
                oldestTime = tile.lastUsed;
                oldestKey = key;
            }
        }

        if (oldestKey != null) {
            _internalCache.remove(oldestKey);
            System.println("Evicted tile " + oldestKey + " from internal cache");
        }
    }

    function tileDataToBitmap(arr as Array<Number>) as Graphics.BufferedBitmap or Null
    {
        // System.println("tile data " + arr);

        if (arr.size() < DATA_TILE_SIZE*DATA_TILE_SIZE)
        {
            System.println("tile length too short: " + arr.size());
            return null;
        }

        if (arr.size() != DATA_TILE_SIZE*DATA_TILE_SIZE)
        {
            // we could load tile partially, but that would require checking each itteration of the for loop, 
            // want to avoid any extra work for perf
            System.println("bad tile length: " + arr.size() + " best effort load");
        }

        // System.println("processing tile data, first colour is: " + arr[0]);

        var localBitmap = newBitmap(TILE_SIZE);
        var localDc = localBitmap.getDc();
        var it = 0;
        for (var i=0; i<DATA_TILE_SIZE; ++i)
        {
            for (var j=0; j<DATA_TILE_SIZE; ++j)
            {
                var colour = null;
                if (TILE_PALLET_MODE == TILE_PALLET_MODE_OPTIMISED_STRING)
                {
                    var byteColour = arr[it] as Number;
                    // System.println("processing colour" + byteColour);
                    // 2 bits per colour (todo set up colour pallete instead)
                    var red = ((byteColour & 0x030) >> 4) * 255 / 3;
                    var green = ((byteColour & 0x0C) >> 2) * 255 / 3;
                    var blue = (byteColour & 0x03) * 255 / 3;
                    colour = (red << 16) | (green << 8) | blue;
                }
                else if (TILE_PALLET_MODE == TILE_PALLET_MODE_OPTIMISED_STRING_WITH_PALLET)
                {
                    var byteColour = arr[it] as Number;
                    colour = _palette[byteColour & 0x3F];
                }
                else if (TILE_PALLET_MODE == TILE_PALLET_MODE_LIST) 
                {
                    colour = arr[it] as Number;
                }
                else
                {
                    System.println("unrecognised tile mode: " + TILE_PALLET_MODE);
                    return null;
                }
                
                it++;
                localDc.setColor(colour, colour);
                if (PIXEL_SIZE == 1)
                {
                    localDc.drawPoint(i, j);
                }
                else {
                    localDc.fillRectangle(i * PIXEL_SIZE, j * PIXEL_SIZE, PIXEL_SIZE, PIXEL_SIZE);
                }
            }
        }

        return localBitmap;
    }
}