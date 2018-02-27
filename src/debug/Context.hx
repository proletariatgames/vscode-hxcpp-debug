package debug;
import cpp.vm.Thread;
import cpp.vm.Deque;
import cpp.vm.Mutex;

import debugger.IController;

import sys.FileSystem;

import utils.InputData;
import utils.Settings;
import utils.Log;

import vscode.debugger.Data;

class Context {
  public static var instance(default, null):Context;
  private static var seq:cpp.AtomicInt = 0;

  public var main_thread(default, null):cpp.vm.Thread;
  public var source_files(default, null):SourceFiles;
  public var breakpoints(default, null):Breakpoints;
  public var thread_cache(default, null):ThreadCache;

  var _stdout_processor:threads.StdoutProcessor;
  var _stdin_processor:threads.StdinProcessor;
  var _workers:threads.Workers;
  var _recorder:threads.Recorder;
  var _debug_connector:threads.DebugConnector;
  var _resetting = false;

  // all
  @:allow(threads) var exit_lock:cpp.vm.Lock = new cpp.vm.Lock();
  // recorder
  @:allow(threads.Recorder) var recorder(default, null):Deque<{ date:Date, io:Bool, ?input:Bool, ?log:utils.Log.LogLevel, msg:String, ?pos:haxe.PosInfos }> = new Deque();

  private var settings:Settings = {
    logLevel: 10, // default
    debugOutput: 
      // '/tmp/log'
      Sys.getEnv('VSCODE_HXCPP_DEBUGGER_DEBUG_OUTPUT')
  };

  public function reset() {
    Log.verbose('reset call: debug_connector.connected=${_debug_connector.connected}');
    if (_debug_connector.connected) {
      _resetting = true;
      _debug_connector.commands.add({ cmd:Exit, cb:null });
      exit_lock.wait();
    } else if (_debug_connector.listen_socket != null) {
      try {
        _debug_connector.listen_socket.close();
      }
      catch(e:Dynamic) {
      }
    }
    _debug_connector = new threads.DebugConnector(this);
    this.breakpoints = new Breakpoints(this);
    this.thread_cache.reset();
  }

  public function new() {
    if (instance != null) {
      throw 'Context is a singleton';
    }
    instance = this;

    this.main_thread = cpp.vm.Thread.current();
    this.source_files = new SourceFiles(this,null);
    this.breakpoints = new Breakpoints(this);
    this.thread_cache = new ThreadCache(this);

    if (settings.debugOutput != null) {
      start_recorder_thread();
    }
    _stdout_processor = new threads.StdoutProcessor(this);
    _stdout_processor.spawn_thread();
    _stdin_processor = new threads.StdinProcessor(this);
    _stdin_processor.spawn_thread();
    _workers = new threads.Workers(this);
    _workers.create_workers(4);
    _debug_connector = new threads.DebugConnector(this);
  }

  public function get_settings() {
    return settings;
  }

  public function connect_debug(host:String, port:Int, ?timeoutSeconds:Int) {
    _debug_connector.connect_and_create_threads(host, port, timeoutSeconds);
  }

  public function query_source_files() {
    var files = switch (add_debugger_command_sync(Files)) {
      case Files(f): f;
      case unexpected:
        Log.fatal('Debugger: Unexpected connector response to Files request: $unexpected');
    };
    var fullPath = switch (add_debugger_command_sync(FilesFullPath)) {
      case Files(f): f;
      case unexpected:
        Log.fatal('Debugger: Unexpected connector response to Files request: $unexpected');
    };

    this.source_files = new SourceFiles(this,this.source_files.classpaths);
    this.source_files.update_sources(files, fullPath);
  }

  public function terminate(code:Int) {
    add_event( ({
      seq: 0,
      type: Event,
      event: Exited,
      body: { exitCode: code }
    } : ExitedEvent) );
    add_event( ({
      seq: 0,
      type: Event,
      event: Terminated,
    } : TerminatedEvent) );
    exit(code);
  }

  inline static var EXIT_TIMEOUT_SECS = 1.0;
  static var terminating = false;

  public function exit(code:Int) {
    Log.verbose('exit($code): $terminating');
    terminating = true;
    _stdout_processor.stdout.add(null);
    var n = 1;
    if (_debug_connector.connected) {
      if (settings.launched) {
        _debug_connector.commands.push({ cmd:Exit, cb:null });
      } else {
        _debug_connector.commands.push({ cmd:Detach, cb:null });
      }

      n++;
    }
    for (_ in 0...n) {
      if (!exit_lock.wait(EXIT_TIMEOUT_SECS)) {
        trace('Exit timeout reached');
      }
    }
    if (_recorder != null) {
      recorder.add(null);
      recorder = null;
      if (!exit_lock.wait(EXIT_TIMEOUT_SECS)) {
        trace('Exit timeout reached');
      }
    }
    Sys.exit(code);
  }


  // threads.StdoutProcessor
  public function add_stdout(output:ProtocolMessage) {
    output.seq = cpp.AtomicInt.atomicInc(cpp.Pointer.addressOf(seq));
    _stdout_processor.stdout.add(haxe.Json.stringify(output));
    return output.seq;
  }

