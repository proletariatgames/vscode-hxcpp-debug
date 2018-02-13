package vscode.debugger;

@:enum abstract TypeEnum(String) {
  var Request = "request";
  var Event = "event";
  var Response = "response";
}

@:enum abstract EventEnum(String) {
  var Initialized = "initialized";
  var Stopped = "stopped";
  var Continued = "continued";
  var Exited = "exited";
  var Terminated = "terminated";
  var Thread = "thread";
  var Output = "output";
  var Breakpoint = "breakpoint";
  var Module = "module";
  var LoadedSource = "loadedSource";
  var Process = "process";
}

@:enum abstract RequestCommandEnum(String) {
  var RunInTerminal = "runInTerminal";
  var Initialize = "initialize";
  var ConfigurationDone = "configurationDone";
  var Launch = "launch";
  var Attach = "attach";
  var Restart = "restart";
  var Disconnect = "disconnect";
  var SetBreakpoints = "setBreakpoints";
  var SetFunctionBreakpoints = "setFunctionBreakpoints";
  var SetExceptionBreakpoints = "setExceptionBreakpoints";
  var Continue = "continue";
  var Next = "next";
  var StepIn = "stepIn";
  var StepOut = "stepOut";
  var StepBack = "stepBack";
  var ReverseContinue = "reverseContinue";
  var RestartFrame = "restartFrame";
  var Goto = "goto";
  var Pause = "pause";
  var StackTrace = "stackTrace";
  var Scopes = "scopes";
  var Variables = "variables";
  var SetVariable = "setVariable";
  var Source = "source";
  var Threads = "threads";
  var Modules = "modules";
  var LoadedSources = "loadedSources";
  var Evaluate = "evaluate";
  var StepInTargets = "stepInTargets";
  var GotoTargets = "gotoTargets";
  var Completions = "completions";
  var ExceptionInfo = "exceptionInfo";
}

@:enum abstract ReasonEnum(String) {
  var New = "new";
  var Changed = "changed";
  var Removed = "removed";
}

@:enum abstract CategoryEnum(String) {
  var Console = "console";
  var Stdout = "stdout";
  var Stderr = "stderr";
  var Telemetry = "telemetry";
}

@:enum abstract StartMethodEnum(String) {
  var Launch = "launch";
  var Attach = "attach";
  var AttachForSuspendedLaunch = "attachForSuspendedLaunch";
}

@:enum abstract KindEnum(String) {
  var Property = "property";
  var Method = "method";
  var Class = "class";
  var Data = "data";
  var Event = "event";
  var BaseClass = "baseClass";
  var InnerClass = "innerClass";
  var Interface = "interface";
  var MostDerivedClass = "mostDerivedClass";
  var Virtual = "virtual";
}

@:enum abstract PathFormatEnum(String) {
  var Path = "path";
  var Uri = "uri";
}

@:enum abstract FilterEnum(String) {
  var Indexed = "indexed";
  var Named = "named";
}

@:enum abstract ContextEnum(String) {
  var Watch = "watch";
  var Repl = "repl";
  var Hover = "hover";
}

@:enum abstract PresentationHintEnum(String) {
  var Normal = "normal";
  var Label = "label";
  var Subtle = "subtle";
}

@:enum abstract VisibilityEnum(String) {
  var Public = "public";
  var Private = "private";
  var Protected = "protected";
  var Internal = "internal";
  var Final = "final";
}

/**
  Base class of requests, responses, and events.
**/
typedef ProtocolMessage = {
  /**
    Sequence number.
  **/
  var seq : Int;
  /**
    Message type.
  **/
  var type : TypeEnum;
}

/**
  A client or server-initiated request.
**/
typedef Request = {
  > ProtocolMessage,
  var type : TypeEnum;
  /**
    The command to execute.
  **/
  var command : RequestCommandEnum;
}

/**
  Server-initiated event.
**/
typedef Event = {
  > ProtocolMessage,
  var type : TypeEnum;
  /**
    Type of event.
  **/
  var event : EventEnum;
}

/**
  Response to a request.
**/
typedef Response = {
  > ProtocolMessage,
  var type : TypeEnum;
  /**
    Sequence number of the corresponding request.
  **/
  var request_seq : Int;
  /**
    Outcome of the request.
  **/
  var success : Bool;
  /**
    The command requested.
  **/
  var command : String;
  /**
    Contains error message if success == false.
  **/
  @:optional var message : String;
}

@:enum abstract StoppedReason(String) {
  var Step = 'step';
  var Breakpoint = 'breakpoint';
  var Exception = 'exception';
  var Pause = 'pause';
  var Entry = 'entry';
}

/**
  Event message for 'initialized' event type.
  This event indicates that the debug adapter is ready to accept configuration requests (e.g. SetBreakpointsRequest, SetExceptionBreakpointsRequest).
  A debug adapter is expected to send this event when it is ready to accept configuration requests (but not before the InitializeRequest has finished).
  The sequence of events/requests is as follows:
  - adapters sends InitializedEvent (after the InitializeRequest has returned)
  - frontend sends zero or more SetBreakpointsRequest
  - frontend sends one SetFunctionBreakpointsRequest
  - frontend sends a SetExceptionBreakpointsRequest if one or more exceptionBreakpointFilters have been defined (or if supportsConfigurationDoneRequest is not defined or false)
  - frontend sends other future configuration requests
  - frontend sends one ConfigurationDoneRequest to indicate the end of the configuration
**/
typedef InitializedEvent = {
  > Event,
  var event : EventEnum;
}

/**
  Event message for 'stopped' event type.
  The event indicates that the execution of the debuggee has stopped due to some condition.
  This can be caused by a break point previously set, a stepping action has completed, by executing a debugger statement etc.
**/
typedef StoppedEvent = {
  > Event,
  var event : EventEnum;
  var body : {
    /**
      The reason for the event.
      For backward compatibility this string is shown in the UI if the 'description' attribute is missing (but it must not be translated).
    **/
    var reason : StoppedReason;
    /**
      The full reason for the event, e.g. 'Paused on exception'. This string is shown in the UI as is.
    **/
    @:optional var description : String;
    /**
      The thread which was stopped.
    **/
    @:optional var threadId : Int;
    /**
      Additional information. E.g. if reason is 'exception', text contains the exception name. This string is shown in the UI.
    **/
    @:optional var text : String;
    /**
      If allThreadsStopped is true, a debug adapter can announce that all threads have stopped.
      *  The client should use this information to enable that all threads can be expanded to access their stacktraces.
      *  If the attribute is missing or false, only the thread with the given threadId can be expanded.
    **/
    @:optional var allThreadsStopped : Bool;
  }

;
}

/**
  Event message for 'continued' event type.
  The event indicates that the execution of the debuggee has continued.
  Please note: a debug adapter is not expected to send this event in response to a request that implies that execution continues, e.g. 'launch' or 'continue'.
  It is only necessary to send a ContinuedEvent if there was no previous request that implied this.
**/
typedef ContinuedEvent = {
  > Event,
  var event : EventEnum;
  var body : {
    /**
      The thread which was continued.
    **/
    var threadId : Int;
    /**
      If allThreadsContinued is true, a debug adapter can announce that all threads have continued.
    **/
    @:optional var allThreadsContinued : Bool;
  }

;
}

/**
  Event message for 'exited' event type.
  The event indicates that the debuggee has exited.
**/
typedef ExitedEvent = {
  > Event,
  var event : EventEnum;
  var body : {
    /**
      The exit code returned from the debuggee.
    **/
    var exitCode : Int;
  }

;
}

/**
  Event message for 'terminated' event types.
  The event indicates that debugging of the debuggee has terminated.
**/
typedef TerminatedEvent = {
  > Event,
  var event : EventEnum;
  @:optional var body : {
    /**
      A debug adapter may set 'restart' to true (or to an arbitrary object) to request that the front end restarts the session.
      The value is not interpreted by the client and passed unmodified as an attribute '__restart' to the launchRequest.
    **/
    @:optional var restart : Dynamic;
  }

;
}

