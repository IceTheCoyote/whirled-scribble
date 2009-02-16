package scribble.data {

import com.whirled.net.NetConstants;

public class Codes
{
    public static const BRUSH_COLORS :Array = [
        0xffffff,
        0x000000,
        0xff0000,
        0x0000ff,
        0xffff00,
        0x00ff00,
        0x964B00,
        0xff00ff,
        0xc0c0c0,
    ];

    public static const BRUSH_WIDTHS :Array = [
        8,
        4,
        4,
        4,
        4,
        4,
        4,
        4,
        4,
    ];

    // Different canvases/modes within a room, don't mess with these numbers
    public static const CANVAS_ROOM :int = 0;
    public static const CANVAS_PICTIONARY :int = 1;
    public static const CANVAS_EXHIBIT :int = 2;

    public static const CANVAS_PREFIXES :Array = [ NetConstants.makePersistent("0"), "1", "2" ];

    /** A room property (Dictionary) that maps playerId to canvasIndex. */
    public static const PLAYER_MODES :String = "mode";

    // Phases within Pictionary
    public static const PHASE_NOT_ENOUGH_PLAYERS :int = 0;
    public static const PHASE_INTERMISSION :int = 1;
    public static const PHASE_PLAYING :int = 2;
    public static const PHASE_PAUSE :int = 3;

    public static const MESSAGE_BROADCAST :String = "broadcast"; // on Game
    public static const MESSAGE_FEED :String = "feed"; // on Game

    public static function isAdmin (playerId :int) :Boolean
    {
        return playerId == 878;
    }

    public static function keyCanvas (prefix :String) :String
    {
        return prefix + "canvas"; // Dictionary
    }

    public static function keyScores (prefix :String) :String
    {
        return prefix + "scores"; // Dictionary
    }

    public static function keyRoster (prefix :String) :String
    {
        return prefix + "roster"; // Dictionary
    }

    public static function keyTurnHolder (prefix :String) :String
    {
        return prefix + "turnHolder"; // int
    }

    public static function keyPhase (prefix :String) :String
    {
        return prefix + "phase"; // int
    }

    public static function keyTicker (prefix :String) :String
    {
        return prefix + "ticker"; // int
    }
}

}
