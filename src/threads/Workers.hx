package threads;
#if haxe4
import sys.thread.Deque;
import sys.thread.Thread;
#else
import cpp.vm.Deque;
import cpp.vm.Thread;
#end

import utils.Log;

class Workers {
  public var worker_fns(default, null):Deque<Void->Void> = new Deque();
  var _context:debug.Context;
  var _thread_spawned = false;

  public function new(ctx) {
    _context = ctx;
  }

  public function create_workers(amount:Int) {
    if (_thread_spawned) {
      throw 'Thread already spawned';
    }
    _thread_spawned = true;

    Log.verbose('Creating $amount workers');
    for (i in 0...amount) {
      Thread.create(function() {
        try {
          while(true) {
            var cb = worker_fns.pop(true);
            if (cb == null) {
              Log.verbose('Worker $i received exit signal');
              // tell othere
              worker_fns.push(null);
              break;
            }
            cb();
          }
        }
        catch(e:Dynamic) {
          Log.fatal('Error on a worker thread: $e');
        }
      });
    }
  }
}