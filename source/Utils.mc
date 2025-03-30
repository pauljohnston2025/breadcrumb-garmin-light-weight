import Toybox.Lang;
import Toybox.System;
import Toybox.Graphics;

const FLOAT_MIN = -340282346638528859811704183484516925440.0000000000000000;
const FLOAT_MAX = 340282346638528859811704183484516925440.0000000000000000;

(:release)
function isSimulator() as Boolean {
  return false;
}

(:debug)
function isSimulator() as Boolean {
  var simulators = ["9f8a103dbb3fe23a4c02a601d429c4c677f2908d"];
  System.println("deviceID: " + System.getDeviceSettings().uniqueIdentifier);
  if (simulators.indexOf(System.getDeviceSettings().uniqueIdentifier) > -1)
  {
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
  if (val < 0)
  {
    return -val;
  }

  return val;
}

// from https://forums.garmin.com/developer/connect-iq/f/discussion/338071/testing-for-nan/1777041#1777041
function isnan(a as Float) as Boolean {
  return a != a;
}

// https://developer.garmin.com/connect-iq/core-topics/graphics/#graphics
// we must call get and keep the reference otherwise it can get cleanup up from under us
// not too bad for temporaries, but terrible for tiles (they can not be garbage collected)
function newBitmap(size as Number, palette as Array or Null) as Graphics.BufferedBitmap
{
    var options = {
      :width => size,
      :height => size,
      :palette => palette,
    };

    var bitmap = Graphics.createBufferedBitmap(options).get();
    if (!(bitmap instanceof BufferedBitmap))
    {
        System.println("Could not allocate buffered bitmap");
        throw new Exception();
    }

    return bitmap;
}

// todo inline with prettier and only log in debug builds
// todo log levels (problably seperate functions)
function log(message as String) as Void
{
  logLevel("D", message);
}

function logLevel(lvl as String, message as String) as Void
{
  System.println("" + System.getTimer() + " " + lvl + " " + message);
}

function logE(message as String) as Void
{
  logLevel("E", message);
}

function stringReplaceFirst(originalString as String, target as String, replacement as String) as String {
    var index = originalString.find(target);

    if (index == null) {
        return originalString; // Target not found, return original string
    }

    var newString = originalString.substring(0, index) +
                    replacement +
                    originalString.substring(index + target.length(), originalString.length());

    return newString;
}