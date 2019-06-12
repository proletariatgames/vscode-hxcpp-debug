package threads;
#if haxe4
import sys.thread.Deque;
import sys.thread.Lock;
import sys.thread.Thread;
#else
import cpp.vm.Deque;
import cpp.vm.Lock;
import cpp.vm.Thread;
#end

import debugger.HaxeProtocol;
import debugger.IController;
import utils.Log;

class DebugConnector {
  public var commands(default, null):Deque<{ cmd:Command, cb:debugger.IController.Message->Void }> = new Deque();
  public var connected(default, null):Bool;
  public var socket_connecting(default, null):Bool = false;
  var input_thread:Thread;
  var output_thread:Thread;
  public var listen_socket(default, null):sys.net.Socket;

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
    var waitLock = new Lock();
    Thread.create(function() {
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
      listen_socket =  null;

      do {
        try {
          listen_socket = new sys.net.Socket();
          listen_socket.bind(new sys.net.Host(host), port);
          listen_socket.listen(1);
        }
        catch(e:Dynamic) {
          Log.log('Debugger: Failed to bind/listen on $host:$port: $e');
          Log.log('Debugger: Trying again in 3 seconds.');
          Sys.sleep(3);
          if (listen_socket != null) {
            listen_socket.close();
          }
          listen_socket = null;
        }
      }
      while (listen_socket == null && !timeout_reached());

      if (listen_socket == null) {
        Log.fatal('Timeout reached while listening to $host:$port');
      }

      var socket = null;

      do {
        try {
          Log.log('Debugger: Listening for client connection on $host:$port....');
          socket = listen_socket.accept();
        }
        catch(e:Dynamic) {
          Log.warn('Debugger: Failed to accept connection: $e');
          Log.log('Debugger: Trying again in 1 second');
          Sys.sleep(1);
        }
      }
      while (socket == null && !timeout_reached());

      var peer = socket.peer();
      connected = true;
      Log.log("VSCHS: Received connection from " + peer.host + ".");

      var initLockInput = new Lock(),
        initLockOutput = new Lock();
      var responses = new Deque<Message>();

      this.input_thread = Thread.create(function() {
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
            case Exited | Detached:
              Log.verbose('Exit message caught: $message');
              connected = false;
              this.commands.push(null);
              responses.push(null);
            case _:
              responses.add(message);
            }
          }
        }
        catch(e:haxe.io.Error) {
          switch(e) {
            case Custom(e) if (Std.is(e, haxe.io.Eof) || e == "EOF"):
              connected = false;
              this.commands.push(null);
              responses.push(null);
            case _:
              Log.fatal('Debugger: Error on the debugger input thread: $e');
          }
        }
        catch (e:haxe.io.Eof) {
          connected = false;
          this.commands.push(null);
          responses.push(null);
        }
        catch (e:Dynamic) {
          Log.fatal('Debugger: Error on the debugger input thread: $e');
        }
      });

      this.output_thread = Thread.create(function() {
        try {
          var out = socket.output;
          HaxeProtocol.writeServerIdentification(out);
          Log.verbose('Server identification was written');
          initLockOutput.release();
          while (true) {
            var msg = this.commands.pop(true);
            if (msg == null) {
              _context.on_debugger_exit();
              break;
            }
            _context.record_io(false, Std.string(msg.cmd));
            HaxeProtocol.writeCommand(out, msg.cmd);
            var resp = responses.pop(true);
            if (resp == null) {
              _context.on_debugger_exit();
              break;
            }
            if (msg.cb != null) {
              _context.add_worker_fn(function() msg.cb(resp));
            }
          }
        }
        catch(e:haxe.io.Error) {
          switch(e) {
            case Custom(e) if (Std.is(e, haxe.io.Eof) || e == "EOF"):
              connected = false;
            case _:
              utils.Log.very_verbose('DebugConnector: Exit signal received');
              _context.exit_lock.release();
              Log.fatal('Debugger: Error on the debugger output thread: $e');
          }
        }
        catch (e:haxe.io.Eof) {
          connected = false;
        }
        catch (e:Dynamic) {
          connected = false;
          Log.fatal('Debugger: Error on the debugger output thread: $e');
        }

        try {
          Log.verbose('Closing socket');
          socket.shutdown(true, true);
          socket.close();
        } catch(e:Dynamic) {
        }
        try {
          Log.verbose('Closing listen socket');
          listen_socket.close();
        } catch(e:Dynamic) {
        }
        utils.Log.very_verbose('DebugConnector: Exit signal received');
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
        utils.Log.very_verbose('DebugConnector: Exit signal received');
        _context.exit_lock.release();
        Log.fatal('Debugger: The server connected but no identification was found');
      }
    }
    catch(e:Dynamic) {
      Log.fatal('Debugger: Fatal error while creating the debug session: $e');
    }
  }
}