/**
  Event message for 'thread' event type.
  The event indicates that a thread has started or exited.
**/
typedef ThreadEvent = {
  > Event,
  var event : EventEnum;
  var body : {
    /**
      The reason for the event.
    **/
    var reason : ReasonEnum;
    /**
      The identifier of the thread.
    **/
    var threadId : Int;
  }

;
}

/**
  Event message for 'output' event type.
  The event indicates that the target has produced some output.
**/
typedef OutputEvent = {
  > Event,
  var event : EventEnum;
  var body : {
    /**
      The output category. If not specified, 'console' is assumed.
    **/
    @:optional var category : CategoryEnum;
    /**
      The output to report.
    **/
    var output : String;
    /**
      If an attribute 'variablesReference' exists and its value is > 0, the output contains objects which can be retrieved by passing variablesReference to the VariablesRequest.
    **/
    @:optional var variablesReference : Float;
    /**
      An optional source location where the output was produced.
    **/
    @:optional var source : Source;
    /**
      An optional source location line where the output was produced.
    **/
    @:optional var line : Int;
    /**
      An optional source location column where the output was produced.
    **/
    @:optional var column : Int;
    /**
      Optional data to report. For the 'telemetry' category the data will be sent to telemetry, for the other categories the data is shown in JSON format.
    **/
    @:optional var data : Dynamic;
  }

;
}

/**
  Event message for 'breakpoint' event type.
  The event indicates that some information about a breakpoint has changed.
**/
typedef BreakpointEvent = {
  > Event,
  var event : EventEnum;
  var body : {
    /**
      The reason for the event.
    **/
    var reason : ReasonEnum;
    /**
      The breakpoint.
    **/
    var breakpoint : Breakpoint;
  }

;
}

/**
  Event message for 'module' event type.
  The event indicates that some information about a module has changed.
**/
typedef ModuleEvent = {
  > Event,
  var event : EventEnum;
  var body : {
    /**
      The reason for the event.
    **/
    var reason : ReasonEnum;
    /**
      The new, changed, or removed module. In case of 'removed' only the module id is used.
    **/
    var module : Module;
  }

;
}

/**
  Event message for 'loadedSource' event type.
  The event indicates that some source has been added, changed, or removed from the set of all loaded sources.
**/
typedef LoadedSourceEvent = {
  > Event,
  var event : EventEnum;
  var body : {
    /**
      The reason for the event.
    **/
    var reason : ReasonEnum;
    /**
      The new, changed, or removed source.
    **/
    var source : Source;
  }

;
}

/**
  Event message for 'process' event type.
  The event indicates that the debugger has begun debugging a new process. Either one that it has launched, or one that it has attached to.
**/
typedef ProcessEvent = {
  > Event,
  var event : EventEnum;
  var body : {
    /**
      The logical name of the process. This is usually the full path to process's executable file. Example: /home/example/myproj/program.js.
    **/
    var name : String;
    /**
      The system process id of the debugged process. This property will be missing for non-system processes.
    **/
    @:optional var systemProcessId : Int;
    /**
      If true, the process is running on the same computer as the debug adapter.
    **/
    @:optional var isLocalProcess : Bool;
    /**
      Describes how the debug engine started debugging this process.
    **/
    @:optional var startMethod : StartMethodEnum;
  }

;
}

/**
  runInTerminal request; value of command field is 'runInTerminal'.
  With this request a debug adapter can run a command in a terminal.
**/
typedef RunInTerminalRequest = {
  > Request,
  var command : RequestCommandEnum;
  var arguments : RunInTerminalRequestArguments;
}

/**
  Arguments for 'runInTerminal' request.
**/
typedef RunInTerminalRequestArguments = {
  /**
    What kind of terminal to launch.
  **/
  @:optional var kind : KindEnum;
  /**
    Optional title of the terminal.
  **/
  @:optional var title : String;
  /**
    Working directory of the command.
  **/
  var cwd : String;
  /**
    List of arguments. The first argument is the command to run.
  **/
  var args : Array<String>;
  /**
    Environment key-value pairs that are added to or removed from the default environment.
  **/
  @:optional var env : {
  }

;
}

/**
  Response to Initialize request.
**/
typedef RunInTerminalResponse = {
  > Response,
  var body : {
    /**
      The process ID.
    **/
    @:optional var processId : Float;
  }

;
}

/**
  On error that is whenever 'success' is false, the body can provide more details.
**/
typedef ErrorResponse = {
  > Response,
  var body : {
    /**
      An optional, structured error message.
    **/
    @:optional var error : Message;
  }

;
}

/**
  Initialize request; value of command field is 'initialize'.
**/
typedef InitializeRequest = {
  > Request,
  var command : RequestCommandEnum;
  var arguments : InitializeRequestArguments;
}

/**
  Arguments for 'initialize' request.
**/
typedef InitializeRequestArguments = {
  /**
    The ID of the (frontend) client using this adapter.
  **/
  @:optional var clientID : String;
  /**
    The ID of the debug adapter.
  **/
  var adapterID : String;
  /**
    The ISO-639 locale of the (frontend) client using this adapter, e.g. en-US or de-CH.
  **/
  @:optional var locale : String;
  /**
    If true all line numbers are 1-based (default).
  **/
  @:optional var linesStartAt1 : Bool;
  /**
    If true all column numbers are 1-based (default).
  **/
  @:optional var columnsStartAt1 : Bool;
  /**
    Determines in what format paths are specified. The default is 'path', which is the native format.
  **/
  @:optional var pathFormat : PathFormatEnum;
  /**
    Client supports the optional type attribute for variables.
  **/
  @:optional var supportsVariableType : Bool;
  /**
    Client supports the paging of variables.
  **/
  @:optional var supportsVariablePaging : Bool;
  /**
    Client supports the runInTerminal request.
  **/
  @:optional var supportsRunInTerminalRequest : Bool;
}

/**
  Response to 'initialize' request.
**/
typedef InitializeResponse = {
  > Response,
}

/**
  ConfigurationDone request; value of command field is 'configurationDone'.
  The client of the debug protocol must send this request at the end of the sequence of configuration requests (which was started by the InitializedEvent).
**/
typedef ConfigurationDoneRequest = {
  > Request,
  var command : RequestCommandEnum;
  @:optional var arguments : ConfigurationDoneArguments;
}

/**
  Arguments for 'configurationDone' request.
  The configurationDone request has no standardized attributes.
**/
typedef ConfigurationDoneArguments = {
}

/**
  Response to 'configurationDone' request. This is just an acknowledgement, so no body field is required.
**/
typedef ConfigurationDoneResponse = {
  > Response,
}

/**
  Launch request; value of command field is 'launch'.
**/
typedef LaunchRequest = {
  > Request,
  var command : RequestCommandEnum;
  var arguments : LaunchRequestArguments;
}

/**
  Arguments for 'launch' request.
**/
typedef LaunchRequestArguments = {
  /**
    If noDebug is true the launch request should launch the program without enabling debugging.
  **/
  @:optional var noDebug : Bool;
}

/**
  Response to 'launch' request. This is just an acknowledgement, so no body field is required.
**/
typedef LaunchResponse = {
  > Response,
}

/**
  Attach request; value of command field is 'attach'.
**/
typedef AttachRequest = {
  > Request,
  var command : RequestCommandEnum;
  var arguments : AttachRequestArguments;
}

/**
  Arguments for 'attach' request.
  The attach request has no standardized attributes.
**/
typedef AttachRequestArguments = {
}

/**
  Response to 'attach' request. This is just an acknowledgement, so no body field is required.
**/
typedef AttachResponse = {
  > Response,
}

