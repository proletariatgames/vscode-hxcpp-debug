package debug;
import cpp.vm.Thread;
import cpp.vm.Deque;
import cpp.vm.Mutex;

import debugger.IController;

import utils.Log;

import vscode.debugger.Data;

using Lambda;
using StringTools;

enum BreakpointOnBreak {
  Internal(fn:Void->Void);
  Normal;
  Conditional(exprCondition:String); 
}

enum BreakpointKind {
  LineBr(file:String, line:Int);
  FuncBr(cls:String, fn:String);
}

enum BreakpointStatus {
  Sending;
  Active;
  Disabled;
  NotFound;
  Error(msg:debugger.IController.Message);
  CustomError(msg:String);
}

typedef Breakpoint = {
  internal_id:Int,
  ?hxcpp_id:Null<Int>,

  on_break:BreakpointOnBreak,
  kind:BreakpointKind,
  status:BreakpointStatus,
}

class Breakpoints {
  var _context:Context;
  var _internal_id = 0;

  var _breakpoints:Map<Int, Breakpoint>;
  var _breakpoints_by_kind:Map<String, Breakpoint>;
  var _hxcpp_to_internal:Map<Int, Int> = new Map();
  var _bp_mutex:cpp.vm.Mutex;

  var _ready:cpp.vm.Deque<{ internal_id: Int, response:debugger.IController.Message }>;
  var _wait_amount:Int = 0;

  public function new(ctx:Context) {
    _context = ctx;

    _ready = new cpp.vm.Deque();
    _breakpoints = new Map();
    _breakpoints_by_kind = new Map();
    _bp_mutex = new cpp.vm.Mutex();
  }

  public function get_breakpoint_from_hxcpp(hxcpp_id:Int):Breakpoint {
    _bp_mutex.acquire();
    var ret = _breakpoints[_hxcpp_to_internal[hxcpp_id]];
    _bp_mutex.release();
    return ret;
  }

  public function get_breakpoint(internal_id:Int):Breakpoint {
    _bp_mutex.acquire();
    var ret = _breakpoints[internal_id];
    _bp_mutex.release();
    return ret;
  }

  private function set_breakpoint(internal_id:Int, bp:Breakpoint) {
    _bp_mutex.acquire();
    _breakpoints[internal_id] = bp;
    _bp_mutex.release();
  }

  public function add_breakpoint(on_break:BreakpointOnBreak, kind:BreakpointKind) {
    Log.assert(cpp.vm.Thread.current().handle == _context.main_thread.handle, "Breakpoint added on a helper thread");
    var desc = Std.string(kind);
    var breakpoint = _breakpoints_by_kind[desc];
    if (breakpoint == null) {
      breakpoint = { internal_id: _internal_id++, kind:kind, on_break:on_break, status:Sending };
      Log.verbose('Adding new breakpoint $breakpoint');
      cmd_add_breakpoint(breakpoint);
    } else {
      Log.verbose('Breakpoint $kind already exists');
      switch [on_break, breakpoint.on_break] {
        case [Internal(_), Internal(_)]:
          breakpoint.on_break = on_break;
        case [Internal(_), _] | [_, Internal(_)]:
          breakpoint.status = CustomError('Cannot replace internal breakpoint');
        case _:
          breakpoint.on_break = on_break;
      }
    }
    return breakpoint.internal_id;
  }

  private function delete_breakpoint(internal_id:Int) {
    Log.assert(cpp.vm.Thread.current().handle == _context.main_thread.handle, "Calling thread is not main thread");
    Log.very_verbose('delete_breakpoint($internal_id)');
    var bp = this._breakpoints[internal_id];
    if (bp == null) {
      Log.verbose('deleting an inexistent breakpoint $internal_id');
      return false;
    }

    if (bp.hxcpp_id != null) {
      _wait_amount++;
      _context.add_debugger_command(DeleteBreakpointRange(bp.hxcpp_id, bp.hxcpp_id), function(msg) {
        _ready.add(null);
      }, false);
    } else {
      Log.verbose('deleting an inactive breakpoint');
    }

    _bp_mutex.acquire();
    this._breakpoints.remove(internal_id);
    _bp_mutex.release();
    this._breakpoints_by_kind.remove(Std.string(bp.kind));
    return true;
  }

