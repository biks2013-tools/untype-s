import Darwin
import Foundation
import UntypeCore

let inputData = FileHandle.standardInput.readDataToEndOfFile()
let run = FocusedInputHelperMain.run(
    arguments: Array(CommandLine.arguments.dropFirst()),
    inputData: inputData
)
print(FocusedInputHelperMain.encodeResult(run.result))
exit(run.exitCode.rawValue)
