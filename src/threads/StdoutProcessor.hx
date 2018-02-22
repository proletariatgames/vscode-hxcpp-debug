package threads;
import cpp.vm.Deque;

class StdoutProcessor {
  public var stdout(default, null):Deque<String> = new Deque();
  var _thread_spawned = false;
  var _context:debug.Context;

  public function new(ctx) {
    _context = ctx;
  }

  public function spawn_thread() {
    if (_thread_spawned) {
      throw 'Thread already spawned';
    }
    _thread_spawned = true;
    cpp.vm.Thread.create(function() {
      var isWindows = Sys.systemName() == "Windows";
      var separator = isWindows ? '\n\n' : '\r\n\r\n';
      var stdoutOutput = Sys.stdout();
      var stdout = this.stdout;
      while (true) {
        try {
          var msg = stdout.pop(true);
          if (msg == null) {
            break;
          }
          var buf = new StringBuf();
          for (i in 0...msg.length) {
            var code = StringTools.fastCodeAt(msg, i);
            if (code < ' '.code) {
              buf.addChar(' '.code);
            } else {
              buf.addChar(code);
            }
          }
          msg = buf.toString();
          var str = 'Content-Length: ${msg.length}$separator$msg';

#if DEBUG_PROTOCOL
          _context.record_io(false, str);
#else
          _context.record_io(false, msg);
#end
          stdoutOutput.writeString(str);
          stdoutOutput.flush();
        } catch(e:Dynamic) {
          utils.Log.error('Internal Debugger Error: Error on stdout thread: $e');
          utils.Log.verbose(haxe.CallStack.toString(haxe.CallStack.exceptionStack()));
        }
      }
      Sys.stdout().flush();
      utils.Log.very_verbose('StdoutProcessor: Exit signal received');
      _context.exit_lock.release();
    });
  }
}