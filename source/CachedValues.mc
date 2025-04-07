import Toybox.Application;
import Toybox.Lang;
import Toybox.Graphics;
import Toybox.System;

class CachedValues {
    private var _settings as Settings;

    var smallTilesPerBigTile as Number;
    var fixedPosition as RectangularPoint or Null;
    // will be changed whenever scale is adjusted, falls back to metersAroundUser when no scale
    var mapMoveDistanceM as Float;

    function initialize(settings as Settings)
    {
        self._settings = settings;
        smallTilesPerBigTile = Math.ceil(256f/_settings.tileSize).toNumber();
        fixedPosition = null;
        // will be changed whenever scale is adjusted, falls back to metersAroundUser when no scale
        mapMoveDistanceM = _settings.metersAroundUser.toFloat();
    }

    function recalculateAll() as Void
    {
        smallTilesPerBigTile = Math.ceil(256f/_settings.tileSize).toNumber();
        if (_settings.fixedLatitude == null || _settings.fixedLongitude == null)
        {
            fixedPosition = null;
        }
        else {
            fixedPosition = RectangularPoint.latLon2xy(_settings.fixedLatitude, _settings.fixedLongitude, 0f); 
        }
    }

    function setMapMoveDistance(value as Float) as Void
    {
        mapMoveDistanceM = value;
    }

    // todo: make all of these take into acount the sceen rotation, and move in the direction the screen is pointing
    // for now just moving NSEW as if there was no screen rotation (N is up)
    function moveFixedPositionUp() as Void
    {
        setPositionIfNotSet();
        var latlong = RectangularPoint.xyToLatLon(fixedPosition.x, fixedPosition.y + mapMoveDistanceM);
        if (latlong != null)
        {
            _settings.setFixedPositionRaw(latlong[0], latlong[1]);
        }
    }

    function moveFixedPositionDown() as Void
    {
        setPositionIfNotSet();
        var latlong = RectangularPoint.xyToLatLon(fixedPosition.x, fixedPosition.y - mapMoveDistanceM);
        if (latlong != null)
        {
            _settings.setFixedPositionRaw(latlong[0], latlong[1]);
        }
    }

    function moveFixedPositionLeft() as Void
    {
        setPositionIfNotSet();
        var latlong = RectangularPoint.xyToLatLon(fixedPosition.x - mapMoveDistanceM, fixedPosition.y);
        if (latlong != null)
        {
            _settings.setFixedPositionRaw(latlong[0], latlong[1]);
        }
    }

    function moveFixedPositionRight() as Void
    {
        setPositionIfNotSet();
        var latlong = RectangularPoint.xyToLatLon(fixedPosition.x + mapMoveDistanceM, fixedPosition.y);
        if (latlong != null)
        {
            _settings.setFixedPositionRaw(latlong[0], latlong[1]);
        }
    }

    // note: this does not save the position just sets it
    function setPositionIfNotSet() as Void
    {
        var lastRenderedLatLongCenter = null;
        // context might not be set yet
        var context = getApp()._breadcrumbContext;
        if (context != null and context instanceof BreadcrumbContext && context has :_breadcrumbRenderer && context._breadcrumbRenderer != null && context._breadcrumbRenderer instanceof BreadcrumbRenderer)
        {
            if (context._breadcrumbRenderer.lastRenderedCenter != null)
            {
                lastRenderedLatLongCenter = RectangularPoint.xyToLatLon(
                    context._breadcrumbRenderer.lastRenderedCenter.x, 
                    context._breadcrumbRenderer.lastRenderedCenter.y
                );
            }
        }
        
        var fixedLatitude = _settings.fixedLatitude;
        var fixedLongitude = _settings.fixedLongitude;
        if (fixedLatitude == null)
        {
            fixedLatitude = lastRenderedLatLongCenter == null ? 0f : lastRenderedLatLongCenter[0];
        }

        if (fixedLongitude == null)
        {
            fixedLongitude = lastRenderedLatLongCenter == null ? 0f : lastRenderedLatLongCenter[1];;
        }
        fixedPosition = RectangularPoint.latLon2xy(fixedLatitude, fixedLongitude, 0f);
        // System.println("new fixed pos: " + fixedPosition);
    }
}