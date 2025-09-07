import Toybox.Position;
import Toybox.Lang;
import Toybox.StringUtil;
import Toybox.Activity;
import Toybox.Math;
import Toybox.Application;
using Toybox.Time;
using Toybox.Time.Gregorian;

const TRACK_ID = -1;
const MIN_DISTANCE_M = 5; // meters
const RESTART_STABILITY_POINT_COUNT = 10; // number of points in a row that need to be within RESTART_STABILITY_DISTANCE_M to be onsisiddered a valid course
//note: RESTART_STABILITY_POINT_COUNT should be set based on DELAY_COMPUTE_COUNT
// if DELAY_COMPUTE_COUNT = 5 seconds, 10 points give us startup cheking for 50 seconds, enough time to get a lock
// max distance allowed to move to be consisdered a stable point (distance from previous point)
// this needs to be relatively high, since the compute interval could be set quite large, or the user could be  on a motortransport (car, bike, jetski)
// eg. at 80kmph with a 5 second compute interval (that may not run for 3 attempts, 15 seconds)
// 80000/60/60*15 = 333.333
const STABILITY_MAX_DISTANCE_M = 400;
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
    var wrongDirection as Boolean;
    function initialize(
        onTrack as Boolean,
        pointWeLeftTrack as RectangularPoint?,
        wrongDirection as Boolean
    ) {
        me.onTrack = onTrack;
        me.pointWeLeftTrack = pointWeLeftTrack;
        me.wrongDirection = wrongDirection;
    }

    function clone() as OffTrackInfo {
        var pointWeLeftTrackL = pointWeLeftTrack;
        if (pointWeLeftTrackL == null) {
            return new OffTrackInfo(onTrack, null, wrongDirection);
        }

        return new OffTrackInfo(onTrack, pointWeLeftTrackL.clone(), wrongDirection);
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
    var createdAt as Number = 0;
    // storageIndex is the id of the route (-1 is the in progress track)
    var storageIndex as Number = 0;
    var name as String;
    var coordinates as PointArray = new PointArray(0); // SCALED (note: altitude is currently unscaled)
    var directions as DirectionPointArray = new DirectionPointArray();
    var lastDirectionIndex as Number = -1;
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

    function initialize(routeIndex as Number, name as String, initalPointCount as Number) {
        _neverStarted = true;
        createdAt = Time.now().value();
        storageIndex = routeIndex;
        coordinates = new PointArray(initalPointCount);
        self.name = name;
    }

    function reverse() as Void {
        // distanceTotal  // we can't reverse the track, (the only one tracking distance total)

        coordinates.reversePoints();
        directions.reversePoints();
        lastDirectionIndex = -1;
        lastClosePointIndex = null;
        lastClosePoint = null; // we want to recalculate off track, since the cheveron direction will change
        writeToDisk(ROUTE_KEY); // write ourselves back to storage in reverse, so next time we load (on app restart) it is correct
    }

    function settingsChanged() as Void {
        // we might have enabled/disabled searching for directions or offtrack
        lastDirectionIndex = -1;
        lastClosePoint = null;
        lastClosePointIndex = null;
    }

    function rescale(scaleFactor as Float) as Void {
        boundingBox[0] = boundingBox[0] * scaleFactor;
        boundingBox[1] = boundingBox[1] * scaleFactor;
        boundingBox[2] = boundingBox[2] * scaleFactor;
        boundingBox[3] = boundingBox[3] * scaleFactor;
        distanceTotal = distanceTotal * scaleFactor;
        boundingBoxCenter.rescaleInPlace(scaleFactor);
        coordinates.rescale(scaleFactor);
        directions.rescale(scaleFactor);
        if (lastClosePoint != null) {
            lastClosePoint.rescaleInPlace(scaleFactor);
        }
        minDistanceMScaled = minDistanceMScaled * scaleFactor;
        maxDistanceMScaled = maxDistanceMScaled * scaleFactor;
    }

    function handleRouteV2(
        routeData as Array<Float>,
        directions as Array<Float>,
        cachedValues as CachedValues
    ) as Boolean {
        // trust the app completely
        coordinates._internalArrayBuffer = routeData;
        coordinates._size = routeData.size();
        me.directions._internalArrayBuffer = directions;
        // we could optimise this further if the app provides us with binding box, center max/min elevation
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
            Storage.setValue(
                key + "coords",
                coordinates._internalArrayBuffer as Array<PropertyValueType>
            );
            Storage.setValue(key + "coordsSize", coordinates._size);
            Storage.setValue(
                key + "directions",
                directions._internalArrayBuffer as Array<PropertyValueType>
            );
            Storage.setValue(key + "distanceTotal", distanceTotal);
            Storage.setValue(key + "elevationMin", elevationMin);
            Storage.setValue(key + "elevationMax", elevationMax);
            Storage.setValue(key + "createdAt", createdAt);
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
        Storage.deleteValue(key + "directions");
        Storage.deleteValue(key + "distanceTotal");
        Storage.deleteValue(key + "elevationMin");
        Storage.deleteValue(key + "elevationMax");
        Storage.deleteValue(key + "createdAt");
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

            var directions = Storage.getValue(key + "directions");
            if (directions == null) {
                directions = []; // back compat
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

            var createdAt = Storage.getValue(key + "createdAt");
            if (createdAt == null) {
                return null;
            }

            var name = Storage.getValue(key + "name");
            if (name == null || !(name instanceof String)) {
                return null;
            }

            var track = new BreadcrumbTrack(storageIndex, name, 0);
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
            track.directions._internalArrayBuffer = directions as Array<Float>;
            track.distanceTotal = distanceTotal as Float;
            track.elevationMin = elevationMin as Float;
            track.elevationMax = elevationMax as Float;
            track.createdAt = createdAt as Number;
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
    function addPointRaw(newPoint as RectangularPoint, distance as Float) as Boolean {
        distanceTotal += distance;
        coordinates.add(newPoint);
        updateBoundingBox(newPoint);
        // todo have a local ref to settings
        if (coordinates.restrictPoints(getApp()._breadcrumbContext.settings.maxTrackPoints)) {
            // a resize occured, calculate important data again
            updatePointDataFromAllPoints();
            return true;
        }

        return false;
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
        logD("onStart");
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
        logD("onStartResume");
        // check from startup
        seenStartupPoints = 0;
        possibleBadPointsAdded = 0;
        inRestartMode = true;
    }

    function handlePointAddStartup(newPoint as RectangularPoint) as [Boolean, Boolean] {
        // genreal p-lan of this function is
        // add data to both startup array and raw array (so we can start drawing points immediately, without the need for patching both arrays together)
        // on unstable points, remove points from both arrays
        // if the main coordinates array has been sliced in half through `restrictPoints()`
        // this may remove more points than needed, but is not a huge concern
        var lastStartupPoint = coordinates.lastPoint();
        if (lastStartupPoint == null) {
            // nothing to compare against, add the point to both arrays
            return [true, addPointRaw(newPoint, 0f)];
        }

        var stabilityCheckDistance = lastStartupPoint.distanceTo(newPoint);
        if (stabilityCheckDistance < minDistanceMScaled) {
            // point too close, no need to add, but its still a good point
            seenStartupPoints++;
            return [false, false];
        }

        // allow large distances when we have just started, we need to get the first point to work from after a resume
        if (stabilityCheckDistance > maxDistanceMScaled && seenStartupPoints != 0) {
            // we are unstable, remove all our stability check points
            seenStartupPoints = 0;
            coordinates.removeLastCountPoints(possibleBadPointsAdded);
            possibleBadPointsAdded = 0;
            updatePointDataFromAllPoints();
            return [false, true];
        }

        // we are stable, see if we can break out of startup
        seenStartupPoints++;
        possibleBadPointsAdded++;
        if (seenStartupPoints == RESTART_STABILITY_POINT_COUNT) {
            inRestartMode = false;
        }

        return [true, addPointRaw(newPoint, stabilityCheckDistance)];
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
    // returns [turnAngleDeg, distancePx] or null if no direction within range
    function checkDirections(
        checkPoint as RectangularPoint,
        distanceCheck as Float
    ) as [Float, Float]? {
        var directionsRaw = directions._internalArrayBuffer; // raw dog access means we can do the calcs much faster
        // longer routes with more points allow more look ahead (up to some percentage of the route)
        var allowedCoordinatePerimiter = maxN(5, (coordinates.pointSize() / 20).toNumber());
        var oldLastDirectionIndex = lastDirectionIndex;
        var oldLastClosePointIndex = lastClosePointIndex;
        if (oldLastClosePointIndex != null) {
            var lastCoordonatesIndexF = oldLastClosePointIndex.toFloat();
            // we know where we are on the track, only look at directions that are ahead of here
            // this allows us to revisit the start of the track, or when we return to the track after being off track we can resume looking for directions
            var stillNearTheLastDirectionPoint = false;
            var startAt = 0;
            if (oldLastDirectionIndex >= 0 && oldLastDirectionIndex < directions.pointSize()) {
                startAt = oldLastDirectionIndex;
                var oldLastDirectionIndexStart = oldLastDirectionIndex * DIRECTION_ARRAY_POINT_SIZE;
                var oldLastDirectionPointDistance = distance(
                    directionsRaw[oldLastDirectionIndexStart],
                    directionsRaw[oldLastDirectionIndexStart + 1],
                    checkPoint.x,
                    checkPoint.y
                );
                stillNearTheLastDirectionPoint = oldLastDirectionPointDistance < distanceCheck;
                var lastDirectionCoordinateIndexF = directionsRaw[oldLastDirectionIndexStart + 3];

                var indexDifference = lastDirectionCoordinateIndexF - oldLastClosePointIndex;
                // this allows us to go back to the start of the track, and get alerts again for the same directions
                // it also allows us to be moving between 2 points in the routescoordinates, and the directions should never go backwards
                if (
                    (indexDifference > 0f && indexDifference < 1f) || // we are between 2 points, use the latest direction point as the coordinates index
                    // we are still within distance to the direction point, use it so we do not trigger the alert again
                    stillNearTheLastDirectionPoint
                ) {
                    lastCoordonatesIndexF = lastDirectionCoordinateIndexF;
                }
            }

            // This alorithm becomes longer and longer as the route goes on, as we check all possible directions until we are too far in the future
            // we should probably only check from a few coordinates in the past, but we have no way of knowing coordinate index to direction index
            // eg. The first direction could be half way through the coordinate list
            // direction arrays are meant to be fairly small, so not a huge issue for now, and it does fast forward so it's only a few ops per direction
            // we may need to store a bucketed list or something if this leads to watchdog errors
            var stopAt = directionsRaw.size();
            for (
                var i = startAt * DIRECTION_ARRAY_POINT_SIZE;
                i < stopAt;
                i += DIRECTION_ARRAY_POINT_SIZE
            ) {
                var coordinatesIndexF = directionsRaw[i + 3];
                if (coordinatesIndexF <= lastCoordonatesIndexF) {
                    // skip any of the directions in the past
                    continue;
                }

                // only allow the directions around our location to be checked
                // we do not want a track that loops back through the same intersection triggerring the direction for the end of the route if we are only part way through
                if (coordinatesIndexF - lastCoordonatesIndexF > allowedCoordinatePerimiter) {
                    return null;
                }

                var distancePx = distance(
                    directionsRaw[i],
                    directionsRaw[i + 1],
                    checkPoint.x,
                    checkPoint.y
                );
                if (distancePx < distanceCheck) {
                    lastDirectionIndex = i / DIRECTION_ARRAY_POINT_SIZE;
                    return [directionsRaw[i + 2], distancePx];
                }
            }

            return null;
        }
        // we do not know where we are on the track, either off track alerts are not enabled, or we are off track
        // in this case, we want to search all directions, since we could rejoin the track at any point

        var lastCoordonatesIndexF = -1f;
        var stillNearTheLastDirectionPoint = false;
        var startAt = 0;
        if (oldLastDirectionIndex >= 0 && oldLastDirectionIndex < directions.pointSize()) {
            var oldLastDirectionIndexStart = oldLastDirectionIndex * DIRECTION_ARRAY_POINT_SIZE;
            startAt = oldLastDirectionIndex;
            var oldLastDirectionPointDistance = distance(
                directionsRaw[oldLastDirectionIndexStart],
                directionsRaw[oldLastDirectionIndexStart + 1],
                checkPoint.x,
                checkPoint.y
            );
            stillNearTheLastDirectionPoint = oldLastDirectionPointDistance < distanceCheck;
            lastCoordonatesIndexF = directionsRaw[oldLastDirectionIndexStart + 3];
        }

        var stopAt = directionsRaw.size();
        for (
            var i = startAt * DIRECTION_ARRAY_POINT_SIZE;
            i < stopAt;
            i += DIRECTION_ARRAY_POINT_SIZE
        ) {
            // any points ahead of us are valid, since we have no idea where we are on the route, but don't allow points to go backwards
            var coordinatesIndexF = directionsRaw[i + 3];
            if (coordinatesIndexF <= lastCoordonatesIndexF) {
                // skip any of the directions in the past, this should not really ever happen since we start at the index, but protect ourselves from ourselves
                continue;
            }

            if (
                stillNearTheLastDirectionPoint &&
                coordinatesIndexF - lastCoordonatesIndexF > allowedCoordinatePerimiter
            ) {
                // prevent any overlap of points further on in the route that go through the same intersection
                // we probably need to include a bit of padding here, since the overlap could be slightly miss-aligned
                // This is done in the loop to allow quick turns in succession to be alerted, but not the directions at the end of the route thats in the same intersection.
                // eg. a left turn followed by a right turn
                // we use the direction alert to know roughly where we are on the route
                // whilst we are within the circle of the last direction only consider the next X points
                return null;
            }

            var distancePx = distance(
                directionsRaw[i],
                directionsRaw[i + 1],
                checkPoint.x,
                checkPoint.y
            );
            if (distancePx < distanceCheck) {
                lastDirectionIndex = i / DIRECTION_ARRAY_POINT_SIZE;
                return [directionsRaw[i + 2], distancePx];
            }
        }

        if (!stillNearTheLastDirectionPoint) {
            // consider all directions again, we have moved outside the perimeter of the last direction
            // this is so we can rejoin at the start
            lastDirectionIndex = -1;
        }
        return null;
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
            return new OffTrackInfo(false, lastClosePoint, false);
        }

        var endSecondScanAtRaw = sizeRaw;
        var coordinatesRaw = coordinates._internalArrayBuffer; // raw dog access means we can do the calcs much faster (and do not need to create a point with altitude)
        var oldLastClosePointIndex = lastClosePointIndex;
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
                        lastClosePointIndex = (i - 1) / ARRAY_POINT_SIZE;
                        lastClosePoint = new RectangularPoint(
                            distToSegmentAndSegPoint[1],
                            distToSegmentAndSegPoint[2],
                            0f
                        );
                        return new OffTrackInfo(true, lastClosePoint, false); // we are travelling in the correct direction, as we found a point in the end of the array
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
                lastClosePointIndex = (i - 1) / ARRAY_POINT_SIZE;
                lastClosePoint = new RectangularPoint(
                    distToSegmentAndSegPoint[1],
                    distToSegmentAndSegPoint[2],
                    0f
                );
                var wrongDirection =
                    oldLastClosePointIndex != null &&
                    lastClosePointIndex != null &&
                    oldLastClosePointIndex > lastClosePointIndex;
                if (wrongDirection) {
                    lastDirectionIndex = -1; // reset the direction index once we go back, this is so we can revisit the direction again if we go past it again
                }
                return new OffTrackInfo(true, lastClosePoint, wrongDirection);
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
        return new OffTrackInfo(false, lastClosePoint, false); // we are not on track, therefore cannot be travelling in reverse
    }

    // returns [if a new point was added to the track, if a complex operation occurred]
    function onActivityInfo(newScaledPoint as RectangularPoint) as [Boolean, Boolean] {
        // todo only call this when a point is added (some points are skipped on smaller distances)
        // _breadcrumbContext.mapRenderer.loadMapTilesForPosition(newPoint, _breadcrumbContext.breadcrumbRenderer._currentScale);

        if (inRestartMode) {
            return handlePointAddStartup(newScaledPoint);
        }

        var lastPoint = lastPoint();
        if (lastPoint == null) {
            // startup mode should have set at least one point, revert to startup mode, something has gone wrong
            onStartResume();
            return [false, false];
        }

        var distance = lastPoint.distanceTo(newScaledPoint);
        if (distance < minDistanceMScaled) {
            // point too close, so we can skip it
            return [false, false];
        }

        if (distance > maxDistanceMScaled) {
            // it's too far away, and likely a glitch
            return [false, false];
        }

        return [true, addPointRaw(newScaledPoint, distance)];
    }
}
