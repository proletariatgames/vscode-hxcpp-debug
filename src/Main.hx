package;

import utils.Tools;
import utils.Log;

import vscode.debugger.Data;

class Main {
  static function main() {
    haxe.Log.trace = function(str,?pos:haxe.PosInfos) {
      Log.verbose(Std.string(str), pos);
    }
    try {
      new DebugAdapter().loop();
    } catch(e:Dynamic) {
      Log.fatal('Debugger: Error on main thread: $e');
    }
  }
}

class DebugAdapter {
  var _output_thread_started:Bool;
  var _context:debug.Context;

  public function new() {
    this._context = new debug.Context();
  }

  public function loop() {
    Log.log('Starting');
    var initialize:InitializeRequest = switch(_context.get_next_input(true)) {
      case VSCodeRequest(req):
        cast req;
      case _: throw 'assert'; // should never happen
    };
    if (initialize.command != Initialize) {
      Log.fatal('vscode debugger protocol error: Expected a initialize request, got $initialize');
    }
    var resp:{ >Response, body:Capabilities } = {
      seq: 0,
      type: Response,
      request_seq: initialize.seq,
      command: Std.string(initialize.command),
      success: true,
      body: {
        supportsConfigurationDoneRequest: true,
        supportsFunctionBreakpoints: true,
        supportsConditionalBreakpoints: true,
        supportsEvaluateForHovers: true,
        supportsStepBack: false,
        supportsSetVariable: true,
        supportsStepInTargetsRequest: true,
        supportsCompletionsRequest: false, // TODO
        supportsRestartRequest: true,
        supportTerminateDebuggee: true,
        supportsLoadedSourcesRequest: true
      }
    };
    _context.add_response(initialize, resp);

    var launch_or_attach:Request = switch(_context.get_next_input(true)) {
      case VSCodeRequest(req):
        cast req;
      case _: throw 'assert'; // should never happen
    };

    var port = this.launch_or_attach(launch_or_attach);
    var settings = _context.get_settings();
    var host = 'localhost';
    if (settings.host != null) {
      host = settings.host;
    }

    _context.connect_debug(host, port, settings.timeout);

    setup_internal_breakpoints();

    _context.add_event( ({
      seq: 0,
      type: Event,
      event: Initialized,
    } : InitializedEvent) );

    // setup the internal breakpoints
    // first of all, query the source files
    _context.query_source_files();
    var first_break = true,
        configuration_done = false,
        after_configuration_done = [];

    while(true) {
      var input = _context.get_next_input(true);
      if (input == null) {
        break;
      }
      switch (input) {
      case Callback(fn):
        fn();
      case DebuggerInterrupt(dbg):
        switch(dbg) {
        case ThreadCreated(thread_number):
          if (!configuration_done) {
            after_configuration_done.push(input);
          } else {
          }
        case ThreadTerminated(thread_number):
          if (!configuration_done) {
            after_configuration_done.push(input);
          } else {
          }
        case ThreadStarted(thread_number):
          if (!configuration_done) {
            after_configuration_done.push(input);
          } else {
          }
        case ThreadStopped(thread_number, stack_frame, cls_name, fn_name, file_name, ln_num):
          if (!configuration_done) {
            Log.verbose('Thread stopped but initial threads answer was still not sent');
            after_configuration_done.push(input);
          } else {
            Log.verbose('ThreadStopped($thread_number) $cls_name::$fn_name');
            // get thread stopped reason
            if (first_break) {
              first_break = false;
              _context.add_event(( {
                seq: 0,
                type: Event,
                event: Stopped,
                body: {
                  reason: Entry,
                  threadId: thread_number,
                  allThreadsStopped: true
                }
              } : StoppedEvent));
            } else {
              emit_thread_stopped(thread_number, stack_frame, cls_name, fn_name, file_name, ln_num);
            }
          }
        case unexpected:
          Log.warn('Debugger: Unexpected debugger interrupt $unexpected');
        }
      case VSCodeRequest(req):
        switch(req.type) {
        case Request:
          var req:Request = cast req;
          switch (req.command) {
          case Restart:
          case Disconnect:
          case SetBreakpoints:
            _context.breakpoints.vscode_set_breakpoints(cast req);
          case SetFunctionBreakpoints:
            _context.breakpoints.vscode_set_fn_breakpoints(cast req);
          case Continue:
            call_and_respond(req, Continue(1));
          case Next:
            call_and_respond(req, Next(1));
          case StepIn:
            call_and_respond(req, Step(1));
          case StepOut:
            call_and_respond(req, Finish(1));
          // case StepBack:
          // case Goto:
          case Pause:
            call_and_respond(req, BreakNow);
          case StackTrace:
            respond_stack_trace(cast req);
          case Scopes:
            respond_scopes(cast req);
          case Variables:
            respond_variables(cast req);
          case SetVariable:
          case Source:
          case Threads:
            respond_threads(req);
          case Modules:
          case LoadedSources:
          case Evaluate:
          // case StepInTargets:
          // case GotoTargets:
          case ExceptionInfo:
          case ConfigurationDone:
            Log.verbose('Configuration Done');
            _context.add_response_to(req, true);
            configuration_done = true;
            for (input in after_configuration_done) {
              _context.add_input(input);
            }
          case unsupported:
            Log.warn('Debugger: Unsupported command ${req.command}');
          }
        case Event:
          var ev:Event = cast req;
          switch (ev.event) {
          // case Stopped:
          case unsupported:
            Log.warn('Debugger: Unsupported event ${ev.event}');
          }
        case unexpected:
          Log.warn('Debugger: Unexpected vscode request type $unexpected');
        }
      }
    }

    Sys.sleep(25);
  }

  private function call_and_respond(req:Request, cmd:debugger.IController.Command, ?reset_cache:Bool=true) {
    _context.add_debugger_command(cmd, function(res) {
      switch(res) {
      case OK:
        if (reset_cache) {
          _context.thread_cache.reset();
        }
        _context.add_response_to(req, true);
      case ErrorCurrentThreadNotStopped(num):
        _context.add_response_to(req, false, 'Error while executing $cmd: Current thread ($num) is not stopped');
      case unexpected:
        _context.add_response_to(req, false, 'Unexpected response to $cmd: $unexpected');
      }
    });
  }

  private static function val_type_to_string(t:debugger.IController.StructuredValueType):String {
    return switch(t) {
      case TypeNull: "Null";
      case TypeBool: "Bool";
      case TypeInt: "Int";
      case TypeFloat: "Float";
      case TypeString: "String";
      case TypeInstance(name) | TypeEnum(name): name;
      case TypeAnonymous(_): "<anonymous>";
      case TypeClass(name): 'Class<' + name + '>';
      case TypeFunction: '<function>';
      case TypeArray: 'Array';
    }
  }

  private function structured_to_vscode(thread_id:Int, frame_id:Int, s:debugger.IController.StructuredValue, name:String, out:Array<vscode.debugger.Data.Variable>) {
    switch(s) {
    case Elided(val_type, get_expression):
      out.push({
        name: name,
        value: '',
        type: val_type_to_string(val_type),
        evaluateName: get_expression,
        variablesReference: _context.thread_cache.get_or_create_var_ref(StackVar(thread_id, frame_id, get_expression)),
      });
    case Single(val_type, val):
      out.push({
        name: name,
        value: val,
        type: val_type_to_string(val_type),
        variablesReference: 0,
      });
    case List(list_type, lst):
      var lst = lst;
      while (true) {
        switch(lst) {
        case Terminator:
          break;
        case Element(name, val, next):
          structured_to_vscode(thread_id, frame_id, val, name, out);
          lst = next;
        }
      }
    }
  }

