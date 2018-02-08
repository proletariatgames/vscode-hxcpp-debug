package utils;
import vscode.debugger.Data;
import cpp.vm.Deque;
import haxe.PosInfos;

@:enum abstract LogLevel(Int) {
    var VeryVerbose = 1;
    var Verbose = 10;
    var Log = 20;
    var Warning = 50;
    var Error = 100;

    inline public function int() {
        return this;
    }
}

class Log {
    public static function log_with_level(level:LogLevel, msg:String, ?pos:PosInfos) {
        var data:OutputEvent = {
            type: Event,
            event: Output,
            seq: 0,
            body: {
                category: level.int() < Warning.int() ? Stdout : Stderr,
                output: msg,
            }
        };
        Globals.addStdout(ProtocolMessage.fromEvent(data));
    }

    inline public static function log(msg:String, ?pos:PosInfos) {
        log_with_level(Log, msg, pos);
    }

    inline public static function verbose(msg:String, ?pos:PosInfos) {
        log_with_level(Verbose, msg, pos);
    }

    inline public static function very_verbose(msg:String, ?pos:PosInfos) {
        log_with_level(VeryVerbose, msg, pos);
    }

    inline public static function warn(msg:String, ?pos:PosInfos) {
        log_with_level(Warning, msg, pos);
    }

    inline public static function error(msg:String, ?pos:PosInfos) {
        log_with_level(Error, msg, pos);
    }
}