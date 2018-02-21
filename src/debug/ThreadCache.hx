package debug;
import cpp.vm.Mutex;

enum VarRef {
  StackFrame(thread_id:Int, frame_id:Int);
  StackVar(thread_id:Int, frame_id:Int, expr:String);
}

class ThreadCache {
  var _context:debug.Context;
  var _current_thread:Int;
  var _current_frame:Int;
  var _cached:debugger.IController.ThreadWhereList;
  var _current_thread_mutex:cpp.vm.Mutex;
  var _cache_lock:cpp.vm.Lock;
  var _var_refs:Array<VarRef>;
  var _var_ref_map:Map<VarRef, Int>;
  var _var_ref_len = 0;

  public function new(context) {
    _current_thread_mutex = new cpp.vm.Mutex();
    _cache_lock = new cpp.vm.Lock();
    _cache_lock.release();
    _cached = Terminator;
    _var_refs = [];
    _var_ref_map = new Map();
    _context = context;
  }

  public function get_or_create_var_ref(vr:VarRef):Int {
    _current_thread_mutex.acquire();
    switch(vr) {
    case StackVar(_, _, expr) if (expr.indexOf('.') >= 0 || expr.indexOf('(') >= 0 || expr.indexOf('[') >= 0): // don't even bother checking
      var newRef = _var_refs.push(vr) - 1;
      _current_thread_mutex.release();
      return newRef;
    case _:

    }
    var existing = _var_ref_map[vr];
    if (existing != null) {
      _current_thread_mutex.release();
      return existing;
    }
    var newRef = _var_refs.push(vr) - 1;
    _var_ref_map[vr] = newRef;
    _current_thread_mutex.release();
    return newRef;
  }

  public function reset() {
    _cache_lock.wait();
    _cached = Terminator;
    _cache_lock.release();
  }

  public function do_with_frame(thread_id:Int, frame_id:Int, cb:Null<debugger.IController.Message>->Void) {
    do_with_thread(thread_id, function(msg) {
      if (msg != null) {
        cb(msg);
        return;
      }
      if (_current_frame == frame_id) {
        cb(null);
      } else {
        switch(_context.add_debugger_command_sync(SetFrame(frame_id))) {
        case ThreadLocation(_):
          _current_frame = frame_id;
          cb(null);
        case err:
          cb(err);
        }
      }
    });
  }

  public function get_threads_where(cb:debugger.IController.Message->Void) {
    _cache_lock.wait();
    _context.add_debugger_command(WhereAllThreads, function(msg) {
      switch (msg) {
      case ThreadsWhere(list):
        _cached = list;
      case _:
        _cached = Terminator;
      }
      _cache_lock.release();
      cb(msg);
    });
  }

  public function get_thread_info(number:Int, cb:debugger.IController.Message->Void) {
    _cache_lock.wait();
    var cache = _cached;
    while (cache != null) {
      switch(cache) {
      case Terminator:
        break;
      case Where(num, _, _, next):
        if (num == number) {
          _cache_lock.release();
          cb(ThreadsWhere(cache));
          return;
        }
        cache = next;
      }
    }
    do_with_thread(number, function(msg) {
      if (msg != null) {
        _cache_lock.release();
        cb(msg);
        return;
      }
      var ret = _context.add_debugger_command_sync(WhereCurrentThread(false));
      switch(ret) {
      case ThreadsWhere(Where(num,status,frame_list,next)):
        _cached = Where(num,status,frame_list,_cached);
      case _:
      }
      _cache_lock.release();
      cb(ret);
    });
  }

  public function do_with_thread(number:Int, fn:Null<debugger.IController.Message>->Void) {
    _current_thread_mutex.acquire();
    var err = null;
    if (_current_thread != number) {
      var msg = _context.add_debugger_command_sync(SetCurrentThread(number));
      switch(msg) {
        case ThreadLocation(_,stack_frame_id,_,_,_,_):
          _current_thread = number;        
          _current_frame = stack_frame_id;
        case OK:
          _current_thread = number;        
          _current_frame = -1; // apparently this happens if the thread is running
        case e:
          err = e;
      }
    }
    fn(err);
    _current_thread_mutex.release();
  }
}