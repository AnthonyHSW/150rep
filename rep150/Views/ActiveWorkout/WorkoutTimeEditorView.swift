import SwiftUI

/// Corrects when a workout happened.
///
/// Start and end are edited together rather than offering a duration field, because duration
/// is derived from them everywhere else — letting it be typed would mean deciding which of the
/// two timestamps a 45-minute workout moved, and either choice is wrong half the time.
struct WorkoutTimeEditorView: View {
    /// Whether the workout has finished. A live one has no end to edit — it is still being
    /// decided — so the sheet offers only its start.
    let isFinished: Bool
    let originalStart: Date
    let originalEnd: Date?
    let onSave: (Date, Date?) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var start: Date
    @State private var end: Date

    /// Upper bound for both pickers. A workout can't have happened in the future, but a
    /// stored timestamp already past "now" — a clock that was wrong, or a session edited
    /// across a time-zone change — has to stay reachable, or the picker silently rewrites it.
    private let latestSelectable: Date

    init(isFinished: Bool, originalStart: Date, originalEnd: Date?, onSave: @escaping (Date, Date?) -> Void) {
        self.isFinished = isFinished
        self.originalStart = originalStart
        self.originalEnd = originalEnd
        self.onSave = onSave

        let fallbackEnd = originalEnd ?? originalStart
        _start = State(initialValue: originalStart)
        _end = State(initialValue: fallbackEnd)
        latestSelectable = max(Date(), originalStart, fallbackEnd)
    }

    /// Only meaningful for a finished workout; a running one has no end to measure to.
    private var duration: TimeInterval {
        max(0, end.timeIntervalSince(start))
    }

    private var hasChanges: Bool {
        start != originalStart || (isFinished && end != (originalEnd ?? originalStart))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker(
                        "Started",
                        selection: $start,
                        in: ...latestSelectable,
                        displayedComponents: [.date, .hourAndMinute]
                    )

                    if isFinished {
                        DatePicker(
                            "Ended",
                            selection: $end,
                            in: start...latestSelectable,
                            displayedComponents: [.date, .hourAndMinute]
                        )
                    }
                } footer: {
                    if isFinished {
                        Text("Duration: \(duration.workoutClockText)")
                            .monospacedDigit()
                    } else {
                        // Still running, so its duration keeps growing from whatever start
                        // is chosen — describing it as a fixed length would be a lie.
                        Text("This workout is still running, so it keeps counting from the start time you pick.")
                    }
                }
            }
            .navigationTitle("Workout Time")
            .navigationBarTitleDisplayMode(.inline)
            // A start dragged past the end would leave the end picker with an empty range.
            // Carrying the end along keeps the workout at the length the user had set,
            // rather than collapsing it to nothing.
            .onChange(of: start) { _, newStart in
                if end < newStart { end = newStart }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(start, isFinished ? end : nil)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(!hasChanges)
                }
            }
        }
    }
}

#Preview {
    WorkoutTimeEditorView(
        isFinished: true,
        originalStart: Date().addingTimeInterval(-7200),
        originalEnd: Date().addingTimeInterval(-3600),
        onSave: { _, _ in }
    )
}
