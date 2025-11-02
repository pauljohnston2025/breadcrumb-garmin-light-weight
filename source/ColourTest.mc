import Toybox.Lang;
import Toybox.Test;

(:test,:debug)
function parseColourRawAllFsOlder2x4Devices(logger as Logger) as Boolean {
    var colour = Settings.parseColourRaw("ignoredKey", "FFFFFFFF", 0);
    logger.debug("All Fs colour is: " + colour);
    return colour == 0xffffff;
}

(:test,:debug)
function parseColourRawAllFs(logger as Logger) as Boolean {
    var colour = Settings.parseColourRaw("ignoredKey", "FFFFFFFF", 0);
    logger.debug("All Fs colour is: " + colour);
    return colour == 0xfeffffff;
}

(:test,:debug)
function parseColourRawMostlyFs(logger as Logger) as Boolean {
    var colour = Settings.parseColourRaw("ignoredKey", "FEFFFFFF", 0);
    logger.debug("Mostly Fs colour is: " + colour);
    return colour == 0xfeffffff;
}

(:test,:debug)
function parseColourRawMostlyFs2(logger as Logger) as Boolean {
    var colour = Settings.parseColourRaw("ignoredKey", "FDFFFFFF", 0);
    logger.debug("Mostly Fs2 colour is: " + colour);
    return colour == 0xfdffffff;
}

(:test,:debug)
function parseColourPartial(logger as Logger) as Boolean {
    var colour = Settings.parseColourRaw("ignoredKey", "abcd", 0);
    return colour == 0xabcd;
}

(:test,:debug)
function parseColourDefaults(logger as Logger) as Boolean {
    var colour = Settings.parseColourRaw("ignoredKey", "yabc", 3);
    logger.debug("Colour defaults is: " + colour);
    return colour == 3;
}
