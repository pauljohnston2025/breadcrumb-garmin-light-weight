import Toybox.Position;
import Toybox.Lang;
import Toybox.Activity;
import Toybox.Application;

class BreadcrumbContext {
  var _breadcrumbRenderer as BreadcrumbRenderer;
  var _route as BreadcrumbTrack or Null;
  var _track as BreadcrumbTrack;
  var _mapRenderer as MapRenderer;
  var _webRequestHandler as WebRequestHandler;
  var _tileCache as TileCache;

  // Set the label of the data field here.
  function initialize() {
    _webRequestHandler = new WebRequestHandler();
    _tileCache = new TileCache(_webRequestHandler);
    _breadcrumbRenderer = new BreadcrumbRenderer(me);
    _mapRenderer = new MapRenderer(_tileCache);
    _route = null;
    _track = new BreadcrumbTrack(me);

    var route = BreadcrumbTrack.readFromDisk(ROUTE_KEY, me);
    if (route != null) {
      _route = route;
    }
  }

  function webRequestHandler() as WebRequestHandler { return _webRequestHandler; }
  function tileCache() as TileCache { return _tileCache; }
  function trackRenderer() as BreadcrumbRenderer { return _breadcrumbRenderer; }
  function mapRenderer() as MapRenderer { return _mapRenderer; }
  function track() as BreadcrumbTrack { return _track; }
  function route() as BreadcrumbTrack or Null { return _route; }
  function newRoute() as BreadcrumbTrack {
    _route = new BreadcrumbTrack(me);
    return _route;
  }
  function clearRoute() as Void {
    newRoute();
    _route.writeToDisk(ROUTE_KEY);
  }
}