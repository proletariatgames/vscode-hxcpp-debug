using StringTools;
class Main {
    public static function main() {
        var ret = new StringBuf(),
            unionFields = new Map(),
            enumFields = new Map();
        var data = haxe.Json.parse(sys.io.File.getContent('debugProtocol.json'));
        var defs = data.definitions;
        var indent = '';
        inline function write(str:String) {
            ret.add('$indent$str\n');
        }
        inline function writeStart(str:String) {
            ret.add('$indent$str');
        }
        inline function writePart(str:String) {
            ret.add(str);
        }
        function begin(str:String) {
            ret.add(str);
            ret.add('\n');
            indent += '  ';
        }
        function end(str:String) {
            indent = indent.substr(2);
            ret.add(indent);
            ret.add(str);
            ret.add('\n');
            if (str == '}') {
                ret.add('\n');
            }
        }
        function comment(str:String) {
            begin('/**');
            for (ln in str.split('\n')) {
                write(ln.trim());
            }
            end('**/');
        }
        function unionPropName(str:String, typeName:String) {
            if (str == 'command') {
                if (typeName.indexOf('Response') >= 0) {
                    return 'ResponseCommand';
                } else if (typeName.indexOf('Request') >= 0) {
                    return 'RequestCommand';
                }
                trace(typeName);
            }
            return str;
        }

        var types = new Map();

        for (typeName in Reflect.fields(defs)) {
            var def = Reflect.field(defs, typeName);
            var allDefs = [];
            if (def.description == null) {
                def.description = '';
            }
            if (def.allOf != null) {
                for (defField in (def.allOf : Array<Dynamic>)) {
                    allDefs.push(defField);
                }
            } else {
                allDefs.push(def);
            }
            var type = { defs: allDefs, nArgs: 0, supers:[], params:new Map() };
            types[typeName] = type;
            function visitDef(def, isTopLevel:Bool) {
                if (def.type == 'object') {
                    var props = def.properties;
                    if (props != null) {
                        for (propName in Reflect.fields(props)) {
                            var prop = Reflect.field(props, propName);
                            if (Reflect.hasField(prop, 'enum')) {
                                var arr:Array<String> = Reflect.field(prop, 'enum');
                                if (arr.length == 1 && isTopLevel) {
                                    var unionName = unionPropName(propName, typeName);
                                    var enumToType = unionFields[unionName];
                                    if (enumToType == null) {
                                        unionFields[unionName] = enumToType = new Map();
                                    }
                                    enumToType[Std.string(Reflect.field(prop, 'enum')[0])] = typeName;
                                } else {
                                    enumFields[propName] = arr;
                                }
                            } else if (prop._enum != null) {
                                enumFields[propName] = prop._enum;
                            }
                            if (prop.type == 'object') {
                                visitDef(prop, false);
                            }
                        }
                    }
                }
            }

            for (def in allDefs) {
                if (def.type == 'object') {
                    visitDef(def, true);
                } else if (Reflect.hasField(def, "$ref")) {
                    var name =  (Reflect.field(def, "$ref") : String).split('/').pop();
                    type.supers.push(name);
                }
            }
        }

        for (typeName in types.keys()) {
            switch(typeName) {
                case 'Variable':
                    continue; // it's got a type field that isn't a union type 
                case _:
            }
            var type = types[typeName];
            for (def in type.defs) {
                if (def.type == 'object') {
                    var props = def.properties;
                    if (props != null) {
                        for (propName in Reflect.fields(props)) {
                            var prop = Reflect.field(props, propName);
                            var unionName = unionPropName(propName, typeName);
                            if (!Reflect.hasField(prop, 'enum') && !Reflect.hasField(prop, "$ref") && unionFields.exists(unionName)) {
                                type.params[propName] = type.nArgs++;
                            }
                        }
                    }
                }
            }
        }

        for (kind in unionFields.keys()) {
            var map = unionFields[kind];
            var name = toFirstUpper(kind) + 'Enum';
            ret.add('@:enum abstract $name<T>(String) {\n');
            for (strName in map.keys()) {
                var typeName = map[strName];
                var type = types[typeName];
                if (type.nArgs != 0) {
                    typeName += '<' + [for (_ in 0...type.nArgs) 'Dynamic'].join(', ') + '>';
                }
                ret.add('  var ${toFirstUpper(strName)} : $name<${typeName}> = "$strName";\n');
            }
            // ret.add('  inline function do<T : $name<T>>(fn:$name<T>->Void) fn(cast this);\n');
            // ret.add('  inline function with<T : $name<T>, B>(fn:$name<T>->B) return fn(cast this);\n');
            ret.add('}\n\n');
        }

        for (enumType in enumFields.keys()) {
            if (unionFields.exists(enumType) || enumType == 'command') {
                continue;
            }
            var names = enumFields[enumType];
            var name = toFirstUpper(enumType) + 'Enum';
            ret.add('@:enum abstract $name(String) {\n');
            for (name in names) {
                ret.add('  var ${toFirstUpper(name)} = "$name";\n');
            }
            ret.add('}\n\n');
        }

        for (typeName in types.keys()) {
            var type = types[typeName];
            var curTypeName = typeName,
                curType = type;
            var addedVars = [ "default" => true ];
            function visitDef(def, name:String) {
                var unionName = name == null ? null : unionPropName(name, typeName);
                if (def.type == 'object') {
                    if (name != null ) begin('{');
                    var required:Array<String> = def.required;
                    if (required == null) {
                        required = [];
                    }
                    for (propName in Reflect.fields(def.properties)) {
                        if (addedVars.exists(propName) || (typeName == 'Response' && propName == 'body')) {
                            continue;
                        }
                        var prop = Reflect.field(def.properties, propName);
                        if (propName == 'body' && prop.type != 'object') {
                            continue;
                        }
                        addedVars[propName] = true;
                        writeStart('');
                        if (prop.description != null) {
                            comment(prop.description);
                            writeStart('');
                        }
                        if (required.indexOf(propName) < 0) {
                            writePart('@:optional ');
                        }
                        writePart('var $propName : ');
                        visitDef(prop, propName);
                        writePart(';\n');
                    }
                    if (name != null ) end('}');
                } else if (Reflect.hasField(def, "$ref")) {
                    var target =  (Reflect.field(def, "$ref") : String).split('/').pop();
                    var type = types[target];
                    writePart(target);
                    if (type.nArgs != 0) {
                        writePart('<');
                        writePart([for (_ in 0...type.nArgs) 'Dynamic'].join(', '));
                        writePart('>');
                    }
                } else if (name != null && unionFields.exists(unionName)) {
                    var typeNameToUse = typeName,
                        typeToUse = type;
                    if (!curType.params.exists(name)) {
                        typeNameToUse = curTypeName;
                        typeToUse = curType;
                    }
                    var argName = toFirstUpper(typeNameToUse);
                    var arg = typeToUse.params[name];
                    if (arg != null) {
                        argName = String.fromCharCode('A'.code + arg);
                    } else if (typeToUse.nArgs != 0) {
                        if (typeToUse == type) {
                            argName += '<' + [for (i in 0...typeToUse.nArgs) String.fromCharCode('A'.code + i)].join(', ') + '>';
                        } else {
                            argName += '<' + [for (i in 0...typeToUse.nArgs) 'Dynamic'].join(', ') + '>';
                        }
                    }
                    writePart(toFirstUpper(unionName) + 'Enum<' + argName + '>');
                } else if (name != null && enumFields.exists(name) ) {
                    writePart(toFirstUpper(name) + 'Enum');
                } else if (Std.is(def.type, Array)) {
                    writePart('Dynamic');
                } else {
                    switch(def.type : String) {
                        case 'string': writePart('String');
                        case 'integer': writePart('Int');
                        case 'boolean': writePart('Bool');
                        case 'number': writePart('Float');
                        case 'array': writePart('Array<'); visitDef(untyped def.items, null); writePart('>');
                        case _:
                            trace(def);
                            writePart(def.type);
                    }
                }
            }

            var skip = false;
            var args = '';
            for (def in type.defs) {
                if (def.type == 'object') {
                    var name = toFirstUpper(typeName);
                    if (type.nArgs != 0) {
                        name += 'Args';
                        args = '<' + [for (i in 0...type.nArgs) String.fromCharCode('A'.code + i)].join(', ') + '>';
                    }
                    if (def.description != null) comment(def.description);
                    writePart('typedef $name$args = ');
                } else if (def.type == 'string' && Reflect.hasField(def, 'enum')) {
                    var name = toFirstUpper(typeName);
                    ret.add('@:enum abstract $name(String) {\n');
                    for (name in (Reflect.field(def, 'enum') : Array<String>)) {
                        ret.add('  var ${toFirstUpper(name)} = "$name";\n');
                    }
                    ret.add('}\n\n');
                    skip = true;
                }
            }
            if (skip) {
                continue;
            }
            begin('{');
            function processDef(def) {
                if (Reflect.hasField(def, "$ref")) {
                    var name = (Reflect.field(def, "$ref") : String).split('/').pop();
                    var refType = types[name];
                    if (refType.nArgs != 0) {
                        curType = refType;
                        curTypeName = name;
                        write('// $name implementation');
                        for (def in refType.defs) {
                            if (def.type == 'object') {
                                visitDef(cast def, null);
                            }
                        }
                        write('// end $name implementation\n');
                        for (def in refType.defs) {
                            processDef(def);
                        }
                    } else {
                        write('> $name,');
                    }

                }
            }
            for (def in type.defs) {
                processDef(def);
            }
            curType = type;
            curTypeName = typeName;
            for (def in type.defs) {
                if (def.type == 'object') {
                    visitDef(cast def, null);
                }
            }
            end('}');
            if (args != '') {
                var name = toFirstUpper(typeName);
                writeStart('@:forward abstract $name$args(${name}Args$args) ');
                begin('{');
                trace(type);
                for (param in type.params.keys()) {
                    var unionName = unionPropName(param, typeName);
                    var unions = unionFields[unionName];
                    if (unions == null) {
                        trace(param);
                        trace(type);
                        continue;
                    }
                    for (typeName in unions) {
                        var type = types[typeName];
                        var typeArgs = '';
                        if (type.nArgs != 0) {
                            typeArgs = '<' + [for (_ in 0...type.nArgs) 'Dynamic'].join(',') + '>';
                        }
                        write('@:from inline public static function from$typeName$args(t:$typeName$typeArgs):$name$args return cast t;');
                        writePart(' ');
                    }
                }
                for (param in type.params.keys()) {
                    var param = unionPropName(param, typeName);
                    var Param = toFirstUpper(param);
                    write('inline public function do${Param}<T : { $param : ${Param}Enum<T> }>(fn:T->Void) fn(cast this);');
                    write('inline public function with${Param}<T : { $param : ${Param}Enum<T> }, Ret>(fn:T->Ret):Ret return fn(cast this);');
                }
                end('}');
            }
        }

        sys.io.File.saveContent('Out.hx', ret.toString());
    }

    inline static function toFirstUpper(str:String) {
        return str.substr(0,1).toUpperCase() + str.substr(1);
    }
}