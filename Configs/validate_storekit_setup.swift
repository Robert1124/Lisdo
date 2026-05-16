import Foundation

let expectedProductIDs: Set<String> = [
    "com.yiwenwu.Lisdo.starterTrial",
    "com.yiwenwu.Lisdo.monthlyBasic",
    "com.yiwenwu.Lisdo.monthlyPlus",
    "com.yiwenwu.Lisdo.monthlyMax",
    "com.yiwenwu.Lisdo.topUpUsage"
]

let repositoryRoot: URL = {
    if let path = CommandLine.arguments.dropFirst().first {
        return URL(fileURLWithPath: path)
    }
    return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
}()

var failures: [String] = []

func fileContents(_ relativePath: String) -> String? {
    let url = repositoryRoot.appendingPathComponent(relativePath)
    return try? String(contentsOf: url, encoding: .utf8)
}

func collectProductIDs(from value: Any) -> Set<String> {
    if let dictionary = value as? [String: Any] {
        var ids = Set<String>()
        if let productID = dictionary["productID"] as? String {
            ids.insert(productID)
        }
        for nestedValue in dictionary.values {
            ids.formUnion(collectProductIDs(from: nestedValue))
        }
        return ids
    }

    if let array = value as? [Any] {
        return array.reduce(into: Set<String>()) { ids, nestedValue in
            ids.formUnion(collectProductIDs(from: nestedValue))
        }
    }

    return []
}

let storeKitURL = repositoryRoot.appendingPathComponent("Configs/Lisdo.storekit")
if FileManager.default.fileExists(atPath: storeKitURL.path) {
    do {
        let data = try Data(contentsOf: storeKitURL)
        let json = try JSONSerialization.jsonObject(with: data)
        let configuredProductIDs = collectProductIDs(from: json)
        let missingProductIDs = expectedProductIDs.subtracting(configuredProductIDs).sorted()
        if !missingProductIDs.isEmpty {
            failures.append("Configs/Lisdo.storekit is missing product IDs: \(missingProductIDs.joined(separator: ", "))")
        }
    } catch {
        failures.append("Configs/Lisdo.storekit is not valid JSON: \(error.localizedDescription)")
    }
} else {
    failures.append("Configs/Lisdo.storekit does not exist.")
}

if let projectYAML = fileContents("project.yml") {
    if !projectYAML.contains("storeKitConfiguration: Configs/Lisdo.storekit") {
        failures.append("project.yml does not wire Configs/Lisdo.storekit into the iOS run scheme.")
    }
} else {
    failures.append("project.yml could not be read.")
}

if let storeKitService = fileContents("Apps/Shared/LisdoStoreKitService.swift") {
    let requiredSnippets = [
        "startTransactionUpdatesListener",
        "Transaction.updates",
        "currentLisdoBearerToken",
        "verifyStoreKitTransaction",
        "finish()"
    ]
    for snippet in requiredSnippets where !storeKitService.contains(snippet) {
        failures.append("LisdoStoreKitService.swift is missing StoreKit update sync snippet: \(snippet)")
    }
} else {
    failures.append("Apps/Shared/LisdoStoreKitService.swift could not be read.")
}

if failures.isEmpty {
    print("StoreKit setup validation passed.")
} else {
    for failure in failures {
        print("StoreKit setup validation failed: \(failure)")
    }
    exit(1)
}
