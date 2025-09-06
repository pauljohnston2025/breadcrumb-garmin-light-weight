import Toybox.Position;
import Toybox.Lang;
import Toybox.Activity;
import Toybox.Math;
import Toybox.Application;
import Toybox.System;

const ARRAY_POINT_SIZE = 12;
const DIRECTION_ARRAY_POINT_SIZE = 13;

// cached values
// we should probbaly do this per latitude to get an estimate and just use a lookup table
const _lonConversion as Float = 20037508.34f / 180.0f;
const _pi360 as Float = Math.PI / 360.0f;
const _pi180 as Float = Math.PI / 180.0f;

class RectangularPoint {
    var x as Float;
    var y as Float;
    var altitude as Float;

    function initialize(_x as Float, _y as Float, _altitude as Float) {
        x = _x;
        y = _y;
        altitude = _altitude;
    }

    function distanceTo(point as RectangularPoint) as Float {
        return distance(point.x, point.y, x, y);
    }

    function valid() as Boolean {
        return !isnan(x) && !isnan(y) && !isnan(altitude);
    }

    function toString() as String {
        return "RectangularPoint(" + x + " " + y + " " + altitude + ")";
    }

    function clone() as RectangularPoint {
        return new RectangularPoint(x, y, altitude);
    }

    function rescale(scaleFactor as Float) as RectangularPoint {
        // unsafe to call with nulls or 0, checks should be made in parent
        return new RectangularPoint(x * scaleFactor, y * scaleFactor, altitude);
    }

    function rescaleInPlace(scaleFactor as Float) as Void {
        // unsafe to call with nulls or 0, checks should be made in parent
        x *= scaleFactor;
        y *= scaleFactor;
    }

    // inverse of https://gis.stackexchange.com/a/387677
    // Converting lat, lon (epsg:4326) into EPSG:3857
    // this function needs to exactly match Point.convert2XY on the companion app
    static function latLon2xy(lat as Float, lon as Float, altitude as Float) as RectangularPoint? {
        var latRect = (Math.ln(Math.tan((90 + lat) * _pi360)) / _pi180) * _lonConversion;
        var lonRect = lon * _lonConversion;

        var point = new RectangularPoint(lonRect.toFloat(), latRect.toFloat(), altitude);
        if (!point.valid()) {
            return null;
        }

        return point;
    }

    // should be the inverse of latLon2xy ie. https://gis.stackexchange.com/a/387677
    static function xyToLatLon(x as Float, y as Float) as [Float, Float]? {
        // Inverse Mercator projection formulas
        var lon = x / _lonConversion; // Longitude (degrees)
        var lat = Math.atan(Math.pow(Math.E, (y / _lonConversion) * _pi180)) / _pi360 - 90;

        if (lat < -90 || lat > 90 || lon < -180 || lon > 180) {
            // logE("Invalid lat/lon values: " + lat + " " + lon);
            return null;
        }

        return [lat.toFloat(), lon.toFloat()];
    }
}

// this is to solve the issue of slice() returning a new array
// we want to instead allocate teh array to a max length, the just remove the last elements
// ie. bigArray = bigArray.slice(0, 100) will result in bigArray + 100 extra items untill big array is garbage collected
// this class allows us to just reduce bigArray to 100 elements in one go
class PointArray {
    // some stats on using byte array over array<float, float, float>
    // before changes (using array<float, float, float>)
    // Application Code: 100702
    // Application Data: 26192
    // route size:
    //  total: 6575
    //  coordinates._internalArrayBuffer: 5745
    //  directions // NA not sent on v2 payload (111 bytes of just the object)
    //
    // after changes (_internalArrayBufferBytes as ByteArray)
    // Application Code: 102427
    // Application Data: 26227
    // route size:
    //  total: 6677
    //  coordinates._internalArrayBufferBytes: 4599
    //  directions: 1263

    // note: the same route wiht no directions is a total of 5309 (1200 bytes saved, but we are now able to use them for direction storage)
    //
    // so we use ~100 bytes more per route/track (but the directions are included) - negligable (net 0 gain)
    // code size goes up by quite a bit though, 1725 bytes of extra code for a saveing of 1200 per route (assuming we have at least 1 route active and the current track this is a net saving of 675 bytes)
    // for users that do not have routes, this is actually a negative, but thats not our normal use case
    // for users trying to have 3 large route, this is a very good thing (saves 3075 bytes)
    // but don't forget, we have added directions support, so we actually have used more memory overall (1700bytes code space), but gained a new feature.

