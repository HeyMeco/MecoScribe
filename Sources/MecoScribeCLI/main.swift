#if os(macOS)
import Foundation

let arguments = Array(CommandLine.arguments.dropFirst())
await ScribeCommand.run(arguments: arguments)
#endif
