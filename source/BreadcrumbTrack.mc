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
function BOUNDING_BOX_DEFAULT() as [Float, Float, Float, Float] {return [FLOAT_MAX, FLOAT_MAX, FLOAT_MIN, FLOAT_MIN];}
function BOUNDING_BOX_CENTER_DEFAULT() as RectangularPoint {return new RectangularPoint(0.0f, 0.0f, 0.0f);}

class OffTrackInfo {
  var onTrack as Boolean;
  //  pointWeLeftTrack is already scaled to pixels
  var pointWeLeftTrack as RectangularPoint;
  function initialize(onTrack as Boolean, pointWeLeftTrack as RectangularPoint)
  {
    me.onTrack = onTrack;
    me.pointWeLeftTrack = pointWeLeftTrack;
  }
}

class BreadcrumbTrack {
  // current scale for any of the data that is scaled (coordinates are prescaled since scale changes are rare - but renders occur alot)
  // nullmeans the coordinates are raw poits, eg. for new routes that have not been scaled yet
  // scaled coordinates will be marked with // SCALED - anything that uses them needs to take scale into account
  var currentScale as Float or Null = null; 
  var lastClosePointIndex as Number or Null;
  // gets updated when track data is loaded, set to first point on track
  // also gets updated wehnever we calculate off track
  var lastClosePoint as RectangularPoint = new RectangularPoint(0f, 0f, 0f); // SCALED (note: altitude is currently unscaled)
  var epoch as Number = 0;
  // storageIndex is the id of the route (-1 is the in progress track)
  var storageIndex as Number = 0;
  var name as String;
  var coordinates as PointArray = new PointArray(); // SCALED (note: altitude is currently unscaled)
  var seenStartupPoints as Number = 0;
  var possibleBadPointsAdded as Number = 0;
  var inRestartMode as Boolean = true;
  var _computeCounter as Number = 0;
  var minDistanceMScaled as Float = MIN_DISTANCE_M.toFloat(); // SCALED
  var maxDistanceMScaled as Float = STABILITY_MAX_DISTANCE_M.toFloat(); // SCALED

  var boundingBox as [Float, Float, Float, Float] = BOUNDING_BOX_DEFAULT(); // SCALED -- since the points are used to generate it on failure
  var boundingBoxCenter as RectangularPoint = BOUNDING_BOX_CENTER_DEFAULT(); // SCALED -- since the points are used to generate it on failure
  var distanceTotal as Decimal = 0f;  // SCALED -- since the points are used to generate it on failure
  var elevationMin as Float = FLOAT_MAX; // UNSCALED
  var elevationMax as Float = FLOAT_MIN; // UNSCALED
  var _neverStarted as Boolean;

  function initialize(
      routeIndex as Number,
      name as String
  ) 
  {
    _neverStarted = true;
    epoch = Time.now().value();
    storageIndex = routeIndex;
    self.name = name;
  }

  function rescale(newScale as Float) as Void
  {
      if (newScale == 0f)
      {
        return; // dont allow silly scales
      }

      var scaleFactor = newScale;
      if (currentScale != null && currentScale != 0)
      {
        // adjsut by old scale
        scaleFactor = newScale / currentScale;
      }

      boundingBox[0] = boundingBox[0] * scaleFactor;
      boundingBox[1] = boundingBox[1] * scaleFactor;
      boundingBox[2] = boundingBox[2] * scaleFactor;
      boundingBox[3] = boundingBox[3] * scaleFactor;
      distanceTotal = distanceTotal * scaleFactor;
      boundingBoxCenter = boundingBoxCenter.rescale(scaleFactor);
      coordinates.rescale(scaleFactor);
      minDistanceMScaled = minDistanceMScaled * scaleFactor;
      maxDistanceMScaled = maxDistanceMScaled * scaleFactor;
      currentScale = newScale;
  }