    // but now i think we get watchdog errors, before it was memory errors though :(
    // we get watchdog errors on 3 large routes ~400 points nand thats without a track
    // watchdog erros were in the rescale method, a relatively simple algorithm but now it has to do `x.encodeNumber(x.decodeNumber() * scale)` instead of just `x[i] = x[i] * scale`;
    // buts its also rescaling all the directions, so maybe its just the fact that we are at 400coords + 100 directions per route.

    // consider statically allocating the full size stright away (prevents remallocs in the underlying cpp code)
    var _internalArrayBufferBytes as ByteArray = []b;
    var _size as Number = 0;

    // not used, since wqe want to do optimised reads from the raw array
    // function get(i as Number) as Float
    // {
    //   return _internalArrayBuffer[i];
    // }

    function initialize(initalPointCount as Number) {
        _internalArrayBufferBytes = new [initalPointCount * ARRAY_POINT_SIZE]b;
        _size = 0;
    }

    function rescale(scaleFactor as Float) as Void {
        // unsafe to call with nulls or 0, checks should be made in parent
        // size is guaranteed to be a multiple of ARRAY_POINT_SIZE
        for (var i = 0; i < _internalArrayBufferBytes.size(); i += ARRAY_POINT_SIZE) {
            var oldX =
                _internalArrayBufferBytes.decodeNumber(Lang.NUMBER_FORMAT_FLOAT, {
                    :offset => i,
                    :endianness => Lang.ENDIAN_BIG,
                }) as Float;
            _internalArrayBufferBytes.encodeNumber(oldX * scaleFactor, Lang.NUMBER_FORMAT_FLOAT, {
                :offset => i,
                :endianness => Lang.ENDIAN_BIG,
            });
            var oldY =
                _internalArrayBufferBytes.decodeNumber(Lang.NUMBER_FORMAT_FLOAT, {
                    :offset => i + 4,
                    :endianness => Lang.ENDIAN_BIG,
                }) as Float;
            _internalArrayBufferBytes.encodeNumber(oldY * scaleFactor, Lang.NUMBER_FORMAT_FLOAT, {
                :offset => i + 4,
                :endianness => Lang.ENDIAN_BIG,
            });
        }
    }

    function add(point as RectangularPoint) as Void {
        _add(point.x);
        _add(point.y);
        _add(point.altitude);
    }

    function removeLastCountPoints(count as Number) as Void {
        resize(size() - count * ARRAY_POINT_SIZE);
    }

    function lastPoint() as RectangularPoint? {
        return getPoint(_size / ARRAY_POINT_SIZE - 1); // stack overflow if we call pointSize()
    }

    function firstPoint() as RectangularPoint? {
        return getPoint(0);
    }

    function getPoint(i as Number) as RectangularPoint? {
        if (i < 0) {
            return null;
        }

        if (i >= _size / ARRAY_POINT_SIZE) {
            return null;
        }

        var offset = i * ARRAY_POINT_SIZE;
        return new RectangularPoint(
            _internalArrayBufferBytes.decodeNumber(Lang.NUMBER_FORMAT_FLOAT, {
                :offset => offset,
                :endianness => Lang.ENDIAN_BIG,
            }) as Float,
            _internalArrayBufferBytes.decodeNumber(Lang.NUMBER_FORMAT_FLOAT, {
                :offset => offset + 4,
                :endianness => Lang.ENDIAN_BIG,
            }) as Float,
            _internalArrayBufferBytes.decodeNumber(Lang.NUMBER_FORMAT_FLOAT, {
                :offset => offset + 8,
                :endianness => Lang.ENDIAN_BIG,
            }) as Float
        );
    }

