import Foundation
import Testing
@testable import AscelerateCore

/// Which certificates a profile type takes, as the developer portal offers them.
@Suite struct ProfileCertificatesTests {
  @Test func universalCertificatesFitEveryPlatform() {
    for profile in ["IOS_APP_STORE", "MAC_APP_STORE", "MAC_CATALYST_APP_STORE", "TVOS_APP_ADHOC"] {
      #expect(Profiles.certificateFits("DISTRIBUTION", profileType: profile))
    }
    for profile in ["IOS_APP_DEVELOPMENT", "MAC_APP_DEVELOPMENT"] {
      #expect(Profiles.certificateFits("DEVELOPMENT", profileType: profile))
    }
  }

  @Test func platformCertificatesFitTheirOwnPlatform() {
    #expect(Profiles.certificateFits("IOS_DISTRIBUTION", profileType: "IOS_APP_STORE"))
    #expect(!Profiles.certificateFits("IOS_DISTRIBUTION", profileType: "MAC_APP_STORE"))
    #expect(Profiles.certificateFits("MAC_APP_DISTRIBUTION", profileType: "MAC_APP_STORE"))
    #expect(Profiles.certificateFits("MAC_APP_DISTRIBUTION", profileType: "MAC_CATALYST_APP_STORE"))
    #expect(!Profiles.certificateFits("MAC_APP_DISTRIBUTION", profileType: "IOS_APP_STORE"))
    #expect(Profiles.certificateFits("IOS_DEVELOPMENT", profileType: "IOS_APP_DEVELOPMENT"))
    #expect(!Profiles.certificateFits("IOS_DEVELOPMENT", profileType: "MAC_APP_DEVELOPMENT"))
    #expect(Profiles.certificateFits("MAC_APP_DEVELOPMENT", profileType: "MAC_APP_DEVELOPMENT"))
    #expect(!Profiles.certificateFits("MAC_APP_DEVELOPMENT", profileType: "IOS_APP_DEVELOPMENT"))
  }

  @Test func installerAndOtherKindsDontFit() {
    for profile in ["IOS_APP_STORE", "MAC_APP_STORE", "MAC_APP_DIRECT", "MAC_APP_DEVELOPMENT"] {
      #expect(!Profiles.certificateFits("MAC_INSTALLER_DISTRIBUTION", profileType: profile))
    }
    #expect(!Profiles.certificateFits("DEVELOPMENT", profileType: "MAC_APP_STORE"))
    #expect(!Profiles.certificateFits("DISTRIBUTION", profileType: "MAC_APP_DIRECT"))
    #expect(Profiles.certificateFits("DEVELOPER_ID_APPLICATION", profileType: "MAC_APP_DIRECT"))
  }
}

/// What a recreated profile takes back: enabled devices that fit, certificates that fit and
/// haven't expired.
@Suite struct ReissueContentsTests {
  let now = Date(timeIntervalSince1970: 1_800_000_000)

  func device(_ id: String, deviceClass: String, status: String? = "ENABLED") -> Devices.Device {
    Devices.Device(id: id, name: id, udid: id, platform: nil, deviceClass: deviceClass, model: nil, status: status, addedDate: nil)
  }

  func certificate(_ id: String, type: String, expires: TimeInterval?) -> Certificates.Certificate {
    Certificates.Certificate(
      id: id, name: nil, displayName: nil, type: type, platform: nil, serialNumber: nil,
      expirationDate: expires.map { now.addingTimeInterval($0) }, activated: nil, content: nil)
  }

  @Test func developmentProfileKeepsEnabledFittingDevicesAndLiveCertificates() {
    let contents = Profiles.reissueContents(
      profileType: "IOS_APP_DEVELOPMENT",
      devices: [
        device("phone", deviceClass: "IPHONE"), device("off", deviceClass: "IPHONE", status: "DISABLED"),
        device("tv", deviceClass: "APPLE_TV"), device("mac", deviceClass: "MAC"),
      ],
      certificates: [
        certificate("live", type: "DEVELOPMENT", expires: 86_400), certificate("old", type: "DEVELOPMENT", expires: -1),
        certificate("dist", type: "DISTRIBUTION", expires: 86_400), certificate("unknown", type: "DEVELOPMENT", expires: nil),
      ],
      now: now)
    // Apple silicon Macs run iPhone apps, so an iOS development profile keeps them.
    #expect(contents.devices?.map(\.id) == ["phone", "mac"])
    #expect(contents.certificates.map(\.id) == ["live", "unknown"])
  }

  @Test func storeProfileHasNoDevicesAndCanEndUpEmpty() {
    let contents = Profiles.reissueContents(
      profileType: "MAC_APP_STORE", devices: [device("mac", deviceClass: "MAC")],
      certificates: [certificate("old", type: "DISTRIBUTION", expires: -60), certificate("ios", type: "IOS_DISTRIBUTION", expires: 60)],
      now: now)
    #expect(contents.devices == nil)
    #expect(contents.certificates.isEmpty)
  }
}