  private function respond_variables(req:VariablesRequest) {
    var ref = _context.thread_cache.get_ref(req.arguments.variablesReference);
    if (ref == null) {
      _context.add_response_to(req, false, 'The variables reference ${req.arguments.variablesReference} was not found');
      return;
    }
    switch(ref) {
    case StackFrame(thread_id, frame_id):
      _context.thread_cache.do_with_frame(thread_id, frame_id, function(msg) {
        if (msg != null) {
          _context.add_response_to(req, false, 'Error while getting frame $frame_id for $thread_id: $msg');
          return;
        }
        // call this synchronously otherwise something else might make this leave the current frame
        switch (_context.add_debugger_command_sync(Variables(false))) {
          case Variables(vars):
            var ret:Array<vscode.debugger.Data.Variable> = [];
            _context.add_debugger_commands_async([for (v in vars) PrintExpression(false, v)], function(msgs) {
              for (i in 0...vars.length) {
                var v = vars[i],
                    msg = msgs[i];
                switch (msg) {
                  case null:
                    ret.push({
                      name: v,
                      value: '<err>',
                      variablesReference: _context.thread_cache.get_or_create_var_ref(StackVar(thread_id, frame_id, v)),
                      evaluateName: v
                    });
                  case Value(exp, type, value):
                    switch (type) {
                    case 'Int', 'Float', 'String', 'Bool', 'Null', 'null':
                      ret.push({
                        name: v,
                        value: value,
                        type: type,
                        variablesReference: 0
                      });
                    case _:
                      ret.push({
                        name: v,
                        value: value,
                        type: type,
                        variablesReference: _context.thread_cache.get_or_create_var_ref(StackVar(thread_id, frame_id, v)),
                        evaluateName: v
                      });
                    }
                  case _:
                    ret.push({
                      name: v,
                      value: '<err>',
                      variablesReference: _context.thread_cache.get_or_create_var_ref(StackVar(thread_id, frame_id, v)),
                      evaluateName: v
                    });
                }
              }
              _context.add_response(req, ({
                seq: 0, type: Response, request_seq: req.seq, command: Std.string(req.command),
                success: true,
                body: {
                  variables: ret
                }
              } : VariablesResponse));
            });
          case ErrorCurrentThreadNotStopped(_):
            _context.add_response_to(req, false, 'Error while getting variables for $frame_id:$thread_id: Thread not stopped');
            return;
          case msg:
            _context.add_response_to(req, false, 'Unexpected error while getting variables for $frame_id:$thread_id: $msg');
        }
      });
    case StackVar(thread_id, frame_id, expr):
      _context.thread_cache.do_with_frame(thread_id, frame_id, function(msg) {
        if (msg != null) {
          _context.add_response_to(req, false, 'Error while getting frame $frame_id for $thread_id: $msg');
          return;
        }
        // call this synchronously otherwise something else might make this leave the current frame
        switch (_context.add_debugger_command_sync(GetStructured(false, expr))) {
        case Structured(structured):
          var ret = [];
          structured_to_vscode(thread_id, frame_id, structured, expr, ret);
          _context.add_response(req, ({
            seq: 0, type: Response, request_seq: req.seq, command: Std.string(req.command),
            success: true,
            body: {
              variables: ret
            }
          } : VariablesResponse));
        case ErrorCurrentThreadNotStopped(_):
          _context.add_response_to(req, false, 'Error while getting variable for $frame_id:$thread_id@$expr: Thread not stopped');
          return;
        case ErrorEvaluatingExpression(details):
          _context.add_response_to(req, false, 'Error while getting variable for $frame_id:$thread_id@$expr: Error evaluating expression: $details');
          return;
        case _:
          _context.add_response_to(req, false, 'Unexpected error while getting variable for $frame_id:$thread_id@$expr');
          return;
        }
      });
    }
  }

  private function respond_scopes(req:ScopesRequest) {
    var thread_and_frame = req.arguments.frameId;
    var thread_id = (thread_and_frame >>> 16) & 0xFFFF;
    var frame_id = thread_and_frame & 0xFFFF;

    _context.thread_cache.get_thread_info(thread_id, function(msg) {
      var ret:Array<Scope> = [];
      switch (msg) {
        case ThreadsWhere(list):
          switch(list) {
          case Terminator:
            _context.add_response_to(req, false, 'Unexpected ThreadsWehre response: Terminator');
            return;
          case Where(num, status, frame_list, next):
            Log.assert(num == thread_id, 'Requested $thread_id - got $num');
            var frame_list = frame_list;
            while (true) {
              switch (frame_list) {
              case Terminator: break;
              case Frame(is_current, number, class_name, fn_name, file_name, ln_num, next):
                if (number == frame_id) {
                  ret.push({
                    name: 'Locals',
                    variablesReference: _context.thread_cache.get_or_create_var_ref(StackFrame(thread_id, frame_id)),
                    expensive: false,
                    source: {
                      name: file_name,
                      path: _context.source_files.resolve_source_path(file_name),
                    },
                    line: ln_num,
                  });
                  ret.push({
                    name: 'Statics',
                    variablesReference: _context.thread_cache.get_or_create_var_ref(StackVar(thread_id, frame_id, class_name)),
                    expensive: false,
                    source: {
                      name: file_name,
                      path: _context.source_files.resolve_source_path(file_name),
                    },
                    line: ln_num,
                  });
                  break;
                }
                frame_list = next;
              }
            }
          }
          if (ret.length == 0) {
            _context.add_response_to(req, false, 'No scope for frame $frame_id and thread $thread_id was found');
          } else {
            _context.add_response(req, ({
              seq: 0, type: Response, request_seq: req.seq, command: Std.string(req.command),
              success: true,
              body: {
                scopes: ret
              }
            } : ScopesResponse));
          }
        case ErrorCurrentThreadNotStopped(_):
          _context.add_response_to(req, false, 'Thread $thread_id is not stopped');
          return;
        case unexpected:
          _context.add_response_to(req, false, 'Unexpected response when getting current thread location: $unexpected');
          return;
      }
    });
  }

  private function respond_stack_trace(req:StackTraceRequest) {
    var thread_id = req.arguments.threadId;
    _context.thread_cache.get_thread_info(thread_id, function(msg) {
      var ret:Array<StackFrame> = [];
      switch (msg) {
        case ThreadsWhere(list):
          switch(list) {
          case Terminator:
            _context.add_response_to(req, false, 'Unexpected ThreadsWhere response: Terminator');
            return;
          case Where(num, status, frame_list, next):
            Log.assert(num == thread_id, 'Requested $thread_id - got $num');
            var frame_list = frame_list;
            while (true) {
              switch (frame_list) {
              case Terminator: break;
              case Frame(is_current, number, class_name, fn_name, file_name, ln_num, next):
                if (number > 0xFFFF) {
                  Log.error('Frame number $number overflow');
                }
                ret.push({
                  id: (thread_id << 16) | (number & 0xFFFF),
                  name: class_name + '.' + fn_name,
                  source: {
                    name: file_name,
                    path: _context.source_files.resolve_source_path(file_name),
                  },
                  line: ln_num,
                  column: 0,
                });
                frame_list = next;
              }
            }
          }
          _context.add_response(req, ({
            seq: 0, type: Response, request_seq: req.seq, command: Std.string(req.command),
            success: true,
            body: {
              stackFrames: ret
            }
          } : StackTraceResponse));
        case ErrorCurrentThreadNotStopped(_):
          _context.add_response_to(req, false, 'Thread $thread_id is not stopped');
          return;
        case unexpected:
          _context.add_response_to(req, false, 'Unexpected response when getting current thread location: $unexpected');
          return;
      }
    });
  }

  private function respond_threads(req:Request, ?cb:Void->Void) {
    _context.thread_cache.get_threads_where(function (msg) {
      var ret:Array<Thread> = [];
      switch (msg) {
      case ThreadsWhere(list):
        var list = list;
        while (true) {
          switch(list) {
          case Terminator:
            break;
          case Where(num, status, frame_list, next):
            ret.push({ id: num, name: 'Thread #$num' });
            list = next;
          }
        }
      case unexpected:
        Log.error('Debugger: Unexpected response to WhereAllThreads: $unexpected');
        _context.add_response_to(req, false, 'Unexpected debugger response $unexpected');
        if (cb != null) _context.add_main_thread_callback(cb);
        return;
      }
      _context.add_response(req, ({
        seq: 0, type: Response, request_seq: req.seq, command: Std.string(req.command),
        success: true,
        body: {
          threads: ret
        }
      } : ThreadsResponse));
      if (cb != null) _context.add_main_thread_callback(cb);
    });
  }

