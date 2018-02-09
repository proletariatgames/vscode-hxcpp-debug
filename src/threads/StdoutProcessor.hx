package threads;
import utils.Globals;

class StdoutProcessor {
    public static function spawn_thread() {
        if (Globals.stdout_processor_thread != null) {
            throw 'There is already an stdout processor thread';
        }
        Globals.stdout_processor_thread = cpp.vm.Thread.create(function() {
            var isWindows = Sys.systemName() == "Windows";
            var separator = isWindows ? '\n\n' : '\r\n\r\n';
            var stdoutOutput = Sys.stdout();
            var stdout = Globals.stdout;
            while (true) {
                try {
                    var msg = stdout.pop(true);
                    if (msg == null) {
                        break;
                    }
                    var str = 'Content-Length: ${msg.length}$separator$msg';
                    Globals.record_io(false, str);
                    stdoutOutput.writeString(str);
                    stdoutOutput.flush();
                } catch(e:Dynamic) {
                    utils.Log.error('Internal Debugger Error: Error on stdout thread: $e');
                }
            }
            Globals.exit_deque.push(true);
        });
    }
}