import Testing
@testable import AscelerateCore

/// The age rating questions preflight counts as unanswered.
@Suite struct AgeRatingTests {
  @Test func unansweredQuestionnaire() {
    #expect(AgeRatingFields().unanswered == 23)
  }

  @Test func answeredQuestionnaire() {
    var fields = Self.answered
    #expect(fields.unanswered == 0)
    // Optional: the Kids category and the override.
    fields.kidsAgeBand = nil
    fields.ageRatingOverride = nil
    #expect(fields.unanswered == 0)
    fields.contests = nil
    fields.isLootBox = nil
    #expect(fields.unanswered == 2)
  }

  @Test func socialMediaAgeRestrictionOnlyForSocialMedia() {
    var fields = Self.answered
    fields.isSocialMediaAgeRestricted = nil
    #expect(fields.unanswered == 0)
    fields.isSocialMedia = true
    #expect(fields.unanswered == 1)
  }

  private static let answered = AgeRatingFields(
    alcoholTobaccoOrDrugUseOrReferences: "NONE", contests: "NONE", gamblingSimulated: "NONE", gunsOrOtherWeapons: "NONE",
    horrorOrFearThemes: "NONE", matureOrSuggestiveThemes: "NONE", profanityOrCrudeHumor: "NONE",
    sexualContentOrNudity: "NONE", sexualContentGraphicAndNudity: "NONE", violenceCartoonOrFantasy: "NONE",
    violenceRealistic: "NONE", violenceRealisticProlongedGraphicOrSadistic: "NONE", medicalOrTreatmentInformation: "NONE",
    isAdvertising: false, isGambling: false, isUnrestrictedWebAccess: false, isUserGeneratedContent: false,
    isMessagingAndChat: false, isLootBox: false, isHealthOrWellnessTopics: false, isParentalControls: false,
    isAgeAssurance: false, isSocialMedia: false, isSocialMediaAgeRestricted: false, kidsAgeBand: "FIVE_AND_UNDER",
    ageRatingOverride: "NONE")
}