/**
  Restart request; value of command field is 'restart'.
  Restarts a debug session. If the capability 'supportsRestartRequest' is missing or has the value false,
  the client will implement 'restart' by terminating the debug adapter first and then launching it anew.
  A debug adapter can override this default behaviour by implementing a restart request
  and setting the capability 'supportsRestartRequest' to true.
**/
typedef RestartRequest = {
  > Request,
  var command : RequestCommandEnum;
  @:optional var arguments : RestartArguments;
}

/**
  Arguments for 'restart' request.
  The restart request has no standardized attributes.
**/
typedef RestartArguments = {
}

/**
  Response to 'restart' request. This is just an acknowledgement, so no body field is required.
**/
typedef RestartResponse = {
  > Response,
}

/**
  Disconnect request; value of command field is 'disconnect'.
**/
typedef DisconnectRequest = {
  > Request,
  var command : RequestCommandEnum;
  @:optional var arguments : DisconnectArguments;
}

/**
  Arguments for 'disconnect' request.
**/
typedef DisconnectArguments = {
  /**
    Indicates whether the debuggee should be terminated when the debugger is disconnected.
    If unspecified, the debug adapter is free to do whatever it thinks is best.
    A client can only rely on this attribute being properly honored if a debug adapter returns true for the 'supportTerminateDebuggee' capability.
  **/
  @:optional var terminateDebuggee : Bool;
}

/**
  Response to 'disconnect' request. This is just an acknowledgement, so no body field is required.
**/
typedef DisconnectResponse = {
  > Response,
}

/**
  SetBreakpoints request; value of command field is 'setBreakpoints'.
  Sets multiple breakpoints for a single source and clears all previous breakpoints in that source.
  To clear all breakpoint for a source, specify an empty array.
  When a breakpoint is hit, a StoppedEvent (event type 'breakpoint') is generated.
**/
typedef SetBreakpointsRequest = {
  > Request,
  var command : RequestCommandEnum;
  var arguments : SetBreakpointsArguments;
}

/**
  Arguments for 'setBreakpoints' request.
**/
typedef SetBreakpointsArguments = {
  /**
    The source location of the breakpoints; either source.path or source.reference must be specified.
  **/
  var source : Source;
  /**
    The code locations of the breakpoints.
  **/
  @:optional var breakpoints : Array<SourceBreakpoint>;
  /**
    Deprecated: The code locations of the breakpoints.
  **/
  @:optional var lines : Array<Int>;
  /**
    A value of true indicates that the underlying source has been modified which results in new breakpoint locations.
  **/
  @:optional var sourceModified : Bool;
}

/**
  Response to 'setBreakpoints' request.
  Returned is information about each breakpoint created by this request.
  This includes the actual code location and whether the breakpoint could be verified.
  The breakpoints returned are in the same order as the elements of the 'breakpoints'
  (or the deprecated 'lines') in the SetBreakpointsArguments.
**/
typedef SetBreakpointsResponse = {
  > Response,
  var body : {
    /**
      Information about the breakpoints. The array elements are in the same order as the elements of the 'breakpoints' (or the deprecated 'lines') in the SetBreakpointsArguments.
    **/
    var breakpoints : Array<Breakpoint>;
  }

;
}

/**
  SetFunctionBreakpoints request; value of command field is 'setFunctionBreakpoints'.
  Sets multiple function breakpoints and clears all previous function breakpoints.
  To clear all function breakpoint, specify an empty array.
  When a function breakpoint is hit, a StoppedEvent (event type 'function breakpoint') is generated.
**/
typedef SetFunctionBreakpointsRequest = {
  > Request,
  var command : RequestCommandEnum;
  var arguments : SetFunctionBreakpointsArguments;
}

/**
  Arguments for 'setFunctionBreakpoints' request.
**/
typedef SetFunctionBreakpointsArguments = {
  /**
    The function names of the breakpoints.
  **/
  var breakpoints : Array<FunctionBreakpoint>;
}

/**
  Response to 'setFunctionBreakpoints' request.
  Returned is information about each breakpoint created by this request.
**/
typedef SetFunctionBreakpointsResponse = {
  > Response,
  var body : {
    /**
      Information about the breakpoints. The array elements correspond to the elements of the 'breakpoints' array.
    **/
    var breakpoints : Array<Breakpoint>;
  }

;
}

/**
  SetExceptionBreakpoints request; value of command field is 'setExceptionBreakpoints'.
  The request configures the debuggers response to thrown exceptions. If an exception is configured to break, a StoppedEvent is fired (event type 'exception').
**/
typedef SetExceptionBreakpointsRequest = {
  > Request,
  var command : RequestCommandEnum;
  var arguments : SetExceptionBreakpointsArguments;
}

/**
  Arguments for 'setExceptionBreakpoints' request.
**/
typedef SetExceptionBreakpointsArguments = {
  /**
    IDs of checked exception options. The set of IDs is returned via the 'exceptionBreakpointFilters' capability.
  **/
  var filters : Array<String>;
  /**
    Configuration options for selected exceptions.
  **/
  @:optional var exceptionOptions : Array<ExceptionOptions>;
}

/**
  Response to 'setExceptionBreakpoints' request. This is just an acknowledgement, so no body field is required.
**/
typedef SetExceptionBreakpointsResponse = {
  > Response,
}

/**
  Continue request; value of command field is 'continue'.
  The request starts the debuggee to run again.
**/
typedef ContinueRequest = {
  > Request,
  var command : RequestCommandEnum;
  var arguments : ContinueArguments;
}

/**
  Arguments for 'continue' request.
**/
typedef ContinueArguments = {
  /**
    Continue execution for the specified thread (if possible). If the backend cannot continue on a single thread but will continue on all threads, it should set the allThreadsContinued attribute in the response to true.
  **/
  var threadId : Int;
}

/**
  Response to 'continue' request.
**/
typedef ContinueResponse = {
  > Response,
  var body : {
    /**
      If true, the continue request has ignored the specified thread and continued all threads instead. If this attribute is missing a value of 'true' is assumed for backward compatibility.
    **/
    @:optional var allThreadsContinued : Bool;
  }

;
}

/**
  Next request; value of command field is 'next'.
  The request starts the debuggee to run again for one step.
  The debug adapter first sends the NextResponse and then a StoppedEvent (event type 'step') after the step has completed.
**/
typedef NextRequest = {
  > Request,
  var command : RequestCommandEnum;
  var arguments : NextArguments;
}

/**
  Arguments for 'next' request.
**/
typedef NextArguments = {
  /**
    Execute 'next' for this thread.
  **/
  var threadId : Int;
}

/**
  Response to 'next' request. This is just an acknowledgement, so no body field is required.
**/
typedef NextResponse = {
  > Response,
}

/**
  StepIn request; value of command field is 'stepIn'.
  The request starts the debuggee to step into a function/method if possible.
  If it cannot step into a target, 'stepIn' behaves like 'next'.
  The debug adapter first sends the StepInResponse and then a StoppedEvent (event type 'step') after the step has completed.
  If there are multiple function/method calls (or other targets) on the source line,
  the optional argument 'targetId' can be used to control into which target the 'stepIn' should occur.
  The list of possible targets for a given source line can be retrieved via the 'stepInTargets' request.
**/
typedef StepInRequest = {
  > Request,
  var command : RequestCommandEnum;
  var arguments : StepInArguments;
}

/**
  Arguments for 'stepIn' request.
**/
typedef StepInArguments = {
  /**
    Execute 'stepIn' for this thread.
  **/
  var threadId : Int;
  /**
    Optional id of the target to step into.
  **/
  @:optional var targetId : Int;
}

/**
  Response to 'stepIn' request. This is just an acknowledgement, so no body field is required.
**/
typedef StepInResponse = {
  > Response,
}

