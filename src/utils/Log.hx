package utils;
#if !macro
import vscode.debugger.Data;
import haxe.PosInfos;
#else
import haxe.macro.Expr;
import haxe.macro.Context;

using haxe.macro.Tools;
#end

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
#if macro
  static function log_with_level(level:Expr, msg:Expr, ?pos:Expr) {
    var call = macro @:pos(msg.pos) utils.Log.Log_Helper.log_with_level($level, $msg);
    if (pos == null || pos.expr.match(EConst(CIdent("null")))) {
      call = macro utils.Log.Log_Helper.log_with_level($level, $msg, $pos);
    }
    return macro @:pos(msg.pos) if ($level == utils.Log.LogLevel.Fatal || debug.Context.instance.has_recorder() || debug.Context.instance.get_settings().logLevel >= $level.int()) {
      $call;
    } else {
      null;
    }
  }
#else
  inline public static function fatal(msg:String, ?pos:haxe.PosInfos):Dynamic {
    return utils.Log.Log_Helper.fatal(msg, pos);
  }

#end

  macro public static function log(msg:Expr, ?pos:Expr) {
    return log_with_level(macro utils.Log.LogLevel.OnlyLog, msg, pos);
  }

  macro public static function verbose(msg:Expr, ?pos:Expr) {
    return log_with_level(macro utils.Log.LogLevel.Verbose, msg, pos);
  }

  macro public static function very_verbose(msg:Expr, ?pos:Expr) {
    return log_with_level(macro utils.Log.LogLevel.VeryVerbose, msg, pos);
  }

  macro public static function warn(msg:Expr, ?pos:Expr) {
    return log_with_level(macro utils.Log.LogLevel.Warning, msg, pos);
  }

  macro public static function error(msg:Expr, ?pos:Expr) {
    return log_with_level(macro utils.Log.LogLevel.Error, msg, pos);
  }

  macro public static function assert(cond:ExprOf<Bool>, ?msg:ExprOf<String>, ?pos:Expr) {
    var epos = Context.currentPos();
    var call = macro @:pos(epos) utils.Log.Log_Helper.log_with_level(Fatal, ("assertion failed: " + $v{cond.toString()} + $msg), $pos);
    if (pos == null || pos.expr.match(EConst(CIdent("null")))) {
      call = macro @:pos(epos) utils.Log.Log_Helper.log_with_level(Fatal, ("assertion failed: " + $v{cond.toString()} + $msg));
    }
    return macro @:pos(epos) if (!($cond)) {
      $call;
    }
  }
}

#if !macro
class Log_Helper {
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
#end