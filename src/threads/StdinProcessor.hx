package threads;
import cpp.vm.Deque;
import utils.InputData;
import utils.Log.*;
import vscode.debugger.Data;

using StringTools;

class StdinProcessor {
  public var inputs(default, null):Deque<InputData> = new Deque();
  var _context:debug.Context;
  var _thread_spawned = false;

  public function new(ctx) {
    _context = ctx;
  }
  
  public function spawn_thread() {
    if (_thread_spawned) {
      throw 'Thread already spawned';
    }
    _thread_spawned = true;
    cpp.vm.Thread.create(function() {
      var input = Sys.stdin();
      var wrapped:InputHelper = null;
#if DEBUG_PROTOCOL
      wrapped = new InputHelper(input);
      input = wrapped;
#end
      var inputs = this.inputs;
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
          if (wrapped != null) {
            _context.record_io(true, wrapped.getBuf());
          }
          var txtMsg = input.readString(len);
          var msg:vscode.debugger.Data.ProtocolMessage = haxe.Json.parse(txtMsg);
          if (msg.type == Response) {
            var resp:Response = cast msg;
            msg = null;
            var cb = _context.get_response_for_seq(resp.request_seq);
            if (cb != null) {
              _context.add_worker_fn(function()
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
          }
          if (wrapped != null) {
            _context.record_io(true, wrapped.getBuf());
          } else {
            _context.record_io(true, txtMsg);
          }
        } 
        catch(e:haxe.io.Error) {
          switch(e) {
            case Custom(e) if (Std.is(e, haxe.io.Eof) || e == "EOF"):
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
