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
        if (_settings.routeName(route.storageIndex).equals(""))
        {
            // settings label takes precedence over our internal one until the setting route entry removed
            _settings.setRouteName(route.storageIndex, route.name);
        }
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
  function newRoute(name as String) as BreadcrumbTrack or Null {
    // we could maybe just not load the route if they are not enabled?
    // but they are pushing a new route from the app for this to happen
    // so forcing the new route to be enabled
    _settings.setRoutesEnabled(true);

    // force the new route name into the settings
    // this can be kind of confusing, since we can have no routes in the context
    // but the settings can have a name and have the route allocated
    // routes should be created by pushing them to the watch from the companion app
    // if routes are configured in settings first, only the colour options will be preserved
    // Id's can be in any order, the next example is correct
    // eg me.routes = [] settings.routes = [{id:2, name: "customroute2"}, {id:0, name: "customroute0"}],
    // loading a route from the phone with name "phoneroute" will result in
    // eg me.routes = [BreadcrumbTrack{storageIndex:0, name: "phoneroute"}] settings.routes = [{id:2, name: "customroute2"}, {id:0, name: "phoneroute"}],
    // the colours will be uneffected
    // note: the route will also be force enabled, as described above
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
      _settings.setRouteEnabled(oldestRoute.storageIndex, true);
      return route;
    }

    // todo get an available id, there may be gaps in our routes
    var nextId = nextAvailableRouteId();
    if (nextId == null)
    {
      System.println("failed to get route");
      return null; // should never happen, we remove the oldest above if we are full
    }
    var route = new BreadcrumbTrack(me, nextId, name);
    _routes.add(route);
    _settings.ensureRouteId(nextId);
    _settings.setRouteName(nextId, route.name);
    _settings.setRouteEnabled(nextId, true);
    return route;
  }

  function nextAvailableRouteId() as Number or Null
  {
      // ie. we might have storageIndex=0, storageIndex=3 so we should allocate storageIndex=1
      for (var i = 0; i < ROUTE_MAX; ++i) {
          if(haveRouteId(i))
          {
            continue;
          }

          return i;
      }

      return null;
  }
  
  function haveRouteId(routeId as Number) as Boolean
  {
      for (var j = 0; j < _routes.size(); ++j) {
          if (_routes[j].storageIndex == routeId)
          {
            return true;      
          }
      }

      return false;
  }

  function clearRoutes() as Void {
    for (var i = 0; i < ROUTE_MAX; ++i) {
      var route = new BreadcrumbTrack(me, i, "");
      route.writeToDisk(ROUTE_KEY);
    }
    _routes = [];
    _settings.clearRoutes();
  }
}