import Toybox.Position;
import Toybox.Lang;
import Toybox.Activity;
import Toybox.Math;
import Toybox.Application;
using Toybox.Time;
using Toybox.Time.Gregorian;

const MAX_POINTS = 1000;
const MIN_DISTANCE_M = 5; // meters
const RESTART_STABILITY_POINT_COUNT = 10; // number of points in a row that need to be within RESTART_STABILITY_DISTANCE_M to be onsisiddered a valid course
//note: RESTART_STABILITY_POINT_COUNT should be set based on DELAY_COMPUTE_COUNT
// if DELAY_COMPUTE_COUNT = 5 seconds, 10 points give us startup cheking for 50 seconds, enough time to get a lock
const STABILITY_MAX_DISTANCE_M = 100; // max distance allowed to move to be consisdered a stable point (distance from previous point)
// note: onActivityInfo is called once per second but delayed by DELAY_COMPUTE_COUNT make sure STABILITY_MAX_DISTANCE_M takes that into account
// ie human averge running speed is 3m/s if DELAY_COMPUTE_COUNT is set to 5 STABILITY_MAX_DISTANCE_M should be set to at least 15
const DELAY_COMPUTE_COUNT = 5;
// start as minimum area, and is set to the correct size as points are added
// we want a 'empty' track to not sway the calculation of what to render
// note: we cannot do a const, as it assigns the array or point by reference
function BOUNDING_BOX_DEFAULT() as [Float, Float, Float, Float] {
    return [FLOAT_MAX, FLOAT_MAX, FLOAT_MIN, FLOAT_MIN];
}
function BOUNDING_BOX_CENTER_DEFAULT() as RectangularPoint {
    return new RectangularPoint(0.0f, 0.0f, 0.0f);
}

class OffTrackInfo {
    var onTrack as Boolean;
    //  pointWeLeftTrack is already scaled to pixels
    var pointWeLeftTrack as RectangularPoint?;
    function initialize(onTrack as Boolean, pointWeLeftTrack as RectangularPoint?) {
        me.onTrack = onTrack;
        me.pointWeLeftTrack = pointWeLeftTrack;
    }

    function clone() as OffTrackInfo {
        var pointWeLeftTrackL = pointWeLeftTrack;
        if (pointWeLeftTrackL == null) {
            return new OffTrackInfo(onTrack, null);
        }

        return new OffTrackInfo(onTrack, pointWeLeftTrackL.clone());
    }
}

class BreadcrumbTrack {
    // the data sotred on this class is scaled (coordinates are prescaled since scale changes are rare - but renders occur alot)
    // scaled coordinates will be marked with // SCALED - anything that uses them needs to take scale into account
    var lastClosePointIndex as Number?;
    // gets updated when track data is loaded, set to first point on track
    // also gets updated wehnever we calculate off track
    // there is one odity with storing lastClosePoint, if the user gets closer to another section of the track we will keep
    // telling them to go back to where they left the track. Acceptable, since the user should do their entire planned route.
    // If they rejoin the track at another point we pick up that they are on track correctly.
    // Multi routes also makes this issue slightly more annoying, in a rare case where a user has left one route, and done another route,
    // when we get close to the first route (if we are still off track) it will snap to the last point they left the route, rather than the start.
    // such a small edge case, that I only found in a random test setup, the performance benifits of caching the lastClosePoint
    // outweigh the chances users will run into this edge case. To solve it we have to process the whole route every time,
    // though we already do this in a multi route setup, we might parse off track alerts for all the other routes then get to the one we are on.
    // single route use case is more common though, so we will optimise for that. in multi route we could store 'last route we were on'
    var lastClosePoint as RectangularPoint? = null; // SCALED (note: altitude is currently unscaled)
    var epoch as Number = 0;
    // storageIndex is the id of the route (-1 is the in progress track)
    var storageIndex as Number = 0;
    var name as String;
    var coordinates as PointArray = new PointArray(); // SCALED (note: altitude is currently unscaled)
    var seenStartupPoints as Number = 0;
    var possibleBadPointsAdded as Number = 0;
    var inRestartMode as Boolean = true;
    var minDistanceMScaled as Float = MIN_DISTANCE_M.toFloat(); // SCALED
    var maxDistanceMScaled as Float = STABILITY_MAX_DISTANCE_M.toFloat(); // SCALED

