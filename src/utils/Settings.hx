package utils;

typedef Settings = {
    ?logLevel:Int,
    ?stopOnEntry:Bool,
    ?debugOutput:String,
}

typedef LaunchSettings = {
    > Settings,
    ?compile: {
        ?path:String,
        command:String
    },
    ?runPath:String,
    runCommand:String
}