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
    _track = new BreadcrumbTrack(me, 0, "");

    _settings = new Settings();
    _settings.loadSettings();

    for (var i = 0; i < ROUTE_MAX; ++i) {
      var route = BreadcrumbTrack.readFromDisk(ROUTE_KEY, i, me);
      if (route != null) {
        _routes.add(route);
        _settings.ensureRouteId(route.storageIndex);
        _settings.setRouteName(route.storageIndex, route.name);
      }
    }

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
  function newRoute(name as String) as BreadcrumbTrack {
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
      var route = new BreadcrumbTrack(me, oldestRoute.storageIndex, name);
      _settings.ensureRouteId(oldestRoute.storageIndex);
      _settings.setRouteName(oldestRoute.storageIndex, route.name);
      return route;
    }

    // todo get an available id, there may be gaps in our routes
    // ie. we might have storageIndex=0, storageIndex=3 so we should allocate storageIndex=1
    var nextId = _routes.size();
    var route = new BreadcrumbTrack(me, nextId, name);
    _routes.add(route);
    _settings.ensureRouteId(nextId);
    _settings.setRouteName(nextId, route.name);
    return route;
  }
  function clearRoutes() as Void {
    for (var i = 0; i < ROUTE_MAX; ++i) {
      var route = new BreadcrumbTrack(me, i, "");
      route.writeToDisk(ROUTE_KEY);
    }
  }
}