    var boundingBox as [Float, Float, Float, Float] = BOUNDING_BOX_DEFAULT(); // SCALED -- since the points are used to generate it on failure
    var boundingBoxCenter as RectangularPoint = BOUNDING_BOX_CENTER_DEFAULT(); // SCALED -- since the points are used to generate it on failure
    var distanceTotal as Float = 0f; // SCALED -- since the points are used to generate it on failure
    var elevationMin as Float = FLOAT_MAX; // UNSCALED
    var elevationMax as Float = FLOAT_MIN; // UNSCALED
    var _neverStarted as Boolean;

    function initialize(routeIndex as Number, name as String) {
        _neverStarted = true;
        epoch = Time.now().value();
        storageIndex = routeIndex;
        self.name = name;
    }

    function rescale(scaleFactor as Float) as Void {
        boundingBox[0] = boundingBox[0] * scaleFactor;
        boundingBox[1] = boundingBox[1] * scaleFactor;
        boundingBox[2] = boundingBox[2] * scaleFactor;
        boundingBox[3] = boundingBox[3] * scaleFactor;
        distanceTotal = distanceTotal * scaleFactor;
        boundingBoxCenter.rescaleInPlace(scaleFactor);
        coordinates.rescale(scaleFactor);
        if (lastClosePoint != null) {
            lastClosePoint.rescaleInPlace(scaleFactor);
        }
        minDistanceMScaled = minDistanceMScaled * scaleFactor;
        maxDistanceMScaled = maxDistanceMScaled * scaleFactor;
    }

    function handleRouteV2(routeData as Array<Float>, cachedValues as CachedValues) as Boolean {
        // trust the app completely
        coordinates._internalArrayBuffer = routeData;
        coordinates._size = routeData.size();
        // we could optimise this firther if the app rpovides us with biunding box, center max/min elevation
        // but it makes it really hard to add any more cached data to the route, that the companion app then has to send
        // by making these rectangular coordinates, we skip a huge amount of math converting them from lat/long
        updatePointDataFromAllPoints();
        var wrote = writeToDisk(ROUTE_KEY); // write to disk before we scale, all routes on disk are unscaled
        var currentScale = cachedValues.currentScale;
        if (currentScale != 0f) {
            rescale(currentScale);
        }
        cachedValues.recalculateAll();
        return wrote;
    }

    // writeToDisk should always be in raw meters coordinates // UNSCALED
    function writeToDisk(key as String) as Boolean {
        try {
            key = key + storageIndex;
            Storage.setValue(key + "bb", boundingBox);
            Storage.setValue(key + "bbc", [
                boundingBoxCenter.x,
                boundingBoxCenter.y,
                boundingBoxCenter.altitude,
            ]);
            Storage.setValue(key + "coords", coordinates._internalArrayBuffer as Array<PropertyValueType>);
            Storage.setValue(key + "coordsSize", coordinates._size);
            Storage.setValue(key + "distanceTotal", distanceTotal);
            Storage.setValue(key + "elevationMin", elevationMin);
            Storage.setValue(key + "elevationMax", elevationMax);
            Storage.setValue(key + "epoch", epoch);
            Storage.setValue(key + "name", name);
        } catch (e) {
            // it will still be in memory, just not persisted, this is bad as the user will think it worked, so return false to indicate error
            logE("failed route save: " + e.getErrorMessage());
            ++$.globalExceptionCounter;
            return false;
        }
        return true;
    }