  private function emit_thread_stopped(thread_number : Int, stack_frame : Int,
                                      class_name : String, function_name : String,
                                      file_name : String, line_number : Int)
  {
    // get reason
    _context.thread_cache.reset();
    _context.thread_cache.get_thread_info(thread_number, function(msg) {
      var thread_status = null;
      switch(msg) {
      case ThreadsWhere(list):
        var list = list;
        while(true) {
          switch (list) {
            case Terminator:
              break;
            case Where(num, status, frame_list, next):
              if (num == thread_number) {
                thread_status = status;
                break;
              }
              Log.warn('WhereCurrentThread did not return the current stopped thread ($num != $thread_number)');
              list = next;
          }
        }
      case unexpected:
        Log.error('Unexpected ThreadsWhere response: $unexpected');
      }
      if (thread_status == null) {
        Log.fatal('Error while checking break reason for thread $thread_number ($file_name : $line_number)');
      }

      var should_break = true,
          msg = null,
          reason:StoppedEventReasonEnum = null;
      switch (thread_status) {
      case Running:
        Log.error('Unexpected thread status Running');
      case StoppedImmediate:
        reason = Pause;
      case StoppedBreakpoint(bp_num):
        reason = Breakpoint;
        var bp = _context.breakpoints.get_breakpoint_from_hxcpp(bp_num);
        switch(bp.on_break) {
        case Internal(fn):
          fn();
          should_break = false;
          return;
        case Conditional(expr):
          switch (_context.add_debugger_command_sync(PrintExpression(false, expr))) {
          case Value(_, type, value):
            if (type != 'Bool') {
              msg = 'This conditional breakpoint did not return a Bool. It returned $type';
              Log.error('The condition `$expr` on breakpoint $bp_num did not return a Bool. It returned a $type. Breaking');
            } else if (value != "true") {
              should_break = false;
            }
          case ErrorEvaluatingExpression(details):
            Log.error('Error while evaluating condition `$expr`: $details');
            msg = 'The breakpoint condition returned an error: $details';
          case _:
          }
        case Normal:
        }
      case StoppedUncaughtException:
        reason = Exception;
      case StoppedCriticalError(description):
        reason = Exception;
        msg = 'Stopped because of a critical error: $description';
      }

      if (should_break) {
        _context.add_event(( {
          seq: 0,
          type: Event,
          event: Stopped,
          body: {
            reason: reason,
            threadId: thread_number,
            allThreadsStopped: true,
            text: msg
          }
        } : StoppedEvent));
      }
    });
  }

  private function launch_or_attach(launch_or_attach:Request) {
    var port = -1,
        host = 'localhost';
    switch(launch_or_attach.command) {
    case Launch:
      var launch:LaunchRequest = cast launch_or_attach;
      var settings = _context.get_settings();
      for (field in Reflect.fields(launch.arguments)) {
        var curField = Reflect.field(settings, field);
        if (curField == null) {
          Reflect.setField(settings, field, Reflect.field(launch.arguments, field));
        }
      }
      _context.start_recorder_thread();

      // compile
      function change_terminal_args(args:Array<String>) {
        if (Sys.systemName() == "Windows") {
          return ["cmd","/C", '"' + args.join('" "') +'" || exit 1'];
        } else {
          return args;
        }
      }
      var curSettings:utils.Settings.LaunchSettings = cast settings;
      if (curSettings.compile != null && curSettings.compile.args != null) {
        if (curSettings.compileDir == null) {
          Log.fatal('If a compilation is specified, `compileDir must be set');
        }

        var args = curSettings.compile.args.copy();
        var ret = utils.Tools.spawn_process_sync(args.shift(), args, curSettings.compileDir);
        if (ret != 0) {
          Log.error('Compilation failed');
          _context.terminate(1);
        }
      }

      // run
      if (curSettings.run == null) {
        Log.log('Terminating: There is nothing to run');
        _context.terminate(0);
      }
      if (curSettings.run.cwd == null) {
        Log.fatal('`run.cwd` must be set');
      }
      if (curSettings.port == null) {
        port = 6972;
      } else {
        port = curSettings.port;
      }
      var envs:haxe.DynamicAccess<String> = {
        HXCPP_DEBUG: "true"
      };
      if (port < 0) {
        Log.verbose('Finding a random port');
        port = find_random_port(host);
        Log.verbose('Port found at $port');
      }
      envs["HXCPP_DEBUGGER_PORT"] = port + "";

      _context.add_request( ({
        seq: 0,
        type: Request,
        command: RunInTerminal,
        arguments: {
          title: "Hxcpp Debugger Launch",
          cwd: curSettings.run.cwd,
          args: change_terminal_args(curSettings.run.args),
          env: cast envs
        }
      } : RunInTerminalRequest), function(res) {
        var res:RunInTerminalResponse = cast res;
        if (!res.success) {
          Log.log('Command output: ${res.message}');
          _context.terminate(1);
        }
        trace(res.body);
      });

    case Attach:
      var attach:AttachRequest = cast launch_or_attach;

      var settings = _context.get_settings();
      for (field in Reflect.fields(attach.arguments)) {
        var curField = Reflect.field(settings, field);
        if (curField == null) {
          Reflect.setField(settings, field, Reflect.field(attach.arguments, field));
        }
      }
      _context.start_recorder_thread();

      var curSettings:utils.Settings.AttachSettings = cast settings;
      port = curSettings.port;
      if (port <= 0) {
        Log.fatal('Attach: Invalid port $port');
      }
    case _:
      Log.fatal('protocol error: Expected "launch" or "attach", but got $launch_or_attach');
    }
    return port;
  }

  private function setup_internal_breakpoints() {
    _context.breakpoints.add_breakpoint(Internal(on_cppia_load), FuncBr('debugger.Debug', 'refreshCppiaDefinitions'));
    _context.breakpoints.add_breakpoint(Internal(on_new_classpaths), FuncBr('debugger.Debug', 'setClassPaths'));
    _context.breakpoints.add_breakpoint(Normal, FuncBr('debugger.Debug', 'debugBreak'));
  }

  private function on_new_classpaths() {
    Log.verbose('Receiving new classpaths');

    switch(_context.add_debugger_command_sync(GetStructured(false, 'classpaths'))) {
    case Structured(List(_Array, lst)):
      var arr = [];
      var lst = lst;
      while (lst != Terminator) {
        switch(lst) {
        case Element(_, Single(_,value), next):
          arr.push(value);
          lst = next;
        case _:
          Log.error('Unexpected structured value $lst when getting new class paths');
          break;
        }
      }
      _context.source_files.add_classpaths(arr);
      Log.log('Classpath information updated');
      Log.verbose('Added classpaths: $arr');
    case unexpected:
      Log.error('Unexpected response when getting new classpaths: $unexpected');
    }

    switch (_context.add_debugger_command_sync(Continue(1))) {
    case OK:
    case ErrorCurrentThreadNotStopped(n):
      Log.fatal('Internal classpaths load: Current thread is not stopped ($n)');
    case ErrorBadCount(n):
      Log.fatal('Internal classpaths load: Bad count ($n)');
    case unexpected:
      Log.fatal('Internal classpaths load: Unexpected ($unexpected)');
    }
  }

