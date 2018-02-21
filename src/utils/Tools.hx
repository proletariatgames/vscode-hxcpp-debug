package utils;

class Tools {
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
}