    static function clearRoute(key as String, storageIndex as Number) as Void {
        key = key + storageIndex;
        // removing any key should cause it to fail to load next time, but would look weird when debugging, so remove all keys
        Storage.deleteValue(key + "bb");
        Storage.deleteValue(key + "bbc");
        Storage.deleteValue(key + "coords");
        Storage.deleteValue(key + "coordsSize");
        Storage.deleteValue(key + "distanceTotal");
        Storage.deleteValue(key + "elevationMin");
        Storage.deleteValue(key + "elevationMax");
        Storage.deleteValue(key + "epoch");
        Storage.deleteValue(key + "name");
    }

    static function readFromDisk(key as String, storageIndex as Number) as BreadcrumbTrack? {
        key = key + storageIndex;
        try {
            var bb = Storage.getValue(key + "bb");
            if (bb == null) {
                return null;
            }
            var bbc = Storage.getValue(key + "bbc");
            if (bbc == null || !(bbc instanceof Array) || bbc.size() != 3) {
                return null;
            }
            var coords = Storage.getValue(key + "coords");
            if (coords == null) {
                return null;
            }

            var coordsSize = Storage.getValue(key + "coordsSize");
            if (coordsSize == null) {
                return null;
            }

            var distanceTotal = Storage.getValue(key + "distanceTotal");
            if (distanceTotal == null) {
                return null;
            }

            var elevationMin = Storage.getValue(key + "elevationMin");
            if (elevationMin == null) {
                return null;
            }

            var elevationMax = Storage.getValue(key + "elevationMax");
            if (elevationMax == null) {
                return null;
            }

            var epoch = Storage.getValue(key + "epoch");
            if (epoch == null) {
                return null;
            }

            var name = Storage.getValue(key + "name");
            if (name == null || !(name instanceof String)) {
                return null;
            }

            var track = new BreadcrumbTrack(storageIndex, name);
            track.boundingBox = bb as [Float, Float, Float, Float];
            if (track.boundingBox.size() != 4) {
                return null;
            }
            track.boundingBoxCenter = new RectangularPoint(
                bbc[0] as Float,
                bbc[1] as Float,
                bbc[2] as Float
            );
            track.coordinates._internalArrayBuffer = coords as Array<Float>;
            track.coordinates._size = coordsSize as Number;
            track.distanceTotal = distanceTotal as Float;
            track.elevationMin = elevationMin as Float;
            track.elevationMax = elevationMax as Float;
            track.epoch = epoch as Number;
            if (track.coordinates.size() % ARRAY_POINT_SIZE != 0) {
                return null;
            }
            track.setInitialLastClosePoint();
            return track;
        } catch (e) {
            return null;
        }
    }

    function lastPoint() as RectangularPoint? {
        return coordinates.lastPoint();
    }

    function firstPoint() as RectangularPoint? {
        return coordinates.firstPoint();
    }

    function addLatLongRaw(lat as Float, lon as Float, altitude as Float) as Void {
        var newPoint = RectangularPoint.latLon2xy(lat, lon, altitude);
        if (newPoint == null) {
            return;
        }
        var lastPoint = lastPoint();
        if (lastPoint == null) {
            addPointRaw(newPoint, 0f);
            setInitialLastClosePoint();
            return;
        }

        var distance = lastPoint.distanceTo(newPoint);

        if (distance < minDistanceMScaled) {
            // no need to add points closer than this
            return;
        }

        addPointRaw(newPoint, distance);
    }

    // new point should be in scale already
    function addPointRaw(newPoint as RectangularPoint, distance as Float) as Void {
        distanceTotal += distance;
        coordinates.add(newPoint);
        updateBoundingBox(newPoint);
        if (coordinates.restrictPoints(MAX_POINTS)) {
            // a resize occured, calculate important data again
            updatePointDataFromAllPoints();
        }
    }