  private function on_cppia_load() {
    Log.log('Cppia load call detected');
    // Log.verbose(_context.add_debugger_command_sync(WhereCurrentThread(false)) +'');
    // update files
    Log.verbose('Updating source files');
    this._context.query_source_files();
    // refresh breakpoints that were not found
    Log.verbose('Refreshing breakpoints');
    this._context.breakpoints.refresh_breakpoints();
    // continue
    switch (_context.add_debugger_command_sync(Continue(1))) {
    case OK:
    case ErrorCurrentThreadNotStopped(n):
      Log.fatal('Internal cppia load: Current thread is not stopped ($n)');
    case ErrorBadCount(n):
      Log.fatal('Internal cppia load: Bad count ($n)');
    case unexpected:
      Log.fatal('Internal cppia load: Unexpected ($unexpected)');
    }
  }

  private static function find_random_port(host:String) {
    while (true) {
      var port = Std.random(60000) + 1024; 
      try {
        var sock = new sys.net.Socket();
        sock.bind(new sys.net.Host(host), port);
        sock.close();
        return port;
      }
      catch(e:Dynamic) {
      }
    }
  }

}

// class DebugAdapter {
//   var _input:AsyncInput;
//   var _output:Output;
//   static var _log:Output;

//   var _init_args:Dynamic;
//   var _launch_req:Dynamic;

//   var _compile_process:Process;
//   var _compile_stdout:AsyncInput;
//   var _compile_stderr:AsyncInput;

//   var _runCommand:String = null;
//   var _runPath:String = null;
//   var _runInTerminal:Bool = false;
//   var _run_process:Process;

//   var _warn_timeout:Float = 0;

//   var _server_initialized:Bool = false;
//   var _first_stopped:Bool = false;
//   var _send_stopped:Array<Int> = [];

//   var _vsc_haxe_server:Thread;
//   var _debugger_messages:Deque<Message>;
//   var _debugger_commands:Deque<Command>;
//   var _pending_responses:Array<Dynamic>;
//   var _run_exit_deque:Deque<Int>;

//   public function new(i:Input, o:Output, log_o:Output) {
//     _input = new AsyncInput(i);
//     _output = o;
//     _log = log_o;
//     _log_mutex = new Mutex();

//     _debugger_messages = new Deque<Message>();
//     _debugger_commands = new Deque<Command>();
//     _run_exit_deque = new Deque<Int>();

//     _pending_responses = [];

//     // set an environment variable so that the program knows it's being debugged
//     Sys.putEnv('HXCPP_DEBUG', 'true');

//     while (true) {
//       if (_input.hasData() && outstanding_variables==null) read_from_vscode();
//       if (_compile_process!=null) read_compile();
//       if (_run_process!=null) check_debugger_messages();
//       if (_warn_timeout>0 && Sys.time()>_warn_timeout) {
//         _warn_timeout = 0;
//         log_and_output("Client not yet connected, does it 1) call new HaxeRemote(true, 'localhost'), 2) compiled with -debug, and 3) define -D HXCPP_DEBUGGER ?");
//       }
//       // Grr, this is dying instantly... gnome-terminal layer closes :(
//       // var exit:Null<Int> = _run_exit_deque.pop(false);
//       // if (exit != null) {
//       //   log_and_output("Client app process exited: "+exit);
//       //   do_disconnect();
//       // }
//       Sys.sleep(0.05);
//     }
//   }

//   static public function do_throw(s:String) {
//     log(s);
//     throw s;
//   }

//   static var _log_mutex:Mutex;
//   static public function log(s:String) {
//     _log_mutex.acquire();
//     if (_log!=null) {
//       _log.writeString(Sys.time()+": "+s+"\n");
//       _log.flush();
//     }
//     _log_mutex.release();
//   }

//   function burn_blank_line():Void
//   {
//     var b:Int;
// #if windows
//     if ((b=_input.readByte())!=10) log("Protocol error, expected 10, got "+b);
// #else
//     if ((b=_input.readByte())!=13) log("Protocol error, expected 13, got "+b);
//     if ((b=_input.readByte())!=10) log("Protocol error, expected 10, got "+b);
// #end
//   }

//   // Let's see how this works in Windows before we go trying to improve it...
//   function split_args(str:String):Array<String>
//   {
//     str = StringTools.replace(str, "\\ ", "_LITERAL_SPACE");
//     var r = ~/(?:[^\s"]+|"[^"]*")+/g;
//     var args = [];
//     r.map(str,
//           function(r):String {
//             var match = r.matched(0);
//             args.push(StringTools.replace(match ,"_LITERAL_SPACE", " "));
//             return '';
//           });
//     return args;
//   }

//   function read_from_vscode():Void
//   {
//     var b:Int;
//     var line:StringBuf = new StringBuf();
//     while ((b=_input.readByte())!=10) {
//       if (b!=13) line.addChar(b);
//     }

//     // Read header
//     var values = line.toString().split(':');
//     if (values[0]=="Content-Length") {
//       burn_blank_line();
//       handle_request(read_json(Std.parseInt(values[1])));
//     } else {
//       log("Ignoring unknown header:\n"+line.toString());
//     }
//   }

//   function read_json(num_bytes:Int):Dynamic
//   {
//     log("Reading "+num_bytes+" bytes...");
//     var json:String = _input.read(num_bytes).getString(0, num_bytes);
//     log(json);
//     return haxe.format.JsonParser.parse(json);
//   }

//   function send_response(response:Dynamic):Void
//   {
//     _context.add_stdout(response);
// //     var json:String = haxe.format.JsonPrinter.print(response);
// //     var b = Bytes.ofString(json);

// //     log("----> Sending "+b.length+" bytes:");
// //     log(json);

// //     _output.writeString("Content-Length: "+(b.length));
// // #if windows
// //     _output.writeByte(10);
// //     _output.writeByte(10);
// // #else
// //     _output.writeByte(13);
// //     _output.writeByte(10);
// //     _output.writeByte(13);
// //     _output.writeByte(10);
// // #end
// //     _output.writeBytes(b, 0, b.length);
// //     _output.flush();
//   }

//   var _event_sequence:Int = 1;
//   function send_event(event:Dynamic):Void
//   {
//     event.seq = _event_sequence++;
//     event.type = "event";
//     send_response(event);
//   }

//   inline function log_and_output(output:String):Void
//   {
//     log(output);
//     send_output(output);
//   }

//   function send_output(output:String, category:String='console', add_newline:Bool=true):Void
//   {
//     // Attempts at seeing all messages ???
//     // output = StringTools.replace(output, "\"", "");
//     // if (output.length>20) {
//     //   output = output.substr(0,20);
//     //   add_newline = true;
//     // }

//     var n = add_newline ? "\n" : "";

//     if (output.indexOf("\n")>0) {
//       // seems to choke on large (or multi-line) output, send separately
//       var lines = output.split("\n");
//       for (i in 0...lines.length) {
//         var line = lines[i] + (i==lines.length-1 ? n : "\n");
//         send_event({"event":"output", "body":{"category":category,"output":line}});
//       }
//     } else {
//       send_event({"event":"output", "body":{"category":category,"output":(output+n)}});
//     }
//   }

//   function handle_request(request:Dynamic):Void
//   {
//     var command:String = request.command;
//     log("Got command: "+command);

//     var response:Dynamic = {
//       type:"response",
//       request_seq:request.seq,
//       command:request.command,
//       success:false
//     }

//     switch command {
//       case "initialize": {
//         log("Initializing... _run_process is: "+_run_process);
//         _init_args = request.arguments;
//         response.success = true;

//         response.body = {};

//         // From debugSession.ts, initializeRequest(), doesn't make a difference:

