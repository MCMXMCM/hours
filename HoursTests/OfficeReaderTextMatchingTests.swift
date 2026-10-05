import XCTest
@testable import Hours

@MainActor
final class OfficeReaderTextMatchingTests: XCTestCase {
    func testSharedRunMatchesOriginalAlgorithmForEveryShortSequence() {
        let alphabet = ["et", "dominus", "meus"]
        var sequences: [[String]] = [[]]
        var level: [[String]] = [[]]
        for _ in 0..<4 {
            level = level.flatMap { prefix in alphabet.map { prefix + [$0] } }
            sequences += level
        }
        for left in sequences {
            for right in sequences {
                let expected = originalSharedRun(left, right)
                let actual = OfficeReaderSectionBuilder.longestSharedRun(left, right)
                if actual != expected {
                    XCTFail("Changed contiguous matching: \(left), \(right): \(actual) != \(expected)")
                    return
                }
            }
        }
    }

    func testRepeatedWordsAndLongExactPassagesKeepTheirFullRun() {
        let passage = (0..<300).map { "verbum\($0)" }
        XCTAssertEqual(OfficeReaderSectionBuilder.longestSharedRun(passage, passage), 300)
        XCTAssertEqual(OfficeReaderSectionBuilder.longestSharedRun(["incipit"] + passage + ["amen"], passage), 300)
        let repeated = Array(repeating: "dominus", count: 120)
        let separated = Array(repeated.prefix(70)) + ["et"] + Array(repeated.prefix(50))
        XCTAssertEqual(OfficeReaderSectionBuilder.longestSharedRun(repeated, separated), 70)
        XCTAssertEqual(OfficeReaderSectionBuilder.longestSharedRun(["a", "b", "c"], ["a", "x", "b", "c"]), 2)
    }

    private func originalSharedRun(_ left: [String], _ right: [String]) -> Int {
        var longest = 0
        for i in left.indices {
            for j in right.indices {
                var length = 0
                while i + length < left.count, j + length < right.count,
                      left[i + length] == right[j + length] {
                    length += 1
                }
                longest = max(longest, length)
            }
        }
        return longest
    }
}
