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
      var last = null;
      while (true) {
        last = new DebugAdapter(last);
        last.loop();
      }
    } catch(e:Dynamic) {
      Log.fatal('Debugger: Error on main thread: $e\n${haxe.CallStack.toString(haxe.CallStack.exceptionStack())}');
    }
  }
}

class DebugAdapter {
  static inline var DEFAULT_TIMEOUT_SECS = 120;
  var _output_thread_started:Bool;
  var _context:debug.Context;
  var _last_reason:StoppedEventReasonEnum = Entry;
  var _launch_or_attach:Request;

  public function new(oldAdapter:DebugAdapter) {
    if (oldAdapter != null) {
      _launch_or_attach = oldAdapter._launch_or_attach;
    }
    this._context = oldAdapter == null ? new debug.Context() : oldAdapter._context;
  }

  public function loop() {
    if (_launch_or_attach == null) {
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

      _launch_or_attach = switch(_context.get_next_input(true)) {
        case VSCodeRequest(req):
          cast req;
        case _: throw 'assert'; // should never happen
      };
    }

    var port = this.launch_or_attach(_launch_or_attach);
    var settings = _context.get_settings();
    if (settings.timeout == null) {
      settings.timeout = DEFAULT_TIMEOUT_SECS;
    } else if (settings.timeout < 0) {
      settings.timeout = null;
    }

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
    var configuration_done = false,
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
            _context.add_event(({
              seq: 0, type: Event,
              event: Thread,
              body: {
                reason: Started,
                threadId: thread_number
              }
            } : ThreadEvent));
          }
        case ThreadTerminated(thread_number):
          if (!configuration_done) {
            after_configuration_done.push(input);
          } else {
            _context.add_event(({
              seq: 0, type: Event,
              event: Thread,
              body: {
                reason: Exited,
                threadId: thread_number
              }
            } : ThreadEvent));
          }
        case ThreadStarted(thread_number):
          _context.thread_cache.reset();
          if (!configuration_done) {
            after_configuration_done.push(input);
          } else {
            _context.add_event(({
              seq: 0, type: Event,
              event: Continued,
              body: {
                threadId: thread_number
              }
            } : ContinuedEvent));
          }
        case ThreadStopped(thread_number, stack_frame, cls_name, fn_name, file_name, ln_num):
          _context.thread_cache.reset();
          if (!configuration_done) {
            Log.verbose('Thread stopped but initial threads answer was still not sent');
            after_configuration_done.push(input);
          } else {
            // get thread stopped reason
            if (_last_reason != null) {
              _context.add_event(( {
                seq: 0,
                type: Event,
                event: Stopped,
                body: {
                  reason: _last_reason,
                  threadId: thread_number,
                  allThreadsStopped: true
                }
              } : StoppedEvent));
              // if (_last_reason == Entry && !_context.get_settings().stopOnEntry) {
              //   _context.add_debugger_command(Continue(1));
              // }
              _last_reason = null;
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
            if (_launch_or_attach.command == Launch) {
              _context.thread_cache.reset();
              _context.reset();
              _context.add_event( ({
                seq: 0,
                type: Event,
                event: Exited,
                body: { exitCode: 0 }
              } : ExitedEvent) );
              return;
            } else {
              Log.fatal('Cannot restart an attached application');
            }
          case Disconnect:
            if (_launch_or_attach.command == Launch) {
              _context.add_debugger_command(Exit);
            } else {
              _context.add_debugger_command(Continue(1));
              _context.add_debugger_command(Detach);
            }
            _context.exit(0);
          case SetBreakpoints:
            _context.breakpoints.vscode_set_breakpoints(cast req);
          case SetFunctionBreakpoints:
            _context.breakpoints.vscode_set_fn_breakpoints(cast req);
          case Continue:
            _last_reason = null;
            call_and_respond(req, Continue(1));
          case Next:
            _last_reason = Step;
            call_and_respond(req, Next(1));
          case StepIn:
            _last_reason = Step;
            call_and_respond(req, Step(1));
          case StepOut:
            _last_reason = Step;
            call_and_respond(req, Finish(1));
          case Pause:
            _last_reason = Pause;
            call_and_respond(req, BreakNow);
          case StackTrace:
            respond_stack_trace(cast req);
          case Scopes:
            respond_scopes(cast req);
          case Variables:
            respond_variables(cast req);
          case SetVariable:
            respond_set_variable(cast req);
          case Threads:
            respond_threads(req);
          case Modules:
          case Evaluate:
            respond_evaluate(cast req);
          case ConfigurationDone:
            Log.verbose('Configuration Done');
            _context.add_response_to(req, true);
            configuration_done = true;
            // make sure we have the updated classpaths
            on_new_classpaths(true);
            for (input in after_configuration_done) {
              _context.add_input(input);
            }
            _context.thread_cache.init();
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

  private static function val_type_to_class_type(t:debugger.IController.StructuredValueType):Null<String> {
    return switch(t) {
      case TypeInstance(name) | TypeClass(name): name;
      case _: null;
    }
  }

  private static function val_list_type_to_class_type(t:debugger.IController.StructuredValueListType):String {
    return switch(t) {
      case Instance(cls): cls;
      case _: null;
    }
  }

  private function structured_to_vscode(thread_id:Int, frame_id:Int, 
                                        s:debugger.IController.StructuredValue, name:String,
                                        out:Array<vscode.debugger.Data.Variable>, 
                                        cls_type:Null<debugger.Runtime.ClassDef>,
                                        expr:Null<String>,
                                        main_call=true) {
    var info:Null<debugger.Runtime.VariableProperties> = null,
        hint:VariablePresentationHint = null,
        force_elided = false;
    if (!main_call && cls_type != null) {
      info = cls_type.vars[name];
      if (info != null) {
        hint = {
          kind: switch(info.kind) {
              case Var: Property;
              case Method: Method;
              case Class: Class;
              case Data: Data;
              case Event: Event;
              case BaseClass: BaseClass;
              case Interface: Interface;
              case Virtual: Virtual;
            },
          attributes: [],
          visibility: switch(info.visibility) {
              case Public: Public;
              case Private: Private;
              case Protected: Protected;
              case Internal: Internal;
              case Final: Final;
            }
        };
        if (info.attributes.hasAny(Static)) {
          hint.attributes.push('static');
        }
        if (info.attributes.hasAny(Constant)) {
          hint.attributes.push('constant');
        }
        if (info.attributes.hasAny(ReadOnly)) {
          hint.attributes.push('readOnly');
        }
        if (info.attributes.hasAny(Property)) {
          force_elided = true;
        }
      }
    }

    switch(s) {
    case Elided(val_type, get_expression):
      out.push({
        name: name,
        value: '',
        type: val_type_to_string(val_type),
        evaluateName: get_expression,
        variablesReference: 
          _context.thread_cache.get_or_create_var_ref(
            StackVar(thread_id, frame_id, get_expression, val_type_to_class_type(val_type))),
        presentationHint: hint
      });
    case Single(val_type, val):
      out.push({
        name: name,
        value: force_elided ? '' : val,
        type: force_elided ? null : val_type_to_string(val_type),
        presentationHint: hint,
        variablesReference: !force_elided ? 0 :
          _context.thread_cache.get_or_create_var_ref(
            StackVarBuffer(thread_id, frame_id, expr, "get")),
      });
    case List(list_type, lst):
      var lst = lst;
      var count = 0;
      while (true) {
        switch(lst) {
        case Terminator:
          if (count == 0 && list_type.match(Instance("cpp::Pointer"))) {
            out.push({
              name: name,
              value: "cpp.Pointer",
              type: "cpp.Pointer",
              presentationHint: hint,
              variablesReference: 0
            });
          }
          break;
        case Element(name, val, next):
          count++;
          var expr = list_type == _Array ? (expr + '[' + name + ']') : (expr + '.' + name);
          structured_to_vscode(thread_id, frame_id, val, name, out, cls_type, expr, false);
          lst = next;
        }
      }
    }
  }

  private static function val_list_type_to_string(type:debugger.IController.StructuredValueListType) {
    return switch(type) {
      case Anonymous: '<anonymous>';
      case Instance(cls): cls;
      case _Array: 'Array';
      case Class: 'Class';
    }
  }

  private static function is_type_string(s:debugger.IController.StructuredValue) {
    return switch(s) {
      case Single(TypeString | TypeClass("String"), _):
        true;
      case _:
        false;
    }
  }

  private function respond_set_variable(req:SetVariableRequest) {
    var ref = _context.thread_cache.get_last_value_ref(req.arguments.variablesReference);
    if (ref == null) {
      _context.add_response_to(req, false, 'The variables reference ${req.arguments.variablesReference} was not found');
      return;
    }
    var value = req.arguments.value,
        name = req.arguments.name;
    var thread_id,
        frame_id,
        expr;
    switch(ref) {
    case StackFrame(tid, fid):
      thread_id = tid;
      frame_id = fid;
      expr = name;
    case StackVar(tid, fid, e, _) | StackVarBuffer(tid, fid, e, _):
      thread_id = tid;
      frame_id = fid;
      expr = e + '.' + name;
    case StructuredRef(tid, fid, e, _, s):
      thread_id = tid;
      frame_id = fid;
      switch(s) {
      case Elided(_) | Single(_):
        expr = e + '.' + name;
      case List(list_type, lst):
        switch(list_type) {
        case _Array:
          expr = e + '[' + name + ']';
          switch(lst) {
          case Element(_, v, _):
            if (is_type_string(v)) {
              value = haxe.Json.stringify(value);
            }
          case _:
          }
        case _:
          expr = e + '.' + name;
          var lst = lst;
          while (true) {
            switch (lst) {
            case Terminator:
              Log.verbose('Unknown name $name for list $lst');
              break;
            case Element(name, v, next):
              if (name == req.arguments.name) {
                if (is_type_string(v)) {
                  value = haxe.Json.stringify(value);
                }
                break;
              }
              lst = next;
            }
          }
        }
      }
    }
    _context.thread_cache.do_with_frame(thread_id, frame_id, function(msg) {
      if (msg != null) {
        _context.add_response_to(req, false, 'Error while getting frame $frame_id for $thread_id: $msg');
        return;
      }
      _context.add_debugger_command(SetExpression(false, expr, value), function(msg) {
        switch (msg) {
        case Value(_, type, value):
          _context.add_response(req, ({
            seq: 0, type: Response, request_seq: req.seq, command: Std.string(req.command),
            success: true,
            body: {
              value: type == 'String' ? Std.string(haxe.Json.parse(value)) : value,
              type: type
            }
          } : SetVariableResponse));
        case ErrorCurrentThreadNotStopped(_):
          _context.add_response_to(req, false, 'Error while evaluating expression: Thread not stopped');
          return;
        case ErrorEvaluatingExpression(details):
          _context.add_response_to(req, false, 'Error while evaluating expression: $details');
          return;
        case msg:
          _context.add_response_to(req, false, 'Unexpected error while evaluating expression: $msg');
          return;
        }
      });
    });
  }

  private function respond_evaluate(req:EvaluateRequest) {
    var thread_and_frame = req.arguments.frameId;
    var thread_id = (thread_and_frame >>> 16) & 0xFFFF;
    var frame_id = thread_and_frame & 0xFFFF;

    _context.thread_cache.do_with_frame(thread_id, frame_id, function(msg) {
      if (msg != null) {
        _context.add_response_to(req, false, 'Error while getting frame $frame_id for $thread_id: $msg');
        return;
      }
      _context.add_debugger_command(GetStructured(false, req.arguments.expression), function(msg) {
        switch(msg) {
          case Structured(s):
            var resp:EvaluateResponse = {
              seq: 0, type: Response, request_seq: req.seq, command: Std.string(req.command), success:true,
              body: null
            };
            switch(s) {
            case Elided(val_type, get_expression):
              resp.body = {
                result: val_type_to_string(val_type),
                type: val_type_to_string(val_type),
                variablesReference: _context.thread_cache.get_or_create_var_ref(StackVar(thread_id, frame_id, get_expression, val_type_to_class_type(val_type))),
              };
            case Single(val_type, val):
              resp.body = {
                result: val,
                type: val_type_to_string(val_type),
                variablesReference: 0,
              };
            case List(list_type, lst):
              resp.body = {
                result: val_list_type_to_string(list_type),
                type: val_list_type_to_string(list_type),
                variablesReference: _context.thread_cache.get_or_create_var_ref(StructuredRef(thread_id, frame_id, req.arguments.expression, val_list_type_to_class_type(list_type), s)),
              };
            }
            _context.add_response(req, resp);
          case ErrorCurrentThreadNotStopped(_):
            _context.add_response_to(req, false, 'Error while evaluating expression: Thread not stopped');
            return;
          case ErrorEvaluatingExpression(details):
            _context.add_response_to(req, false, 'Error while evaluating expression: $details');
            return;
          case msg:
            _context.add_response_to(req, false, 'Unexpected error while evaluating expression: $msg');
            return;
        }
      });
    });
  }

  private function respond_variables(req:VariablesRequest) {
    var ref = _context.thread_cache.get_ref(req.arguments.variablesReference);
    if (ref == null) {
      _context.add_response_to(req, false, 'The variables reference ${req.arguments.variablesReference} was not found');
      return;
    }
    switch(ref) {
    case StructuredRef(thread_id, frame_id, expr, cls_type, s):
      _context.thread_cache.get_class_def(cls_type, function(def) {
        var ret = [];
        structured_to_vscode(thread_id, frame_id, s, expr, ret, def, expr);
        _context.add_response(req, ({
          seq: 0, type: Response, request_seq: req.seq, command: Std.string(req.command),
          success: true,
          body: {
            variables: ret
          }
        } : VariablesResponse));
      });
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
            _context.add_debugger_commands_async([for (v in vars) GetStructured(false, v)], function(msgs) {
              for (i in 0...vars.length) {
                var v = vars[i],
                    msg = msgs[i];
                switch (msg) {
                  case null:
                    ret.push({
                      name: v,
                      value: '<err>',
                      variablesReference: _context.thread_cache.get_or_create_var_ref(StackVar(thread_id, frame_id, v, null)),
                      evaluateName: v
                    });
                  case Structured(s):
                    switch(s) {
                    case List(t,_):
                      ret.push({
                        name: v,
                        value: val_list_type_to_string(t),
                        variablesReference: _context.thread_cache.get_or_create_var_ref(StackVar(thread_id, frame_id, v, val_list_type_to_class_type(t))),
                        evaluateName: v
                      });
                    case _:
                      structured_to_vscode(thread_id, frame_id, s, v, ret, null, v);
                    }
                  case _:
                    ret.push({
                      name: v,
                      value: '<err>',
                      variablesReference: _context.thread_cache.get_or_create_var_ref(StackVar(thread_id, frame_id, v, null)),
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
    case StackVarBuffer(thread_id, frame_id, expr, name):
      _context.thread_cache.do_with_frame(thread_id, frame_id, function(msg) {
        if (msg != null) {
          _context.add_response_to(req, false, 'Error while getting frame $frame_id for $thread_id: $msg');
          return;
        }
        // call this synchronously otherwise something else might make this leave the current frame
        switch (_context.add_debugger_command_sync(GetStructured(false, expr))) {
        case Structured(structured):
          var cls_type = null,
              type = null;
          switch(structured) {
            case Elided(val_type,_) | Single(val_type, _): 
              type = val_type_to_string(val_type);
              cls_type = val_type_to_class_type(val_type);
            case List(list_type,_): 
              type = val_list_type_to_string(list_type);
              cls_type = val_list_type_to_class_type(list_type);
          }
          _context.add_response(req, ({
              seq: 0, type: Response, request_seq: req.seq, command: Std.string(req.command),
              success: true,
              body: {
                variables: [{
                  name: name,
                  value: type,
                  type: type,
                  presentationHint: {
                    kind: Property,
                    attributes: [],
                    visibility: Public
                  },
                  evaluateName: expr,
                  variablesReference: 
                    _context.thread_cache.get_or_create_var_ref(
                      StructuredRef(thread_id, frame_id, expr, cls_type, structured))
                }]
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

    case StackVar(thread_id, frame_id, expr, cls_type):
      _context.thread_cache.do_with_frame(thread_id, frame_id, function(msg) {
        if (msg != null) {
          _context.add_response_to(req, false, 'Error while getting frame $frame_id for $thread_id: $msg');
          return;
        }
        // call this synchronously otherwise something else might make this leave the current frame
        switch (_context.add_debugger_command_sync(GetStructured(false, expr))) {
        case Structured(structured):
          _context.thread_cache.set_stack_var_result(req.arguments.variablesReference, structured);
          _context.thread_cache.get_class_def(cls_type, function(def) {
            var ret = [];
            structured_to_vscode(thread_id, frame_id, structured, expr, ret, def, expr);
            _context.add_response(req, ({
              seq: 0, type: Response, request_seq: req.seq, command: Std.string(req.command),
              success: true,
              body: {
                variables: ret
              }
            } : VariablesResponse));
          });

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
                      path: _context.source_files.resolve_source_path_for_vscode(file_name),
                    },
                    line: ln_num,
                  });
                  ret.push({
                    name: 'Statics',
                    variablesReference: _context.thread_cache.get_or_create_var_ref(StackVar(thread_id, frame_id, class_name, class_name)),
                    expensive: false,
                    source: {
                      name: file_name,
                      path: _context.source_files.resolve_source_path_for_vscode(file_name),
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
                    path: _context.source_files.resolve_source_path_for_vscode(file_name),
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
        case Normal | Internal(null):
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
      settings.launched = true;
      for (field in Reflect.fields(launch.arguments)) {
        var curField = Reflect.field(settings, field);
        if (curField == null) {
          Reflect.setField(settings, field, Reflect.field(launch.arguments, field));
        }
      }
      _context.start_recorder_thread();

      // compile
      function change_terminal_args(cwd:String, args:Array<String>) {
        if (args[0].charCodeAt(0) != '.'.code && 
            !haxe.io.Path.isAbsolute(args[0]) && 
            args[0].indexOf('/') < 0 && 
            args[0].indexOf('\\') < 0 &&
            sys.FileSystem.exists(cwd + '/' + args[0]))
        {
          args[0] = (Sys.systemName() == 'Windows' ? '.\\' : './') + args[0];
        }
        return args;
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
          args: change_terminal_args(curSettings.run.cwd, curSettings.run.args),
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
      port = curSettings.port == null ? 6972 : curSettings.port;
      if (port <= 0) {
        Log.fatal('Attach: Invalid port $port');
      }
    case _:
      Log.fatal('protocol error: Expected "launch" or "attach", but got $launch_or_attach');
    }
    return port;
  }

  private function setup_internal_breakpoints() {
    _context.breakpoints.add_breakpoint(Internal(on_cppia_load), FuncBr('debugger.Api', 'refreshCppiaDefinitions'));
    _context.breakpoints.add_breakpoint(Internal(on_new_classpaths.bind(false)), FuncBr('debugger.Api', 'setClassPaths'));
    _context.breakpoints.add_breakpoint(Internal(null), FuncBr('debugger.Api', 'debugBreak'));
  }

  private function on_new_classpaths(initial) {
    Log.verbose('Receiving new classpaths');
    var get_classpaths = initial ? 'debugger.Api.lastClasspaths' : 'classpaths';

    switch(_context.add_debugger_command_sync(GetStructured(false, get_classpaths))) {
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
    case Structured(Single(_, "null")) if (initial):
      // it's still null - no worries
    case unexpected:
      Log.error('Unexpected response when getting new classpaths: $unexpected');
    }

    if (initial) {
      return;
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
    // update files
    Log.verbose('Updating source files');
    this._context.query_source_files();
    // refresh breakpoints that were not found
    Log.verbose('Refreshing breakpoints');
    this._context.thread_cache.reset_class_defs();
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