//         // // This default debug adapter does not support conditional breakpoints.
//         // response.body.supportsConditionalBreakpoints = false;
//         //  
//         // // This default debug adapter does not support hit conditional breakpoints.
//         // response.body.supportsHitConditionalBreakpoints = false;
//         //  
//         // // This default debug adapter does not support function breakpoints.
//         // response.body.supportsFunctionBreakpoints = false;
//         //  
//         // // This default debug adapter implements the 'configurationDone' request.
//         // response.body.supportsConfigurationDoneRequest = true;
//         //  
//         // // This default debug adapter does not support hovers based on the 'evaluate' request.
//         // response.body.supportsEvaluateForHovers = false;
//         //  
//         // // This default debug adapter does not support the 'stepBack' request.
//         // response.body.supportsStepBack = false;
//         //  
//         // // This default debug adapter does not support the 'setVariable' request.
//         // response.body.supportsSetVariable = false;
//         //  
//         // // This default debug adapter does not support the 'restartFrame' request.
//         // response.body.supportsRestartFrame = false;
//         //  
//         // // This default debug adapter does not support the 'stepInTargetsRequest' request.
//         // response.body.supportsStepInTargetsRequest = false;
//         //  
//         // // This default debug adapter does not support the 'gotoTargetsRequest' request.
//         // response.body.supportsGotoTargetsRequest = false;
//         //  
//         // // This default debug adapter does not support the 'completionsRequest' request.
//         // response.body.supportsCompletionsRequest = false;
//         //  
//         // // This default debug adapter does not support the 'restart' request.
//         // response.body.supportsRestartRequest = false;
//         //  
//         // // This default debug adapter does not support the 'exceptionOptions' attribute on the 'setExceptionBreakpointsRequest'.
//         // response.body.supportsExceptionOptions = false;
//         //  
//         // // This default debug adapter does not support the 'format' attribute on the 'variablesRequest', 'evaluateRequest', and 'stackTraceRequest'.
//         // response.body.supportsValueFormattingOptions = false;
//         //  
//         // // This debug adapter does not support the 'exceptionInfoRequest' request.
//         // response.body.supportsExceptionInfoRequest = false;

//         send_response(response);
//       }
//       case "launch": {
//         _launch_req = request;
//         SourceFiles.proj_dir = _launch_req.arguments.cwd;
//         log("Launching... proj_dir="+SourceFiles.proj_dir);
//         var compileCommand:String = null;
//         var compilePath:String = null;
//         for (arg in (_launch_req.arguments.args:Array<String>)) {
//           var eq = arg.indexOf('=');
//           var name = arg.substr(0, eq);
//           var value = arg.substr(eq+1);
//           log("Arg "+name+" is "+value);
//           switch name {
//             case "compileCommand": compileCommand = value;
//             case "compilePath": compilePath = value;
//             case "runCommand": _runCommand = value;
//             case "runPath": _runPath = value;
//             case "runInTerminal": _runInTerminal = (value.toLowerCase()=='true');
//             default: log("Unknown arg name '"+name+"'"); do_disconnect();
//           }
//         }

//         var success = true;
//         if (compileCommand!=null) {
//           log_and_output("Compiling...");
//           log_and_output("cd "+compilePath);
//           log_and_output(compileCommand);
//           _compile_process = start_process(compileCommand, compilePath);
//           _compile_stdout = new AsyncInput(_compile_process.stdout);
//           _compile_stderr = new AsyncInput(_compile_process.stderr);
//         } else {
//           if (_runCommand!=null) {
//             do_run();

//             // The go debug adapter sends this event in response to "launch"
//             send_event({"event":"initialized"});

//           } else {
//             // TODO: terminatedevent...
//             log("Compile, but no runCommand, TODO: terminate...");
//             success = false;
//             response.message = "No compileCmd or runCommand found.";
//           }
//         }

//         response.success = success;
//         send_response(response);
//       }

//       // TODO: implement pause on exceptions on debugger side
//       // case "setExceptionBreakpoints": {
//       //   //{"type":"request","seq":3,"command":"setExceptionBreakpoints","arguments":{"filters":["uncaught"]}}
//       //   _exception_breakpoints_args = request.arguments;
//       //   response.success = true;
//       //   send_response(response);
//       // }

//       case "setBreakpoints": {
//         process_set_breakpoints(request);
//       }

//       case "disconnect": {
//         // TODO: restart?
//         response.success = true;
//         send_response(response);
//         do_disconnect(false);
//       }

//       case "threads": {
//         // ThreadStatus was just populated by stopped event
//         //response.body = {threads: ThreadStatus.last.threads.map(AppThreadStoppedState.toVSCThread)};
//         response.body = {threads: ThreadStatus.live_threads.map(AppThreadStoppedState.idToVSCThread)};
//         response.success = true;
//         send_response(response);
//       }

//       case "stackTrace": {
//         var stackFrames = ThreadStatus.by_id(request.arguments.threadId).stack_frames.concat([]);
//         while (stackFrames.length>(request.arguments.levels:Int)) stackFrames.pop();
//         response.body = {
//           stackFrames:stackFrames.map(StackFrame.toVSCStackFrame)
//         }
//         response.success = true;
//         send_response(response);
//       }

//       case "scopes": {
//         var frameId = request.arguments.frameId;
//         var frame = ThreadStatus.getStackFrameById(frameId);

//         // A scope of locals for each stackFrame
//         response.body = {
//           scopes:[{name:"Locals", variablesReference:frame.variablesReference, expensive:false}]
//         }
//         response.success = true;
//         send_response(response);
//       }

//       case "variables": {
//         var ref_idx:Int = request.arguments.variablesReference;
//         var var_ref = ThreadStatus.var_refs.get(ref_idx);

//         if (var_ref==null) {
//           log("variables requested for unknown variablesReference: "+ref_idx);
//           response.success = false;
//           send_response(response);
//           return;
//         }

//         var frame:StackFrame = var_ref.root;
//         var thread_num = ThreadStatus.threadNumForStackFrameId(frame.id);
//         _debugger_commands.add(SetCurrentThread(thread_num));

//         log("Setting thread num: "+thread_num+", ref "+ref_idx);

//         if (Std.is(var_ref, StackFrame)) {
//           log("variables requested for StackFrame: "+frame.fileName+':'+frame.lineNumber);
//           current_parent = var_ref;
//           _debugger_commands.add(SetFrame(frame.number));
//           _debugger_commands.add(Variables(false));
//           _pending_responses.push(response);
//         } else {
//           current_parent = var_ref;
//           var v:Variable = cast(var_ref);
//           log("sub-variables requested for Variable: "+v.fq_name+":"+v.type);
//           current_fqn = v.fq_name;
//           outstanding_variables_cnt = 0;
//           outstanding_variables = new StringMap<Variable>();

//           if (v.type.indexOf("Array")>=0) {
//             var r = ~/>\[(\d+)/;
//             if (r.match(v.type)) {
//               var length = Std.parseInt(r.matched(1));
//               // TODO - max???
//               for (i in 0...length) {
//                 _debugger_commands.add(PrintExpression(false, current_fqn+'['+i+']'));
//                 outstanding_variables_cnt++;
//                 var name:String = i+'';
//                 var v = new Variable(name, current_parent, true);
//                 outstanding_variables.set(name, v);
//               }
//             } else {
//               // Array, length 0 or unknown
//               current_fqn = null;
//               outstanding_variables_cnt = 0;
//               outstanding_variables = null;
//               response.success = true;
//               response.body = { variables:[] };
//               send_response(response);
//               return;
//             }
//           } else {
//             var params:Array<String> = v.value.split("\n");
//             for (p in params) {
//               var idx = p.indexOf(" : ");
//               if (idx>=0) {
//                 var name:String = StringTools.ltrim(p.substr(0, idx));
//                 _debugger_commands.add(PrintExpression(false,
//                   current_fqn+'.'+name));
//                 outstanding_variables_cnt++;
//                 var v = new Variable(name, current_parent);
//                 outstanding_variables.set(name, v);
//                 log("Creating outstanding named '"+name+"', fq="+v.fq_name);
//               }
//             }
//           }
//           _pending_responses.push(response);
//         }
//       }

//       case "continue": {
//         _debugger_commands.add(Continue(1));
//         _pending_responses.push(response);

//         // response.success = true;
//         // _debugger_commands.add(Continue(1));
//         // // TODO: wait for ThreadStarted message
//         // send_response(response);
//       }

//       case "pause": {
//         _debugger_commands.add(BreakNow);
//         _pending_responses.push(response);
//       }

