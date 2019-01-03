package debug;
import sys.FileSystem;
import utils.Log;

using Lambda;
using StringTools;

class CachedSourceFile {
  public var hxcpp_source_name(default, null):String;
  public var normalized_source_name(default, null):String;
  public var index(default, null):Int;
  public var full_path:Null<String>;

  public function new(source_name:String, index:Int)
  {
    this.hxcpp_source_name = source_name;
    this.normalized_source_name = haxe.io.Path.normalize(source_name);
    this.index = index;
  }
}

class SourceFiles {
  public var classpaths(default, null):Array<String>;
  var _normalized_classpaths:Array<String>;
  var _inferenced_classpaths:Map<String, Bool>;
  var _context:debug.Context;
  var _original_sources:Array<String>;
  var _full_sources:Array<String>;
  var _cached_sources:Map<String, CachedSourceFile>;
  var _normalized_cached_sources:Map<String, CachedSourceFile>;
  var _full_to_cached:Map<String, CachedSourceFile>;

  var _warn_flags:Map<String, Bool>;

  public function new(context, classpaths) {
    this.classpaths = classpaths;
    _normalized_classpaths = classpaths == null ? null : [ for (cp in classpaths) normalize_full_path(cp) ];
    _context = context;
    _cached_sources = new Map();
    _full_to_cached = new Map();
    _normalized_cached_sources = new Map();
    _warn_flags = new Map();
  }

  public function add_classpaths(arr:Array<String>) {
    Log.verbose('add_classpaths $arr');
    if (arr == null) {
      return;
    }

    if (classpaths == null) {
      classpaths = arr;
      _normalized_classpaths = [ for (v in arr) normalize_full_path(v) ];
    }
    for (cp in arr) {
      if (classpaths.indexOf(cp) < 0) {
        classpaths.push(cp);
        _normalized_classpaths.push(normalize_full_path(cp));
      }
    }
  }

  public function update_sources(sources:Array<String>, full_sources:Array<String>) {
    add_classpaths(_context.get_settings().classpaths);
    this._original_sources = sources;
    this._full_sources = [ for (source in full_sources) normalize_full_path(source) ];
    for (i in 0...sources.length) {
      var src = sources[i];
      var cached = _cached_sources[src];
      if (cached == null) {
        _normalized_cached_sources[normalize_full_path(src).toLowerCase()] = _cached_sources[src] = new CachedSourceFile(src, i);
      }
    }

    _inferenced_classpaths = new Map();
    for (cached in _cached_sources) {
      var found = cached.full_path;
      if (found == null) {
        for (full in _full_sources) {
          if (full.endsWith(cached.hxcpp_source_name) && FileSystem.exists(full)) {
            if (found != null && found != full) {
              // conflict
              found = null;
              break;
            } else {
              // found = full.substring(0, full.length - cached.hxcpp_source_name.length);
              found = full;
            }
          }
        }
      }
      if (found != null) {
        _inferenced_classpaths[found.substring(0, found.length - cached.hxcpp_source_name.length)] = true;
        set_full_path(cached, found);
      }
    }

    Log.very_verbose('inferenced classpaths: $_inferenced_classpaths');
  }

  public function normalize_full_path(source:String) {
    return try {
      if (haxe.io.Path.isAbsolute(source) && sys.FileSystem.exists(source)) {
        haxe.io.Path.normalize(FileSystem.fullPath(source));
      } else {
        haxe.io.Path.normalize(source);
      }
    }
    catch(e:Dynamic) {
      haxe.io.Path.normalize(source);
    }
  }

