package scribble.server {

import com.whirled.avrg.*;

import aduros.i18n.MessageUtil;
import aduros.net.REMOTE;
import aduros.net.RemoteCaller;
import aduros.util.F;

import scribble.data.Codes;

public class GameManager
{
    public static const PARLOR_CAPACITY :int = 18;

    public function GameManager (server :Server, ctrl :GameSubControlServer)
    {
        _server = server;
        _ctrl = ctrl;

        _gameReceiver = new RemoteCaller(ctrl, "game");
    }

    protected function requireAdmin (playerId :int) :void
        // throws Error
    {
        if (!Codes.isAdmin(playerId)) {
            throw new Error("Admin permission denied.");
        }
    }

    REMOTE function sendBroadcast (playerId :int, text :String) :void
    {
        requireAdmin(playerId);

        var player :Player = _server.getPlayer(playerId);

        _gameReceiver.apply("broadcast", MessageUtil.pack("m_broadcast", player.getName(), text));
    }

    REMOTE function locatePeers (playerId :int, mode :int) :void
    {
        var result :Array = []; // [ [ [56431, "Bob's room", 4], ... ], [ ... ] ]

        for (var mode :int = 0; mode < 2; ++mode) {
            var rooms :Array = []; // of loose Object
            for each (var room :RoomManager in _server.getRooms()) {
                var pop :int = room.playersInMode(mode);
                if (pop > 0) {
                    rooms.push({
                        roomId: room.ctrl.getRoomId(),
                        name: room.ctrl.getRoomName(),
                        pop: pop
                    });
                }
            }

            var top5 :Array = rooms.sortOn("pop", Array.NUMERIC | Array.DESCENDING).splice(0, 5);

            var modeResult :Array = [];
            for each (var o :Object in top5) {
                Server.log.info("Got Top5 room", "mode", mode, "roomId", o.roomId, "name", o.name, "pop", o.pop);
                modeResult.push([ o.roomId, o.name, o.pop ]);
            }
            result[mode] = modeResult;
        }

        // Respond to client request
        _server.getPlayer(playerId).playerReceiver.apply("peersLocated", result);
    }

    REMOTE function moveToParlor (playerId :int) :void
    {
        _server.getPlayer(playerId).ctrl.moveToRoom(getBestParlor());
    }

    protected function getBestParlor () :int
    {
        var pop :Array = []; // roomId -> population
        for each (var parlorId :int in Codes.PARLORS) {
            var room :RoomManager = _server.getRoom(parlorId);
            pop[parlorId] = (room != null) ? room.ctrl.getPlayerIds().length : 0;
        }

        // List of parlor roomIds that are below max capacity
        var belowCapacity :Array = Codes.PARLORS.filter(function (parlorId :int, ..._) :Boolean {
            return pop[parlorId] < PARLOR_CAPACITY;
        });

        if (belowCapacity.length > 0) {
            // The highest populated room that's below capacity
            return F.foldl(function (bestId :int, parlorId :int) :int {
                return (pop[parlorId] > pop[bestId]) ? parlorId : bestId;
            }, belowCapacity[0], belowCapacity);

        } else {
            // The lowest populated room, if all the rooms are full anyways
            return F.foldl(function (bestId :int, parlorId :int) :int {
                return (pop[parlorId] < pop[bestId]) ? parlorId : bestId;
            }, Codes.PARLORS[0], Codes.PARLORS);
        }
    }

    public function feed (key :String, ... msg) :void
    {
        _gameReceiver.apply("feed", MessageUtil.pack(key, msg));
    }

    protected var _gameReceiver :RemoteCaller;

    protected var _server :Server;
    protected var _ctrl :GameSubControlServer;
}

}
