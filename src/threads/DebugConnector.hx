package threads;
import cpp.vm.Deque;
import debugger.HaxeProtocol;
import debugger.IController;
import utils.Log;

class DebugConnector {
  public var commands(default, null):Deque<{ cmd:Command, cb:debugger.IController.Message->Void }> = new Deque();
  var socket_connecting:Bool = false;
  var input_thread:cpp.vm.Thread;
  var output_thread:cpp.vm.Thread;

  var _context:debug.Context;
  var _thread_spawned = false;

  public function new(ctx) {
    _context = ctx;
  }

  public function connect_and_create_threads(host:String, port:Int, ?timeoutSeconds:Int) {
    if (socket_connecting || input_thread != null || this.output_thread != null) {
      throw 'There are already debugger threads';
    }
    Log.verbose('Connecting to the debugger at $host:$port');
    this.socket_connecting = true;

    var time = Sys.time();
    var waitLock = new cpp.vm.Lock();
    cpp.vm.Thread.create(function() {
      pvt_connect_and_create_threads(host, port, timeoutSeconds);
      waitLock.release();
    });

    while (timeoutSeconds == null || Sys.time() - time < timeoutSeconds) {
      if (waitLock.wait(10)) {
        break;
      } else {
        Log.log("Client not yet connected, does it 1) call new HaxeRemote(true, 'localhost'), 2) compiled with -debug, and 3) define -D HXCPP_DEBUGGER ?");
      }
    }
  }

  private function pvt_connect_and_create_threads(host:String, port:Int, ?timeoutSeconds:Int) {
    try {
      var startTime = Sys.time();
      inline function timeout_reached() {
        return (timeoutSeconds != null && Sys.time() >= startTime + timeoutSeconds);
      }
      var listenSocket =  null;
      
      do {
        try {
          listenSocket = new sys.net.Socket();
          listenSocket.bind(new sys.net.Host(host), port);
          listenSocket.listen(1);
        }
        catch(e:Dynamic) {
          Log.log('Debugger: Failed to bind/listen on $host:$port: $e');
          Log.log('Debugger: Trying again in 3 seconds.');
          Sys.sleep(3);
          if (listenSocket != null) {
            listenSocket.close();
          }
          listenSocket = null;
        }
      }
      while (listenSocket == null && !timeout_reached());

      if (listenSocket == null) {
        Log.fatal('Timeout reached while listening to $host:$port');
      }

      var socket = null;

      do {
        try {
          Log.log('Debugger: Listening for client connection on $host:$port....');
          socket = listenSocket.accept();
        }
        catch(e:Dynamic) {
          Log.warn('Debugger: Failed to accept connection: $e');
          Log.log('Debugger: Trying again in 1 second');
          Sys.sleep(1);
        }
      } 
      while (socket == null && !timeout_reached());

      var peer = socket.peer();
      Log.log("VSCHS: Received connection from " + peer.host + ".");

      var initLockInput = new cpp.vm.Lock(),
        initLockOutput = new cpp.vm.Lock();
      var responses = new cpp.vm.Deque<Message>();

      this.input_thread = cpp.vm.Thread.create(function() {
        try {
          var inp = socket.input;
          HaxeProtocol.readClientIdentification(inp);
          Log.verbose('Client identification was read');
          initLockInput.release();

          while (true) {
            var message = HaxeProtocol.readMessage(inp);
            _context.record_io(true, Std.string(message));
            switch(message) {
            case ThreadCreated(_) | ThreadTerminated(_) | 
               ThreadStarted(_) | ThreadStopped(_):
              // interrupts
              _context.add_input(DebuggerInterrupt(message));
            case _:
              responses.add(message);
            }
          }
        } 
        catch(e:haxe.io.Error) {
          switch(e) {
            case Custom(e) if (Std.is(e, haxe.io.Eof)):
              this.commands.push(null);
            case _:
              Log.fatal('Debugger: Error on the debugger input thread: $e');
          }
        }
        catch (e:haxe.io.Eof) {
          this.commands.push(null);
        }
        catch (e:Dynamic) {
          Log.fatal('Debugger: Error on the debugger input thread: $e');
        }
      });

      this.output_thread = cpp.vm.Thread.create(function() {
        try {
          var out = socket.output;
          HaxeProtocol.writeServerIdentification(out);
          Log.verbose('Server identification was written');
          initLockOutput.release();
          while (true) {
            var msg = this.commands.pop(true);
            if (msg == null) {
              break;
            }
            _context.record_io(false, Std.string(msg.cmd));
            HaxeProtocol.writeCommand(out, msg.cmd);
            var resp = responses.pop(true);
            if (msg.cb != null) {
              _context.add_worker_fn(function() msg.cb(resp));
            }
          }
        }
        catch(e:haxe.io.Error) {
          switch(e) {
            case Custom(e) if (Std.is(e, haxe.io.Eof)):
            case _:
              _context.exit_lock.release();
              Log.fatal('Debugger: Error on the debugger output thread: $e');
          }
        }
        catch (e:haxe.io.Eof) {
        }
        catch (e:Dynamic) {
          _context.exit_lock.release();
          Log.fatal('Debugger: Error on the debugger output thread: $e');
        }
        _context.exit_lock.release();
      });

      var newTimeoutSecs = 60,
        timeoutTime = Sys.time() + newTimeoutSecs;
      Log.verbose('Waiting for connections');
      var success = false;
      if (initLockInput.wait(newTimeoutSecs)) {
        Log.verbose('Init lock input');
        success = true;
      }
      if (!initLockOutput.wait(timeoutTime - Sys.time())) {
        Log.verbose('Init lock output');
        success = true;
      }
      if (!success) {
        _context.exit_lock.release();
        Log.fatal('Debugger: The server connected but no identification was found');
      }
    }
    catch(e:Dynamic) {
      Log.fatal('Debugger: Fatal error while creating the debug session: $e');
    }
  }
}