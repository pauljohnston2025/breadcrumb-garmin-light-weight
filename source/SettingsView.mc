import Toybox.Activity;
import Toybox.Lang;
import Toybox.Time;
import Toybox.WatchUi;
import Toybox.Communications;
import Toybox.Graphics;

class SettingsView extends WatchUi.View {
  var _breadcrumbContext as BreadcrumbContext;

  function initialize(breadcrumbContext as BreadcrumbContext) {
    _breadcrumbContext = breadcrumbContext;
    View.initialize();
  }

  function onLayout(dc as Dc) as Void {
    // for now we render everything in the onUpdate view, and assume only 1 data
    // screen
    var textDim = dc.getTextDimensions("1234", Graphics.FONT_XTINY);
    _breadcrumbContext.trackRenderer().setScreenSize(
      dc.getWidth() * 1.0f,
      textDim[0] * 1.0f
    );

    setLayout($.Rez.Layouts.SettingsLayout(dc));
  }

  // onupdate is not called continuously, so each click event we need to rerender
  // would not be an issue with WatchUi.Picker
  function onUpdate(dc as Dc) as Void {
    // todo: have a much better settings ui based on WatchUi.Picker 
    // see examples in AppData\Roaming\Garmin\ConnectIQ\Sdks\<version>\samples\Picker
    // i was expecting pickers to be a simple 'getNumber', 'getString' and it would do a native ui
    // but it seems  Toybox.WatchUi.NumberPicker and Toybox.WatchUi.NumberPickerDelegate has been deprecated
    // should also be using Toybox.WatchUi.Confirmation and Toybox.WatchUi.ConfirmationDelegate for questions
    // Toybox.WatchUi.Menu
    // Toybox.WatchUi.Menu2 -- might not be supported
    // Toybox.WatchUi.CheckboxMenu
    var renderer = _breadcrumbContext.trackRenderer();
    if (renderer.renderClearTrackUi(dc))
    {
      return;
    }
    renderer.renderUi(dc);
    // we need to keep calling update ourselves (its not called continously when its just a view)
    // not even this seems to let the settings ui re-render, think it has to be a WatchUi.Picker
    // the touch events work, it just does not re-render
    // requestUpdate();

    System.println("rendered");

    // The menu example code tells us to do it like this
    // Call the parent onUpdate function to redraw the layout
    View.onUpdate(dc); // but that just causes a black screen :(
  }
}