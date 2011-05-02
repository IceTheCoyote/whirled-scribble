package scribble.server {

import flash.utils.ByteArray;
import flash.utils.Dictionary;

import com.whirled.avrg.*;
import com.whirled.net.*;

import aduros.net.REMOTE;
import aduros.net.BatchInvoker;
import aduros.util.F;

import scribble.data.Codes;

public class RoomManager
{
    public function RoomManager (ctrl :RoomSubControlServer)
    {
        test = ctrl;

        test.addEventListener(AVRGameRoomEvent.PLAYER_LEFT, onPlayerLeft);
        test.addEventListener(AVRGameRoomEvent.SIGNAL_RECEIVED, onSignal);
        test.addEventListener(AVRGameRoomEvent.ROOM_UNLOADED, onRoomUnloaded);

        const self :RoomManager = this; // Fucking Actionscript
        test.doBatch(function () :void {
            // Reinitialize memory. It turns out if a game is rebooted by the owner uploading a new
            // version, non-persistent memory sticks around!
            test.props.set(Codes.PLAYER_MODES, null, true);

            _pictionary = new PictionaryCanvas(1, self);

            _canvases.push(new BackdropCanvas(0, self));
            _canvases.push(_pictionary);
        });

        _invoker = new BatchInvoker(test);
        _invoker.start(200);
    }

    public function get ctrl () :RoomSubControlServer
    {
        return test;
    }

    /** All the players in this room. */
    public function get players () :Dictionary
    {
        return _players; // TODO: Necessary?
    }

    /** Counts the number of players in this room that are in the given mode. */
    public function playersInMode (mode :int) :int
    {
        var count :int = 0;
        for each (var m :int in test.props.get(Codes.PLAYER_MODES)) {
            if (m == mode) {
                count += 1;
            }
        }
        return count;
    }

    protected function onPlayerLeft (event :AVRGameRoomEvent) :void
    {
        _invoker.push(F.callback(setMode, event.value, null));
    }

    protected function onSignal (event :AVRGameRoomEvent) :void
    {
        if (event.name == "quest:kill") {
            var killerId :int = event.value[0];
            var level :int = event.value[2];
            var mode :int = event.value[3];
            if (killerId in _players && mode == 0 && level >= 120) {
                Player(_players[killerId]).stats.submit("killedMonster", true);
            }
        }
    }

    protected function onRoomUnloaded (event :AVRGameRoomEvent) :void
    {
        _invoker.stop();
    }

    protected function getCanvas (playerId :int) :Canvas
    {
        var modes :Dictionary = Dictionary(test.props.get(Codes.PLAYER_MODES));
        if (modes == null) {
            throw new Error("Modes dictionary not found.");
        }

        var canvas :Canvas = Canvas(_canvases[modes[playerId]]);
        if (canvas == null) {
            throw new Error("No valid mode found for player.");
        }

        return canvas;
    }

    public function setMode (playerId :int, newMode :Object) :void
    {
        var modes :Dictionary = Dictionary(test.props.get(Codes.PLAYER_MODES));

        if (modes != null && playerId in modes) {
            var oldMode :int = int(modes[playerId]);
            Canvas(_canvases[oldMode]).playerDidClose(playerId);
        }

        if (newMode != null) {
            Canvas(_canvases[newMode]).playerDidOpen(playerId);
        }

        test.props.setIn(Codes.PLAYER_MODES, playerId, newMode, true);
    }

    REMOTE function changeMode (playerId :int, mode :int) :void
    {
        // For the sake of keeping a snappy UI, this isn't put on the batch invoker
        test.doBatch(setMode, playerId, mode);
    }

    REMOTE function sendStroke (playerId :int, strokeBytes :ByteArray) :void
    {
        _invoker.push(F.callback(getCanvas(playerId).sendStroke, playerId, strokeBytes));
    }

    REMOTE function sendStrokeList (playerId :int, list :Array) :void
    {
        _invoker.push(F.callback(getCanvas(playerId).sendStrokeList, playerId, list));
    }

    REMOTE function removeStrokes (playerId :int, strokeIds :Array) :void
    {
        _invoker.push(F.callback(getCanvas(playerId).removeStrokes, playerId, strokeIds));
    }

    REMOTE function clearCanvas (playerId :int) :void
    {
        _invoker.push(F.callback(getCanvas(playerId).clearCanvas, playerId));
    }

    REMOTE function pictionaryPass (playerId :int) :void
    {
        _invoker.push(F.callback(_pictionary.pass, playerId));
    }

    REMOTE function pictionaryGuess (playerId :int, guess :String) :void
    {
        _invoker.push(F.callback(_pictionary.guess, playerId, guess));
    }

    REMOTE function toggleLock (playerId :int) :void
    {
        _invoker.push(getCanvas(playerId).toggleLock);
    }

    protected var test :RoomSubControlServer;
    protected var _players :Dictionary = new Dictionary(); // playerId -> Player

    protected var _canvases :Array = []; // of Canvas
    protected var _pictionary :PictionaryCanvas;

    protected var _invoker :BatchInvoker;
}

}
