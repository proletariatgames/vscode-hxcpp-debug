package utils;
import cpp.vm.Deque;
import threads.StdoutProcessor;

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

    @:allow(threads) static var exit_deque:Deque<Bool> = new Deque();

    public static function add_stdout<T>(output:vscode.debugger.Data.ProtocolMessage<T>) {
        output.seq = cpp.AtomicInt.atomicInc(cpp.Pointer.addressOf(seq));
        stdout.add(haxe.Json.stringify(output));
        return output.seq;
    }

    public static function add_event<T>(output:vscode.debugger.Data.Event<T>) {
        output.seq = cpp.AtomicInt.atomicInc(cpp.Pointer.addressOf(seq));
        stdout.add(haxe.Json.stringify(output));
        return output.seq;
    }

    public static function add_response_to(req:vscode.debugger.Data.Request<Dynamic>, success:Bool, ?message:String) {
        var out:vscode.debugger.Data.Response = {
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

    public static function get_next_stdin<T>(block:Bool):vscode.debugger.Data.Request<T> {
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