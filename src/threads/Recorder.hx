package threads;

class Recorder {
  var _context:debug.Context;
  var _thread_spawned = false;

  public function new(ctx) {
    _context = ctx;
  }

  public function spawn_thread(output:String) {
    if (_thread_spawned) {
      throw 'Thread already spawned';
    }
    _thread_spawned = true;

    var out = sys.io.File.write(output, false);
    cpp.vm.Thread.create(function() {
      var data = _context.recorder;
      while (true) {
        try {
          var cur = data.pop(true);
          if (cur == null) {
            break;
          }
          var buf = new StringBuf();
          buf.add(cur.date);
          if (cur.io) {
            if (cur.input) {
              buf.add(' <--');
            } else {
              buf.add(' -->');
            }
            #if DEBUG_MESSAGES
            buf.add('\n');
            #else
            buf.add(' ');
            #end

            buf.add(cur.msg);
            
            buf.add('\n');
            #if DEBUG_MESSAGES
            buf.add('--------------------------------------------\n\n');
            #end
          } else {
            buf.add(' === ');
            switch(cur.log) {
              case VeryVerbose:
                buf.add('[VVBOSE ] ');
              case Verbose:
                buf.add('[VERBOSE] ');
              case OnlyLog:
                buf.add('[LOG    ] ');
              case Warning:
                buf.add('[WARNING] ');
              case Error:
                buf.add('[ERROR   ] ');
              case Fatal:
                buf.add('[FATAL   ] ');
            }
            buf.add(cur.msg);
            buf.add('\n');
          }
          
          out.writeString(buf.toString());
          out.flush();
        } catch(e:Dynamic) {
          data.push({ io:false, msg:'ERROR on the log recorder thread: $e', log:Error, date:Date.now() });
        }
      }
      _context.exit_lock.release();
    });
  }
}