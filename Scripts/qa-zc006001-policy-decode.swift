import Foundation

@main
struct ZC006001PolicyDecodeProbe {
    static func main() {
        guard CommandLine.arguments.count == 2 else {
            fputs("usage: qa-zc006001-policy-decode <policy-json>\n", stderr)
            exit(2)
        }

        do {
            let url = URL(fileURLWithPath: CommandLine.arguments[1])
            let data = try Data(contentsOf: url, options: [.mappedIfSafe])
            let policy = try JSONDecoder.zoidPolicy.decode(UserPolicy.self, from: data)
                .upgradedToCurrentSchema()
                .validated()
            print("PASS: production UserPolicy decode schema=\(policy.schemaVersion) zone=\(policy.schedule.timeZoneIdentifier)")
        } catch {
            fputs("FAIL: production UserPolicy decode rejected policy: \(error)\n", stderr)
            exit(1)
        }
    }
}
