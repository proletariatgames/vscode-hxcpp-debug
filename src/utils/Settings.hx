package utils;

typedef Settings = {
    ?logLevel:Int,
    ?stopOnEntry:Bool,
    ?debugOutput:String,
}

typedef LaunchSettings = {
    > Settings,
    ?compile: {
        ?cwd:String,
        ?args:Array<String>
    },
    run: {
        ?cwd:String,
        args:Array<String>
    },
    ?port:Int,
}