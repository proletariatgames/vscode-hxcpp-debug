package utils;
import cpp.vm.Deque;
import debugger.IController;
import threads.StdoutProcessor;
import vscode.debugger.Data;

class Globals {
    @:allow(threads.StdoutProcessor) static var stdout(default, null):Deque<String> = new Deque();
    private static var seq:cpp.AtomicInt = 0;

    public static function exit(code:Int) {
        stdout.add(null);
        var n = 1;
        if (recorder_thread != null) {
            n++;
            recorder.add(null);
        }
        if (debugger_output_thread != null) {
            debugger_commands.push(null);
            n++;
        }
        for (_ in 0...n) {
            exit_deque.pop(true);
        }
        Sys.exit(code);
    }

    public static function terminate(code:Int) {
        add_event( ({
            seq: 0,
            type: Event,
            event: Exited,
            body: { exitCode: code }
        } : ExitedEvent) );
        exit(code);
    }

    @:allow(threads) static var exit_deque:Deque<Bool> = new Deque();

    public static function add_stdout(output:ProtocolMessage) {
        output.seq = cpp.AtomicInt.atomicInc(cpp.Pointer.addressOf(seq));
        stdout.add(haxe.Json.stringify(output));
        return output.seq;
    }

    public static function add_event(output:Event) {
        output.seq = cpp.AtomicInt.atomicInc(cpp.Pointer.addressOf(seq));
        stdout.add(haxe.Json.stringify(output));
        return output.seq;
    }

    private static var responses:Map<Int, Response->Void> = new Map();
    private static var responses_mutex:cpp.vm.Mutex = new cpp.vm.Mutex();

    public static function get_response_for_seq(seq:Int):Null<Response->Void> {
        var ret = null;
        responses_mutex.acquire();
        ret = responses[seq];
        if (ret != null) {
            responses.remove(seq);
        }
        responses_mutex.release();

        return ret;
    }

    public static function add_request_wait(output:Request) {
        var lock = new cpp.vm.Lock();
        var ret = null;
        add_request(output, function(r) { ret = r; lock.release(); });
        lock.wait();
        return ret;
    }

    public static function add_request(output:Request, ?cb:Response->Void) {
        output.seq = cpp.AtomicInt.atomicInc(cpp.Pointer.addressOf(seq));
        if (cb != null) {
            responses_mutex.acquire();
            responses[output.seq] = cb;
            responses_mutex.release();
        }
        stdout.add(haxe.Json.stringify(output));
        return output.seq;
    }

    public static function add_request_sync(output:Request, ?timeout:Float):Response {
        var lock = new cpp.vm.Lock();
        var ret = null;
        add_request(output, function(r) {
            ret = r;
            lock.release();
        });
        lock.wait(timeout);
        return ret;
    }

    public static function add_response(req:Request, response:Response) {
        response.request_seq = req.seq;
        response.command = cast req.command;
        response.seq = cpp.AtomicInt.atomicInc(cpp.Pointer.addressOf(seq));
        stdout.add(haxe.Json.stringify(response));
        return response.seq;
    }

    public static function add_response_to(req:Request, success:Bool, ?message:String) {
        var out:Response = {
            seq: cpp.AtomicInt.atomicInc(cpp.Pointer.addressOf(seq)),
            type: Response,
            request_seq: req.seq,
            success: success,
            command: cast req.command,
            message: message
        };
        stdout.add(haxe.Json.stringify(out));
        return out.seq;
    }

    @:allow(threads.StdoutProcessor) static var stdout_processor_thread:cpp.vm.Thread;

    @:allow(threads.StdinProcessor,threads.DebugConnector) static var inputs(default, null):Deque<InputData> = new Deque();

    public static function add_main_thread_callback(cb:Void->Void) {
        inputs.add(Callback(cb));
    }

    public static function get_next_input(block:Bool):InputData {
        return inputs.pop(block);
    }

    public static function add_back_input(input:InputData) {
        inputs.add(input);
    }

    @:allow(threads.StdinProcessor) static var stdin_processor_thread:cpp.vm.Thread;

    @:allow(threads.Recorder) static var recorder(default, null):Deque<{ date:Date, io:Bool, ?input:Bool, ?log:Log.LogLevel, msg:String, ?pos:haxe.PosInfos }> = new Deque();

