// layout inspired by https://github.com/vtrifonov-esfiddle/ConnectIqDataPickers
// but I have simplified the ui significantly

import Toybox.Graphics;
import Toybox.WatchUi;
import Toybox.Lang;

class NumberPicker {
    private var currentVal as String;
    private var _charset as String;
    private var letterPositions as Array<Array<Number>>;
    private var halfWidth as Number or Null;
    private var myText as WatchUi.Text;
    const halfHitboxSize as Number = 25;

    function initialize(charset as String) {
        _charset = charset;
        currentVal = "";
        letterPositions = [];
        halfWidth = null;

        myText = new WatchUi.Text({
            :text=>"",
            :color=>Graphics.COLOR_WHITE,
            :font=>Graphics.FONT_SMALL,
            :locX=>WatchUi.LAYOUT_HALIGN_CENTER,
            :locY=>WatchUi.LAYOUT_VALIGN_CENTER
        });
    }  

    function onLayout(dc as Dc) as Void {
        halfWidth = dc.getWidth()/2;
        letterPositions = pointsOnCircle(halfWidth, halfWidth, halfWidth - halfHitboxSize, _charset.length());
    }

    private function pointsOnCircle(centerX as Number, centerY as Number, radius as Number, numPoints as Number) as Array<Array<Number>> {
        var points = new [numPoints];

        var angleIncrement = 2 * Math.PI / numPoints;

        for (var i = 0; i < numPoints; i++) {
            var angle = i * angleIncrement;

            var x = centerX + radius * Math.cos(angle);
            var y = centerY + radius * Math.sin(angle);

            points[i] = [x, y];
        }

        return points;
    }

    function onUpdate(dc as Dc) as Void {
        // todo use system colours (there are consts for this somewhere)
        var bgColour = backgroundColour(currentVal);
        dc.setColor(bgColour, bgColour);
        dc.clear();
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(4);
        for (var i = 0; i < letterPositions.size(); i++) {
            var point = letterPositions[i];
            var pointX = point[0];
            var pointY = point[1];
            var letter = self._charset.substring(i, i + 1);
            dc.drawText(pointX, pointY, Graphics.FONT_SMALL, letter, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        }

        if (halfWidth != null)
        {
            myText.draw(dc);
            // dc.drawText(halfWidth, halfWidth, Graphics.FONT_SMALL, currentVal, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        }
    }

    function confirm() as Void
    {
        onReading(currentVal);
    }
    
    function removeLast() as Void
    {
        if (currentVal.length() <= 0)
        {
            WatchUi.popView(WatchUi.SLIDE_IMMEDIATE);
            return;
        }

        currentVal = currentVal.substring(null, -1);
        myText.setText(currentVal);
        forceRefresh();
    }

    function onTap(x as Number, y as Number) as Boolean
    {
        var letter = letterOfTap(x, y);
        if (letter == null)
        {
            return false;
        }

        currentVal += letter;
        myText.setText(currentVal);
        return true;
    }

    function letterOfTap(x as Number, y as Number) as String or Null
    {
        for (var i = 0; i < letterPositions.size(); i++) {
            var point = letterPositions[i];
            var pointX = point[0];
            var pointY = point[1];

            // Check if the tap is within the hit box
            if (x >= pointX - halfHitboxSize &&
                x <= pointX + halfHitboxSize &&
                y >= pointY - halfHitboxSize &&
                y <= pointY + halfHitboxSize) {
                return self._charset.substring(i, i + 1);
            }
        }

        return null;
    }

    protected function onReading(value as String);
    protected function backgroundColour(value as String) as Number
    {
        return Graphics.COLOR_BLACK;
    }
}

class FloatPicker extends NumberPicker {
    function initialize() {
        NumberPicker.initialize("0123456789.");
    }

    protected function onReading(value as String) as Void
    {
        onValue(value.toFloat());
    }

    protected function onValue(value as Float or Null) as Void;
}

class IntPicker extends NumberPicker {
    function initialize() {
        NumberPicker.initialize("0123456789");
    }

    protected function onReading(value as String) as Void
    {
        onValue(value.toNumber());
    }

    protected function onValue(value as Number or Null) as Void;
}

class ColourPicker extends NumberPicker {
    function initialize() {
        NumberPicker.initialize("0123456789ABCDEF");
    }

    protected function onReading(value as String) as Void
    {
        onValue(value.toNumberWithBase(16));
    }

    protected function onValue(value as Number or Null) as Void;

    protected function backgroundColour(value as String) as Number
    {
        var ret = value.toNumberWithBase(16);
        if (ret == null)
        {
            return Graphics.COLOR_BLACK;
        }

        return ret;
    }
}

class RerenderIgnoredView extends WatchUi.View {
  function initialize() {
    View.initialize();

    // for seom reason WatchUi.requestUpdate(); was not working so im pushing this view just to remove it, which should force a re-render
    // timer = new Timer.Timer();
    // need a timer running of this, since button presses from within the delegate were not trigering a reload
    // timer.start(method(:onTimer), 1000, true);
    // but timers are not available in the settings view (or at all in datafield)
    // "Module 'Toybox.Timer' not available to 'Data Field'"
  }

  function onLayout(dc as Dc) as Void {
    WatchUi.popView(WatchUi.SLIDE_IMMEDIATE);
  }
}

function forceRefresh() as Void
{
    WatchUi.requestUpdate(); // sometimes does not work, but lets call it anyway
    WatchUi.pushView(new RerenderIgnoredView(), null, WatchUi.SLIDE_IMMEDIATE);
}


class NumberPickerView extends WatchUi.View {
  private var picker as NumberPicker;

  function initialize(picker as NumberPicker) {
    self.picker = picker;
    View.initialize();

    // timer = new Timer.Timer();
    // need a timer running of this, since button presses from within the delegate were not trigering a reload
    // timer.start(method(:onTimer), 1000, true);
    // but timers are not available in the settings view (or at all in datafield)
    // "Module 'Toybox.Timer' not available to 'Data Field'"
  }

  function onLayout(dc as Dc) as Void {
    picker.onLayout(dc);
  }

  function onUpdate(dc as Dc) as Void {
    picker.onUpdate(dc);
    // System.println("onUpdate");
    // Some exampls have the line below, do not do that, screen goes black (though it does work in the examples, guess just not when lanunched from menu?)
    // View.onUpdate(dc);
  }
}

class NumberPickerDelegate extends WatchUi.BehaviorDelegate {
    private var picker as NumberPicker;

    function initialize(picker as NumberPicker) {
        self.picker = picker;
        WatchUi.BehaviorDelegate.initialize();
    }

    function onTap(evt as WatchUi.ClickEvent) as Boolean {
        // System.println("got number picker tap (x,y): (" + evt.getCoordinates()[0] + "," +
        //                evt.getCoordinates()[1] + ")");

        var coords = evt.getCoordinates();
        var x = coords[0];
        var y = coords[1];

        var handled = picker.onTap(x, y);
        if (handled)
        {
            forceRefresh();
        }
        return handled;
    }

    function onKey(keyEvent as WatchUi.KeyEvent) {
        var key = keyEvent.getKey();
        // System.println("got number picker key event: " + key);  // e.g. KEY_MENU = 7
        if (key == WatchUi.KEY_ENTER)
        {
            picker.confirm();
            WatchUi.popView(WatchUi.SLIDE_IMMEDIATE);
            return true;
        }

        return false;
    }

    function onBack() {
        // System.println("got back");
        picker.removeLast();
        return true;
    }
}
