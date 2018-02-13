package threads;
import utils.Globals;
import utils.Log;

class Worker {
    public static function create_workers(amount:Int) {
        Log.verbose('Creating $amount workers');
        for (i in 0...amount) {
            cpp.vm.Thread.create(function() {
                try {
                    while(true) {
                        var cb = Globals.worker_fns.pop(true);
                        if (cb == null) {
                            Log.verbose('Worker $i received exit signal');
                            // tell othere
                            Globals.worker_fns.push(null);
                            break;
                        }
                        cb();
                    }
                }
                catch(e:Dynamic) {
                    Log.fatal('Error on a worker thread: $e');
                }
            });
        }
    }
}