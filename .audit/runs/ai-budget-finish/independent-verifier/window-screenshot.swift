import CoreGraphics
import Foundation

guard CommandLine.arguments.count == 3,
      let pid = Int32(CommandLine.arguments[1]) else {
    fputs("usage: window-screenshot.swift <pid> <output-path>\n", stderr)
    exit(2)
}

let outputPath = CommandLine.arguments[2]
guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]],
      let window = windows.first(where: {
          ($0[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == pid
              && ($0[kCGWindowLayer as String] as? NSNumber)?.intValue == 0
      }),
      let windowNumber = window[kCGWindowNumber as String] as? NSNumber else {
    fputs("no on-screen window for pid \(pid)\n", stderr)
    exit(1)
}

let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
process.arguments = ["-x", "-l", windowNumber.stringValue, outputPath]
try process.run()
process.waitUntilExit()
guard process.terminationStatus == 0 else {
    fputs("screencapture failed with \(process.terminationStatus)\n", stderr)
    exit(1)
}
print("PASS: captured \(outputPath)")
