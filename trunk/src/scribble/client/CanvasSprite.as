package scribble.client {

import flash.display.DisplayObject;
import flash.display.Sprite;
import flash.events.Event;
import flash.events.IEventDispatcher;
import flash.utils.ByteArray;
import flash.utils.Dictionary;

import com.whirled.net.*;

import com.threerings.util.Command;
import com.threerings.util.SortedHashMap;
import com.threerings.util.ValueEvent;

import scribble.data.Codes;
import scribble.data.Stroke;

/** Contains all the meaty sauce for drawing a networked interactive canvas. */
public class CanvasSprite extends Sprite
{
    public static const CANVAS_CLEARED :String = "CanvasCleared";

    public function CanvasSprite (prefix :String, source :IEventDispatcher = null)
    {
        _prefix = prefix;
        _source = (source != null) ? source : this; // See declaration for wtf this is

        this.addEventListener(CANVAS_CLEARED, function (... _) :void {
            reset();
        });
        this.addEventListener(StrokeEvent.STROKE_ADDED, function (event :StrokeEvent) :void {
            if (event.isMyStroke()) {
                _pendingStrokes.put(event.strokeId, event.stroke);
                if (event.stroke.isEnding) {
                    _overlay.pop();
                    _pendingStrokes.forEach(function (strokeId :int, stroke :Stroke) :void {
                        _strokes.addStroke(stroke, strokeId, event.artistId, false);
                        trace(strokeId);
                    });
                    _pendingStrokes.clear();
                }

            } else {
                _strokes.addStroke(event.stroke, event.strokeId, event.artistId);
            }
        });
        this.addEventListener(StrokeEvent.STROKE_REMOVED, function (event :StrokeEvent) :void {
            _strokes.removeStroke(event.strokeId);
            _pendingStrokes.remove(event.strokeId);
        });

        _composer.addEventListener(StrokeComposer.STROKE_COMPOSED, onStrokeComposed);
        _composer.addEventListener(StrokeComposer.STROKE_REJECTED, function (... _) :void {
            _overlay.pop();
        });

        addEventListener(Event.ADDED_TO_STAGE, function (... _) :void {
            Game.ctrl.room.props.addEventListener(ElementChangedEvent.ELEMENT_CHANGED, onRoomElementChanged);
            Game.ctrl.room.props.addEventListener(PropertyChangedEvent.PROPERTY_CHANGED, onRoomPropertyChanged);
        });

        addEventListener(Event.REMOVED_FROM_STAGE, function (... _) :void {
            Game.ctrl.room.props.removeEventListener(ElementChangedEvent.ELEMENT_CHANGED, onRoomElementChanged);
            Game.ctrl.room.props.removeEventListener(PropertyChangedEvent.PROPERTY_CHANGED, onRoomPropertyChanged);
        });

        addChild(_strokes);
        addChild(_overlay);
    }

    protected function onRoomElementChanged (event :ElementChangedEvent) :void
    {
        if (event.name == Codes.keyCanvas(_prefix)) {
            var added :Boolean = (event.newValue != null);
            var se :StrokeEvent = new StrokeEvent(added ?
                StrokeEvent.STROKE_ADDED : StrokeEvent.STROKE_REMOVED);
            var value :Object = added ? event.newValue : event.oldValue;

            se.strokeId = event.key;
            se.artistId = int(value[0]);
            se.stroke = Stroke.fromBytes(ByteArray(value[1]));

            dispatchEvent(se);
        }
    }

    protected function onRoomPropertyChanged (event :PropertyChangedEvent) :void
    {
        if (event.name == Codes.keyCanvas(_prefix) && event.newValue == null) {
            dispatchEvent(new Event(CANVAS_CLEARED));
        }
    }

    public function init (animate :Boolean) :void
    {
        reset();

        var strokes :Dictionary = Dictionary(
            Game.ctrl.room.props.get(Codes.keyCanvas(_prefix)));

        for (var key :String in strokes) {
            var strokeId :int = int(key);
            var artistId :int = int(strokes[strokeId][0]);
            var stroke :Stroke = Stroke.fromBytes(ByteArray(strokes[strokeId][1]));
            _strokes.addStroke(stroke, strokeId, artistId, animate);
        }
    }

    protected function onStrokeComposed (event :ValueEvent) :void
    {
        // See _source
        Command.dispatch(_source, ScribbleController.SEND_STROKE, Stroke(event.value));
    }

    public function createToolbox () :Sprite
    {
        var toolbox :Sprite = new Sprite();

        var picker :BrushPicker = new BrushPicker();
        picker.addEventListener(BrushPicker.BRUSH_CHANGED, function (event :ValueEvent) :void {
            var brushId :int = int(event.value);
            _composer.setBrush(brushId);
            _overlay.setBrush(brushId);
        });
        toolbox.addChild(picker);

        var clearButton :ClearButton = new ClearButton();
        clearButton.x = toolbox.width;
        toolbox.addChild(clearButton);

        var undo :UndoSprite = new UndoSprite(this);
        this.addEventListener(CanvasSprite.CANVAS_CLEARED, function (... _) :void {
            undo.reset();
        });
        _overlay.addEventListener(DrawingOverlay.BRUSH_DOWN, function (... _) :void {
            // Clear redo history on canvas click
            undo.clearRedo();
        });
        undo.x = toolbox.width;
        toolbox.addChild(undo);

        return toolbox;
    }

    protected function reset () :void
    {
        _strokes.clear();
        _overlay.clear();
        _composer.reset();
        _pendingStrokes.clear();
    }

    protected var _prefix :String;

    /**
     * When the brush is down, save my incoming strokes to this map, when the brush is lifted we'll
     * add them.
     */
    protected var _pendingStrokes :SortedHashMap =
        new SortedHashMap(SortedHashMap.NUMERIC_KEYS); // strokeId -> Stroke

    /**
     * Because this canvas may be in a mob, we need to specify the _source so CommandEvents will
     * stay within our app and not wind up to the mob sprite, which is controlled by the Whirled
     * client.
     */
    protected var _source :IEventDispatcher;

    protected var _strokes :StrokeContainer = new StrokeContainer(640, 480);
    protected var _overlay :DrawingOverlay = new DrawingOverlay(640, 480);
    protected var _composer :StrokeComposer = new StrokeComposer(_overlay, null);
}

}
