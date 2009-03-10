package scribble.client {

import flash.display.Sprite;
import flash.events.Event;
import flash.events.KeyboardEvent;
import flash.events.MouseEvent;
import flash.filters.DropShadowFilter;
import flash.geom.Rectangle;
import flash.text.TextField;
import flash.text.TextFieldAutoSize;
import flash.text.TextFieldType;
import flash.ui.Keyboard;
import flash.utils.Dictionary;

import com.gskinner.motion.GTween;

import com.threerings.flash.TextFieldUtil;
import com.threerings.util.Command;

import com.whirled.avrg.*;
import com.whirled.net.*;

import aduros.display.ImageButton;
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

        _inviteButton.y = _panel.height-_inviteButton.height;
        _inviteButton.addEventListener(MouseEvent.CLICK, function(... _) :void {
            Game.ctrl.local.showInvitePage(Messages.en.xlate("picto_invite"));
        });

        _wordField.x = _panel.width;
        _wordField.y = _panel.height - 24;

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
            Game.ctrl.room.addEventListener(MessageReceivedEvent.MESSAGE_RECEIVED, onRoomMessage);
            Game.ctrl.local.addEventListener(AVRGameControlEvent.SIZE_CHANGED, onResize);
        });
        addEventListener(Event.REMOVED_FROM_STAGE, function (... _) :void {
            Game.ctrl.room.props.removeEventListener(PropertyChangedEvent.PROPERTY_CHANGED, onRoomPropertyChanged);
            Game.ctrl.room.props.removeEventListener(ElementChangedEvent.ELEMENT_CHANGED, onRoomElementChanged);
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
                Game.ctrl.local.feedback(Messages.en.xlate("picto_intermission"));
                if (_panel.contains(_inviteButton)) {
                    _panel.removeChild(_inviteButton);
                }
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
                Game.ctrl.local.feedback(Messages.en.xlate("picto_not_enough_players"));
                _panel.addChild(_inviteButton);
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
                var turnHolder :int = _logic.getTurnHolder();

                // If I'm the turn holder
                if (_logic.getPlayerId(turnHolder) == Game.ctrl.player.getPlayerId()) {
                    _panel.addChild(_wordField);
                } else if (_panel.contains(_wordField)) {
                    _panel.removeChild(_wordField);
                }

                _roster.setTurnHolder(turnHolder);
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

    protected function onRoomMessage (event :MessageReceivedEvent) :void
    {
        switch (event.name) {
            case Codes.msgGuess(_prefix):
                Game.ctrl.local.feedback(Messages.en.xlate("picto_guess",
                    Game.getName(_logic.getPlayerId(event.value[0])), event.value[1]));
                break;

            case Codes.msgPass(_prefix):
                Game.ctrl.local.feedback(Messages.en.xlate("picto_pass",
                    Game.getName(_logic.getPlayerId(_logic.getTurnHolder())), event.value));
                break;
        }
    }

    REMOTE function sendWord (word :String) :void
    {
        _wordField.text = word;
        Game.log.info("Got word to draw", "word", word);
    }

    protected var _panel :Sprite = new Sprite(); // Holds the goods

    protected var _roster :RosterSprite = new RosterSprite();
    protected var _tickerContainer :Sprite = new Sprite();
    protected var _canvas :CanvasSprite;

    [Embed(source="../../../res/invite.png")]
    protected static const ICON_INVITE :Class;
    protected var _inviteButton :ImageButton = new ImageButton(new ICON_INVITE());

    protected var _wordField :TextField = TextFieldUtil.createField("",
        { textColor: 0xffffff, selectable: false,
            autoSize: TextFieldAutoSize.RIGHT, outlineColor: 0x00000 },
        { font: "_sans", size: 24, bold: true });

    protected var _prefix :String;
    protected var _logic :PictionaryLogic;

    protected var _slideIn :GTween;
    protected var _transitionReversed :Boolean;
}

}
