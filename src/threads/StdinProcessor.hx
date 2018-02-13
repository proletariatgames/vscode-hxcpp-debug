package threads;
using StringTools;
import utils.Globals;
import utils.Log.*;
import vscode.debugger.Data;

class StdinProcessor {
    public static function spawn_thread() {
        if (Globals.stdin_processor_thread != null) {
            throw 'There is already an stdin processor thread';
        }
        Globals.stdin_processor_thread = cpp.vm.Thread.create(function() {
            // var isWindows = Sys.systemName() == "Windows";
            var input = Sys.stdin();
            var wrapped = null;
            if (true) {
                wrapped = new InputHelper(input);
                input = wrapped;
            }
            var inputs = Globals.inputs;
            while (true) {
                try {
                    var len = 0;
                    while (true) {
                        // header
                        var ln = input.readLine().trim();
                        if (ln.length == 0) {
                            break;
                        }
                        var parts = ln.split(':');
                        if (parts[0].toLowerCase() == 'content-length') {
                            len = Std.parseInt(parts[1]);
                        } else {
                            verbose('Ignoring unknown header ${parts[0]}');
                        }
                    }
                    // var tmp = input.readLine().trim();
                    if (wrapped != null) {
                        Globals.record_io(true, wrapped.getBuf());
                    }
                    // if (tmp.length != 0) {
                    //     error('Debugger Input: Expected two blank lines after headers! Got "$tmp" instead');
                    //     continue;
                    // }
                    var msg:vscode.debugger.Data.ProtocolMessage = haxe.Json.parse(input.readString(len));
                    if (msg.type == Response) {
                        var resp:Response = cast msg;
                        msg = null;
                        var cb = Globals.get_response_for_seq(resp.request_seq);
                        if (cb != null) {
                            Globals.add_worker_fn(function()
                                try {
                                    cb(resp);
                                }
                                catch(e:Dynamic) {
                                    utils.Log.error('Internal debugger error while calling callback for $resp: $e');
                                    utils.Log.verbose(haxe.CallStack.toString(haxe.CallStack.exceptionStack()));
                                }
                            );
                        }
                    }
                    if (msg != null) {
                        inputs.add(utils.InputData.VSCodeRequest(msg));
                        // stdin.add(msg);
                    }
                    if (wrapped != null) {
                        Globals.record_io(true, wrapped.getBuf());
                    }
                } 
                catch(e:haxe.io.Error) {
                    switch(e) {
                        case Custom(e) if (Std.is(e, haxe.io.Eof)):
                            // input closed
                            inputs.push(null);
                            break;
                        case _:
                            utils.Log.error('Internal Debugger Error: Error on stdin thread: $e');
                    }
                }
                catch(e:haxe.io.Eof) {
                    // input closed
                    inputs.push(null);
                    break;
                }
                catch(e:Dynamic) {
                    utils.Log.error('Internal Debugger Error: Error on stdin thread: $e');
                    utils.Log.verbose(haxe.CallStack.toString(haxe.CallStack.exceptionStack()));
                }
            }
        });
    }
}

class InputHelper extends haxe.io.Input {
    var wrapped:haxe.io.Input;
    var buf:StringBuf;
    public function new(wrapped) {
        this.wrapped = wrapped;
        this.buf = new StringBuf();
    }
    

	override public function readByte() : Int {
        var ret = wrapped.readByte();
        buf.addChar(ret);
        return ret;
    }

    public function getBuf() {
        var ret = buf.toString();
        this.buf = new StringBuf();
        return ret;
    }

	// override public function readBytes( s : Bytes, pos : Int, len : Int ) : Int {
    // }
}
