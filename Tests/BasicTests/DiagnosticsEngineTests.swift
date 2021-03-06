/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import XCTest

import Basic

// FIXME: We should just move this to Basic.
private struct StringDiagnostic: DiagnosticData {
    static let id = DiagnosticID(
        type: StringDiagnostic.self,
        name: "org.swift.diags.string-diagnostic",
        description: {
             $0 <<< { $0.str }
        }
    )

    let str: String

    init(_ str: String) {
        self.str = str
    }
}

fileprivate struct FooDiag: DiagnosticData {
    static let id = DiagnosticID(
        type: FooDiag.self,
        name: "org.swift.diags.tests.cycle",
        description: {
             $0 <<< "literal"
             $0 <<< { $0.arr.joined(separator: ", ") }
             $0 <<< { $0.int }
             $0 <<< { $0.str }
             $0 <<< .literal("bar", preference: .high)
             $0 <<< .substitution({ ($0 as! FooDiag).str }, preference: .low)
        }
    )

    let arr: [String]
    let str: String
    let int: Int
}

fileprivate struct FooLocation: DiagnosticLocation {
    let name: String

    var localizedDescription: String {
        return name
    }
}

class DiagnosticsEngineTests: XCTestCase {
    func testBasics() {
        let diagnostics = DiagnosticsEngine() 
        diagnostics.emit(
            data: FooDiag(arr: ["foo", "bar"], str: "str", int: 2),
            location: FooLocation(name: "foo loc")
        )
        let diag = diagnostics.diagnostics[0]

        XCTAssertEqual(diagnostics.diagnostics.count, 1)
        XCTAssertEqual(diag.location.localizedDescription, "foo loc")
        XCTAssertEqual(diag.localizedDescription, "literal foo, bar 2 str bar str")
        XCTAssertEqual(diag.behavior, .error)

        let id = diag.id
        XCTAssertEqual(id.name, "org.swift.diags.tests.cycle")
        XCTAssertEqual(id.defaultBehavior, .error)

        var result = ""
        for fragment in id.description {
            switch fragment {
            case let .literalItem(string, pref):
                result += string + "\(pref)"
            case let .substitutionItem(accessor, pref):
                result += accessor(diag.data).diagnosticDescription + "\(pref)"
            }
        }
        XCTAssertEqual(result, "literaldefaultfoo, bardefault2defaultstrdefaultbarhighstrlow")
    }

    func testMerging() {
        let engine1 = DiagnosticsEngine() 
        engine1.emit(
            data: FooDiag(arr: ["foo", "bar"], str: "str", int: 2),
            location: FooLocation(name: "foo loc")
        )
        XCTAssertEqual(engine1.diagnostics.count, 1)

        let engine2 = DiagnosticsEngine() 
        engine2.emit(
            data: FooDiag(arr: ["foo", "bar"], str: "str", int: 2),
            location: FooLocation(name: "foo loc")
        )
        engine2.emit(
            data: FooDiag(arr: ["foo", "bar"], str: "str", int: 2),
            location: FooLocation(name: "foo loc")
        )
        XCTAssertEqual(engine2.diagnostics.count, 2)

        engine1.merge(engine2)
        XCTAssertEqual(engine1.diagnostics.count, 3)
        XCTAssertEqual(engine2.diagnostics.count, 2)
    }

    func testHandlers() {
        var handledDiagnostics: [Diagnostic] = []
        let handler: DiagnosticsEngine.DiagnosticsHandler = { diagnostic in 
            handledDiagnostics.append(diagnostic)
        }

        let diagnostics = DiagnosticsEngine(handlers: [handler])
        let location = FooLocation(name: "location")
        diagnostics.emit(
            data: FooDiag(arr: ["foo", "bar"], str: "str", int: 2),
            location: location
        )
        diagnostics.emit(data: StringDiagnostic("diag 2"), location: location)
        diagnostics.emit(data: StringDiagnostic("end"), location: location)

        XCTAssertEqual(handledDiagnostics.count, 3)
        for diagnostic in handledDiagnostics {
            XCTAssertEqual(diagnostic.location.localizedDescription, location.localizedDescription)
        }
        XCTAssertEqual(handledDiagnostics[0].localizedDescription, "literal foo, bar 2 str bar str")
        XCTAssertEqual(handledDiagnostics[1].localizedDescription, "diag 2")
        XCTAssertEqual(handledDiagnostics[2].localizedDescription, "end")
    }

    static var allTests = [
        ("testBasics", testBasics),
        ("testMerging", testMerging),
        ("testHandlers", testHandlers),
    ]
}
