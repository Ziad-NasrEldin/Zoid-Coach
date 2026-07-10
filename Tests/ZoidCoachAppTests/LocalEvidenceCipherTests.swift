import Foundation
import Testing
@testable import ZoidCoachInfrastructure

@Test
func localEvidenceCipherRoundTripsAndRejectsTampering() throws {
    let key = Data((0..<32).map(UInt8.init))
    let cipher = try LocalEvidenceCipher(keyData: key)
    let privateText = Data("Private WhatsApp meeting evidence".utf8)

    let encrypted = try cipher.encrypt(privateText)
    let decrypted = try cipher.decrypt(encrypted)
    var tampered = encrypted
    tampered[tampered.startIndex] ^= 0x01

    #expect(encrypted != privateText)
    #expect(decrypted == privateText)
    #expect(throws: (any Error).self) { try cipher.decrypt(tampered) }
}