  public function get_source_path(full_path:String) {
    var normalized = normalize_full_path(full_path).toLowerCase();
    var ret = _full_to_cached[normalized];
    if (ret != null) {
      return ret.hxcpp_source_name;
    }

    ret = _normalized_cached_sources[normalized];
    if (ret != null) {
      // the source path is already a full path
      return ret.hxcpp_source_name;
    }

    var idx = normalized.indexOf('/_std/');
    if (idx >= 0) {
      // _std is normally not in the classpath
      var path = full_path.substring(idx + '/_std/'.length);
      Log.verbose('_std path found: $normalized ($path)');
      ret = _normalized_cached_sources[path];
      if (ret != null) {
        set_full_path(ret, full_path);
      }
    }

    Log.verbose('get_source_path($full_path) could not be found with the normalized full path');
    // lookup on the classpaths
    var cp = _normalized_classpaths;
    if (cp == null || cp.length == 0) {
      warn_once('classpaths', 'Debugger: Could not find the local path to $full_path. ' +
        'This can happen if this is a cppia source that was not loaded yet, ' +
        'or if was a conflict on the file naming.\n' +
        'Consider adding `classpaths` to your configuration file ' +
        'to specifiy the original full classpaths where the compilation took place.');
      cp = [ for (path in _inferenced_classpaths.keys()) path ];
    }

    Log.very_verbose('looking up using $cp');
    var best:String = null;
    for (path in cp) {
      // Log.very_verbose('"${normalized.toLowerCase()}".startsWith("${path.toLowerCase()}"): ${normalized.toLowerCase().startsWith(path.toLowerCase())}');
      if (normalized.toLowerCase().startsWith(path.toLowerCase())) {
        if (best == null || best.length < path.length) {
          best = path;
        }
      }
    }

    if (best == null) {
      Log.verbose('Could not determine the source path for $full_path');
      return full_path;
    }
    var remaining = normalized.substring(best.length);
    while (remaining.charAt(0) == '/') {
      remaining = remaining.substring(1);
    }

    Log.verbose('Looking for normalize cached source named $remaining');
    ret = _normalized_cached_sources[remaining];
    if (ret == null) {
      Log.verbose('Could not determine the source path for the normalized source $remaining');
      return remaining;
    }

    set_full_path(ret, full_path);
    return ret.hxcpp_source_name;
  }

  private function set_full_path(cached:CachedSourceFile, full_path:String) {
    cached.full_path = full_path;
    _full_to_cached[normalize_full_path(full_path).toLowerCase()] = cached;
  }

  public function resolve_source_path_for_vscode(name:String) {
    var ret = resolve_source_path(name);
    if (Sys.systemName() == "Windows") {
      ret = ret.replace('/','\\');
    }
    return 'file:///' + ret;
  }

  private function warn_once(name:String, msg:String, ?pos:haxe.PosInfos) {
    if (_warn_flags[name]) {
      Log.verbose(msg, pos);
      return;
    }
    Log.warn(msg, pos);
    _warn_flags[name] = true;
  }

  public function resolve_source_path(name:String) {
    if (name.trim() == '?') {
      return name;
    }

    var ret = _cached_sources[name];
    if (ret != null && ret.full_path != null) {
      return ret.full_path;
    }

    if (FileSystem.exists(name)) {
      // already full path
      return name;
    }

    var normalized = null;
    if (ret == null) {
      normalized = haxe.io.Path.normalize(name);
      ret = _normalized_cached_sources[normalized.toLowerCase()];
      if (ret != null && ret.full_path != null) {
        return ret.full_path;
      }
    }

    if (ret == null) {
      warn_once('refreshCppia', 'Could not find a source path for $name. Perhaps this is a cppia file and no debugger.Api.refreshCppiaDefinitions was called?');
      ret = new CachedSourceFile(name, -1);
      _cached_sources[name] = ret;
      _normalized_cached_sources[normalized.toLowerCase()] = ret;
    }

    // lookup using the classpaths
    var cp = classpaths;
    if (cp == null || cp.length == 0) {
      warn_once('classpaths', 'Debugger: Could not find the full path to $name. ' +
        'This can happen if the source was deleted or if this is a cppia package.\n' +
        'In case this is a cppia package, consider adding `classpaths` to your configuration file ' +
        'to specifiy the original full classpaths where the compilation took place. This way relative paths ' +
        'can be expanded.');
      cp = [ for (path in _inferenced_classpaths.keys()) path ];
    }

    var cp = cp.find(function(dir) return sys.FileSystem.exists(dir + '/' + normalized));
    if (cp != null) {
      set_full_path(ret, cp + '/' + normalized);
      return ret.full_path;
    } else {
      Log.error('Debugger: Could not find the full path to $name. Perhaps it was deleted, or `classpath` is not set or incomplete');
      return name;
    }
  }
}