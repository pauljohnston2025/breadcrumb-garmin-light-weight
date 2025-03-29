import Toybox.Position;
import Toybox.Lang;
import Toybox.Activity;
import Toybox.Application;

class BreadcrumbContext {
  var _breadcrumbRenderer as BreadcrumbRenderer;
  var _routes as Array<BreadcrumbTrack>;
  var _track as BreadcrumbTrack;
  var _settings as Settings;
  var _webRequestHandler as WebRequestHandler;
  var _tileCache as TileCache;
  var _mapRenderer as MapRenderer;

  // Set the label of the data field here.
  function initialize() {
    _breadcrumbRenderer = new BreadcrumbRenderer(me);
    _routes = [];
    _track = new BreadcrumbTrack(me, 0);

    for (var i = 0; i < ROUTE_MAX; ++i) {
      var route = BreadcrumbTrack.readFromDisk(ROUTE_KEY, i, me);
      if (route != null) {
        _routes.add(route);
      }
    }

    _settings = new Settings();
    _settings.loadSettings();
    _webRequestHandler = new WebRequestHandler(_settings);
    _tileCache = new TileCache(_webRequestHandler, _settings);
    _mapRenderer = new MapRenderer(_tileCache, _settings);
  }

  function settings() as Settings { return _settings; }
  function webRequestHandler() as WebRequestHandler { return _webRequestHandler; }
  function tileCache() as TileCache { return _tileCache; }
  function trackRenderer() as BreadcrumbRenderer { return _breadcrumbRenderer; }
  function mapRenderer() as MapRenderer { return _mapRenderer; }
  function track() as BreadcrumbTrack { return _track; }
  function routes() as Array<BreadcrumbTrack> or Null { return _routes; }
  function newRoute() as BreadcrumbTrack {
    if (_routes.size() >= ROUTE_MAX)
    {
      var oldestRoute = null;
      for (var i = 0; i < _routes.size(); ++i) {
        var thisRoute = _routes[i];
        if (oldestRoute == null || oldestRoute.epoch > thisRoute.epoch)
        {
            oldestRoute = thisRoute;
        }
      }
      _routes.remove(oldestRoute);
      var route = new BreadcrumbTrack(me, oldestRoute.storageIndex);
      return route;
    }
    var route = new BreadcrumbTrack(me, _routes.size());
    _routes.add(route);
    return route;
  }
  function clearRoutes() as Void {
    for (var i = 0; i < ROUTE_MAX; ++i) {
      var route = new BreadcrumbTrack(me, i);
      route.writeToDisk(ROUTE_KEY);
    }
  }
}