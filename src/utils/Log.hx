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
    var loggedMsg = msg;
    if (pos != null) {
      loggedMsg = pos.fileName + ':' + pos.lineNumber + ': ' + msg;
    }
    debug.Context.instance.record_log(level, loggedMsg, pos);
    if (level != Fatal && debug.Context.instance.get_settings().logLevel < level.int()) {
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
      debug.Context.instance.add_stdout(data);
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
    log_with_level(Warning, 'Warning: ' +  msg, pos);
  }

  inline public static function error(msg:String, ?pos:PosInfos) {
    log_with_level(Error, msg, pos);
  }

  inline public static function fatal(msg:String, ?pos:PosInfos):Dynamic {
    log_with_level(Fatal, msg, pos);
    debug.Context.instance.exit(1);
    throw 'assert';
  }

  inline public static function assert(cond:Bool, msg:String, ?pos:PosInfos) {
    if (!cond) {
      log_with_level(Fatal, msg, pos);
    }
  }
}