    function updatePointDataFromAllPoints() as Void {
        boundingBox = BOUNDING_BOX_DEFAULT();
        boundingBoxCenter = BOUNDING_BOX_CENTER_DEFAULT();
        elevationMin = FLOAT_MAX;
        elevationMax = FLOAT_MIN;
        distanceTotal = 0f;
        var pointSize = coordinates.pointSize();
        var prevPoint = coordinates.firstPoint();
        if (prevPoint == null) {
            return;
        }
        updateBoundingBox(prevPoint);
        for (var i = 1; i < pointSize; ++i) {
            var point = coordinates.getPoint(i);
            // should never be null, but check to be safe
            if (point == null) {
                break;
            }

            updateBoundingBox(point);
            distanceTotal += prevPoint.distanceTo(point);
            prevPoint = point;
        }
    }

    function updateBoundingBox(point as RectangularPoint) as Void {
        boundingBox[0] = minF(boundingBox[0], point.x);
        boundingBox[1] = minF(boundingBox[1], point.y);
        boundingBox[2] = maxF(boundingBox[2], point.x);
        boundingBox[3] = maxF(boundingBox[3], point.y);

        elevationMin = minF(elevationMin, point.altitude);
        elevationMax = maxF(elevationMax, point.altitude);

        boundingBoxCenter = new RectangularPoint(
            boundingBox[0] + (boundingBox[2] - boundingBox[0]) / 2.0,
            boundingBox[1] + (boundingBox[3] - boundingBox[1]) / 2.0,
            0.0f
        );
    }

    // call on first start
    function onStart() as Void {
        log("onStart");
        // check from startup, and also clear the current coordinates,
        // anything we got before start is invalid
        coordinates.clear();
        // we also need to reset the bounding box, as its only ever expanded, never reduced
        boundingBox = BOUNDING_BOX_DEFAULT();
        boundingBoxCenter = BOUNDING_BOX_CENTER_DEFAULT();
        distanceTotal = 0f;
        elevationMin = FLOAT_MAX;
        elevationMax = FLOAT_MIN;
        _neverStarted = false;
        onStartResume();
    }

    // when an activity has been stopped, and we have moved and restarted
    function onStartResume() as Void {
        if (_neverStarted) {
            onStart();
        }
        log("onStartResume");
        // check from startup
        seenStartupPoints = 0;
        possibleBadPointsAdded = 0;
        inRestartMode = true;
    }

    function handlePointAddStartup(newPoint as RectangularPoint) as Boolean {
        // genreal p-lan of this function is
        // add data to both startup array and raw array (so we can start drawing points immediately, without the need for patching both arrays together)
        // on unstable points, remove points from both arrays
        // if the main coordinates array has been sliced in half through `restrictPoints()`
        // this may remove more points than needed, but is not a huge concern
        var lastStartupPoint = coordinates.lastPoint();
        if (lastStartupPoint == null) {
            // nothing to compare against, add the point to both arrays
            addPointRaw(newPoint, 0f);
            return true;
        }

        var stabilityCheckDistance = lastStartupPoint.distanceTo(newPoint);
        if (stabilityCheckDistance < minDistanceMScaled) {
            // point too close, no need to add, but its still a good point
            seenStartupPoints++;
            return false;
        }

        if (stabilityCheckDistance > maxDistanceMScaled) {
            // we are unstable, remove all our stability check points
            seenStartupPoints = 0;
            coordinates.removeLastCountPoints(possibleBadPointsAdded);
            possibleBadPointsAdded = 0;
            updatePointDataFromAllPoints();
            return false;
        }

        // we are stable, see if we can break out of startup
        seenStartupPoints++;
        possibleBadPointsAdded++;
        addPointRaw(newPoint, stabilityCheckDistance);

        if (seenStartupPoints == RESTART_STABILITY_POINT_COUNT) {
            inRestartMode = false;
        }

        return true;
    }

