package utils;
import cpp.vm.Deque;
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

    @:allow(threads.StdinProcessor) static var stdin(default, null):Deque<Dynamic> = new Deque();

    public static function get_next_stdin(block:Bool):Request {
        return stdin.pop(block);
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
}