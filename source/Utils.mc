import Toybox.Lang;
import Toybox.System;
import Toybox.Graphics;
import Toybox.Time;

const FLOAT_MIN = -340282346638528859811704183484516925440.0;
const FLOAT_MAX = 340282346638528859811704183484516925440.0;
const NUMBER_MAX = 0x7fffffff;

(:release)
function isSimulator() as Boolean {
    return false;
}

(:debug)
function isSimulator() as Boolean {
    var simulators = ["9f8a103dbb3fe23a4c02a601d429c4c677f2908d"];
    System.println("deviceID: " + System.getDeviceSettings().uniqueIdentifier);
    if (simulators.indexOf(System.getDeviceSettings().uniqueIdentifier) > -1) {
        System.println("simulator detected");
        return true;
    }

    return false;
}

function maxF(lhs as Float, rhs as Float) as Float {
    if (lhs > rhs) {
        return lhs;
    }

    return rhs;
}

function maxN(lhs as Number, rhs as Number) as Number {
    if (lhs > rhs) {
        return lhs;
    }

    return rhs;
}

function minF(lhs as Float, rhs as Float) as Float {
    if (lhs < rhs) {
        return lhs;
    }

    return rhs;
}

function minN(lhs as Number, rhs as Number) as Number {
    if (lhs < rhs) {
        return lhs;
    }

    return rhs;
}

function abs(val as Float) as Float {
    if (val < 0) {
        return -val;
    }

    return val;
}

// from https://forums.garmin.com/developer/connect-iq/f/discussion/338071/testing-for-nan/1777041#1777041
function isnan(a as Float) as Boolean {
    return a != a;
}

class BitmapCreateError extends Lang.Exception {
    function initialize() {
        Exception.initialize();
    }

    function getErrorMessage() as String? {
        return "failed btmap create";
    }
}

// https://developer.garmin.com/connect-iq/core-topics/graphics/#graphics
// we must call get and keep the reference otherwise it can get cleanup up from under us
// not too bad for temporaries, but terrible for tiles (they can not be garbage collected)
function newBitmap(width as Number, height as Number) as Graphics.BufferedBitmap {
    var options = {
        :width => width,
        :height => height,
    };

    var bitmap = Graphics.createBufferedBitmap(options).get();
    if (!(bitmap instanceof BufferedBitmap)) {
        System.println("Could not allocate buffered bitmap");
        throw new BitmapCreateError();
    }

    return bitmap;
}

// todo inline with prettier and only log in debug builds
// todo log levels (problably seperate functions)
function log(message as String) as Void {
    logLevel("D", message);
}

function logLevel(lvl as String, message as String) as Void {
    System.println("" + Time.now().value() + " " + lvl + " " + message);
}

function logE(message as String) as Void {
    logLevel("E", message);
}

function logD(message as String) as Void {
    logLevel("D", message);
}

// todo (perf): make these inline functions, and set options for vivoactive so these functions result in a direct call to dc
// only  way to set colour of text is through setColour, which does not support alpha channel, so reverting these changes
function setFillHelper(dc as Dc, colour as Number) as Void {
    if (dc has :setFill) {
        // vivoactive does not have setFill
        dc.setFill(colour);
        return;
    }

    dc.setColor(colour, colour);
}

function setStrokeHelper(dc as Dc, colour as Number) as Void {
    if (dc has :setStroke) {
        // vivoactive does not have setStroke
        dc.setStroke(colour);
        return;
    }

    dc.setColor(colour, colour);
}

(:scaledbitmap)
function drawScaledBitmapHelper(
    dc as Dc,
    x as Numeric,
    y as Numeric,
    width as Numeric,
    height as Numeric,
    bitmap as BitmapType
) as Void {
    dc.drawScaledBitmap(x, y, width, height, bitmap);
}

(:noscaledbitmap)
function drawScaledBitmapHelper(
    dc as Dc,
    x as Numeric,
    y as Numeric,
    width as Numeric,
    height as Numeric,
    bitmap as BitmapType
) as Void {
    // is there any reason not to move this into main code and just use AffineTransform every time - even for devices that support drawScaledBitmap?
    // I assume one has a performance benifit over the other?
    // need to test which is better (or if there is any noticible difference)
    // todo cache this transform so we do nto need to recreate every time
    var tileScaleFactor = getApp()._breadcrumbContext.cachedValues().tileScaleFactor;
    var scaleMatrix = new AffineTransform();
    scaleMatrix.scale(tileScaleFactor, tileScaleFactor); // scale
    try {
        dc.drawBitmap2(x, y, bitmap, {
            :transform => scaleMatrix,
            // Use bilinear filtering for smoother results when rotating/scaling (less noticible tearing)
            :filterMode => Graphics.FILTER_MODE_BILINEAR,
        });
    } catch (e) {
        logE("failed drawBitmap2: " + e.getErrorMessage());
        ++$.globalExceptionCounter;
    }
}

function padStart(str as String?, targetLength as Number, padChar as Char) as String {
    var currentStr = str == null ? "" : str;
    var currentLength = currentStr.length();

    if (targetLength <= 0 || currentLength >= targetLength) {
        return currentStr; // No padding needed or invalid target length
    }

    var paddingNeeded = targetLength - currentLength;
    var padding = "";

    // Build the padding string
    // Note: Repeated string concatenation can be inefficient in MonkeyC
    // for VERY long padding, but is usually fine for typical use cases.
    for (var i = 0; i < paddingNeeded; i++) {
        padding += padChar;
    }

    return padding + currentStr;
}

function stringReplaceFirst(
    originalString as String,
    target as String,
    replacement as String
) as String {
    var index = originalString.find(target);

    if (index == null) {
        return originalString; // Target not found, return original string
    }

    var newString =
        originalString.substring(0, index) +
        replacement +
        originalString.substring(index + target.length(), originalString.length());

    return newString;
}

function isHttpResponseCode(responseCode as Number) as Boolean
{
    return responseCode > 0;
}