/**
  StepOut request; value of command field is 'stepOut'.
  The request starts the debuggee to run again for one step.
  The debug adapter first sends the StepOutResponse and then a StoppedEvent (event type 'step') after the step has completed.
**/
typedef StepOutRequest = {
  > Request,
  var command : RequestCommandEnum;
  var arguments : StepOutArguments;
}

/**
  Arguments for 'stepOut' request.
**/
typedef StepOutArguments = {
  /**
    Execute 'stepOut' for this thread.
  **/
  var threadId : Int;
}

/**
  Response to 'stepOut' request. This is just an acknowledgement, so no body field is required.
**/
typedef StepOutResponse = {
  > Response,
}

/**
  StepBack request; value of command field is 'stepBack'.
  The request starts the debuggee to run one step backwards.
  The debug adapter first sends the StepBackResponse and then a StoppedEvent (event type 'step') after the step has completed. Clients should only call this request if the capability supportsStepBack is true.
**/
typedef StepBackRequest = {
  > Request,
  var command : RequestCommandEnum;
  var arguments : StepBackArguments;
}

/**
  Arguments for 'stepBack' request.
**/
typedef StepBackArguments = {
  /**
    Exceute 'stepBack' for this thread.
  **/
  var threadId : Int;
}

/**
  Response to 'stepBack' request. This is just an acknowledgement, so no body field is required.
**/
typedef StepBackResponse = {
  > Response,
}

/**
  ReverseContinue request; value of command field is 'reverseContinue'.
  The request starts the debuggee to run backward. Clients should only call this request if the capability supportsStepBack is true.
**/
typedef ReverseContinueRequest = {
  > Request,
  var command : RequestCommandEnum;
  var arguments : ReverseContinueArguments;
}

/**
  Arguments for 'reverseContinue' request.
**/
typedef ReverseContinueArguments = {
  /**
    Exceute 'reverseContinue' for this thread.
  **/
  var threadId : Int;
}

/**
  Response to 'reverseContinue' request. This is just an acknowledgement, so no body field is required.
**/
typedef ReverseContinueResponse = {
  > Response,
}

/**
  RestartFrame request; value of command field is 'restartFrame'.
  The request restarts execution of the specified stackframe.
  The debug adapter first sends the RestartFrameResponse and then a StoppedEvent (event type 'restart') after the restart has completed.
**/
typedef RestartFrameRequest = {
  > Request,
  var command : RequestCommandEnum;
  var arguments : RestartFrameArguments;
}

/**
  Arguments for 'restartFrame' request.
**/
typedef RestartFrameArguments = {
  /**
    Restart this stackframe.
  **/
  var frameId : Int;
}

/**
  Response to 'restartFrame' request. This is just an acknowledgement, so no body field is required.
**/
typedef RestartFrameResponse = {
  > Response,
}

/**
  Goto request; value of command field is 'goto'.
  The request sets the location where the debuggee will continue to run.
  This makes it possible to skip the execution of code or to executed code again.
  The code between the current location and the goto target is not executed but skipped.
  The debug adapter first sends the GotoResponse and then a StoppedEvent (event type 'goto').
**/
typedef GotoRequest = {
  > Request,
  var command : RequestCommandEnum;
  var arguments : GotoArguments;
}

/**
  Arguments for 'goto' request.
**/
typedef GotoArguments = {
  /**
    Set the goto target for this thread.
  **/
  var threadId : Int;
  /**
    The location where the debuggee will continue to run.
  **/
  var targetId : Int;
}

/**
  Response to 'goto' request. This is just an acknowledgement, so no body field is required.
**/
typedef GotoResponse = {
  > Response,
}

/**
  Pause request; value of command field is 'pause'.
  The request suspenses the debuggee.
  The debug adapter first sends the PauseResponse and then a StoppedEvent (event type 'pause') after the thread has been paused successfully.
**/
typedef PauseRequest = {
  > Request,
  var command : RequestCommandEnum;
  var arguments : PauseArguments;
}

/**
  Arguments for 'pause' request.
**/
typedef PauseArguments = {
  /**
    Pause execution for this thread.
  **/
  var threadId : Int;
}

/**
  Response to 'pause' request. This is just an acknowledgement, so no body field is required.
**/
typedef PauseResponse = {
  > Response,
}

/**
  StackTrace request; value of command field is 'stackTrace'. The request returns a stacktrace from the current execution state.
**/
typedef StackTraceRequest = {
  > Request,
  var command : RequestCommandEnum;
  var arguments : StackTraceArguments;
}

/**
  Arguments for 'stackTrace' request.
**/
typedef StackTraceArguments = {
  /**
    Retrieve the stacktrace for this thread.
  **/
  var threadId : Int;
  /**
    The index of the first frame to return; if omitted frames start at 0.
  **/
  @:optional var startFrame : Int;
  /**
    The maximum number of frames to return. If levels is not specified or 0, all frames are returned.
  **/
  @:optional var levels : Int;
  /**
    Specifies details on how to format the stack frames.
  **/
  @:optional var format : StackFrameFormat;
}

/**
  Response to 'stackTrace' request.
**/
typedef StackTraceResponse = {
  > Response,
  var body : {
    /**
      The frames of the stackframe. If the array has length zero, there are no stackframes available.
      This means that there is no location information available.
    **/
    var stackFrames : Array<StackFrame>;
    /**
      The total number of frames available.
    **/
    @:optional var totalFrames : Int;
  }

;
}

/**
  Scopes request; value of command field is 'scopes'.
  The request returns the variable scopes for a given stackframe ID.
**/
typedef ScopesRequest = {
  > Request,
  var command : RequestCommandEnum;
  var arguments : ScopesArguments;
}

/**
  Arguments for 'scopes' request.
**/
typedef ScopesArguments = {
  /**
    Retrieve the scopes for this stackframe.
  **/
  var frameId : Int;
}

/**
  Response to 'scopes' request.
**/
typedef ScopesResponse = {
  > Response,
  var body : {
    /**
      The scopes of the stackframe. If the array has length zero, there are no scopes available.
    **/
    var scopes : Array<Scope>;
  }

;
}

/**
  Variables request; value of command field is 'variables'.
  Retrieves all child variables for the given variable reference.
  An optional filter can be used to limit the fetched children to either named or indexed children.
**/
typedef VariablesRequest = {
  > Request,
  var command : RequestCommandEnum;
  var arguments : VariablesArguments;
}

/**
  Arguments for 'variables' request.
**/
typedef VariablesArguments = {
  /**
    The Variable reference.
  **/
  var variablesReference : Int;
  /**
    Optional filter to limit the child variables to either named or indexed. If ommited, both types are fetched.
  **/
  @:optional var filter : FilterEnum;
  /**
    The index of the first variable to return; if omitted children start at 0.
  **/
  @:optional var start : Int;
  /**
    The number of variables to return. If count is missing or 0, all variables are returned.
  **/
  @:optional var count : Int;
  /**
    Specifies details on how to format the Variable values.
  **/
  @:optional var format : ValueFormat;
}

/**
  Response to 'variables' request.
**/
typedef VariablesResponse = {
  > Response,
  var body : {
    /**
      All (or a range) of variables for the given variable reference.
    **/
    var variables : Array<Variable>;
  }

;
}

/**
  setVariable request; value of command field is 'setVariable'.
  Set the variable with the given name in the variable container to a new value.
**/
typedef SetVariableRequest = {
  > Request,
  var command : RequestCommandEnum;
  var arguments : SetVariableArguments;
}

/**
  Arguments for 'setVariable' request.
**/
typedef SetVariableArguments = {
  /**
    The reference of the variable container.
  **/
  var variablesReference : Int;
  /**
    The name of the variable.
  **/
  var name : String;
  /**
    The value of the variable.
  **/
  var value : String;
  /**
    Specifies details on how to format the response value.
  **/
  @:optional var format : ValueFormat;
}

