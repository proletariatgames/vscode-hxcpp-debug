package utils;

enum InputData {
    VSCodeRequest(req:vscode.debugger.Data.ProtocolMessage);
    // VSCodeResponse(res:vscode.debugger.Data.Response);
    DebuggerInterrupt(msg:debugger.IController.Message);
    Callback(fn:Void->Void);
}