    public static function record_io(input:Bool, msg:String) {
        if (settings.debugOutput != null) {
            recorder.add({ date:Date.now(), io:true, input:input, msg:msg });
        }
    }

    public static function record_log(level:Log.LogLevel, msg:String, pos:haxe.PosInfos) {
        if (settings.debugOutput != null) {
            recorder.add({ date:Date.now(), io:false, log:level, msg:msg, pos:pos });
        }
    }

    @:allow(threads.Recorder) static var recorder_thread:cpp.vm.Thread;

    private static var settings:Settings = {
        logLevel: 10, // default
        debugOutput: 
            '/tmp/log'
            //Sys.getEnv('VSCODE_HXCPP_DEBUGGER_DEBUG_OUTPUT')
    };

    public static function get_settings() {
        return settings;
    }

    @:allow(threads.DebugConnector) static var debugger_commands:Deque<{ cmd:Command, cb:debugger.IController.Message->Void }> = new Deque();

    public static function add_debugger_command(cmd:Command, ?cb:debugger.IController.Message->Void) {
        debugger_commands.add({ cmd:cmd, cb:cb });
    }

    public static function add_debugger_command_sync(cmd:Command, ?timeout:Float):debugger.IController.Message {
        var lock = new cpp.vm.Lock();
        var ret = null;
        add_debugger_command(cmd, function(r) {
            ret = r;
            lock.release();
        });
        lock.wait(timeout);
        return ret;
    }

    @:allow(threads.DebugConnector) static var debugger_socket_connecting:Bool = false;
    @:allow(threads.DebugConnector) static var debugger_input_thread:cpp.vm.Thread;
    @:allow(threads.DebugConnector) static var debugger_output_thread:cpp.vm.Thread;

    public static function spawn_process(cmd:String, args:Array<String>, cwd:String, cb:Int->Void) {
        try {
            var old = Sys.getCwd();
            Sys.setCwd(cwd);
            var proc = new sys.io.Process(cmd, args);
            Sys.setCwd(old);
            cpp.vm.Thread.create(function() {
                var out = proc.stdout;
                try {
                    while(true) {
                        Log.log(out.readLine());
                    }
                }
                catch(e:haxe.io.Eof) {
                }
                catch(e:Dynamic) {
                    Log.error('Error while reading output from process $cmd: $e');
                }
            });
            cpp.vm.Thread.create(function() {
                var out = proc.stderr;
                try {
                    while(true) {
                        Log.error(out.readLine());
                    }
                }
                catch(e:haxe.io.Eof) {
                }
                catch(e:Dynamic) {
                    Log.error('Error while reading output from process $cmd: $e');
                }
            });
            cpp.vm.Thread.create(function() {
                var exit = proc.exitCode();
                cb(exit);
            });
        }
        catch(e:Dynamic) {
            Log.error('Process $cmd has failed with $e');
            cb(1);
        }
    }

    public static function spawn_process_sync(cmd:String, args:Array<String>, cwd:String):Int {
        try {
            var old = Sys.getCwd();
            Sys.setCwd(cwd);
            var proc = new sys.io.Process(cmd, args);
            Sys.setCwd(old);
            cpp.vm.Thread.create(function() {
                var out = proc.stdout;
                try {
                    while(true) {
                        Log.log(out.readLine());
                    }
                }
                catch(e:haxe.io.Eof) {
                }
                catch(e:Dynamic) {
                    Log.error('Error while reading output from process $cmd: $e');
                }
            });
            cpp.vm.Thread.create(function() {
                var out = proc.stderr;
                try {
                    while(true) {
                        Log.error(out.readLine());
                    }
                }
                catch(e:haxe.io.Eof) {
                }
                catch(e:Dynamic) {
                    Log.error('Error while reading output from process $cmd: $e');
                }
            });
            return proc.exitCode();
        }
        catch(e:Dynamic) {
            Log.error('Process $cmd has failed with $e');
            return -1;
        }
    }

    @:allow(threads.Worker) static var worker_fns:Deque<Void->Void> = new Deque();

    public static function add_worker_fn(fn:Void->Void) {
        if (fn == null) {
            Log.error('Null worker function');
        } else {
            worker_fns.add(fn);
        }
    }
}