    function pointFromActivityInfo(activityInfo as Activity.Info) as RectangularPoint? {
        var loc = activityInfo.currentLocation;
        if (loc == null) {
            return null;
        }

        var altitude = activityInfo.altitude;
        if (altitude == null) {
            return null;
        }

        var asDeg = loc.toDegrees();
        var lat = asDeg[0].toFloat();
        var lon = asDeg[1].toFloat();

        return RectangularPoint.latLon2xy(lat, lon, altitude);
    }

    function setInitialLastClosePoint() as Void {
        var point = coordinates.getPoint(0);
        if (point != null) {
            lastClosePoint = point;
        }
    }

    function calculateDistancePointToSegment(
        pointP as RectangularPoint,
        segmentAX as Float,
        segmentAY as Float,
        segmentBX as Float,
        segmentBY as Float
    ) as [Decimal, Float, Float] {
        // Vector V = B - A
        var vx = segmentBX - segmentAX;
        var vy = segmentBY - segmentAY;
        var segmentLengthSq = vx * vx + vy * vy;

        if (segmentLengthSq == 0.0) {
            // Points A and B are the same
            // Calculate the final distance
            var xDist = pointP.x - segmentAX;
            var yDist = pointP.y - segmentAY;
            var closestDistance = Math.sqrt(xDist * xDist + yDist * yDist);
            return [closestDistance, segmentAX, segmentAY];
        }

        // --- Simplified Vector Math ---

        // Vector W = P - A
        var wx = pointP.x - segmentAX;
        var wy = pointP.y - segmentAY;

        // Dot product W . V
        var dotWV = wx * vx + wy * vy;

        // Calculate t = (W . V) / |V|^2
        var t = dotWV / segmentLengthSq;

        // Clamp t to the range [0, 1]
        var clampedT = maxF(0.0, minF(1.0, t));

        // Calculate closest point on segment: Closest = A + clampedT * V
        var closestX = segmentAX + clampedT * vx;
        var closestY = segmentAY + clampedT * vy;

        // Calculate the final distance
        var xDist = pointP.x - closestX;
        var yDist = pointP.y - closestY;
        var closestSegmentDistance = Math.sqrt(xDist * xDist + yDist * yDist);
        return [closestSegmentDistance, closestX, closestY];
    }