/**
  Response to 'setVariable' request.
**/
typedef SetVariableResponse = {
  > Response,
  var body : {
    /**
      The new value of the variable.
    **/
    var value : String;
    /**
      The type of the new value. Typically shown in the UI when hovering over the value.
    **/
    @:optional var type : TypeEnum;
    /**
      If variablesReference is > 0, the new value is structured and its children can be retrieved by passing variablesReference to the VariablesRequest.
    **/
    @:optional var variablesReference : Float;
    /**
      The number of named child variables.
      The client can use this optional information to present the variables in a paged UI and fetch them in chunks.
    **/
    @:optional var namedVariables : Float;
    /**
      The number of indexed child variables.
      The client can use this optional information to present the variables in a paged UI and fetch them in chunks.
    **/
    @:optional var indexedVariables : Float;
  }

;
}

/**
  Source request; value of command field is 'source'.
  The request retrieves the source code for a given source reference.
**/
typedef SourceRequest = {
  > Request,
  var command : RequestCommandEnum;
  var arguments : SourceArguments;
}

/**
  Arguments for 'source' request.
**/
typedef SourceArguments = {
  /**
    Specifies the source content to load. Either source.path or source.sourceReference must be specified.
  **/
  @:optional var source : Source;
  /**
    The reference to the source. This is the same as source.sourceReference. This is provided for backward compatibility since old backends do not understand the 'source' attribute.
  **/
  var sourceReference : Int;
}

/**
  Response to 'source' request.
**/
typedef SourceResponse = {
  > Response,
  var body : {
    /**
      Content of the source reference.
    **/
    var content : String;
    /**
      Optional content type (mime type) of the source.
    **/
    @:optional var mimeType : String;
  }

;
}

/**
  Thread request; value of command field is 'threads'.
  The request retrieves a list of all threads.
**/
typedef ThreadsRequest = {
  > Request,
  var command : RequestCommandEnum;
}

/**
  Response to 'threads' request.
**/
typedef ThreadsResponse = {
  > Response,
  var body : {
    /**
      All threads.
    **/
    var threads : Array<Thread>;
  }

;
}

/**
  Modules can be retrieved from the debug adapter with the ModulesRequest which can either return all modules or a range of modules to support paging.
**/
typedef ModulesRequest = {
  > Request,
  var command : RequestCommandEnum;
  var arguments : ModulesArguments;
}

/**
  Arguments for 'modules' request.
**/
typedef ModulesArguments = {
  /**
    The index of the first module to return; if omitted modules start at 0.
  **/
  @:optional var startModule : Int;
  /**
    The number of modules to return. If moduleCount is not specified or 0, all modules are returned.
  **/
  @:optional var moduleCount : Int;
}

/**
  Response to 'modules' request.
**/
typedef ModulesResponse = {
  > Response,
  var body : {
    /**
      All modules or range of modules.
    **/
    var modules : Array<Module>;
    /**
      The total number of modules available.
    **/
    @:optional var totalModules : Int;
  }

;
}

/**
  Retrieves the set of all sources currently loaded by the debugged process.
**/
typedef LoadedSourcesRequest = {
  > Request,
  var command : RequestCommandEnum;
  @:optional var arguments : LoadedSourcesArguments;
}

/**
  Arguments for 'loadedSources' request.
  The 'loadedSources' request has no standardized arguments.
**/
typedef LoadedSourcesArguments = {
}

/**
  Response to 'loadedSources' request.
**/
typedef LoadedSourcesResponse = {
  > Response,
  var body : {
    /**
      Set of loaded sources.
    **/
    var sources : Array<Source>;
  }

;
}

/**
  Evaluate request; value of command field is 'evaluate'.
  Evaluates the given expression in the context of the top most stack frame.
  The expression has access to any variables and arguments that are in scope.
**/
typedef EvaluateRequest = {
  > Request,
  var command : RequestCommandEnum;
  var arguments : EvaluateArguments;
}

/**
  Arguments for 'evaluate' request.
**/
typedef EvaluateArguments = {
  /**
    The expression to evaluate.
  **/
  var expression : String;
  /**
    Evaluate the expression in the scope of this stack frame. If not specified, the expression is evaluated in the global scope.
  **/
  @:optional var frameId : Int;
  /**
    The context in which the evaluate request is run.
  **/
  @:optional var context : ContextEnum;
  /**
    Specifies details on how to format the Evaluate result.
  **/
  @:optional var format : ValueFormat;
}

/**
  Response to 'evaluate' request.
**/
typedef EvaluateResponse = {
  > Response,
  var body : {
    /**
      The result of the evaluate request.
    **/
    var result : String;
    /**
      The optional type of the evaluate result.
    **/
    @:optional var type : TypeEnum;
    /**
      Properties of a evaluate result that can be used to determine how to render the result in the UI.
    **/
    @:optional var presentationHint : VariablePresentationHint;
    /**
      If variablesReference is > 0, the evaluate result is structured and its children can be retrieved by passing variablesReference to the VariablesRequest.
    **/
    var variablesReference : Float;
    /**
      The number of named child variables.
      The client can use this optional information to present the variables in a paged UI and fetch them in chunks.
    **/
    @:optional var namedVariables : Float;
    /**
      The number of indexed child variables.
      The client can use this optional information to present the variables in a paged UI and fetch them in chunks.
    **/
    @:optional var indexedVariables : Float;
  }

;
}

/**
  StepInTargets request; value of command field is 'stepInTargets'.
  This request retrieves the possible stepIn targets for the specified stack frame.
  These targets can be used in the 'stepIn' request.
  The StepInTargets may only be called if the 'supportsStepInTargetsRequest' capability exists and is true.
**/
typedef StepInTargetsRequest = {
  > Request,
  var command : RequestCommandEnum;
  var arguments : StepInTargetsArguments;
}

/**
  Arguments for 'stepInTargets' request.
**/
typedef StepInTargetsArguments = {
  /**
    The stack frame for which to retrieve the possible stepIn targets.
  **/
  var frameId : Int;
}

/**
  Response to 'stepInTargets' request.
**/
typedef StepInTargetsResponse = {
  > Response,
  var body : {
    /**
      The possible stepIn targets of the specified source location.
    **/
    var targets : Array<StepInTarget>;
  }

;
}

/**
  GotoTargets request; value of command field is 'gotoTargets'.
  This request retrieves the possible goto targets for the specified source location.
  These targets can be used in the 'goto' request.
  The GotoTargets request may only be called if the 'supportsGotoTargetsRequest' capability exists and is true.
**/
typedef GotoTargetsRequest = {
  > Request,
  var command : RequestCommandEnum;
  var arguments : GotoTargetsArguments;
}

/**
  Arguments for 'gotoTargets' request.
**/
typedef GotoTargetsArguments = {
  /**
    The source location for which the goto targets are determined.
  **/
  var source : Source;
  /**
    The line location for which the goto targets are determined.
  **/
  var line : Int;
  /**
    An optional column location for which the goto targets are determined.
  **/
  @:optional var column : Int;
}

/**
  Response to 'gotoTargets' request.
**/
typedef GotoTargetsResponse = {
  > Response,
  var body : {
    /**
      The possible goto targets of the specified location.
    **/
    var targets : Array<GotoTarget>;
  }

;
}

/**
  CompletionsRequest request; value of command field is 'completions'.
  Returns a list of possible completions for a given caret position and text.
  The CompletionsRequest may only be called if the 'supportsCompletionsRequest' capability exists and is true.
**/
typedef CompletionsRequest = {
  > Request,
  var command : RequestCommandEnum;
  var arguments : CompletionsArguments;
}

