import Foundation

/// RPTC 配置报文的负载。
///
/// 字段宽度来自 DMRGateway / MMDVMHost 的实现，总长 302 字节（含 "RPTC" 与 ID）：
/// ```
/// 0..3  "RPTC"   4..7  ID        8..15   呼号(8)
/// 16..24  接收频率(9)            25..33  发射频率(9)
/// 34..35  功率(2)                36..37  色码(2)
/// 38..45  纬度(8)                46..54  经度(9)
/// 55..57  天线高度(3)            58..77  位置(20)
/// 78..96  描述(19)               97      时隙(1) 1=TS1 2=TS2 3=both
/// 98..221 URL(124)              222..261 软件ID(40)
/// 262..301 包ID(40)
/// ```
public struct RepeaterInfo {
    public var callsign: String
    public var rxFrequencyHz: UInt32
    public var txFrequencyHz: UInt32
    public var txPower: Int
    public var colorCode: Int
    public var latitude: Double
    public var longitude: Double
    public var antennaHeight: Int
    public var location: String
    public var description: String
    /// 1 = 仅时隙1，2 = 仅时隙2，3 = 双时隙。
    public var slots: Int
    public var url: String
    public var softwareID: String
    public var packageID: String

    public static let packetLength = 302

    public init(callsign: String = "N0CALL",
                rxFrequencyHz: UInt32 = 430_000_000,
                txFrequencyHz: UInt32 = 430_000_000,
                txPower: Int = 1,
                colorCode: Int = 1,
                latitude: Double = 0,
                longitude: Double = 0,
                antennaHeight: Int = 0,
                location: String = "",
                description: String = "Pi-Star Swift Client",
                slots: Int = 3,
                url: String = "",
                softwareID: String = "BrandMeisterKit-Swift",
                packageID: String = "PiStarBrandMeister") {
        self.callsign = callsign
        self.rxFrequencyHz = rxFrequencyHz
        self.txFrequencyHz = txFrequencyHz
        self.txPower = txPower
        self.colorCode = colorCode
        self.latitude = latitude
        self.longitude = longitude
        self.antennaHeight = antennaHeight
        self.location = location
        self.description = description
        self.slots = slots
        self.url = url
        self.softwareID = softwareID
        self.packageID = packageID
    }

    public func encoded(repeaterID: UInt32) -> [UInt8] {
        var bytes = HBP.config
        bytes += repeaterID.bigEndianBytes
        bytes += RepeaterInfo.field(callsign, 8)
        bytes += RepeaterInfo.field(RepeaterInfo.frequencyText(rxFrequencyHz), 9, left: false, pad: "0")
        bytes += RepeaterInfo.field(RepeaterInfo.frequencyText(txFrequencyHz), 9, left: false, pad: "0")
        bytes += RepeaterInfo.field(String(txPower), 2, left: false, pad: "0")
        bytes += RepeaterInfo.field(String(colorCode), 2, left: false, pad: "0")
        bytes += RepeaterInfo.field(String(format: "%08.5f", latitude), 8, left: false, pad: "0")
        bytes += RepeaterInfo.field(String(format: "%09.5f", longitude), 9, left: false, pad: "0")
        bytes += RepeaterInfo.field(String(antennaHeight), 3, left: false, pad: "0")
        bytes += RepeaterInfo.field(location, 20)
        bytes += RepeaterInfo.field(description, 19)
        bytes += RepeaterInfo.field(String(slots), 1)
        bytes += RepeaterInfo.field(url, 124)
        bytes += RepeaterInfo.field(softwareID, 40)
        bytes += RepeaterInfo.field(packageID, 40)
        return bytes
    }

    /// 频率字段是 10Hz 为单位的 9 位十进制串。
    static func frequencyText(_ hz: UInt32) -> String {
        String(hz / 10)
    }

    /// 定长 ASCII 字段：超长截断，不足补齐。
    static func field(_ value: String,
                      _ width: Int,
                      left: Bool = true,
                      pad: Character = " ") -> [UInt8] {
        var bytes = Array(value.utf8.prefix(width))
        if bytes.count < width {
            let filler = [UInt8](repeating: pad.asciiValue ?? 0x20, count: width - bytes.count)
            bytes = left ? bytes + filler : filler + bytes
        }
        return bytes
    }
}
