import Toybox.Application;
import Toybox.Lang;
import Toybox.Graphics;
import Toybox.System;

enum /*Mode*/ {
  MODE_NORMAL,
  MODE_ELEVATION,
  MODE_MAX,
}

class Settings {
    // should be a multiple of 256 (since thats how tiles are stored, though the companion app will render them scaled for you)
    // we will support rounding up though. ie. if we use 50 the 256 tile will be sliced into 6 chunks on the phone, this allows us to support more pixel sizes. 
    // so math.ceil should be used what figuring out how many meters a tile is.
    // eg. maybe we cannot do 128 but we can do 120 (this would limit the number of tiles, but the resolution would be slightly off)
    var tileSize as Number = 64;
    // there is both a memory limit to the number of tiles we can store, as well as a storage limit
    // for now this is both, though we may be able to store more than we can in memory 
    // so we could use the storage as a tile cache, and revert to loading from there, as it would be much faster than 
    // fetching over bluetooth
    // not sure if we can even store bitmaps into storage, it says only BitmapResource
    // id have to serialise it to an array and back out (might not be too hard)
    // 64 is enough to render outside the screen a bit 64*64 tiles with 64 tiles gives us 512*512 worth of pixel data
    var tileCacheSize as Number = 64; // represented in number of tiles, parsed from a string eg. "64"=64tiles, "100KB"=100/2Kb per tile = 50 
    var mode as Number = MODE_NORMAL;
    // todo clear tile cache when this changes
    var mapEnabled as Boolean = true;
    var trackColour as Number = Graphics.COLOR_GREEN;
    var routeColour as Number = Graphics.COLOR_BLUE;
    var elevationColour as Number = Graphics.COLOR_ORANGE;

    // calculated whenever others change
    var smallTilesPerBigTile = Math.ceil(256f/tileSize);
    
    // todo add support for
    var userColour as Number = Graphics.COLOR_ORANGE;

    function initialize() {
        loadSettings();
    }

    function setMode(_mode as Number) as Void {
        mode = _mode;
        Application.Properties.setValue("mode", mode);
    }

    function nextMode() as Void
    {
        // System.println("mode cycled");
        // could just add one and check if over MODE_MAX?
        mode++;
        if (mode >= MODE_MAX)
        {
            mode = MODE_NORMAL;
        }

        setMode(mode);
    }

    function parseTileCacheSizeString(sizeString as String, _tileSize as Number) as Number {
        try {
            var unit = sizeString.substring(sizeString.length() - 2, sizeString.length()); // Extract unit ("KB")
            if (unit.equals("KB")) {
                var value = sizeString.substring(0, sizeString.length() - 2).toNumber();
                // todo figure out a sane value for _memoryKbPerPixel
                // probably better to just specify a number
                var memoryKbPerPixel = 1;
                return value / (memoryKbPerPixel * _tileSize * _tileSize);
            }

            return sizeString.toNumber();
        } 
        catch (e) {
            logE("Error parsing tile size: " + sizeString);
        }

        return 64;
    }

    // Helper function to parse colour
    function parseColor(colorString as String, defaultValue as Number) as Number {
        try {
            return (colorString).toNumberWithBase(16);
        } catch (e) {
            System.println("Error parsing color: " + colorString);
        }
        return defaultValue;
    }

    // Load the values initially from storage
    function loadSettings() as Void {
        System.println("loadSettings: Loading all settings");
        tileSize = Application.Properties.getValue("tileSize") as Number;
        smallTilesPerBigTile = Math.ceil(256f/tileSize);

        var tileCacheSizeString = Application.Properties.getValue("tileCacheSize") as String;
        tileCacheSize = parseTileCacheSizeString(tileCacheSizeString, tileSize);
        mode = Application.Properties.getValue("mode") as Number;
        mapEnabled = Application.Properties.getValue("mapEnabled") as Boolean;
        trackColour = parseColor(Application.Properties.getValue("trackColour") as String, Graphics.COLOR_GREEN);
        routeColour = parseColor(Application.Properties.getValue("routeColour") as String, Graphics.COLOR_BLUE);
        elevationColour = parseColor(Application.Properties.getValue("elevationColour") as String, Graphics.COLOR_ORANGE);

    }

    //Called on settings change
   function onSettingsChanged() as Void {
        System.println("onSettingsChanged: Setting Changed, loading");
        loadSettings();
    }
}