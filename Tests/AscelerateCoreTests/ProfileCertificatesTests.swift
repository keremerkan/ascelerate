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
