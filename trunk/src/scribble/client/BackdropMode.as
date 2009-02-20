package scribble.client {

import flash.display.Sprite;
import flash.events.Event;
import flash.geom.Rectangle;

import com.gskinner.motion.GTween;

import com.whirled.avrg.MobSubControlClient;
import com.whirled.avrg.AVRGameControlEvent;

import scribble.data.Codes;

public class BackdropMode extends ModeSprite
{
    public function BackdropMode ()
    {
        // One time setting. These bounds aren't updated when the backdrop changes
        // Consider just making the bounds [MAX_INT, MAX_INT]?
        var bounds :Array = Game.ctrl.local.getRoomBounds();
        _canvas = new CanvasSprite(Codes.CANVAS_PREFIXES[Codes.CANVAS_ROOM],
            bounds[0], bounds[1], this);

        //addChild(_canvas);

        _toolbox = _canvas.createToolbox();
        addChild(_toolbox);

        onResize();
        _toolbox.y += _toolbox.height;

        _slideIn = new GTween(_toolbox, 2, {y: _toolbox.y-_toolbox.height}, {autoPlay: false});
        _fadeOut = new GTween(this, 2, {alpha: 0}, {autoPlay: false});
        _fadeOut.addEventListener(Event.COMPLETE, onFadeComplete);
    }

    protected function onFadeComplete (event :Event) :void
    {
        if (alpha == 0) {
            super.didLeave();
        }
    }

    override public function didEnter () :void
    {
        var mob :MobSubControlClient = Game.ctrl.room.getMobSubControl(Codes.MOB_FOREGROUND);
        if (mob != null) {
            Sprite(mob.getMobSprite()).addChild(_canvas);
            mob.setHotSpot(_canvas.width/2, _canvas.height, 0);
        } else {
            Game.log.warning("Where's the mob?");
        }

        if (_transition == 0) {
            _slideIn.play();
            _transition = 1;
        } else {
            GraphicsUtil.flip(_slideIn);
            GraphicsUtil.flip(_fadeOut);
            _transition = 2;
        }

        _canvas.init(true);

        Game.ctrl.local.addEventListener(AVRGameControlEvent.SIZE_CHANGED, onResize);
    }

    protected function onResize (... _) :void
    {
        var screen :Rectangle = Game.ctrl.local.getPaintableArea();

        // Bind to bottom right
        _toolbox.x = screen.width-_toolbox.width;
        _toolbox.y = screen.height-_toolbox.height;
    }

    override public function didLeave () :void
    {
        var mob :MobSubControlClient = Game.ctrl.room.getMobSubControl(Codes.MOB_FOREGROUND);
        Sprite(mob.getMobSprite()).removeChild(_canvas);

        GraphicsUtil.flip(_slideIn);

        if (_transition == 1) {
            _fadeOut.play();
        } else {
            GraphicsUtil.flip(_fadeOut);
        }
        _transition = 2;

        Game.ctrl.local.removeEventListener(AVRGameControlEvent.SIZE_CHANGED, onResize);
    }

    protected var _canvas :CanvasSprite;
    protected var _toolbox :Sprite;

    // Transitions
    protected var _slideIn :GTween;
    protected var _fadeOut :GTween;
    protected var _transition :int = 0;
}

}