/**
  Arguments for 'completions' request.
**/
typedef CompletionsArguments = {
  /**
    Returns completions in the scope of this stack frame. If not specified, the completions are returned for the global scope.
  **/
  @:optional var frameId : Int;
  /**
    One or more source lines. Typically this is the text a user has typed into the debug console before he asked for completion.
  **/
  var text : String;
  /**
    The character position for which to determine the completion proposals.
  **/
  var column : Int;
  /**
    An optional line for which to determine the completion proposals. If missing the first line of the text is assumed.
  **/
  @:optional var line : Int;
}

/**
  Response to 'completions' request.
**/
typedef CompletionsResponse = {
  > Response,
  var body : {
    /**
      The possible completions for .
    **/
    var targets : Array<CompletionItem>;
  }

;
}

/**
  ExceptionInfoRequest request; value of command field is 'exceptionInfo'.
  Retrieves the details of the exception that caused the StoppedEvent to be raised.
**/
typedef ExceptionInfoRequest = {
  > Request,
  var command : RequestCommandEnum;
  var arguments : ExceptionInfoArguments;
}

/**
  Arguments for 'exceptionInfo' request.
**/
typedef ExceptionInfoArguments = {
  /**
    Thread for which exception information should be retrieved.
  **/
  var threadId : Int;
}

/**
  Response to 'exceptionInfo' request.
**/
typedef ExceptionInfoResponse = {
  > Response,
  var body : {
    /**
      ID of the exception that was thrown.
    **/
    var exceptionId : String;
    /**
      Descriptive text for the exception provided by the debug adapter.
    **/
    @:optional var description : String;
    /**
      Mode that caused the exception notification to be raised.
    **/
    var breakMode : ExceptionBreakMode;
    /**
      Detailed information about the exception.
    **/
    @:optional var details : ExceptionDetails;
  }

;
}

/**
  Information about the capabilities of a debug adapter.
**/
typedef Capabilities = {
  /**
    The debug adapter supports the configurationDoneRequest.
  **/
  @:optional var supportsConfigurationDoneRequest : Bool;
  /**
    The debug adapter supports function breakpoints.
  **/
  @:optional var supportsFunctionBreakpoints : Bool;
  /**
    The debug adapter supports conditional breakpoints.
  **/
  @:optional var supportsConditionalBreakpoints : Bool;
  /**
    The debug adapter supports breakpoints that break execution after a specified number of hits.
  **/
  @:optional var supportsHitConditionalBreakpoints : Bool;
  /**
    The debug adapter supports a (side effect free) evaluate request for data hovers.
  **/
  @:optional var supportsEvaluateForHovers : Bool;
  /**
    Available filters or options for the setExceptionBreakpoints request.
  **/
  @:optional var exceptionBreakpointFilters : Array<ExceptionBreakpointsFilter>;
  /**
    The debug adapter supports stepping back via the stepBack and reverseContinue requests.
  **/
  @:optional var supportsStepBack : Bool;
  /**
    The debug adapter supports setting a variable to a value.
  **/
  @:optional var supportsSetVariable : Bool;
  /**
    The debug adapter supports restarting a frame.
  **/
  @:optional var supportsRestartFrame : Bool;
  /**
    The debug adapter supports the gotoTargetsRequest.
  **/
  @:optional var supportsGotoTargetsRequest : Bool;
  /**
    The debug adapter supports the stepInTargetsRequest.
  **/
  @:optional var supportsStepInTargetsRequest : Bool;
  /**
    The debug adapter supports the completionsRequest.
  **/
  @:optional var supportsCompletionsRequest : Bool;
  /**
    The debug adapter supports the modules request.
  **/
  @:optional var supportsModulesRequest : Bool;
  /**
    The set of additional module information exposed by the debug adapter.
  **/
  @:optional var additionalModuleColumns : Array<ColumnDescriptor>;
  /**
    Checksum algorithms supported by the debug adapter.
  **/
  @:optional var supportedChecksumAlgorithms : Array<ChecksumAlgorithm>;
  /**
    The debug adapter supports the RestartRequest. In this case a client should not implement 'restart' by terminating and relaunching the adapter but by calling the RestartRequest.
  **/
  @:optional var supportsRestartRequest : Bool;
  /**
    The debug adapter supports 'exceptionOptions' on the setExceptionBreakpoints request.
  **/
  @:optional var supportsExceptionOptions : Bool;
  /**
    The debug adapter supports a 'format' attribute on the stackTraceRequest, variablesRequest, and evaluateRequest.
  **/
  @:optional var supportsValueFormattingOptions : Bool;
  /**
    The debug adapter supports the exceptionInfo request.
  **/
  @:optional var supportsExceptionInfoRequest : Bool;
  /**
    The debug adapter supports the 'terminateDebuggee' attribute on the 'disconnect' request.
  **/
  @:optional var supportTerminateDebuggee : Bool;
  /**
    The debug adapter supports the delayed loading of parts of the stack, which requires that both the 'startFrame' and 'levels' arguments and the 'totalFrames' result of the 'StackTrace' request are supported.
  **/
  @:optional var supportsDelayedStackTraceLoading : Bool;
  /**
    The debug adapter supports the 'loadedSources' request.
  **/
  @:optional var supportsLoadedSourcesRequest : Bool;
}

/**
  An ExceptionBreakpointsFilter is shown in the UI as an option for configuring how exceptions are dealt with.
**/
typedef ExceptionBreakpointsFilter = {
  /**
    The internal ID of the filter. This value is passed to the setExceptionBreakpoints request.
  **/
  var filter : FilterEnum;
  /**
    The name of the filter. This will be shown in the UI.
  **/
  var label : String;
}

/**
  A structured message object. Used to return errors from requests.
**/
typedef Message = {
  /**
    Unique identifier for the message.
  **/
  var id : Int;
  /**
    A format string for the message. Embedded variables have the form '{name}'.
    If variable name starts with an underscore character, the variable does not contain user data (PII) and can be safely used for telemetry purposes.
  **/
  var format : String;
  /**
    An object used as a dictionary for looking up the variables in the format string.
  **/
  @:optional var variables : {
  }

;
  /**
    If true send to telemetry.
  **/
  @:optional var sendTelemetry : Bool;
  /**
    If true show user.
  **/
  @:optional var showUser : Bool;
  /**
    An optional url where additional information about this message can be found.
  **/
  @:optional var url : String;
  /**
    An optional label that is presented to the user as the UI for opening the url.
  **/
  @:optional var urlLabel : String;
}

/**
  A Module object represents a row in the modules view.
  Two attributes are mandatory: an id identifies a module in the modules view and is used in a ModuleEvent for identifying a module for adding, updating or deleting.
  The name is used to minimally render the module in the UI.
  
  Additional attributes can be added to the module. They will show up in the module View if they have a corresponding ColumnDescriptor.
  
  To avoid an unnecessary proliferation of additional attributes with similar semantics but different names
  we recommend to re-use attributes from the 'recommended' list below first, and only introduce new attributes if nothing appropriate could be found.
**/
typedef Module = {
  /**
    Unique identifier for the module.
  **/
  var id : Dynamic;
  /**
    A name of the module.
  **/
  var name : String;
  /**
    optional but recommended attributes.
    always try to use these first before introducing additional attributes.
    
    Logical full path to the module. The exact definition is implementation defined, but usually this would be a full path to the on-disk file for the module.
  **/
  @:optional var path : String;
  /**
    True if the module is optimized.
  **/
  @:optional var isOptimized : Bool;
  /**
    True if the module is considered 'user code' by a debugger that supports 'Just My Code'.
  **/
  @:optional var isUserCode : Bool;
  /**
    Version of Module.
  **/
  @:optional var version : String;
  /**
    User understandable description of if symbols were found for the module (ex: 'Symbols Loaded', 'Symbols not found', etc.
  **/
  @:optional var symbolStatus : String;
  /**
    Logical full path to the symbol file. The exact definition is implementation defined.
  **/
  @:optional var symbolFilePath : String;
  /**
    Module created or modified.
  **/
  @:optional var dateTimeStamp : String;
  /**
    Address range covered by this module.
  **/
  @:optional var addressRange : String;
}