//       case "next": {
//         _debugger_commands.add(Next(1));
//         response.success = true;
//         send_response(response);
//       }

//       case "stepIn": {
//         _debugger_commands.add(Step(1));
//         response.success = true;
//         send_response(response);
//       }

//       case "stepOut": {
//         _debugger_commands.add(Finish(1));
//         response.success = true;
//         send_response(response);
//       }

//       // evaluate == watch

//       default: {
//         log("====== UNHANDLED COMMAND: "+command);
//       }
//     }
//   }

//   private static inline var REMOVE_ME:DirtyFlag = false;
//   private static inline var DONT_REMOVE_ME:DirtyFlag = true;
//   var breakpoint_state = new StringMap<IntMap<DirtyFlag>>();
//   function process_set_breakpoints(request:Dynamic)
//   {
//     var response:Dynamic = {
//       type:"response",
//       request_seq:request.seq,
//       command:request.command,
//       success:true
//     }

//     //{"type":"request","seq":3,"command":"setBreakpoints","arguments":{"source":{"path":"/home/jward/dev/vscode-hxcpp-debug/test openfl/Source/Main.hx"},"lines":[17]}}
//     var file:String = SourceFiles.getDebuggerFilename(request.arguments.source.path);
//     log("Setting breakpoints in:");
//     log(" VSC: "+request.arguments.source.path);
//     log(" DBG: "+file);

//     // Breakpoints messages from VSCode are file-at-a-time, so
//     // mark the bp's in this file as "to be removed"
//     if (!breakpoint_state.exists(file)) breakpoint_state.set(file, new IntMap<DirtyFlag>());
//     for (ln in breakpoint_state.get(file).keys()) {
//       breakpoint_state.get(file).set(ln, REMOVE_ME);
//     }

//     // It doesn't seem hxcpp-debugger corrects/verifies line
//     // numbers, so just pass these back as verified
//     var breakpoints = [];
//     for (line in (request.arguments.lines:Array<Int>)) {
//       if (!breakpoint_state.get(file).exists(line)) {
//         _debugger_commands.add(AddFileLineBreakpoint(file, line));
//       }
//       breakpoint_state.get(file).set(line, DONT_REMOVE_ME);

//       breakpoints.push({ verified:true, line:line});
//     }

//     for (ln in breakpoint_state.get(file).keys()) {
//       if (breakpoint_state.get(file).get(ln)==REMOVE_ME) {
//         _debugger_commands.add(DeleteFileLineBreakpoint(file, ln));
//         breakpoint_state.get(file).remove(ln);
//       }
//     }

//     response.body = { breakpoints:breakpoints }
//     send_response(response);
//   }

//   function do_run() {
//     log("Starting VSCHaxeServer port 6972...");
//     _vsc_haxe_server = Thread.create(start_server);
//     _vsc_haxe_server.sendMessage(log);
//     _vsc_haxe_server.sendMessage(_debugger_messages);
//     _vsc_haxe_server.sendMessage(_debugger_commands);

//     if (!FileSystem.isDirectory(_runPath)) {
//       log_and_output("Error: runPath not found: "+_runPath);
//       do_disconnect();
//       return;
//     }

//     var exec = Path.normalize(_runPath+'/'+_runCommand);
//     if (!FileSystem.exists(exec)) {
//       if (FileSystem.exists(exec+".exe")) {
//         _runCommand += '.exe';
//       } else {
//         log_and_output("Warning: runCommand not found: "+exec);
//       }
//     }

//     log_and_output("Launching application...");

//     _run_process = start_process(_runCommand, _runPath, _runInTerminal);
//     var t = Thread.create(monitor_run_process);
//     t.sendMessage(_run_exit_deque);
//     t.sendMessage(_run_process);

//     _warn_timeout = Sys.time()+3;

//     // Wait for debugger to connect... TODO: timeout?
//     _server_initialized = false;
//   }

//   function read_compile() {
//     // TODO: non-blocking compile process, send stdout as we receive it,
//     // handle disconnect

//     var line:StringBuf = new StringBuf();
//     var compile_finished:Bool = false;

//     while (_compile_stderr.hasData()) {
//       try {
//         line.addChar(_compile_stderr.readByte());
//       } catch (e : haxe.io.Eof) {
//         break;
//       }
//     }

//     while (_compile_stdout.hasData()) {
//       try {
//         line.addChar(_compile_stdout.readByte());
//       } catch (e : haxe.io.Eof) {
//         compile_finished = true;
//         break;
//       }
//     }
//     if (_compile_stdout.isClosed()) compile_finished = true;

//     //var output = compile_process.stdout.readAll();
//     var result = line.toString();
//     result = (~/\x1b\[[0-9;]*m/g).replace(result, "");

//     if (result.length>0) {
//       log("Compiler: "+result);
//       send_output(result, 'console', false);
//     }

//     if (compile_finished) {

//       var success = _compile_process.exitCode()==0;
//       log_and_output("Compile "+(success ? "succeeded!" : "FAILED!"));
//       _compile_process = null;
//       _compile_stdout = null;
//       _compile_stderr = null;

//       if (success) {
//         do_run();
//       } else {
//         do_disconnect();
//       }
//     }

//   }

//   function do_disconnect(send_exited:Bool=true):Void
//   {
//     if (_run_process!=null) {
//       log("Killing _run_process");
//       _run_process.close();
//       _run_process.kill(); // TODO, this is not closing the app
//       _run_process = null;
//     }
//     if (_compile_process!=null) {
//       log("Killing _compile_process");
//       _compile_process.close();
//       _compile_process.kill(); // TODO, this is not closing the process
//       _compile_process = null;
//     }
//     if (send_exited) {
//       log("Sending exited event to VSCode");
//       send_event({"event":"terminated"});
//     } // else { hmm, is there a disconnect event we can send? }
//     log("Disconnecting...");
//     Sys.exit(0);
//   }

//   function start_process(cmd:String, path:String, in_terminal:Bool=false):Process
//   {
//     var old:String = null;
//     if (in_terminal) {
// #if mac
//       // Create /tmp/run, run "open /tmp/run"
//       var run = sys.io.File.write("/tmp/run", false);
//       run.writeString("cd "+path.split(" ").join('\\ ')+"; ./"+cmd.split(" ").join('\\ '));
//       run.flush(); run.close();
//       Sys.command("chmod", ["a+x", "/tmp/run"]);
//       cmd = "open /tmp/run";
// #elseif linux
//       // TODO: optional terminal command (for non-gnome-terminal/ubuntu)
//       cmd = "gnome-terminal --working-directory="+path.split(" ").join('\\ ')+" -x ./"+cmd.split(" ").join('\\ ');
// #elseif windows
//       // Hmm, this should work but doesn't...
//       // cmd = "start /wait cmd /C \"cd "+path+" && "+cmd+"\"";
//       send_output("Error: runInTerminal not yet supported in Windows...");
// #end
//     } else {
//       old = Sys.getCwd();
//       Sys.setCwd(path);
//     }
//     log("cmd: "+cmd);
//     var args = split_args(cmd);
//     log("args: "+args.join('|'));
//     var display = args.join(" ");
//     cmd = args.shift();

//     // ./ as current directory isn't typically in PATH
//     // Shouldn't be necessary for windows as the current directory
//     // is in the PATH by default... I think.
// #if (!windows)
//     if (sys.FileSystem.exists(path+SourceFiles.SEPARATOR+cmd)) {
//       log("Setting ./ prefix");
//       cmd = "./"+cmd;
//     }
// #end

//     var proc = new sys.io.Process(cmd, args);
//     log("Starting: "+display+", pid="+proc.getPid());
//     if (old!=null) Sys.setCwd(old);
//     return proc;
//   }

//   static function start_server():Void
//   {
//     var log:String->Void = Thread.readMessage(true);
//     var messages:Deque<Message> = Thread.readMessage(true);
//     var commands:Deque<Command> = Thread.readMessage(true);
//     var vschs = new debugger.VSCHaxeServer(log, commands, messages);
//     // fyi, the above constructor function does not return
//   }

