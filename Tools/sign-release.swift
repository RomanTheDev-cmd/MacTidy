import Foundation
import CryptoKit

let key = try Curve25519.Signing.PrivateKey(rawRepresentation: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])))
let package = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[2]))
let signature = try key.signature(for: package)
try signature.write(to: URL(fileURLWithPath: CommandLine.arguments[3]), options: .atomic)
