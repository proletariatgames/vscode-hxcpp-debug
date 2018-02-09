package threads;
import utils.Globals;
import utils.Log.*;

class Recorder {
    public static function spawn_thread(output:String) {
        if (Globals.recorder_thread != null) {
            throw 'There is already a recorder thread';
        }
        var out = sys.io.File.write(output, false);
        Globals.recorder_thread = cpp.vm.Thread.create(function() {
            var data = Globals.recorder;
            while (true) {
                try {
                    var cur = data.pop(true);
                    if (cur == null) {
                        break;
                    }
                    var buf = new StringBuf();
                    if (cur.io) {
                        if (cur.input) {
                            buf.add('<---  ${cur.date} input\n');
                        } else {
                            buf.add('--->  ${cur.date} output\n');
                        }
                        buf.add(cur.msg);
                        buf.add('\n--------------------------------------------\n\n');
                    } else {
                        buf.add('==== ${cur.date} ');
                        switch(cur.log) {
                            case VeryVerbose:
                                buf.add('[VVBOSE ] ');
                            case Verbose:
                                buf.add('[VERBOSE] ');
                            case OnlyLog:
                                buf.add('[LOG    ] ');
                            case Warning:
                                buf.add('[WARNING] ');
                            case Error:
                                buf.add('[ERROR   ] ');
                            case Fatal:
                                buf.add('[FATAL   ] ');
                        }
                        buf.add(cur.msg);
                        buf.add('\n');
                    }
                    
                    out.writeString(buf.toString());
                    out.flush();
                } catch(e:Dynamic) {
                    data.push({ io:false, msg:'ERROR on the log recorder thread: $e', log:Error, date:Date.now() });
                }
            }
            Globals.exit_deque.push(true);
        });
    }
}