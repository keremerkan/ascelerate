import AppStoreConnect
import ArgumentParser
import Foundation

/// Shared driver for `iap availability` / `sub availability`. Fetches the current
/// availability via `fetchCurrent` (treating DecodingError / 404 as "none set — inherits
/// the app's territories"), prints it in view mode, or computes the add/remove set math,
/// prints a change summary, confirms, and hands the final list to `post` for the
/// wholesale schedule replacement. `productNoun` names the product kind in the
/// no-availability message (e.g. "IAP", "subscription").
func runProductAvailability(
  productID: String,
  productNoun: String,
  add: String?,
  remove: String?,
  availableInNewTerritories: String?,
  verbose: Bool,
  fetchCurrent: () async throws -> (availableInNew: Bool?, territories: [String]),
  post: (_ availableInNew: Bool, _ territories: [String]) async throws -> Void
) async throws {
  // Fetch current availability
  var currentAvailableInNew: Bool?
  var currentTerritories: [String] = []
  var hasAvailability = false
  do {
    let current = try await fetchCurrent()
    currentAvailableInNew = current.availableInNew
    currentTerritories = current.territories
    hasAvailability = true
  } catch is DecodingError {
    hasAvailability = false
  } catch let error as ResponseError {
    if case .requestFailure(_, let statusCode, _) = error, statusCode == 404 {
      hasAvailability = false
    } else {
      throw error
    }
  }

  let isEditMode = add != nil || remove != nil || availableInNewTerritories != nil

  let newAvailableInNewFlag: Bool?
  if let s = availableInNewTerritories {
    guard let b = Bool(s.lowercased()) else {
      throw ValidationError("Invalid value for --available-in-new-territories. Use 'true' or 'false'.")
    }
    newAvailableInNewFlag = b
  } else {
    newAvailableInNewFlag = nil
  }

  if !isEditMode {
    // View mode
    print("Product ID: \(productID)")
    if !hasAvailability {
      print(yellow("⚠ No per-\(productNoun) availability set — inherits the app's territories."))
      return
    }
    print("Available in new territories: \(currentAvailableInNew == true ? "Yes" : currentAvailableInNew == false ? "No" : "—")")
    print()
    let sorted = currentTerritories.sorted()
    print("Available (\(sorted.count)):")
    printAvailabilityTerritories(sorted, verbose: verbose)
    return
  }

  // Edit mode — compute the new territory list
  let addCodes = Set(add?.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).uppercased() } ?? [])
  let removeCodes = Set(remove?.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).uppercased() } ?? [])

  let overlap = addCodes.intersection(removeCodes)
  if !overlap.isEmpty {
    throw ValidationError("Territory codes in both --add and --remove: \(overlap.sorted().joined(separator: ", "))")
  }

  var newTerritories = Set(currentTerritories)
  newTerritories.formUnion(addCodes)
  newTerritories.subtract(removeCodes)

  let effectiveAvailableInNew = newAvailableInNewFlag ?? currentAvailableInNew ?? true
  let finalList = newTerritories.sorted()

  if finalList.isEmpty {
    throw ValidationError("Cannot have zero available territories — at least one is required.")
  }

  // Summary
  print("Product ID: \(productID)")
  print("Available in new territories: \(effectiveAvailableInNew ? "Yes" : "No")")
  let addedCodes = addCodes.subtracting(currentTerritories).sorted()
  let removedCodes = removeCodes.intersection(currentTerritories).sorted()
  if !addedCodes.isEmpty {
    print("Adding:    \(addedCodes.joined(separator: ", "))")
  }
  if !removedCodes.isEmpty {
    print("Removing:  \(removedCodes.joined(separator: ", "))")
  }
  if addedCodes.isEmpty && removedCodes.isEmpty && newAvailableInNewFlag == nil {
    print("No changes.")
    return
  }
  print("New total available: \(finalList.count) territor\(finalList.count == 1 ? "y" : "ies")")
  print()

  guard confirm("Apply this availability? [y/N] ") else {
    cancelled()
    return
  }

  try await post(effectiveAvailableInNew, finalList)

  print()
  success("Updated", "availability for \(productID) (\(finalList.count) territories).")
}

private func printAvailabilityTerritories(_ codes: [String], verbose: Bool) {
  if verbose {
    let en = Locale(identifier: "en")
    for code in codes {
      let name = en.localizedString(forRegionCode: code) ?? code
      print("  \(code)  \(name)")
    }
  } else {
    for i in stride(from: 0, to: codes.count, by: 10) {
      let end = min(i + 10, codes.count)
      let row = codes[i..<end].joined(separator: "  ")
      print("  \(row)")
    }
  }
}
