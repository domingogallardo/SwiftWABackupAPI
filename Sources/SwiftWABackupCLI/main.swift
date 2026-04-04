import Foundation

let application = CLIApplication()
let exitCode = application.run(arguments: Array(CommandLine.arguments.dropFirst()))
exit(exitCode)
