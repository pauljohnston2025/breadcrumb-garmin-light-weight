// layout inspired by https://github.com/vtrifonov-esfiddle/ConnectIqDataPickers
// but I have simplified the ui significantly

import Toybox.Graphics;
import Toybox.WatchUi;
import Toybox.Lang;

(:settingsView)
class NumberPicker {
    private var currentVal as String;
    private var _charset as String;
    private var maxLength as Number;
    private var letterPositions as Array<[Float, Float]>;
    private var halfWidth as Number?;
    private var myText as WatchUi.Text;
    const halfHitboxSize as Number = 35;

    function initialize(charset as String, maxLength as Number) {
        self.maxLength = maxLength;
        _charset = charset;
        currentVal = "";
        letterPositions = [];
        halfWidth = null;

        myText = new WatchUi.Text({
            :text => "",
            :color => Graphics.COLOR_WHITE,
            :font => Graphics.FONT_SMALL,
            :locX => WatchUi.LAYOUT_HALIGN_CENTER,
            :locY => WatchUi.LAYOUT_VALIGN_CENTER,
        });
    }

    function onLayout(dc as Dc) as Void {
        halfWidth = dc.getWidth() / 2;
        letterPositions = pointsOnCircle(
            halfWidth,
            halfWidth,
            halfWidth - halfHitboxSize,
            _charset.length()
        );
    }

    private function pointsOnCircle(
        centerX as Number,
        centerY as Number,
        radius as Number,
        numPoints as Number
    ) as Array<[Float, Float]> {
        var points = new [numPoints];

        var angleIncrement = (2 * Math.PI) / numPoints;

        for (var i = 0; i < numPoints; i++) {
            var angle = i * angleIncrement;

            var x = centerX + radius * Math.cos(angle).toFloat();
            var y = centerY + radius * Math.sin(angle).toFloat();

            points[i] = [x, y];
        }

        return points as Array<[Float, Float]>;
    }

    function onUpdate(dc as Dc) as Void {
        var bgColour = backgroundColour(currentVal);
        dc.setColor(Graphics.COLOR_WHITE, bgColour);
        dc.clear();
        dc.clear();
        dc.setPenWidth(4);
        for (var i = 0; i < letterPositions.size(); i++) {
            var point = letterPositions[i];
            var pointX = point[0];
            var pointY = point[1];
            var letter = self._charset.substring(i, i + 1);
            dc.drawText(
                pointX,
                pointY,
                Graphics.FONT_SMALL,
                letter,
                Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER
            );
        }

        myText.draw(dc);
    }

    function confirm() as Void {
        onReading(currentVal);
    }

    function removeLast() as Void {
        if (currentVal.length() <= 0) {
            WatchUi.popView(WatchUi.SLIDE_IMMEDIATE);
            return;
        }

        var subStr = currentVal.substring(null, -1);
        if (subStr != null) {
            currentVal = subStr;
            myText.setText(currentVal);
            forceRefresh();
        }
    }

    function onTap(x as Number, y as Number) as Boolean {
        var letter = letterOfTap(x, y);
        if (letter == null || currentVal.length() >= maxLength) {
            return false;
        }

        currentVal += letter;
        myText.setText(currentVal);
        return true;
    }

    function letterOfTap(x as Number, y as Number) as String? {
        for (var i = 0; i < letterPositions.size(); i++) {
            var point = letterPositions[i];
            var pointX = point[0];
            var pointY = point[1];

            // Check if the tap is within the hit box
            if (inHitbox(x, y, pointX, pointY, halfHitboxSize.toFloat())) {
                return self._charset.substring(i, i + 1);
            }
        }

        return null;
    }

    protected function onReading(value as String) as Void;
    protected function backgroundColour(value as String) as Number {
        return Graphics.COLOR_BLACK;
    }
}

(:settingsView)
class FloatPicker extends NumberPicker {
    var defaultVal as Float;
    function initialize(defaultVal as Float) {
        NumberPicker.initialize("0123456789.", 10);
        me.defaultVal = defaultVal;
    }

    protected function onReading(value as String) as Void {
        onValue(Settings.parseFloatRaw("key", value, defaultVal));
    }

    protected function onValue(value as Float?) as Void;
}

(:settingsView)
class IntPicker extends NumberPicker {
    var defaultVal as Number;
    function initialize(defaultVal as Number) {
        NumberPicker.initialize("-0123456789", 10);
        me.defaultVal = defaultVal;
    }

    protected function onReading(value as String) as Void {
        onValue(Settings.parseNumberRaw("key", value, defaultVal));
    }

    protected function onValue(value as Number?) as Void;
}

(:settingsView)
class ColourPicker extends NumberPicker {
    var defaultVal as Number;
    function initialize(defaultVal as Number) {
        NumberPicker.initialize("0123456789ABCDEF", 6);
        me.defaultVal = defaultVal;
    }

    protected function onReading(value as String) as Void {
        onValue(Settings.parseColourRaw("key", value, defaultVal));
    }

    protected function onValue(value as Number?) as Void;

    protected function backgroundColour(value as String) as Number {
        return Settings.parseColourRaw("key", value, Graphics.COLOR_BLACK);
    }
}

(:settingsView)
class RerenderIgnoredView extends WatchUi.View {
    function initialize() {
        View.initialize();

        // for seom reason WatchUi.requestUpdate(); was not working so im pushing this view just to remove it, which should force a re-render
        // note: this seems to be a problem with datafields settings views on physical devices, appears to work fine on the sim
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

(:settingsView)
function forceRefresh() as Void {
    WatchUi.requestUpdate(); // sometimes does not work, but lets call it anyway
    WatchUi.pushView(new RerenderIgnoredView(), null, WatchUi.SLIDE_IMMEDIATE);
}

(:settingsView)
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
        // logT("onUpdate");
        // Some exampls have the line below, do not do that, screen goes black (though it does work in the examples, guess just not when lanunched from menu?)
        // View.onUpdate(dc);
    }
}

(:settingsView)
class NumberPickerDelegate extends WatchUi.BehaviorDelegate {
    private var picker as NumberPicker;

    function initialize(picker as NumberPicker) {
        self.picker = picker;
        WatchUi.BehaviorDelegate.initialize();
    }

    function onTap(evt as WatchUi.ClickEvent) as Boolean {
        // logT("got number picker tap (x,y): (" + evt.getCoordinates()[0] + "," +
        //                evt.getCoordinates()[1] + ")");

        var coords = evt.getCoordinates();
        var x = coords[0];
        var y = coords[1];

        var handled = picker.onTap(x, y);
        if (handled) {
            forceRefresh();
        }
        return handled;
    }

    function onKey(keyEvent as WatchUi.KeyEvent) {
        var key = keyEvent.getKey();
        // logT("got number picker key event: " + key);  // e.g. KEY_MENU = 7
        if (key == WatchUi.KEY_ENTER) {
            picker.confirm();
            WatchUi.popView(WatchUi.SLIDE_IMMEDIATE);
            return true;
        }

        return false;
    }

    function onBack() {
        // logT("got back");
        picker.removeLast();
        return true;
    }
}
