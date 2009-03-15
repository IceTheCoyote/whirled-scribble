package scribble.client {

import flash.display.Sprite;
import flash.events.Event;
import flash.events.KeyboardEvent;
import flash.events.MouseEvent;
import flash.filters.DropShadowFilter;
import flash.geom.Rectangle;
import flash.net.URLRequest;
import flash.net.URLVariables;
import flash.text.TextField;
import flash.text.TextFieldAutoSize;
import flash.ui.Keyboard;
import flash.utils.Dictionary;

import com.gskinner.motion.GTween;

import com.threerings.flash.TextFieldUtil;
import com.threerings.util.Command;

import com.whirled.*;
import com.whirled.avrg.*;
import com.whirled.net.*;

import aduros.display.DisplayUtil;
import aduros.display.ImageButton;
import aduros.net.REMOTE;

import scribble.data.Codes;
import scribble.data.PictionaryLogic;

public class PictionaryMode extends ModeSprite
{
    public static const CANVAS_WIDTH :int = 400;
    public static const CANVAS_HEIGHT :int = 300;
    public static const SPACING :int = 8;

    public function PictionaryMode ()
    {
        _prefix = Codes.CANVAS_PREFIXES[Codes.CANVAS_PICTIONARY];
        _logic = new PictionaryLogic(_prefix, Game.ctrl.room.props);

        _panel = new Sprite();
        _panel.graphics.beginFill(0xffffff);
        _panel.graphics.drawRect(0, 0, CANVAS_WIDTH, CANVAS_HEIGHT);
        _panel.graphics.endFill();

        _panel.addChild(_wordField);
        _panel.addChild(_hintField);

        _canvas = new CanvasSprite(_prefix, CANVAS_WIDTH, CANVAS_HEIGHT);
        _panel.addChild(_canvas);

        _tickerContainer.x = CANVAS_WIDTH + RosterSprite.WIDTH/2 - TickerSprite.RADIUS;
        _tickerContainer.y = SPACING;
        _panel.addChild(_tickerContainer);

        _roster.x = CANVAS_WIDTH;
        _roster.y = 2*TickerSprite.RADIUS + 2*SPACING + 1;
        _panel.addChild(_roster);

        _toolbox = _canvas.createToolbox();
        _toolbox.y = CANVAS_HEIGHT;
        _panel.addChild(_toolbox);

        _panel.graphics.beginFill(0xc0c0c0);
        _panel.graphics.drawRect(0, CANVAS_HEIGHT, CANVAS_WIDTH, _toolbox.height);
        _panel.graphics.drawRect(CANVAS_WIDTH, 0, RosterSprite.WIDTH, 2*SPACING + 2*TickerSprite.RADIUS);
        _panel.graphics.endFill();

        _panel.filters = [ new DropShadowFilter() ];
        addChild(_panel);

        _turnHolderControls.x = CANVAS_WIDTH;

        Command.bind(_passButton, MouseEvent.CLICK, ScribbleController.PICTIONARY_PASS);
        _turnHolderControls.addChild(_passButton);

        _referenceButton.x = _passButton.width;
        _referenceButton.addEventListener(MouseEvent.CLICK, function (... _) :void {
            var data :URLVariables = new URLVariables();
            data.hl = "en";
            data.q = _wordField.text;

            var url :URLRequest = new URLRequest("http://images.google.com/images");
            url.data = data;

            flash.net.navigateToURL(url, "_blank");
        });
        _turnHolderControls.addChild(_referenceButton);

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
            Game.ctrl.room.addEventListener(ControlEvent.CHAT_RECEIVED, onChat);
        });
        addEventListener(Event.REMOVED_FROM_STAGE, function (... _) :void {
            Game.ctrl.room.props.removeEventListener(PropertyChangedEvent.PROPERTY_CHANGED, onRoomPropertyChanged);
            Game.ctrl.room.props.removeEventListener(ElementChangedEvent.ELEMENT_CHANGED, onRoomElementChanged);
            Game.ctrl.room.removeEventListener(MessageReceivedEvent.MESSAGE_RECEIVED, onRoomMessage);
            Game.ctrl.local.removeEventListener(AVRGameControlEvent.SIZE_CHANGED, onResize);
            Game.ctrl.room.removeEventListener(ControlEvent.CHAT_RECEIVED, onChat);
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
        DisplayUtil.removeAllChildren(_tickerContainer);
    }

    protected function updatePhase () :void
    {
        var canDraw :Boolean = _logic.canDraw(Game.ctrl.player.getPlayerId());

        DisplayUtil.setContains(_panel, _toolbox, canDraw);
        _canvas.enabled = canDraw;

        var phase :int = _logic.getPhase();

        switch (phase) {
            case PictionaryLogic.PHASE_INTERMISSION:
                setTicker(PictionaryLogic.DELAY_INTERMISSION);
                Game.ctrl.local.feedback(Messages.en.xlate("m_picto_intermission"));
                break;

            case PictionaryLogic.PHASE_PAUSE:
                clearTicker();
                Game.ctrl.local.feedback("= Pause");
                break;

            case PictionaryLogic.PHASE_PLAYING:
                setTicker(PictionaryLogic.DELAY_PLAYING);
                setHint(_logic.getHint());
                break;

            case PictionaryLogic.PHASE_NOT_ENOUGH_PLAYERS:
                clearTicker();
                Game.ctrl.local.feedback(Messages.en.xlate("m_picto_notEnoughPlayers"));
                break;
        }

        // Use visible here instead of setContains to not mess with the z-order
        _wordField.visible = (phase == PictionaryLogic.PHASE_PLAYING && canDraw);

        DisplayUtil.setContains(_panel, _turnHolderControls,
            phase == PictionaryLogic.PHASE_PLAYING && canDraw);
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
                _roster.setTurnHolder(event.newValue != null ? int(event.newValue) : -1);
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

            case Codes.keyHint(_prefix):
                setHint(_logic.getHint());
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
            case Codes.msgPass(_prefix):
                Game.ctrl.local.feedback(Messages.en.xlate("m_picto_pass",
                    Game.getName(_logic.getPlayerId(_logic.getTurnHolder())), event.value));
                setHint(event.value as String);
                break;

            case Codes.msgCorrect(_prefix):
                Game.ctrl.local.feedback(Messages.en.xlate("m_picto_correct",
                    Game.getName(event.value[0]),
                    Game.getName(_logic.getPlayerId(_logic.getTurnHolder())),
                    event.value[2],
                    event.value[1]));
                setHint(event.value[1] as String);
                break;
            
            case Codes.msgFail(_prefix):
                Game.ctrl.local.feedback(Messages.en.xlate("m_picto_fail",
                    Game.getName(_logic.getPlayerId(_logic.getTurnHolder())), event.value));
                setHint(event.value as String);
                break;
        }
    }

    protected function setHint (hint :String) :void
    {
        if (hint == null) {
            _hintField.visible = false;
        } else {
            _hintField.visible = true;
            _hintField.text = hint;
        }
    }

    protected function onChat (event :ControlEvent) :void
    {
        var playerId :int = Game.ctrl.player.getPlayerId();
        if (Game.ctrl.room.getEntityProperty(EntityControl.PROP_MEMBER_ID, event.name) == playerId
            && _logic.canGuess(playerId)) {
            Command.dispatch(this, ScribbleController.PICTIONARY_GUESS, event.value);
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

    protected var _toolbox :Sprite;

    [Embed(source="../../../res/pass.png")]
    protected static const ICON_PASS :Class;
    protected var _passButton :ImageButton = new ImageButton(
        new ICON_PASS(), Messages.en.xlate("t_pass"));

    [Embed(source="../../../res/image.png")]
    protected static const ICON_REFERENCE :Class;
    protected var _referenceButton :ImageButton = new ImageButton(
        new ICON_REFERENCE(), Messages.en.xlate("t_reference"));

    protected var _turnHolderControls :Sprite = new Sprite();

    protected var _wordField :TextField = TextFieldUtil.createField("",
        { textColor: 0xffffff, selectable: false, width: 0,
            x: CANVAS_WIDTH-SPACING, y: CANVAS_HEIGHT-24-SPACING,
            autoSize: TextFieldAutoSize.RIGHT, outlineColor: 0x00000 },
        { font: "_sans", size: 24, bold: true });

    protected var _hintField :TextField = TextFieldUtil.createField("",
        { textColor: 0xffffff, selectable: false, width: 0,
            x: 0, y: 0,
            autoSize: TextFieldAutoSize.LEFT, outlineColor: 0x00000 },
        { font: "_sans", size: 24, bold: true });

    protected var _prefix :String;
    protected var _logic :PictionaryLogic;

    protected var _slideIn :GTween;
    protected var _transitionReversed :Boolean;
}

}