/**
  A ColumnDescriptor specifies what module attribute to show in a column of the ModulesView, how to format it, and what the column's label should be.
  It is only used if the underlying UI actually supports this level of customization.
**/
typedef ColumnDescriptor = {
  /**
    Name of the attribute rendered in this column.
  **/
  var attributeName : String;
  /**
    Header UI label of column.
  **/
  var label : String;
  /**
    Format to use for the rendered values in this column. TBD how the format strings looks like.
  **/
  @:optional var format : String;
  /**
    Datatype of values in this column.  Defaults to 'string' if not specified.
  **/
  @:optional var type : TypeEnum;
  /**
    Width of this column in characters (hint only).
  **/
  @:optional var width : Int;
}

/**
  The ModulesViewDescriptor is the container for all declarative configuration options of a ModuleView.
  For now it only specifies the columns to be shown in the modules view.
**/
typedef ModulesViewDescriptor = {
  var columns : Array<ColumnDescriptor>;
}

/**
  A Thread
**/
typedef Thread = {
  /**
    Unique identifier for the thread.
  **/
  var id : Int;
  /**
    A name of the thread.
  **/
  var name : String;
}

/**
  A Source is a descriptor for source code. It is returned from the debug adapter as part of a StackFrame and it is used by clients when specifying breakpoints.
**/
typedef Source = {
  /**
    The short name of the source. Every source returned from the debug adapter has a name. When sending a source to the debug adapter this name is optional.
  **/
  @:optional var name : String;
  /**
    The path of the source to be shown in the UI. It is only used to locate and load the content of the source if no sourceReference is specified (or its vaule is 0).
  **/
  @:optional var path : String;
  /**
    If sourceReference > 0 the contents of the source must be retrieved through the SourceRequest (even if a path is specified). A sourceReference is only valid for a session, so it must not be used to persist a source.
  **/
  @:optional var sourceReference : Float;
  /**
    An optional hint for how to present the source in the UI. A value of 'deemphasize' can be used to indicate that the source is not available or that it is skipped on stepping.
  **/
  @:optional var presentationHint : PresentationHintEnum;
  /**
    The (optional) origin of this source: possible values 'internal module', 'inlined content from source map', etc.
  **/
  @:optional var origin : String;
  /**
    An optional list of sources that are related to this source. These may be the source that generated this source.
  **/
  @:optional var sources : Array<Source>;
  /**
    Optional data that a debug adapter might want to loop through the client. The client should leave the data intact and persist it across sessions. The client should not interpret the data.
  **/
  @:optional var adapterData : Dynamic;
  /**
    The checksums associated with this file.
  **/
  @:optional var checksums : Array<Checksum>;
}

/**
  A Stackframe contains the source location.
**/
typedef StackFrame = {
  /**
    An identifier for the stack frame. It must be unique across all threads. This id can be used to retrieve the scopes of the frame with the 'scopesRequest' or to restart the execution of a stackframe.
  **/
  var id : Int;
  /**
    The name of the stack frame, typically a method name.
  **/
  var name : String;
  /**
    The optional source of the frame.
  **/
  @:optional var source : Source;
  /**
    The line within the file of the frame. If source is null or doesn't exist, line is 0 and must be ignored.
  **/
  var line : Int;
  /**
    The column within the line. If source is null or doesn't exist, column is 0 and must be ignored.
  **/
  var column : Int;
  /**
    An optional end line of the range covered by the stack frame.
  **/
  @:optional var endLine : Int;
  /**
    An optional end column of the range covered by the stack frame.
  **/
  @:optional var endColumn : Int;
  /**
    The module associated with this frame, if any.
  **/
  @:optional var moduleId : Dynamic;
  /**
    An optional hint for how to present this frame in the UI. A value of 'label' can be used to indicate that the frame is an artificial frame that is used as a visual label or separator. A value of 'subtle' can be used to change the appearance of a frame in a 'subtle' way.
  **/
  @:optional var presentationHint : PresentationHintEnum;
}

/**
  A Scope is a named container for variables. Optionally a scope can map to a source or a range within a source.
**/
typedef Scope = {
  /**
    Name of the scope such as 'Arguments', 'Locals'.
  **/
  var name : String;
  /**
    The variables of this scope can be retrieved by passing the value of variablesReference to the VariablesRequest.
  **/
  var variablesReference : Int;
  /**
    The number of named variables in this scope.
    The client can use this optional information to present the variables in a paged UI and fetch them in chunks.
  **/
  @:optional var namedVariables : Int;
  /**
    The number of indexed variables in this scope.
    The client can use this optional information to present the variables in a paged UI and fetch them in chunks.
  **/
  @:optional var indexedVariables : Int;
  /**
    If true, the number of variables in this scope is large or expensive to retrieve.
  **/
  var expensive : Bool;
  /**
    Optional source for this scope.
  **/
  @:optional var source : Source;
  /**
    Optional start line of the range covered by this scope.
  **/
  @:optional var line : Int;
  /**
    Optional start column of the range covered by this scope.
  **/
  @:optional var column : Int;
  /**
    Optional end line of the range covered by this scope.
  **/
  @:optional var endLine : Int;
  /**
    Optional end column of the range covered by this scope.
  **/
  @:optional var endColumn : Int;
}

/**
  A Variable is a name/value pair.
  Optionally a variable can have a 'type' that is shown if space permits or when hovering over the variable's name.
  An optional 'kind' is used to render additional properties of the variable, e.g. different icons can be used to indicate that a variable is public or private.
  If the value is structured (has children), a handle is provided to retrieve the children with the VariablesRequest.
  If the number of named or indexed children is large, the numbers should be returned via the optional 'namedVariables' and 'indexedVariables' attributes.
  The client can use this optional information to present the children in a paged UI and fetch them in chunks.
**/
typedef Variable = {
  /**
    The variable's name.
  **/
  var name : String;
  /**
    The variable's value. This can be a multi-line text, e.g. for a function the body of a function.
  **/
  var value : String;
  /**
    The type of the variable's value. Typically shown in the UI when hovering over the value.
  **/
  @:optional var type : TypeEnum;
  /**
    Properties of a variable that can be used to determine how to render the variable in the UI.
  **/
  @:optional var presentationHint : VariablePresentationHint;
  /**
    Optional evaluatable name of this variable which can be passed to the 'EvaluateRequest' to fetch the variable's value.
  **/
  @:optional var evaluateName : String;
  /**
    If variablesReference is > 0, the variable is structured and its children can be retrieved by passing variablesReference to the VariablesRequest.
  **/
  var variablesReference : Int;
  /**
    The number of named child variables.
    The client can use this optional information to present the children in a paged UI and fetch them in chunks.
  **/
  @:optional var namedVariables : Int;
  /**
    The number of indexed child variables.
    The client can use this optional information to present the children in a paged UI and fetch them in chunks.
  **/
  @:optional var indexedVariables : Int;
}

/**
  Optional properties of a variable that can be used to determine how to render the variable in the UI.
**/
typedef VariablePresentationHint = {
  /**
    The kind of variable. Before introducing additional values, try to use the listed values.
  **/
  @:optional var kind : KindEnum;
  /**
    Set of attributes represented as an array of strings. Before introducing additional values, try to use the listed values.
  **/
  @:optional var attributes : Array<String>;
  /**
    Visibility of variable. Before introducing additional values, try to use the listed values.
  **/
  @:optional var visibility : VisibilityEnum;
}