  public function add_event(output:Event) {
    output.seq = cpp.AtomicInt.atomicInc(cpp.Pointer.addressOf(seq));
    _stdout_processor.stdout.add(haxe.Json.stringify(output));
    return output.seq;
  }

  public function add_response(req:Request, response:Response) {
    response.request_seq = req.seq;
    response.command = cast req.command;
    response.seq = cpp.AtomicInt.atomicInc(cpp.Pointer.addressOf(seq));
    _stdout_processor.stdout.add(haxe.Json.stringify(response));
    return response.seq;
  }

  public function add_response_to(req:Request, success:Bool, ?message:String) {
    var out:Response = {
      seq: cpp.AtomicInt.atomicInc(cpp.Pointer.addressOf(seq)),
      type: Response,
      request_seq: req.seq,
      success: success,
      command: cast req.command,
      message: message
    };
    _stdout_processor.stdout.add(haxe.Json.stringify(out));
    return out.seq;
  }

  // threads.StdoutProcessor
  private var responses:Map<Int, Response->Void> = new Map();
  private var responses_mutex:cpp.vm.Mutex = new cpp.vm.Mutex();

  @:allow(threads.StdinProcessor) function get_response_for_seq(seq:Int):Null<Response->Void> {
    var ret = null;
    responses_mutex.acquire();
    ret = responses[seq];
    if (ret != null) {
      responses.remove(seq);
    }
    responses_mutex.release();

    return ret;
  }

  public function add_request(output:Request, ?cb:Response->Void, ?callOnMainThread=true) {
    output.seq = cpp.AtomicInt.atomicInc(cpp.Pointer.addressOf(seq));
    if (cb != null) {
      responses_mutex.acquire();
      responses[output.seq] = callOnMainThread ? function(req) this.add_main_thread_callback(cb.bind(req)) : cb;
      responses_mutex.release();
    }
    _stdout_processor.stdout.add(haxe.Json.stringify(output));
    return output.seq;
  }

  public function add_request_sync(output:Request, ?timeout:Float):Response {
    var lock = new cpp.vm.Lock();
    var ret = null;
    add_request(output, function(r) {
      ret = r;
      lock.release();
    }, false);
    lock.wait(timeout);
    return ret;
  }

  // threads.StdinProcessor
  public function get_next_input(block:Bool):InputData {
    return _stdin_processor.inputs.pop(block);
  }

  public function add_input(input:InputData) {
    _stdin_processor.inputs.add(input);
  }

  public function add_main_thread_callback(cb:Void->Void) {
    _stdin_processor.inputs.add(Callback(cb));
  }

  // threads.Recorder
  public function record_io(input:Bool, msg:String) {
    if (_recorder != null) {
      recorder.add({ date:Date.now(), io:true, input:input, msg:msg });
    }
  }

  public function record_log(level:utils.Log.LogLevel, msg:String, pos:haxe.PosInfos) {
    if (_recorder != null) {
      recorder.add({ date:Date.now(), io:false, log:level, msg:msg, pos:pos });
    }
  }

  // threads.DebugConnector
  public function start_recorder_thread() {
    if (_recorder == null && settings.debugOutput != null) {
      _recorder = new threads.Recorder(this);
      var out = settings.debugOutput;
      if (!FileSystem.exists(out)) {
        FileSystem.createDirectory(out);
      }
      if (FileSystem.isDirectory(out)) {
        out += '/' + DateTools.format(Date.now(), '%Y%m%d_%H%M%S_log.txt');
      }

      _recorder.spawn_thread(out);
    }
  }

  public function add_worker_fn(fn:Void->Void) {
    if (fn == null) {
      Log.error('Null worker function');
    } else {
      this._workers.worker_fns.add(fn);
    }
  }

  public function add_debugger_command(cmd:Command, ?cb:debugger.IController.Message->Void, ?callOnMainThread:Bool=true) {
    _debug_connector.commands.add({ cmd:cmd, cb:callOnMainThread && cb != null ? function(msg) add_main_thread_callback(cb.bind(msg)) : cb });
  }

  public function add_debugger_command_sync(cmd:Command, ?timeout:Float):debugger.IController.Message {
    var lock = new cpp.vm.Lock();
    var ret = null;
    add_debugger_command(cmd, function(r) {
      ret = r;
      lock.release();
    }, false);
    lock.wait(timeout);
    return ret;
  }

  public function on_debugger_exit() {
    Log.verbose('on_debugger_exit $terminating');
    if (_resetting) {
      _resetting = false;
      return;
    }
    if (!terminating) {
      this.terminate(0);
    }
  }

  public function add_debugger_commands_async(cmds:Array<Command>, cb:Array<debugger.IController.Message>->Void, ?callOnMainThread=true) {
    if (!callOnMainThread) {
      var oldCb = cb;
      cb = function(msgs) add_main_thread_callback(oldCb.bind(msgs));
    }
    if (cmds.length == 0) {
      cb([]);
      return;
    }
    var mutex = new cpp.vm.Mutex(), 
        ret = [],
        count = 0,
        len = cmds.length;
    for (i in 0...cmds.length) {
      var cmd = cmds[i];
      add_debugger_command(cmd, function(msg) {
        mutex.acquire();
        count++;
        ret[i] = msg;
        var shouldCall = count == len;
        mutex.release();
        if (shouldCall) {
          cb(ret);
        }
      }, false);
    }
  }
}