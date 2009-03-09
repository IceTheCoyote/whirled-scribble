package scribble.client {

import flash.display.Sprite;
import flash.events.Event;
import flash.events.KeyboardEvent;
import flash.filters.DropShadowFilter;
import flash.geom.Rectangle;
import flash.text.TextField;
import flash.text.TextFieldType;
import flash.ui.Keyboard;
import flash.utils.Dictionary;

import com.gskinner.motion.GTween;

import com.threerings.flash.TextFieldUtil;
import com.threerings.util.Command;

import com.whirled.avrg.*;
import com.whirled.net.*;

import aduros.net.REMOTE;

import scribble.data.Codes;
import scribble.data.PictionaryLogic;

public class PictionaryMode extends ModeSprite
{
    public function PictionaryMode ()
    {
        _prefix = Codes.CANVAS_PREFIXES[Codes.CANVAS_PICTIONARY];
        _logic = new PictionaryLogic(_prefix, Game.ctrl.room.props);

        _panel = new Sprite();
        _panel.graphics.beginFill(0xffffff);
        _panel.graphics.drawRect(0, 0, 640, 480);
        _panel.graphics.endFill();
        _panel.filters = [ new DropShadowFilter() ];

        _canvas = new CanvasSprite(_prefix, 640, 480);

        _panel.addChild(_canvas);

        _tickerContainer.x = 200;
        _panel.addChild(_tickerContainer);

        _roster.x = 400;
        _panel.addChild(_roster);

        var guesser :TextField = TextFieldUtil.createField("Type here",
            { borderColor: 0, type: TextFieldType.INPUT, restrict: "A-Za-z " });
        guesser.addEventListener(KeyboardEvent.KEY_DOWN, function (event :KeyboardEvent) :void {
            if (event.keyCode == Keyboard.ENTER) {
                Command.dispatch(guesser, ScribbleController.PICTIONARY_GUESS, guesser.text);
                guesser.text = "";
            }
        });
        _panel.addChild(guesser);

        var toolbox :Sprite = _canvas.createToolbox();
        toolbox.y = _canvas.height - toolbox.height;
        _panel.addChild(toolbox);

        addChild(_panel);

        var screen :Rectangle = Game.ctrl.local.getPaintableArea();

        _panel.y = -_panel.height;
        _slideIn = new GTween(_panel, 2, {y: (screen.height-_panel.height)/2}, {autoPlay: false});
        _slideIn.addEventListener(Event.COMPLETE, onSlideComplete);

        onResize();

        addEventListener(Event.ADDED_TO_STAGE, function (... _) :void {
            _canvas.init(false);
            updatePhase();
            initRoster();

            Game.ctrl.room.props.addEventListener(PropertyChangedEvent.PROPERTY_CHANGED, onRoomPropertyChanged);
            Game.ctrl.room.props.addEventListener(ElementChangedEvent.ELEMENT_CHANGED, onRoomElementChanged);
            Game.ctrl.player.addEventListener(MessageReceivedEvent.MESSAGE_RECEIVED, onPlayerMessage);
            Game.ctrl.room.addEventListener(MessageReceivedEvent.MESSAGE_RECEIVED, onRoomMessage);
            Game.ctrl.local.addEventListener(AVRGameControlEvent.SIZE_CHANGED, onResize);
        });
        addEventListener(Event.REMOVED_FROM_STAGE, function (... _) :void {
            Game.ctrl.room.props.removeEventListener(PropertyChangedEvent.PROPERTY_CHANGED, onRoomPropertyChanged);
            Game.ctrl.room.props.removeEventListener(ElementChangedEvent.ELEMENT_CHANGED, onRoomElementChanged);
            Game.ctrl.player.removeEventListener(MessageReceivedEvent.MESSAGE_RECEIVED, onPlayerMessage);
            Game.ctrl.room.removeEventListener(MessageReceivedEvent.MESSAGE_RECEIVED, onRoomMessage);
            Game.ctrl.local.removeEventListener(AVRGameControlEvent.SIZE_CHANGED, onResize);
        });
    }

    protected function onResize (... _) :void
    {
        var screen :Rectangle = Game.ctrl.local.getPaintableArea();
        if (screen != null) {
            _panel.x = (screen.width-_panel.width)/2; // Center horizontal
        }
    }

    public override function didEnter () :void
    {
        if (_slideIn.state == GTween.BEGINNING) {
            _slideIn.play();
        } else {
            GraphicsUtil.flip(_slideIn);
            _transitionReversed = !_transitionReversed;
        }
    }

    protected function onSlideComplete (event :Event) :void
    {
        if (_transitionReversed) {
            super.didLeave();
        }
    }

    public override function didLeave () :void
    {
        GraphicsUtil.flip(_slideIn);
        _transitionReversed = !_transitionReversed;
    }

    protected function setTicker (duration :int) :void
    {
        clearTicker();
        _tickerContainer.addChild(
            new TickerSprite(Game.ctrl.room.props, Codes.keyTicker(_prefix), duration));
    }

    protected function clearTicker () :void
    {
        GraphicsUtil.removeAllChildren(_tickerContainer);
    }

    protected function updatePhase () :void
    {
        switch (_logic.getPhase()) {
            case PictionaryLogic.PHASE_INTERMISSION:
                setTicker(PictionaryLogic.DELAY_INTERMISSION);
                Game.ctrl.local.feedback("= Intermission");
                break;

            case PictionaryLogic.PHASE_PAUSE:
                clearTicker();
                Game.ctrl.local.feedback("= Pause");
                break;

            case PictionaryLogic.PHASE_PLAYING:
                setTicker(PictionaryLogic.DELAY_PLAYING);
                Game.ctrl.local.feedback("= Playing");
                break;

            case PictionaryLogic.PHASE_NOT_ENOUGH_PLAYERS:
                clearTicker();
                Game.ctrl.local.feedback("= Not enough players");
                break;
        }
    }

    protected function initRoster () :void
    {
        _roster.clear();

        var modes :Dictionary = Dictionary(Game.ctrl.room.props.get(Codes.PLAYER_MODES));
        var roster :Dictionary = _logic.getRoster();

        for (var key :String in roster) {
            var rosterId :int = int(key);
            var playerId :int = roster[rosterId];
            var scores :Dictionary = _logic.getScores();
            if (playerId in modes && modes[playerId] == Codes.CANVAS_PICTIONARY) {
                _roster.add(rosterId, Game.getName(playerId));
                _roster.setScore(rosterId, scores[rosterId]);
            }
        }
    }

    protected function onRoomPropertyChanged (event :PropertyChangedEvent) :void
    {
        switch (event.name) {
            case Codes.keyPhase(_prefix):
                updatePhase();
                break;

            case Codes.keyTurnHolder(_prefix):
                _roster.setTurnHolder(_logic.getTurnHolder());
                break;

            case Codes.keyScores(_prefix):
                if (event.newValue == null) {
                    for (var rosterId :String in _logic.getRoster()) {
                        _roster.setScore(int(rosterId), 0);
                    }
                } else {
                    Game.log.warning("Scores set to something other than null?", "value", event.newValue);
                }
                break;
        }
    }

    protected function onRoomElementChanged (event :ElementChangedEvent) :void
    {
        switch (event.name) {
            case Codes.PLAYER_MODES:
                var rosterId :int = _logic.getRosterId(event.key);
                if (event.oldValue == Codes.CANVAS_PICTIONARY) {
                    _roster.remove(rosterId);
                }
                if (event.newValue == Codes.CANVAS_PICTIONARY) {
                    _roster.add(rosterId, Game.getName(event.key));
                    _roster.setScore(rosterId, _logic.getScores()[rosterId]);
                }
                break;

            case Codes.keyScores(_prefix):
                _roster.setScore(event.key, int(event.newValue));
                break;
        }
    }

    protected function onPlayerMessage (event :MessageReceivedEvent) :void
    {
        if (event.name == Codes.MESSAGE_SECRET_WORD) {
            //_word = event.value;
        }
    }

    protected function onRoomMessage (event :MessageReceivedEvent) :void
    {
    }

    REMOTE function sendWord (word :String) :void
    {
        Game.ctrl.local.feedback("Got secret word: " + word);
    }

    protected var _panel :Sprite = new Sprite(); // Holds the goods

    protected var _roster :RosterSprite = new RosterSprite();
    protected var _tickerContainer :Sprite = new Sprite();
    protected var _canvas :CanvasSprite;

    protected var _prefix :String;
    protected var _logic :PictionaryLogic;

    protected var _slideIn :GTween;
    protected var _transitionReversed :Boolean;
}

}