    function restrictPoints(maPoints as Number) as Boolean {
        // make sure we only have an acceptancbe amount of points
        // current process is to cull every second point
        // this means near the end of the track, we will have lots of close points
        // the start of the track will start getting more and more granular every
        // time we cull points
        if (size() / ARRAY_POINT_SIZE < maPoints) {
            return false;
        }

        // we need to do this without creating a new array, since we do not want to
        // double the memory size temporarily
        // slice() will create a new array, we avoid this by using our custom class
        for (var i = 0, j = 0; i < size(); i += ARRAY_POINT_SIZE * 2, j += ARRAY_POINT_SIZE) {
            _internalArrayBufferBytes.encodeNumber(
                _internalArrayBufferBytes.decodeNumber(Lang.NUMBER_FORMAT_FLOAT, {
                    :offset => i,
                    :endianness => Lang.ENDIAN_BIG,
                }) as Float,
                Lang.NUMBER_FORMAT_FLOAT,
                {
                    :offset => j,
                    :endianness => Lang.ENDIAN_BIG,
                }
            );

            _internalArrayBufferBytes.encodeNumber(
                _internalArrayBufferBytes.decodeNumber(Lang.NUMBER_FORMAT_FLOAT, {
                    :offset => i + 4,
                    :endianness => Lang.ENDIAN_BIG,
                }) as Float,
                Lang.NUMBER_FORMAT_FLOAT,
                {
                    :offset => j + 4,
                    :endianness => Lang.ENDIAN_BIG,
                }
            );

            _internalArrayBufferBytes.encodeNumber(
                _internalArrayBufferBytes.decodeNumber(Lang.NUMBER_FORMAT_FLOAT, {
                    :offset => i + 8,
                    :endianness => Lang.ENDIAN_BIG,
                }) as Float,
                Lang.NUMBER_FORMAT_FLOAT,
                {
                    :offset => j + 8,
                    :endianness => Lang.ENDIAN_BIG,
                }
            );
        }

        resize((ARRAY_POINT_SIZE * maPoints) / 2);
        logD("restrictPoints occurred");
        return true;
    }

    function reversePoints() as Void {
        var pointsCount = pointSize();
        if (pointsCount <= 1) {
            return;
        }

        for (
            var leftIndex = -4, rightIndex = size() - DIRECTION_ARRAY_POINT_SIZE;
            leftIndex < rightIndex;
            rightIndex -= DIRECTION_ARRAY_POINT_SIZE /*left increment done in loop*/
        ) {
            // hard code instead of for loop to hopefully optimise better
            // we should probaly optimise the 4 in a row byte swap too, though i do not think we have a memcpy or anything similar
            var rightIndex0 = rightIndex;
            var rightIndex1 = rightIndex + 4;
            var rightIndex2 = rightIndex + 8;
            leftIndex += 4;
            var temp =
                _internalArrayBufferBytes.decodeNumber(Lang.NUMBER_FORMAT_FLOAT, {
                    :offset => leftIndex,
                    :endianness => Lang.ENDIAN_BIG,
                }) as Float;
            _internalArrayBufferBytes.encodeNumber(
                _internalArrayBufferBytes.decodeNumber(Lang.NUMBER_FORMAT_FLOAT, {
                    :offset => rightIndex0,
                    :endianness => Lang.ENDIAN_BIG,
                }) as Float,
                Lang.NUMBER_FORMAT_FLOAT,
                {
                    :offset => leftIndex,
                    :endianness => Lang.ENDIAN_BIG,
                }
            );
            _internalArrayBufferBytes.encodeNumber(temp, Lang.NUMBER_FORMAT_FLOAT, {
                :offset => rightIndex0,
                :endianness => Lang.ENDIAN_BIG,
            });

            leftIndex += 4;
            temp =
                _internalArrayBufferBytes.decodeNumber(Lang.NUMBER_FORMAT_FLOAT, {
                    :offset => leftIndex,
                    :endianness => Lang.ENDIAN_BIG,
                }) as Float;
            _internalArrayBufferBytes.encodeNumber(
                _internalArrayBufferBytes.decodeNumber(Lang.NUMBER_FORMAT_FLOAT, {
                    :offset => rightIndex1,
                    :endianness => Lang.ENDIAN_BIG,
                }) as Float,
                Lang.NUMBER_FORMAT_FLOAT,
                {
                    :offset => leftIndex,
                    :endianness => Lang.ENDIAN_BIG,
                }
            );
            _internalArrayBufferBytes.encodeNumber(temp, Lang.NUMBER_FORMAT_FLOAT, {
                :offset => rightIndex1,
                :endianness => Lang.ENDIAN_BIG,
            });

            leftIndex += 4;
            temp =
                _internalArrayBufferBytes.decodeNumber(Lang.NUMBER_FORMAT_FLOAT, {
                    :offset => leftIndex,
                    :endianness => Lang.ENDIAN_BIG,
                }) as Float;
            _internalArrayBufferBytes.encodeNumber(
                _internalArrayBufferBytes.decodeNumber(Lang.NUMBER_FORMAT_FLOAT, {
                    :offset => rightIndex2,
                    :endianness => Lang.ENDIAN_BIG,
                }) as Float,
                Lang.NUMBER_FORMAT_FLOAT,
                {
                    :offset => leftIndex,
                    :endianness => Lang.ENDIAN_BIG,
                }
            );
            _internalArrayBufferBytes.encodeNumber(temp, Lang.NUMBER_FORMAT_FLOAT, {
                :offset => rightIndex2,
                :endianness => Lang.ENDIAN_BIG,
            });
        }

        logD("reversePoints occurred");
    }

