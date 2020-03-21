import struct Foundation.URL
import Version
import Files
import ShellOut
import SwiftyTextTable
import Rainbow

struct Manifest: Decodable {
    let dependencies: [Dependency]
}

struct Dependency: Decodable {
    let url: URL
    let requirement: Requirement

    var packageName: String {
        url.lastPathComponent.replacingOccurrences(of: ".git", with: "")
    }

    func availableVersions() throws -> [Version] {
        let checkoutDir = try Folder(path: ".build/checkouts/\(packageName)")
        let lsRemote = try shellOut(to: "git", arguments: ["ls-remote", "--tags"], at: checkoutDir.path)
        return lsRemote
            .split(separator: "\n")
            .dropFirst() // Remote description
            .map {
                $0.split(separator: "\t")
                    .last!
                    .trimmingCharacters(in: .whitespaces)
                    .replacingOccurrences(of: "refs/tags/", with: "")
            }
            .compactMap { Version($0) }
    }

    func requirementIsOutdated() throws -> Bool {
        switch self.requirement {
        case .range(let range):
            guard let latestRemoteVersion = try availableVersions().last,
                let upperBound = range.upper
            else {
                return false
            }
            return upperBound < latestRemoteVersion
        case .exact(let exact):
            guard let latestRemoteVersion = try availableVersions().last,
                let exactVersion = Version(exact)
            else {
                return false
            }
            return exactVersion < latestRemoteVersion
        default:
            return false
        }
    }

    enum Requirement {
        case range(Range)
        case exact(String)
        case branch(String)
        case revision(String)
        case localPackage
    }

    private enum CodingKeys: CodingKey {
        case url
        case requirement
    }

    private enum RequirementContainer: CodingKey {
        case range
//        case exact
        case branch
//        case revision
//        case localPackage
    }

    struct Range: Decodable {
        let lowerBound: String
        let upperBound: String

        var lower: Version? {
            Version(lowerBound)
        }

        var upper: Version? {
            Version(upperBound)
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let url = try container.decode(URL.self, forKey: .url)
        self.url = url

        let requirement = try container.nestedContainer(keyedBy: RequirementContainer.self, forKey: .requirement)
        if let range = try? requirement.decode([Range].self, forKey: .range) {
            assert(range.count == 1)
            self.requirement = .range(range.first!)
        } else if let branch = try? requirement.decode([String].self, forKey: .branch) {
            assert(branch.count == 1)
            self.requirement = .branch(branch.first!)
        } else {
            fatalError("Failed to decode dependency requirement for \(url)")
        }
    }
}

extension Dependency.Requirement {
    var tableText: String {
        switch self {
        case .range(let range):
            return "\(range.lowerBound)..<\(range.upperBound)"
        case .exact(let exact):
            return exact
        case .branch(let branch):
            return branch
        case .revision(let revision):
            return revision
        case .localPackage:
            return "local"
        }
    }
}

extension Dependency: TextTableRepresentable {
    static let columnHeaders = [
        "Name",
        "Requirement",
        "Latest"
    ]

    var tableValues: [CustomStringConvertible] {
        let isOutdated = (try? requirementIsOutdated()) ?? false
        let latestVersion = (try? availableVersions().last?.description) ?? "n/a"
        return [
            packageName,
            isOutdated ? requirement.tableText.red + " ⬆️" : requirement.tableText,
            latestVersion
        ]
    }
}
