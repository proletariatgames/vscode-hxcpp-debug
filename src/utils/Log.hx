package utils;
import vscode.debugger.Data;
import haxe.PosInfos;

@:enum abstract LogLevel(Int) {
    var VeryVerbose = 100;
    var Verbose = 50;
    var OnlyLog = 10;
    var Warning = 5;
    var Error = 1;
    var Fatal = 0;

    inline public function int() {
        return this;
    }
}

class Log {
    public static function log_with_level(level:LogLevel, msg:String, ?pos:PosInfos) {
        Globals.record_log(level, msg, pos);
        if (level != Fatal && Globals.get_settings().logLevel < level.int()) {
            return;
        }

        for (piece in msg.split('\n')) {
            var data:OutputEvent = {
                type: Event,
                event: Output,
                seq: 0,
                body: {
                    category: level.int() > Warning.int() ? Stdout : Stderr,
                    output: piece + '\n',
                }
            };
            Globals.add_stdout(data);
        }
    }

    inline public static function log(msg:String, ?pos:PosInfos) {
        log_with_level(OnlyLog, msg, pos);
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

    inline public static function fatal(msg:String, ?pos:PosInfos) {
        log_with_level(Fatal, msg, pos);
        Globals.exit(1);
    }
}