  public function vscode_set_breakpoints(request:SetBreakpointsRequest):Void {
    Log.assert(cpp.vm.Thread.current().handle == _context.main_thread.handle, "Setting breakpoints on a different thread");
    wait_all_added();
    // first of all, delete all unreferenced breakpoints
    var full_path = _context.source_files.normalize_full_path(request.arguments.source.path),
        to_delete = [];
    var lines = request.arguments.breakpoints;
    for (bp in _breakpoints) {
      if (bp.on_break.match(Internal(_))) continue;
      switch(bp.kind) {
      case LineBr(file, line) if (file == full_path):
        if (lines == null || !lines.exists(function(src) return src.line == line)) {
          to_delete.push(bp);
        }
      case _:
      }
    }

    for (bp in to_delete) {
      delete_breakpoint(bp.internal_id);
    }
    var ids = [];
    for (line in lines) {
      var on_break = line.condition != null && line.condition.trim().length != 0 ? Conditional(line.condition) : Normal;
      ids.push(this.add_breakpoint(on_break, LineBr(full_path, line.line)));
    }
    
    var bps = [];
    var ret:SetBreakpointsResponse = { type: Response, seq:0, request_seq: request.seq, success:true, command: Std.string(request.command), body: { breakpoints: bps } };
    if (ids.length > 0) {
      wait_all_added();
      for (i in 0...lines.length) {
        var ln = lines[i];
        var id = ids[i];
        var bp = _breakpoints[id];
        var msg = null;
        if (bp.hxcpp_id == null) {
          switch(bp.status) {
            case NotFound:
              msg = 'This source was not found on the binary. It might be loaded dynamically by cppia';
            case Error(err):
              msg = 'Unexpected debugger response $err';
            case CustomError(err):
              msg = err;
            case _:
              Log.error('Unexpected status ${bp.status} for breakpoint $id');
          }
        }

        bps.push({ id: id, verified:bp.hxcpp_id != null, message: msg, line:ln.line });
      }
    }

    _context.add_response(request, ret);
  }

  public function vscode_set_fn_breakpoints(request:SetFunctionBreakpointsRequest):Void {
    Log.assert(cpp.vm.Thread.current().handle == _context.main_thread.handle, "Setting breakpoints on a different thread");
    wait_all_added();
    // first of all, delete all unreferenced breakpoints
    var to_delete = [];
    var bps = request.arguments.breakpoints;
    for (bp in _breakpoints) {
      if (bp.on_break.match(Internal(_))) continue;
      switch(bp.kind) {
      case FuncBr(c,f):
        if (!request.arguments.breakpoints.exists(function(bp) return bp.name == '$c.$f')) {
          to_delete.push(bp);
        }
      case _:
      }
    }

    for (bp in to_delete) {
      delete_breakpoint(bp.internal_id);
    }
    var ids = [];
    for (bp in bps) {
      var on_break = bp.condition != null && bp.condition.trim().length != 0 ? Conditional(bp.condition) : Normal;
      var split = null, chr = null;
      if (bp.name.startsWith('/')) {
        split = ~/[^\\]\//.split(bp.name);
        chr = '/';
      } else {
        split = bp.name.split('.');
        chr = '.';
      }
      var fn = split.pop(),
          cls = split.join(chr);
      ids.push(this.add_breakpoint(on_break, FuncBr(cls, fn)));
    }
    
    var bps = [];
    var ret:SetFunctionBreakpointsResponse = { type: Response, seq:0, request_seq: request.seq, success:true, command: Std.string(request.command), body: { breakpoints: bps } };
    if (ids.length > 0) {
      wait_all_added();
      for (i in 0...bps.length) {
        var ln = bps[i];
        var id = ids[i];
        var bp = _breakpoints[id];
        var msg = null;
        if (bp.hxcpp_id == null) {
          switch(bp.status) {
            case NotFound:
              msg = 'This source was not found on the binary. It might be loaded dynamically by cppia';
            case Error(err):
              msg = 'Unexpected debugger response $err';
            case CustomError(err):
              msg = err;
            case _:
              Log.error('Unexpected status ${bp.status} for breakpoint $id');
          }
        }

        bps.push({ id: id, verified:bp.hxcpp_id != null, message: msg, line:ln.line });
      }
    }

    _context.add_response(request, ret);
  }

