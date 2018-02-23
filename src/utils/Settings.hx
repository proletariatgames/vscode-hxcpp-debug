package utils;

typedef Settings = {
    ?logLevel:Int,
    ?stopOnEntry:Bool,
    ?debugOutput:String,
    ?timeout:Int,
    ?compileDir:String,
    ?classpaths:Array<String>,
    ?host:String,
    ?launched:Bool,
}

typedef LaunchSettings = {
    > Settings,
    ?compile: {
        ?args:Array<String>
    },
    run: {
        ?cwd:String,
        args:Array<String>
    },
    ?port:Int,
}

typedef AttachSettings = {
    > Settings,
    ?port:Int,
}