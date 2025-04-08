import Toybox.WatchUi;
import Toybox.System;
import Toybox.Lang;

// see BreadcrumbDataFieldView if touch stops working
class BreadcrumbDataFieldDelegate extends WatchUi.InputDelegate {
  var _breadcrumbContext as BreadcrumbContext;

  function initialize(breadcrumbContext as BreadcrumbContext) {
    InputDelegate.initialize();
    _breadcrumbContext = breadcrumbContext;
  }

  function onKey(keyEvent as WatchUi.KeyEvent) {
    System.println("got key event: " + keyEvent.getKey());  // e.g. KEY_MENU = 7
    return false;
  }

  // see BreadcrumbDataFieldView if touch stops working
  function onTap(evt as WatchUi.ClickEvent) as Boolean {
    // System.println("got tap (x,y): (" + evt.getCoordinates()[0] + "," +
    //                evt.getCoordinates()[1] + ")");

    var coords = evt.getCoordinates();
    var x = coords[0];
    var y = coords[1];
    var renderer = _breadcrumbContext.trackRenderer();
    var settings = _breadcrumbContext.settings();
    var cachedValues = _breadcrumbContext.cachedValues();

    if (settings.uiMode == UI_MODE_NONE)
    {
      return false;
    }

    if (renderer.handleClearRoute(x, y))
    {
      // returns true if it handles touches on top left
      // also blocks input if we are in the menu
      return true;
    }

    var hitboxSize = renderer.hitboxSize;
    var halfHitboxSize = hitboxSize / 2.0f;

    // perhaps put this into new class to handle touch events, and have a
    // renderer for that ui would allow us to switch out ui and handle touched
    // differently also will alow setting the scren height
    if (  y > renderer.modeSelectY - halfHitboxSize 
       && y < renderer.modeSelectY + halfHitboxSize  
       && x > renderer.modeSelectX - halfHitboxSize
       && x < renderer.modeSelectX + halfHitboxSize) {
      // top right
      settings.nextMode();
      return true;
    } 

    if (settings.mode == MODE_DEBUG)
    {
      return false;
    }
    
    if (  y > renderer.returnToUserY - halfHitboxSize 
       && y < renderer.returnToUserY + halfHitboxSize  
       && x > renderer.returnToUserX - halfHitboxSize
       && x < renderer.returnToUserX + halfHitboxSize) {
      // return to users location
      // bottom left
      settings.setFixedPosition(null, null, true);
      return true;
    } else if (  y > renderer.mapEnabledY - halfHitboxSize 
       && y < renderer.mapEnabledY + halfHitboxSize  
       && x > renderer.mapEnabledX - halfHitboxSize
       && x < renderer.mapEnabledX + halfHitboxSize) {
        // botom right
      if (settings.mode == MODE_NORMAL)
      {
        settings.toggleMapEnabled();
        return true;
      }
      
      return false;
    }
    else if (y < hitboxSize) {
      if (settings.mode == MODE_MAP_MOVE)
      {
        cachedValues.moveFixedPositionUp();
        return true;
      }
      // top of screen
      renderer.incScale();
      return true;
    } else if(y > cachedValues.screenHeight - hitboxSize) {
      // bottom of screen
      if (settings.mode == MODE_MAP_MOVE)
      {
        cachedValues.moveFixedPositionDown();
        return true;
      }
      renderer.decScale();
      return true;
    }
    else if(x > cachedValues.screenWidth - hitboxSize) {
      // right of screen
      if (settings.mode == MODE_MAP_MOVE)
      {
        cachedValues.moveFixedPositionRight();
        return true;
      }
      renderer.resetScale();
      return true;
    }
    else if(x < hitboxSize) {
      // left of screen
      if (settings.mode == MODE_MAP_MOVE)
      {
        cachedValues.moveFixedPositionLeft();
        return true;
      }
      settings.nextZoomAtPaceMode();
      return true;
    }
    
    return false;
  }
}