//   static function monitor_run_process() {
//     var dq:Deque<Int> = Thread.readMessage(true);
//     var proc:Process = Thread.readMessage(true);

//     log("PM: Monitoring process: "+proc.getPid());
//     var exit = proc.exitCode();
//     log("PM: Detected process exit: "+exit);

//     dq.push(exit);
//   }
//   var current_parent:IVarRef;
//   var current_fqn:String;
//   var outstanding_variables:StringMap<Variable>;
//   var outstanding_variables_cnt:Int = 0;

//   function has_pending(command:String):Bool
//   {
//     for (i in _pending_responses) {
//       if (i.command==command) {
//         return true;
//       }
//     }
//     return false;
//   }

//   function check_pending(command:String):Dynamic
//   {
//     var remove:Dynamic = null;
//     for (i in _pending_responses) {
//       if (i.command==command) {
//         remove = i;
//         break;
//       }
//     }
//     if (remove!=null) {
//       _pending_responses.remove(remove);
//     }
//     return remove;
//   }

//   function check_finished_variables():Void
//   {
//     if (outstanding_variables_cnt==0) {
//       var response:Dynamic = check_pending("variables");
//       var variables = [];
//       for (name in outstanding_variables.keys()) {
//         variables.push(outstanding_variables.get(name));
//       }
//       response.body = { variables: variables.map(Variable.toVSCVariable) };

//       outstanding_variables = null;
//       current_fqn = null;
//       response.success = true;
//       send_response(response);
//     }
//   }

//   function check_debugger_messages():Void
//   {
//     var message:Message = _debugger_messages.pop(false);

//     if (message==null) return;

//     switch (message) {
//     case Files(list):
//       // Don't know why -- it hangs printing this message
//       log("Got message: Files(...)");
//     case Value(expression, type, value):
//       // Too verbose, just expression and type
//       log("Got message: Value("+expression+", "+type+", ...)");
//     default:
//       log("Got message: "+message);
//     }

//     // The first OK indicates a connection with the debugger
//     if (message==OK && _server_initialized == false) {
//       _warn_timeout = 0;
//       _server_initialized = true;
//       return;
//     }

//     switch (message) {

//     case Files(list):
//       log("Populating "+(SourceFiles.files==null ? "SourceFiles.files" : "SourceFiles.files_full"));
//       var tgt:Array<String>;
//       if (SourceFiles.files==null) {
//         tgt = SourceFiles.files = [];
//       } else {
//         tgt = SourceFiles.files_full = [];
//       }

//       for(name in list) {
//           if (name.indexOf("Main.hx")>=0) log("Push: "+name);
//           tgt.push(name);
//       }

//       // Send initialized after files have been queried, ready to
//       // accept breakpoints
//       if (tgt==SourceFiles.files_full) {
//         send_event({"event":"initialized"});
//       }

//     case ThreadStarted(number):
//       // respond to continue, if it was a continue
//       var response:Dynamic = check_pending("continue");
//       if (response!=null) {
//         response.success = true;
//         send_response(response);
//       }

//     case ThreadStopped(number, frameNumber, className, functionName,
//                        fileName, lineNumber):
//       log("\nThread " + number + " stopped in " +
//           className + "." + functionName + "() at " +
//           fileName + ":" + lineNumber + ".");

//       // First time thread stopped, ask for files first
//       if (!_first_stopped) {
//         _first_stopped = true;
//         _debugger_commands.add(Files);
//         _debugger_commands.add(FilesFullPath);
//       }

//     //_debugger_commands.add(WhereAllThreads);
//       _debugger_commands.add(SetCurrentThread(number));
//       _debugger_commands.add(WhereCurrentThread(false));
//       _send_stopped.push(number);

//     case ThreadCreated(number):
//       log("Thread " + number + " created.");
//       if (ThreadStatus.live_threads.indexOf(number)>=0) {
//         DebugAdapter.log("Error, thread "+number+" already exists");
//       }
//       ThreadStatus.live_threads.push(number);
//       send_output("Thread " + number + " created.");
//       send_event({"event":"thread", "body":{"reason":"started","threadId":number}});

//     case ThreadTerminated(number):
//       log("Thread " + number + " terminated.");
//       if (ThreadStatus.live_threads.indexOf(number)<0) {
//         DebugAdapter.log("Error, thread "+number+" doesn't exist");
//       }
//       ThreadStatus.live_threads.remove(number);
//       send_output("Thread " + number + " terminated.");
//       send_event({"event":"thread", "body":{"reason":"exited","threadId":number}});

//     case ThreadsWhere(list):
//       new ThreadStatus(); // catches new AppThreadStoppedState(), new StackFrame()
//       while (true) {
//         switch (list) {
//         case Terminator:
//           break;
//         case Where(number, status, frameList, next):
//           var t = new AppThreadStoppedState(number);

//           // Respond to pause if there was one, then send stopped event
//           var ssidx = _send_stopped.indexOf(number);
//           if (ssidx>=0) {
//             var stop_reason:String = has_pending("pause") ? "paused" : "entry";
//             send_event({"event":"stopped", "body":{"reason":stop_reason,"threadId":number}});
//             _send_stopped.remove(number);
//           }

//           var reason:String = "";
//           var report_reason:Bool = false;
//           reason += ("Thread " + number + " (");
//           var isRunning : Bool = false;
//           switch (status) {
//           case Running:
//             reason += ("running)\n");
//             list = next;
//             isRunning = true;
//           case StoppedImmediate:
//             reason += ("stopped):\n");
//           case StoppedBreakpoint(number):
//             reason += ("stopped in breakpoint " + number + "):\n");
//           case StoppedUncaughtException:
//             reason += ("uncaught exception):\n");
//             report_reason = true;
//           case StoppedCriticalError(description):
//             reason += ("critical error: " + description + "):\n");
//             report_reason = true;
//           }
//           var hasStack = false;
//           while (true) {
//             switch (frameList) {
//             case Terminator:
//               break;
//             case Frame(isCurrent, number, className, functionName,
//                        fileName, lineNumber, next):
//               reason += ((isCurrent ? "* " : "  "));
//               reason += (padStringRight(Std.string(number), 5));
//               reason += (" : " + className + "." + functionName +
//                          "()");
//               reason += (" at " + fileName + ":" + lineNumber + "\n");
//               new StackFrame(number, className, functionName, fileName, lineNumber);
//               hasStack = true;
//               frameList = next;
//             }
//           }
//           if (!hasStack && !isRunning) {
//             reason += ("No stack.\n");
//           }
//           if (report_reason) {
//             log_and_output(StringTools.rtrim(reason));
//           }

//           list = next;
//         }
//       }

//       if (_send_stopped.length==0) {
//         // no more stops pending? respond to pause, if it was a pause
//         var response:Dynamic = check_pending("pause");
//         if (response!=null) {
//           response.success = true;
//           send_response(response);
//         }
//       }

//     // Only occurs when requesting variables (names) from a frame
//     case Variables(list):
//       if (!Std.is(current_parent, StackFrame)) do_throw("Error, current_parent should be a StackFrame!");
//       if (outstanding_variables!=null) do_throw("Error, variables collision!");
//       outstanding_variables = new StringMap<Variable>();
//       outstanding_variables_cnt = 0;

//       for(name in list) {
//         var v = new Variable(name, current_parent);
//         outstanding_variables.set(name, v);
//         _debugger_commands.add(PrintExpression(false, v.name));
//         outstanding_variables_cnt++;
//       }

//       // No variables?
//       if (outstanding_variables_cnt==0) check_finished_variables();