    function _add(item as Float) as Void {
        if (_internalArrayBufferBytes.size() - _size > 4) {
            _internalArrayBufferBytes.encodeNumber(item, Lang.NUMBER_FORMAT_FLOAT, {
                :offset => _size,
                :endianness => Lang.ENDIAN_BIG,
            });
            _size += 4;
            return;
        }

        var tempBuffer = new [4]b;
        tempBuffer.encodeNumber(item, Lang.NUMBER_FORMAT_FLOAT, {
            :offset => 0,
            :endianness => Lang.ENDIAN_BIG,
        });

        _internalArrayBufferBytes.addAll(tempBuffer);
        _size = _internalArrayBufferBytes.size();
    }

    // the raw size
    function size() as Number {
        return _size;
    }

    // the number of points
    function pointSize() as Number {
        return size() / ARRAY_POINT_SIZE;
    }

    function resize(size as Number) as Void {
        if (size > _internalArrayBufferBytes.size()) {
            throw new Exception();
        }

        if (size < 0) {
            size = 0;
        }

        _size = size;
    }

    function clear() as Void {
        resize(0);
    }
}

// a flat array for memory perf Array<Float> where Array[0] = X1 Array[1] = Y1 etc. similar to the coordinates array
// [xLatRect, YLatRect, angleToTurnDegrees (-180 to 180), coordinatesIndex]
class DirectionPointArray {
    // the array type has an extra byte overhead per item stored (5 bytes per item)
    // so we pack this much tighter by using a bytearray, but the access becomes much more complex
    // bytearray.decodeNumber(NUMBER_FORMAT_FLOAT)
    // bytearray.decodeNumber(NUMBER_FORMAT_SINT8) // we could store the angle as an int8 -90 to 90 representing -180 to 180 (2 deg per value)
    // I think all the bytearray.decodeNumber could trip the watchdog
    // for 95 pointSize() itmes in the array it is
    // - 1263 bytes when using ByteArray (just 28 extra bytes overhead of the raw bytes needed)
    // - 1935 bytes when using array<float> (5 bytes per item) note this does not go down it we get createive and use <float, float, char, float> the 'char' type still takes up 5 actual bytes
    // this allows 3 large routes to fit into memory, but as suspected the overhead triggers the watchdog
    // turns out I forgot to build in release mode, and debug build was causing memory limits and watchdog errors
    // so all the new code added is likely causing the OOM, and relase build seems to work ok with 3 large routes if maps are disabled (to limit OOM)
    // and even better, I had a large (300 tiles) offline storage cache active at the time. 3 large roues are working fine with directions and offline storage cache set to 10 tiles
    var _internalArrayBuffer as ByteArray = new [0]b;

    function rescale(scaleFactor as Float) as Void {
        // unsafe to call with nulls or 0, checks should be made in parent
        // size is guaranteed to be a multiple of ARRAY_POINT_SIZE
        for (var i = 0; i < _internalArrayBuffer.size(); i += DIRECTION_ARRAY_POINT_SIZE) {
            var oldX =
                _internalArrayBuffer.decodeNumber(Lang.NUMBER_FORMAT_FLOAT, {
                    :offset => i,
                    :endianness => Lang.ENDIAN_BIG,
                }) as Float;
            _internalArrayBuffer.encodeNumber(oldX * scaleFactor, Lang.NUMBER_FORMAT_FLOAT, {
                :offset => i,
                :endianness => Lang.ENDIAN_BIG,
            });
            var oldY =
                _internalArrayBuffer.decodeNumber(Lang.NUMBER_FORMAT_FLOAT, {
                    :offset => i + 4,
                    :endianness => Lang.ENDIAN_BIG,
                }) as Float;
            _internalArrayBuffer.encodeNumber(oldY * scaleFactor, Lang.NUMBER_FORMAT_FLOAT, {
                :offset => i + 4,
                :endianness => Lang.ENDIAN_BIG,
            });
        }
    }

