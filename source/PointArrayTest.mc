import Toybox.Lang;
import Toybox.Test;

(:test)
function latLon2xyTest(logger as Logger) as Boolean {
  var point = RectangularPoint.latLon2xy(-27.492250, 153.030049, 123.4);
  logger.debug("point = " + point);
  return point.x == 17035226.0 && point.y == -3185107.25 && point.altitude == 123.4;
}

(:test)
function latLon2xyTest2(logger as Logger) as Boolean {
  var point = RectangularPoint.latLon2xy(-26.492250, 153.030049, 123.4);
  logger.debug("point = " + point);
  return point.x == 17035226.0 && point.y == -3060177.500000 && point.altitude == 123.4;
}

(:test)
function latLon2xyRoundTrip(logger as Logger) as Boolean {
  var lat = -26.492250;
  var long = 153.030049;
  var point = RectangularPoint.latLon2xy(lat, long, 123.4);
  var latlong = RectangularPoint.xyToLatLon(point.x, point.y);

  Test.assert(latlong != null);
  logger.debug(latlong[0]);
  logger.debug(latlong[1]);
  Test.assert((lat - latlong[0]) < 0.001f);
  Test.assert((long - latlong[1]) < 0.001f);
  return true;
}