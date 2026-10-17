import Foundation

/// Loads the bundled `Exercises.csv` once into memory for the exercise picker.
struct ExerciseCatalog {
    static let all: [Exercise] = loadFromBundle()

    static func search(_ query: String) -> [Exercise] {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return all }
        return all.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    static func grouped() -> [(muscle: String, exercises: [Exercise])] {
        let groups = Dictionary(grouping: all, by: \.primaryMuscle)
        return groups.keys.sorted().map { muscle in
            (muscle: muscle, exercises: groups[muscle]!.sorted { $0.name < $1.name })
        }
    }

    private static func loadFromBundle() -> [Exercise] {
        guard let url = Bundle.main.url(forResource: "Exercises", withExtension: "csv"),
              let contents = try? String(contentsOf: url, encoding: .utf8) else {
            return []
        }

        var lines = contents.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard !lines.isEmpty else { return [] }
        lines.removeFirst() // header

        return lines.compactMap { line in
            guard !line.isEmpty else { return nil }
            let fields = line.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            guard fields.count == 4 else { return nil }
            return Exercise(id: fields[0], name: fields[1], primaryMuscle: fields[2], imageName: fields[3])
        }
    }
}