/**
  Properties of a breakpoint passed to the setBreakpoints request.
**/
typedef SourceBreakpoint = {
  /**
    The source line of the breakpoint.
  **/
  var line : Int;
  /**
    An optional source column of the breakpoint.
  **/
  @:optional var column : Int;
  /**
    An optional expression for conditional breakpoints.
  **/
  @:optional var condition : String;
  /**
    An optional expression that controls how many hits of the breakpoint are ignored. The backend is expected to interpret the expression as needed.
  **/
  @:optional var hitCondition : String;
}

/**
  Properties of a breakpoint passed to the setFunctionBreakpoints request.
**/
typedef FunctionBreakpoint = {
  /**
    The name of the function.
  **/
  var name : String;
  /**
    An optional expression for conditional breakpoints.
  **/
  @:optional var condition : String;
  /**
    An optional expression that controls how many hits of the breakpoint are ignored. The backend is expected to interpret the expression as needed.
  **/
  @:optional var hitCondition : String;
}

/**
  Information about a Breakpoint created in setBreakpoints or setFunctionBreakpoints.
**/
typedef Breakpoint = {
  /**
    An optional unique identifier for the breakpoint.
  **/
  @:optional var id : Int;
  /**
    If true breakpoint could be set (but not necessarily at the desired location).
  **/
  var verified : Bool;
  /**
    An optional message about the state of the breakpoint. This is shown to the user and can be used to explain why a breakpoint could not be verified.
  **/
  @:optional var message : String;
  /**
    The source where the breakpoint is located.
  **/
  @:optional var source : Source;
  /**
    The start line of the actual range covered by the breakpoint.
  **/
  @:optional var line : Int;
  /**
    An optional start column of the actual range covered by the breakpoint.
  **/
  @:optional var column : Int;
  /**
    An optional end line of the actual range covered by the breakpoint.
  **/
  @:optional var endLine : Int;
  /**
    An optional end column of the actual range covered by the breakpoint. If no end line is given, then the end column is assumed to be in the start line.
  **/
  @:optional var endColumn : Int;
}

/**
  A StepInTarget can be used in the 'stepIn' request and determines into which single target the stepIn request should step.
**/
typedef StepInTarget = {
  /**
    Unique identifier for a stepIn target.
  **/
  var id : Int;
  /**
    The name of the stepIn target (shown in the UI).
  **/
  var label : String;
}

/**
  A GotoTarget describes a code location that can be used as a target in the 'goto' request.
  The possible goto targets can be determined via the 'gotoTargets' request.
**/
typedef GotoTarget = {
  /**
    Unique identifier for a goto target. This is used in the goto request.
  **/
  var id : Int;
  /**
    The name of the goto target (shown in the UI).
  **/
  var label : String;
  /**
    The line of the goto target.
  **/
  var line : Int;
  /**
    An optional column of the goto target.
  **/
  @:optional var column : Int;
  /**
    An optional end line of the range covered by the goto target.
  **/
  @:optional var endLine : Int;
  /**
    An optional end column of the range covered by the goto target.
  **/
  @:optional var endColumn : Int;
}

/**
  CompletionItems are the suggestions returned from the CompletionsRequest.
**/
typedef CompletionItem = {
  /**
    The label of this completion item. By default this is also the text that is inserted when selecting this completion.
  **/
  var label : String;
  /**
    If text is not falsy then it is inserted instead of the label.
  **/
  @:optional var text : String;
  /**
    The item's type. Typically the client uses this information to render the item in the UI with an icon.
  **/
  @:optional var type : CompletionItemType;
  /**
    This value determines the location (in the CompletionsRequest's 'text' attribute) where the completion text is added.
    If missing the text is added at the location specified by the CompletionsRequest's 'column' attribute.
  **/
  @:optional var start : Int;
  /**
    This value determines how many characters are overwritten by the completion text.
    If missing the value 0 is assumed which results in the completion text being inserted.
  **/
  @:optional var length : Int;
}

@:enum abstract CompletionItemType(String) {
  var Method = "method";
  var Function = "function";
  var Constructor = "constructor";
  var Field = "field";
  var Variable = "variable";
  var Class = "class";
  var Interface = "interface";
  var Module = "module";
  var Property = "property";
  var Unit = "unit";
  var Value = "value";
  var Enum = "enum";
  var Keyword = "keyword";
  var Snippet = "snippet";
  var Text = "text";
  var Color = "color";
  var File = "file";
  var Reference = "reference";
  var Customcolor = "customcolor";
}

@:enum abstract ChecksumAlgorithm(String) {
  var MD5 = "MD5";
  var SHA1 = "SHA1";
  var SHA256 = "SHA256";
  var Timestamp = "timestamp";
}

/**
  The checksum of an item calculated by the specified algorithm.
**/
typedef Checksum = {
  /**
    The algorithm used to calculate this checksum.
  **/
  var algorithm : ChecksumAlgorithm;
  /**
    Value of the checksum.
  **/
  var checksum : String;
}

/**
  Provides formatting information for a value.
**/
typedef ValueFormat = {
  /**
    Display the value in hex.
  **/
  @:optional var hex : Bool;
}

/**
  Provides formatting information for a stack frame.
**/
typedef StackFrameFormat = {
  > ValueFormat,
  /**
    Displays parameters for the stack frame.
  **/
  @:optional var parameters : Bool;
  /**
    Displays the types of parameters for the stack frame.
  **/
  @:optional var parameterTypes : Bool;
  /**
    Displays the names of parameters for the stack frame.
  **/
  @:optional var parameterNames : Bool;
  /**
    Displays the values of parameters for the stack frame.
  **/
  @:optional var parameterValues : Bool;
  /**
    Displays the line number of the stack frame.
  **/
  @:optional var line : Bool;
  /**
    Displays the module of the stack frame.
  **/
  @:optional var module : Bool;
  /**
    Includes all stack frames, including those the debug adapter might otherwise hide.
  **/
  @:optional var includeAll : Bool;
}

/**
  An ExceptionOptions assigns configuration options to a set of exceptions.
**/
typedef ExceptionOptions = {
  /**
    A path that selects a single or multiple exceptions in a tree. If 'path' is missing, the whole tree is selected. By convention the first segment of the path is a category that is used to group exceptions in the UI.
  **/
  @:optional var path : Array<ExceptionPathSegment>;
  /**
    Condition when a thrown exception should result in a break.
  **/
  var breakMode : ExceptionBreakMode;
}

@:enum abstract ExceptionBreakMode(String) {
  var Never = "never";
  var Always = "always";
  var Unhandled = "unhandled";
  var UserUnhandled = "userUnhandled";
}

/**
  An ExceptionPathSegment represents a segment in a path that is used to match leafs or nodes in a tree of exceptions. If a segment consists of more than one name, it matches the names provided if 'negate' is false or missing or it matches anything except the names provided if 'negate' is true.
**/
typedef ExceptionPathSegment = {
  /**
    If false or missing this segment matches the names provided, otherwise it matches anything except the names provided.
  **/
  @:optional var negate : Bool;
  /**
    Depending on the value of 'negate' the names that should match or not match.
  **/
  var names : Array<String>;
}

/**
  Detailed information about an exception that has occurred.
**/
typedef ExceptionDetails = {
  /**
    Message contained in the exception.
  **/
  @:optional var message : String;
  /**
    Short type name of the exception object.
  **/
  @:optional var typeName : String;
  /**
    Fully-qualified type name of the exception object.
  **/
  @:optional var fullTypeName : String;
  /**
    Optional expression that can be evaluated in the current scope to obtain the exception object.
  **/
  @:optional var evaluateName : String;
  /**
    Stack trace at the time the exception was thrown.
  **/
  @:optional var stackTrace : String;
  /**
    Details of the exception contained by this exception, if any.
  **/
  @:optional var innerException : Array<ExceptionDetails>;
}