    function reversePoints() as Void {
        var pointsCount = pointSize();
        if (pointsCount <= 1) {
            return;
        }

        for (
            var leftIndex = -4, rightIndex = size() - DIRECTION_ARRAY_POINT_SIZE;
            leftIndex < rightIndex;
            rightIndex -= DIRECTION_ARRAY_POINT_SIZE /*left increment done in loop*/
        ) {
            // hard code instead of for loop to hopefully optimise better
            // we should probaly optimise the 4 in a row byte swap too, though i do not think we have a memcpy or anything similar
            var rightIndex0 = rightIndex;
            var rightIndex1 = rightIndex + 4;
            var rightIndex2 = rightIndex + 8;
            var rightIndex3 = rightIndex + 9;
            leftIndex += 4;
            var temp =
                _internalArrayBuffer.decodeNumber(Lang.NUMBER_FORMAT_FLOAT, {
                    :offset => leftIndex,
                    :endianness => Lang.ENDIAN_BIG,
                }) as Float;
            _internalArrayBuffer.encodeNumber(
                _internalArrayBuffer.decodeNumber(Lang.NUMBER_FORMAT_FLOAT, {
                    :offset => rightIndex0,
                    :endianness => Lang.ENDIAN_BIG,
                }) as Float,
                Lang.NUMBER_FORMAT_FLOAT,
                {
                    :offset => leftIndex,
                    :endianness => Lang.ENDIAN_BIG,
                }
            );
            _internalArrayBuffer.encodeNumber(temp, Lang.NUMBER_FORMAT_FLOAT, {
                :offset => rightIndex0,
                :endianness => Lang.ENDIAN_BIG,
            });

            leftIndex += 4;
            temp =
                _internalArrayBuffer.decodeNumber(Lang.NUMBER_FORMAT_FLOAT, {
                    :offset => leftIndex,
                    :endianness => Lang.ENDIAN_BIG,
                }) as Float;
            _internalArrayBuffer.encodeNumber(
                _internalArrayBuffer.decodeNumber(Lang.NUMBER_FORMAT_FLOAT, {
                    :offset => rightIndex1,
                    :endianness => Lang.ENDIAN_BIG,
                }) as Float,
                Lang.NUMBER_FORMAT_FLOAT,
                {
                    :offset => leftIndex,
                    :endianness => Lang.ENDIAN_BIG,
                }
            );
            _internalArrayBuffer.encodeNumber(temp, Lang.NUMBER_FORMAT_FLOAT, {
                :offset => rightIndex1,
                :endianness => Lang.ENDIAN_BIG,
            });

            leftIndex += 4;
            temp =
                _internalArrayBuffer.decodeNumber(Lang.NUMBER_FORMAT_SINT8, {
                    :offset => leftIndex,
                    :endianness => Lang.ENDIAN_BIG,
                }) as Float;
            // this is the direction we need to turn, it also needs to be reversed
            _internalArrayBuffer.encodeNumber(
                -_internalArrayBuffer.decodeNumber(Lang.NUMBER_FORMAT_SINT8, {
                    :offset => rightIndex2,
                    :endianness => Lang.ENDIAN_BIG,
                }) as Float,
                Lang.NUMBER_FORMAT_SINT8,
                {
                    :offset => leftIndex,
                    :endianness => Lang.ENDIAN_BIG,
                }
            );
            _internalArrayBuffer.encodeNumber(-temp, Lang.NUMBER_FORMAT_SINT8, {
                :offset => rightIndex2,
                :endianness => Lang.ENDIAN_BIG,
            });

            leftIndex += 1;
            temp =
                _internalArrayBuffer.decodeNumber(Lang.NUMBER_FORMAT_FLOAT, {
                    :offset => leftIndex,
                    :endianness => Lang.ENDIAN_BIG,
                }) as Float;
            _internalArrayBuffer.encodeNumber(
                _internalArrayBuffer.decodeNumber(Lang.NUMBER_FORMAT_FLOAT, {
                    :offset => rightIndex3,
                    :endianness => Lang.ENDIAN_BIG,
                }) as Float,
                Lang.NUMBER_FORMAT_FLOAT,
                {
                    :offset => leftIndex,
                    :endianness => Lang.ENDIAN_BIG,
                }
            );
            _internalArrayBuffer.encodeNumber(temp, Lang.NUMBER_FORMAT_FLOAT, {
                :offset => rightIndex3,
                :endianness => Lang.ENDIAN_BIG,
            });
        }

        logD("reverseDirectionPoints occurred");
    }

    // the raw size
    function size() as Number {
        return _internalArrayBuffer.size();
    }

    // the number of points
    function pointSize() as Number {
        return size() / DIRECTION_ARRAY_POINT_SIZE;
    }
}
