package utils;
import cpp.vm.Deque;

class Globals {
    public static var stdout(default, null):Deque<String>;
    private static var seq:cpp.AtomicInt = 0;

    public static function addStdout<T>(output:vscode.debugger.Data.ProtocolMessage<T>) {
        output.seq = cpp.AtomicInt.atomicInc(cpp.Pointer.addressOf(seq));
        stdout.add(haxe.Json.stringify(output));
    }
}