  // writeToDisk should always be in raw meters coordinates // UNSCALED
  function writeToDisk(key as String) as Void {
    key = key + storageIndex;
    Storage.setValue(key + "bb", boundingBox);
    Storage.setValue(key + "bbc", [
      boundingBoxCenter.x, boundingBoxCenter.y, boundingBoxCenter.altitude
    ]);
    Storage.setValue(key + "coords", coordinates._internalArrayBuffer);
    Storage.setValue(key + "coordsSize", coordinates._size);
    Storage.setValue(key + "distanceTotal", distanceTotal);
    Storage.setValue(key + "elevationMin", elevationMin);
    Storage.setValue(key + "elevationMax", elevationMax);
    Storage.setValue(key + "epoch", epoch);
    Storage.setValue(key + "name", name);
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

  static function readFromDisk(key as String, storageIndex as Number) as BreadcrumbTrack or Null {
    key = key + storageIndex;
    try {
      var bb = Storage.getValue(key + "bb");
      if (bb == null) {
        return null;
      }
      var bbc = Storage.getValue(key + "bbc");
      if (bbc == null) {
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
      if (name == null) {
        return null;
      }

      var track = new BreadcrumbTrack(storageIndex, name);
      track.boundingBox = bb as[Float, Float, Float, Float];
      if (track.boundingBox.size() != 4) {
        return null;
      }
      track.boundingBoxCenter = new RectangularPoint(
          bbc[0] as Float, bbc[1] as Float, bbc[2] as Float);
      track.coordinates._internalArrayBuffer = coords as Array<Float>;
      track.coordinates._size = coordsSize as Number;
      track.distanceTotal = distanceTotal as Decimal;
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

  function lastPoint() as RectangularPoint or Null 
  {
    return coordinates.lastPoint();
  }

  function firstPoint() as RectangularPoint or Null 
  {
    return coordinates.firstPoint();
  }

  function addLatLongRaw(lat as Float, lon as Float, altitude as Float) as Void {
    var newPoint = RectangularPoint.latLon2xy(lat, lon, altitude);
    if (newPoint == null)
    {
      return;
    }
    var lastPoint = lastPoint();
    if (lastPoint == null)
    {
      addPointRaw(newPoint, 0f);
      setInitialLastClosePoint();
      return;
    }

    var distance = lastPoint.distanceTo(newPoint);

    if (distance < minDistanceMScaled)
    {
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
    if (coordinates.restrictPoints(MAX_POINTS))
    {
      // a resize occured, calculate important data again
      updatePointDataFromAllPoints();
    }
  }

  function updatePointDataFromAllPoints() as Void
  {
    boundingBox = BOUNDING_BOX_DEFAULT();
    boundingBoxCenter = BOUNDING_BOX_CENTER_DEFAULT();
    elevationMin = FLOAT_MAX;
    elevationMax = FLOAT_MIN;
    distanceTotal = 0f;
    var pointSize = coordinates.pointSize();
    var prevPoint = coordinates.firstPoint();
    if (prevPoint == null)
    {
      return;
    }
    updateBoundingBox(prevPoint);
    for (var i = 1; i < pointSize; ++i) {
      var point = coordinates.getPoint(i);
      // should never be null, but check to be safe
      if (point == null)
      {
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
        boundingBox[1] + (boundingBox[3] - boundingBox[1]) / 2.0, 0.0f);
  }

  // call on first start
  function onStart() as Void
  {
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
  function onStartResume() as Void
  {
    if (_neverStarted)
    {
      onStart();
    }
    log("onStartResume");
    // check from startup
    seenStartupPoints = 0;
    possibleBadPointsAdded = 0;
    inRestartMode = true;
  }

  function handlePointAddStartup(newPoint as RectangularPoint) as Boolean
  {
    // genreal p-lan of this function is
    // add data to both startup array and raw array (so we can start drawing points immediately, without the need for patching both arrays together)
    // on unstable points, remove points from both arrays
    // if the main coordinates array has been sliced in half through `restrictPoints()` 
    // this may remove more points than needed, but is not a huge concern
    var lastStartupPoint = coordinates.lastPoint();
    if (lastStartupPoint == null || seenStartupPoints == 0)
    {
      // nothing to compare against, add the point to both arrays
      // setting to 1 instead of incrementing, just incase they do not get cleaed when they should
      seenStartupPoints = 1;
      possibleBadPointsAdded = 1;
      addPointRaw(newPoint, 0f);
      return true;
    }

    var stabilityCheckDistance = lastStartupPoint.distanceTo(newPoint);
    if (stabilityCheckDistance < minDistanceMScaled)
    {
      // point too close, no need to add, but its still a good point
      seenStartupPoints++;
      return false;
    }

    if (stabilityCheckDistance > maxDistanceMScaled)
    {
        // we are unstable, remove all points
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
    
    if (seenStartupPoints == RESTART_STABILITY_POINT_COUNT)
    {
      // we have enough stable points that we can exist restart mode and just handle them as normal points
      inRestartMode = false;
      seenStartupPoints = 0;
      possibleBadPointsAdded = 0;
    }

    return true;
  }

  function pointFromActivityInfo(activityInfo as Activity.Info) as RectangularPoint or Null {
    // System.println("computing data field");
    _computeCounter++;
    // slow down the calls to onActivityInfo as its a heavy operation checking
    // the distance we don't really need data much faster than this anyway
    if (_computeCounter != DELAY_COMPUTE_COUNT) {
      return null;
    }

    _computeCounter = 0;

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

  function setInitialLastClosePoint() as Void
  {
    var point = coordinates.getPoint(0);
    if (point != null)
    {
      lastClosePoint = point;
    }
  }

  function calculateDistancePointToSegment(
          pointP as RectangularPoint,
          segmentA as RectangularPoint,
          segmentB as RectangularPoint
      ) as [Float, RectangularPoint] {

      var segmentLengthSq = segmentA.distanceTo(segmentB);
      segmentLengthSq = segmentLengthSq * segmentLengthSq;

      if (segmentLengthSq == 0.0) { // Points A and B are the same
          return [pointP.distanceTo(segmentA), pointP];
      }

      // --- Simplified Vector Math ---
      // Vector V = B - A
      var vx = segmentB.x - segmentA.x; // Example if x, y are accessible
      var vy = segmentB.y - segmentA.y; // Example

      // Vector W = P - A
      var wx = pointP.x - segmentA.x; // Example
      var wy = pointP.y - segmentA.y; // Example

      // Dot product W . V
      var dotWV = wx * vx + wy * vy;

      // Calculate t = (W . V) / |V|^2
      var t = dotWV / segmentLengthSq;

      // Clamp t to the range [0, 1]
      var clampedT = maxF(0.0, minF(1.0, t)); // Use appropriate Math functions

      // Calculate closest point on segment: Closest = A + clampedT * V
      var closestX = segmentA.x + clampedT * vx;
      var closestY = segmentA.y + clampedT * vy;

      // Create a temporary point object for the closest point on the segment
      var closestPointOnSegment = new RectangularPoint(closestX, closestY, 0f);

      // Calculate the final distance
      return [pointP.distanceTo(closestPointOnSegment), closestPointOnSegment];
  }

  // checkpoint should already be scaled, as should distanceCheck
  function checkOffTrack(checkPoint as RectangularPoint, distanceCheck as Float) as OffTrackInfo {
    // the big annying thing with off track alerts is that routes do not have evenly spaced points
    // if the route goes in a straight line, there is only 2 points, these can be frther than the alert distance
    // larger routes also have further spaced apart points (since we are limited to 500ish points per route to be able to transfer them from phone)
    // this means we could be ontrack, but between 2 points
    // this makes the calculation significantly harder :(, since we have to draw a line between each set of points and see if the user is 
    // within some limit of that line
    var endSecondScanAt = coordinates.pointSize() - 1;
    if (lastClosePointIndex != null) {
      endSecondScanAt = (lastClosePointIndex < (coordinates.pointSize() - 1)) ? lastClosePointIndex : (coordinates.pointSize() - 1);
      // note: this algoriithm will likely fail if the user is doing the track in the oposite direction
      // but we resort to scanning all the points below anyway
      for (var i = lastClosePointIndex; i < coordinates.pointSize() - 1; ++i) {
        var p1 = coordinates.getPoint(i); // p1 can never be null, its always withing size (unless a slice happens in parallel somehow?)
        var p2 = coordinates.getPoint(i + 1); // p2 can never be null (we stop at 1 less than the end of the array), its always withing size (unless a slice happens in parallel somehow?)

        var distToSegmentAndSegPoint = calculateDistancePointToSegment(checkPoint, p1, p2);
        if (distToSegmentAndSegPoint[0] < distanceCheck)
        {
          lastClosePointIndex = i;
          lastClosePoint = distToSegmentAndSegPoint[1];
          return new OffTrackInfo(true, lastClosePoint);
        }
      }

      lastClosePointIndex = null; // we have to search the start of the range now
    }

    // System.println("lastClosePointIndex: " + lastClosePointIndex);
    
    for (var i = 0; i < endSecondScanAt; ++i) {
      var p1 = coordinates.getPoint(i); // p1 can never be null, its always withing size (unless a slice happens in parallel somehow?)
      var p2 = coordinates.getPoint(i + 1); // p2 should not be null, we sanitized it at the top fof the function to end at -1 from the size

      var distToSegmentAndSegPoint = calculateDistancePointToSegment(checkPoint, p1, p2);
      if (distToSegmentAndSegPoint[0] < distanceCheck)
      {
        lastClosePointIndex = i;
        lastClosePoint = distToSegmentAndSegPoint[1];
        return new OffTrackInfo(true, lastClosePoint);
      }
    }
    return new OffTrackInfo(false, lastClosePoint);
  }

  // returns true if a new point was added to the track
  function onActivityInfo(newPoint as RectangularPoint) as Boolean {
    // todo only call this when a point is added (some points are skipped on smaller distances)
    // _breadcrumbContext.mapRenderer().loadMapTilesForPosition(newPoint, _breadcrumbContext.trackRenderer()._currentScale);

    if (currentScale != null && currentScale != 0f)
    {
      newPoint = newPoint.rescale(currentScale);
    }
    
    if (inRestartMode)
    {
      return handlePointAddStartup(newPoint);
    }
    
    var lastPoint = lastPoint();
    if (lastPoint == null)
    {
      // startup mode should have set at least one point, revert to startup mode, something has gone wrong
      onStartResume();
      return false;
    }

    var distance = lastPoint.distanceTo(newPoint);
    if (distance < minDistanceMScaled)
    {
      // point too close, so we can skip it
      return false;
    }

    if (distance > maxDistanceMScaled)
    {
      // it's too far away, and likely a glitch
      return false;
    }

    addPointRaw(newPoint, distance);
    return true;
  }
}
