import Darwin
import Foundation
import UntypeCore

@main
struct UntypeExecutable {
    static func main() async {
        let args = Array(CommandLine.arguments.dropFirst())
        if BundledAppLaunch.shouldLaunchUI(arguments: args, bundleURL: Bundle.main.bundleURL) {
            do {
                exit(Int32(try NativeUntypeUILauncher.launchBlockingOnCurrentThread()))
            } catch let error as UntypeError {
                StandardStreamWriter(file: stderr).write("\(error.diagnosticLine)\n")
                exit(error.exitCode.rawValue)
            } catch {
                StandardStreamWriter(file: stderr).write("unknown: \(error.localizedDescription)\n")
                exit(ExitCode.unknown.rawValue)
            }
        }

        let command = UntypeCommand(
            stdout: StandardStreamWriter(file: stdout),
            stderr: StandardStreamWriter(file: stderr),
            stdoutIsTTY: isatty(fileno(stdout)) == 1
        )

        let code = await command.run(args)
        exit(Int32(code))
    }
}