    // checkpoint should already be scaled, as should distanceCheck
    function checkOffTrack(checkPoint as RectangularPoint, distanceCheck as Float) as OffTrackInfo {
        // logD("checking off track: " + storageIndex);
        // the big annying thing with off track alerts is that routes do not have evenly spaced points
        // if the route goes in a straight line, there is only 2 points, these can be frther than the alert distance
        // larger routes also have further spaced apart points (since we are limited to 500ish points per route to be able to transfer them from phone)
        // this means we could be ontrack, but between 2 points
        // this makes the calculation significantly harder :(, since we have to draw a line between each set of points and see if the user is
        // within some limit of that line
        var sizeRaw = coordinates.size();
        if (sizeRaw < 2) {
            return new OffTrackInfo(false, lastClosePoint);
        }

        var endSecondScanAtRaw = sizeRaw;
        var coordinatesRaw = coordinates._internalArrayBuffer; // raw dog access means we can do the calcs much faster (and do not need to create a point with altitude)
        if (lastClosePointIndex != null) {
            var lastClosePointRawStart = lastClosePointIndex * ARRAY_POINT_SIZE;
            // note: this algoriithm will likely fail if the user is doing the track in the oposite direction
            // but we resort to scanning all the points below anyway
            // this for loop is optimised for on track, and navigating in the direction of the track
            // it should result in only a single itteration in most cases, as they get closer to the next point
            // we need at least 2 points of reference to be able to itterate the for loop,
            // if we were the second to last point the for loop will never run
            if (lastClosePointRawStart <= sizeRaw - 2 * ARRAY_POINT_SIZE) {
                endSecondScanAtRaw = lastClosePointRawStart + ARRAY_POINT_SIZE; // the second scan needs to include endSecondScanAtRaw, or we would skip a point in the overlap
                var lastPointX = coordinatesRaw[lastClosePointRawStart];
                var lastPointY = coordinatesRaw[lastClosePointRawStart + 1];
                for (
                    var i = lastClosePointRawStart + ARRAY_POINT_SIZE;
                    i < sizeRaw;
                    i += ARRAY_POINT_SIZE
                ) {
                    var nextX = coordinatesRaw[i];
                    var nextY = coordinatesRaw[i + 1];

                    var distToSegmentAndSegPoint = calculateDistancePointToSegment(
                        checkPoint,
                        lastPointX,
                        lastPointY,
                        nextX,
                        nextY
                    );

                    if (distToSegmentAndSegPoint[0] < distanceCheck) {
                        lastClosePointIndex = i;
                        lastClosePoint = new RectangularPoint(
                            distToSegmentAndSegPoint[1],
                            distToSegmentAndSegPoint[2],
                            0f
                        );
                        return new OffTrackInfo(true, lastClosePoint);
                    }

                    lastPointX = nextX;
                    lastPointY = nextY;
                }
            }
            lastClosePointIndex = null; // we have to search the start of the range now
        }

        // System.println("lastClosePointIndex: " + lastClosePointIndex);
        var lastPointX = coordinatesRaw[0];
        var lastPointY = coordinatesRaw[1];
        // The below for loop only runs when we are off track, or when the user is navigating the track in the reverse direction
        // so we need to check which point is closest, rather than grabbing the last point we left the track.
        // Because that could default to a random spot on the track, or the start of the track that is further away.
        var lastClosestX = lastPointX;
        var lastClosestY = lastPointY;
        var lastClosestDist = FLOAT_MAX;
        for (var i = ARRAY_POINT_SIZE; i < endSecondScanAtRaw; i += ARRAY_POINT_SIZE) {
            var nextX = coordinatesRaw[i];
            var nextY = coordinatesRaw[i + 1];

            var distToSegmentAndSegPoint = calculateDistancePointToSegment(
                checkPoint,
                lastPointX,
                lastPointY,
                nextX,
                nextY
            );
            if (distToSegmentAndSegPoint[0] < distanceCheck) {
                lastClosePointIndex = i;
                lastClosePoint = new RectangularPoint(
                    distToSegmentAndSegPoint[1],
                    distToSegmentAndSegPoint[2],
                    0f
                );
                return new OffTrackInfo(true, lastClosePoint);
            }

            if (distToSegmentAndSegPoint[0] < lastClosestDist) {
                lastClosestDist = distToSegmentAndSegPoint[0];
                lastClosestX = distToSegmentAndSegPoint[1];
                lastClosestY = distToSegmentAndSegPoint[2];
            }

            lastPointX = nextX;
            lastPointY = nextY;
        }

        lastClosePoint = new RectangularPoint(lastClosestX, lastClosestY, 0f);
        return new OffTrackInfo(false, lastClosePoint);
    }

    // returns true if a new point was added to the track
    function onActivityInfo(newScaledPoint as RectangularPoint) as Boolean {
        // todo only call this when a point is added (some points are skipped on smaller distances)
        // _breadcrumbContext.mapRenderer().loadMapTilesForPosition(newPoint, _breadcrumbContext.trackRenderer()._currentScale);

        if (inRestartMode) {
            return handlePointAddStartup(newScaledPoint);
        }

        var lastPoint = lastPoint();
        if (lastPoint == null) {
            // startup mode should have set at least one point, revert to startup mode, something has gone wrong
            onStartResume();
            return false;
        }

        var distance = lastPoint.distanceTo(newScaledPoint);
        if (distance < minDistanceMScaled) {
            // point too close, so we can skip it
            return false;
        }

        if (distance > maxDistanceMScaled) {
            // it's too far away, and likely a glitch
            return false;
        }

        addPointRaw(newScaledPoint, distance);
        return true;
    }
}