  private function cmd_add_breakpoint(bp:Breakpoint) {
    _wait_amount++;
    var internal_id = bp.internal_id;
    _bp_mutex.acquire();
    _breakpoints[internal_id] = bp;
    _bp_mutex.release();
    _breakpoints_by_kind[Std.string(bp.kind)] = bp;
    var cmd = switch (bp.kind) {
      case LineBr(file, line):
        var source_to_send = _context.source_files.get_source_path(file);
        Command.AddFileLineBreakpoint(source_to_send, line);
      case FuncBr(cls, fn):
        Command.AddClassFunctionBreakpoint(cls, fn);
    }
    _context.add_debugger_command(cmd, function(ret) {
      _ready.add({ response: ret, internal_id:internal_id });
    }, false);
  }

  public function refresh_breakpoints() {
    Log.assert(cpp.vm.Thread.current().handle == _context.main_thread.handle, "Breakpoint added on a helper thread");
    if (_wait_amount != 0) {
      wait_all_added();
    }

    for (bp in _breakpoints) {
      var resend = false;
      switch(bp.status) {
      case Sending:
        Log.error('Debugger: Unexpected breakpoint with `sending` status $bp');
      case NotFound | Error(_) | CustomError(_):
        resend = true;
      case Active:
        switch(bp.kind) {
        case FuncBr(c, f) if (c.startsWith('/') || f.startsWith('/')):
          resend = true;
        case _:
        }
      case Disabled:
      }
      if (resend) {
        cmd_add_breakpoint(bp);
      }
    }
  }

  public function wait_all_added() {
    Log.assert(cpp.vm.Thread.current().handle == _context.main_thread.handle, "wait_all_added called on a helper thread");
    for (i in 0..._wait_amount) {
      var id = _ready.pop(true);
      if (id != null) {
        var bp = _breakpoints[id.internal_id];
        if (bp == null) {
          Log.error('Debugger error: Breakpoint ${id.internal_id} just got a response, but it is not registered!');
        }
        switch(id.response) {
        case FileLineBreakpointNumber(num):
          bp.status = Active;
          bp.hxcpp_id = num;
          _bp_mutex.acquire();
          _hxcpp_to_internal[num] = bp.internal_id;
          _bp_mutex.release();
        case ClassFunctionBreakpointNumber(num, bad_classes):
          if (bad_classes != null && bad_classes.length > 0) {
            Log.verbose('Found some bad classes while setting breakpoint: $bad_classes');
          }
          bp.status = Active;
          bp.hxcpp_id = num;
          _bp_mutex.acquire();
          _hxcpp_to_internal[num] = bp.internal_id;
          _bp_mutex.release();
        case ErrorBadFunctionNameRegex(details):
          bp.status = CustomError('Bad function name regex: $details');
        case ErrorBadClassNameRegex(details):
          bp.status = CustomError('Bad class name regex: $details');
        case ErrorNoMatchingFunctions(_,_,bad_classes):
          if (bad_classes != null && bad_classes.length > 0) {
            Log.verbose('Found some bad classes while setting breakpoint: $bad_classes');
          }
          bp.status = NotFound;
        case ErrorNoSuchFile(_):
          bp.status = NotFound;
        case unexpected:
          Log.error('Unexpected response ${unexpected} for breakpoint $bp');
          bp.status = Error(unexpected);
        }
      }
    }
    _wait_amount = 0;
  }
}