//     case Value(expression, type, value):
//       //Sys.println(expression + " : " + type + " = " + value);
//       if (current_fqn==null) {
//         var v:Variable = outstanding_variables.get(expression);
//         v.assign(type, value);
//         log("Variable: "+v.fq_name+" assigned variablesReference "+v.variablesReference);
//       } else {
//         log("Got FQ["+current_fqn+"] value: "+message);
//         var name = expression.substr(current_fqn.length+1);
//         // TODO: Array, 1]
//         var v:Variable = outstanding_variables.get(name);
//         if (v!=null) {
//           v.assign(type, value);
//         } else {
//           log("Uh oh, didn't find variable named: "+name);
//         }
//       }
//       outstanding_variables_cnt--;
//       check_finished_variables();

//     case ErrorEvaluatingExpression(details):
//       //Sys.println(expression + " : " + type + " = " + value);
//       log("Error evaluating expression: "+details);
//       outstanding_variables_cnt--;
//       check_finished_variables();

//     case FileLineBreakpointNumber(number):
//       log("Breakpoint " + number + " set and enabled.");

//     default:
//       log("====== UNHANDLED MESSAGE: "+message);
//     }
//   }

//   private static function padStringRight(str : String, width : Int)
//   {
//     var spacesNeeded = width - str.length;

//     if (spacesNeeded <= 0) {
//       return str;
//     }

//     if (gEmptySpace[spacesNeeded] == null) {
//       var str = "";
//       for (i in 0...spacesNeeded) {
//         str += " ";
//       }
//       gEmptySpace[spacesNeeded] = str;
//     }

//     return (gEmptySpace[spacesNeeded] + str);
//   }
//   private static var gEmptySpace : Array<String> = [ "" ];

// }

// class StackFrame implements IVarRef {

//   //static var instances:Array<StackFrame> = [];

//   public var number(default, null):Int;
//   public var className(default, null):String;
//   public var functionName(default, null):String;
//   public var fileName(default, null):String;
//   public var lineNumber(default, null):Int;
//   public var id(default, null):Int;

//   public var variablesReference:Int;

//   public var parent:IVarRef;
//   public var root(get, null):StackFrame;
//   public function get_root():StackFrame
//   {
//     return cast(this);
//   }

//   public function new(number:Int,
//                       className:String,
//                       functionName:String,
//                       fileName:String,
//                       lineNumber:Int)
//   {
//     this.number = number;
//     this.className = className;
//     this.functionName = functionName;
//     this.fileName = fileName;
//     this.lineNumber = lineNumber;

//     root = this;

//     this.id = ThreadStatus.register_stack_frame(this);
//   }

//   public static function toVSCStackFrame(s:StackFrame):Dynamic
//   {

//     // TODO: windows separator?
//     return {
//       name:s.className+'.'+s.functionName,
//       source:SourceFiles.getVSCSource(s.fileName),
//       line:s.lineNumber,
//       column:0,
//       id:s.id
//     }
//   }
// }


// class Variable implements IVarRef {

//   public var name(default, null):String;
//   public var value(default, null):String;
//   public var type(default, null):String;

//   public var variablesReference:Int;
//   var is_decimal = false;

//   public function new(name:String, parent:IVarRef, decimal:Bool=false) {
//     this.name = name;
//     this.parent = parent;
//     is_decimal = decimal;
//   }

//   public var parent:IVarRef;
//   public var root(get, null):StackFrame;
//   public function get_root():StackFrame
//   {
//     var p:IVarRef = parent;
//     while (p.parent!=null) p = p.parent;
//     return cast(p);
//   }

//   public var fq_name(get, null):String;
//   public function get_fq_name():String
//   {
//     var fq = name;
//     if (Std.is(parent, Variable)) {
//       fq = cast(parent, Variable).fq_name+(is_decimal ? '['+name+']' : '.'+name);
//     }
//     return fq;

//     var parent = parent;
//     while (parent!=null && Std.is(parent, Variable)) {
//       fq = cast(parent, Variable).name+'.'+fq;
//     }
//     return fq;
//   }

//   public function assign(type:String, value:String):Void
//   {
//     if (this.type!=null) DebugAdapter.do_throw("Variable can only be assigned once");
//     this.type = type;
//     this.value = value;

//     if (SIMPLES.indexOf(type)<0) {
//       ThreadStatus.register_var_ref(this);
//     }
//   }

//   private static var SIMPLES:Array<String> = ["String", "NULL", "Bool", "Int", "Float",
//                                               "Anonymous", "Function"
//                                              ];
//   public static function toVSCVariable(v:Variable):Dynamic {
//     return {
//       name:v.name,
//       value:v.variablesReference==0 ? (v.value==null ? "--DebugEvalError--" : v.value) : "["+v.type+"]",
//       variablesReference:v.variablesReference
//     };
//   }
// }

// // IVarRef, implemented by StackFrame and Variable
// interface IVarRef {
//   public var parent:IVarRef;
//   public var root(get, null):StackFrame;
//   public var variablesReference:Int;
// }

// class AppThreadStoppedState {
//   public var id:Int;
//   public var stack_frames:Array<StackFrame>;
//   public function new(id:Int) {
//     this.id = id;
//     this.stack_frames = [];
//     ThreadStatus.register_app_thread(this);
//   }
//   public static function toVSCThread(t:AppThreadStoppedState) { return { id:t.id, name:"Thread #"+t.id }; }
//   public static function idToVSCThread(id:Int) { return { id:id, name:"Thread #"+id }; }
// }

// class ThreadStatus {
//   public function new() { }

//   // Managed by ThreadCreated and ThreadTerminated
//   public static var live_threads:Array<Int> = [0];

//   // Updated whenever thread stops
//   public static var threads:IntMap<AppThreadStoppedState> = new IntMap<AppThreadStoppedState>();
//   public static var var_refs:IntMap<IVarRef> = new IntMap<IVarRef>();
//   private static var latest_thread_id:Int = 0;

//   public static function by_id(id:Int):AppThreadStoppedState { return threads.get(id); }

//   public static function getStackFrameById(frameId:Int):StackFrame
//   {
//     for (thread in threads.iterator()) {
//       for (stack in thread.stack_frames) {
//         if (stack.id==frameId) return stack;
//       }
//     }
//     return null;
//   }

//   public static function threadNumForStackFrameId(frameId:Int):Int
//   {
//     for (thread in threads.iterator()) {
//       for (stack in thread.stack_frames) {
//         if (frameId==stack.id) return thread.id;
//       }
//     }
//     DebugAdapter.log("Error, thread not found for frameId "+frameId);
//     return -1;
//   }

//   public static function register_app_thread(t:AppThreadStoppedState):Void
//   {
//     latest_thread_id = t.id;
//     if (threads.exists(t.id)) {
//       // Dispose stack frames, var references, etc
//       DebugAdapter.log("Disposing old thread "+t.id+" stack frames, etc");
//       ThreadStatus.dispose_thread(threads.get(t.id));
//     }
//     threads.set(t.id, t);
//   }

//   private static var stack_frame_id_cnt:Int = 0;
//   public static function register_stack_frame(frame:StackFrame):Int
//   {
//     var val = stack_frame_id_cnt++;
//     threads.get(latest_thread_id).stack_frames.push(frame);
//     register_var_ref(frame);
//     return val;
//   }

//   private static var var_ref_id_cnt:Int = 0;
//   public static function register_var_ref(iv:IVarRef):Void
//   {
//     var_ref_id_cnt++; // start at 1
//     var_refs.set(var_ref_id_cnt, iv);
//     iv.variablesReference = var_ref_id_cnt;
//   }

//   public static function dispose_thread(t:AppThreadStoppedState):Void
//   {
//     // Delete frame and all variables inside it?
//     var rem_vars:Array<Int> = [];
//     for (frame in t.stack_frames) {
//       for (var_ref in var_refs.keys()) {
//         var iv:IVarRef = var_refs.get(var_ref);
//         if (iv==frame || iv.root==frame) rem_vars.push(var_ref);
//       }
//     }
//     for (var_ref in rem_vars) {
//       var_refs.remove(var_ref);
//     }
//     threads.remove(t.id);
//   }
// }
