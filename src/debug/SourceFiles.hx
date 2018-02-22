package debug;
import sys.FileSystem;
import utils.Log;

using Lambda;
using StringTools;

class SourceFiles {
  public var classpaths(default, null):Array<String>;
  var _context:debug.Context;
  var _sources:Array<String>;
  var _original_sources:Array<String>;
  var _full_sources:Array<String>;

  public function new(context, classpaths) {
    this.classpaths = classpaths;
    _context = context;
  }

  public function add_classpaths(arr:Array<String>) {
    if (arr == null) {
      return;
    }

    if (classpaths == null) {
      classpaths = arr;
    }
    for (cp in arr) {
      if (classpaths.indexOf(cp) < 0) {
        classpaths.push(cp);
      }
    }
  }

  public function update_sources(sources:Array<String>, full_sources:Array<String>) {
    add_classpaths(_context.get_settings().classpaths);
    this._original_sources = sources;
    this._sources = [ for (source in sources) haxe.io.Path.normalize(source) ];
    this._full_sources = [ for (source in full_sources) normalize_full_path(source) ];
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
    for (i in 0..._full_sources.length) {
      if (_full_sources[i].toLowerCase() == normalized) {
        Log.very_verbose('get_source_path($full_path) = ${_original_sources[i]}');
        return _original_sources[i];
      }
    }
    // this might be a cppia source, which doesn't contain the full path
    for (i in 0..._original_sources.length) {
      if (normalized.endsWith(_original_sources[i].toLowerCase()) && normalize_full_path(resolve_source_path(_original_sources[i])).toLowerCase() == normalized) {
        Log.very_verbose('cppia: get_source_path($full_path) = ${_original_sources[i]}');
        return _original_sources[i];
      }
    }

    Log.verbose(Std.string(_full_sources));
    Log.verbose('get_source_path($full_path -> $normalized) could not find any candidate');
    return normalized;
  }

  public function resolve_source_path(name:String) {
    if (name.trim() == '?') {
      return name;
    }
    var normalized = haxe.io.Path.normalize(name);
    var ret = null;
    var idx = _sources.indexOf(name);
    if (idx >= 0) {
      ret = _full_sources[idx];
    }
    if (ret == null) {
      ret = _full_sources.find(function(full) return full.endsWith(normalized));
    }
    if (ret == null) {
      Log.error('Debugger: Could not find the path to $name');
      return name;
    }
    if (!sys.FileSystem.exists(ret)) {
      // this can happen because cppia packages don't have a full path associated with them
      if (classpaths == null) {
        Log.error('Debugger: Could not find the full path to $name. ' +
          'This can happen if the source was deleted or if this is a cppia package.\n' +
          'In case this is a cppia package, consider adding `classpaths` to your configuration file ' +
          'to specifiy the original full classpaths where the compilation took place. This way relative paths ' +
          'can be expanded.');
        return name;
      } else {
        var cp = classpaths.find(function(dir) return sys.FileSystem.exists(dir + '/' + normalized));
        if (cp != null) {
          return cp + '/' + normalized;
        } else {
          Log.error('Debugger: Could not find the full path to $name. Perhaps it was deleted, or `compileDir` references the wrong path');
          return name;
        }
      }
    } else {
      return ret;
    }
  }
}