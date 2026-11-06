import CryptoKit
import Foundation

/// 登录鉴权：`SHA256(salt ‖ password)`。
///
/// 与 Pi-Star 一致：主站下发 4 字节 salt（RPTACK 的第 6..9 字节），
/// 客户端把 salt 的原始字节拼上密码后做 SHA256，取 32 字节摘要放进 RPTK。
public enum SHA256Auth {
    public static func digest(salt: UInt32, password: String) -> [UInt8] {
        digest(Array(salt.bigEndianBytes) + Array(password.utf8))
    }

    public static func digest(_ input: [UInt8]) -> [UInt8] {
        Array(SHA256.hash(data: Data(input)))
    }
}
