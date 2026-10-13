// SpectroKit S1 test partition (ADR 064 section 3.3): the methods of QuantificationMethodTests that move with the EDX core;
// the rest stay in MethodTests.swift. Helpers are duplicated, not shared, across the split.
//
//  MethodTests.swift
//  v5.0 WP3 lane M (prediction M1, first half): the quantification method as a byte-stable value with a hash,
//  and the replay step "quantification" with its input edges and its rewind. Each test names the mutation it
//  catches; each was broken once.
//
import XCTest
import SpectroCore

@MainActor
final class QuantificationMethodSpectro: XCTestCase {

    private func richMethod() -> QuantificationMethod {
        var m = QuantificationMethod()
        m.estimator = .poissonMaximumLikelihood
        m.background = .wholeRangePolynomial6
        m.elements = [
            .init(symbol: "Mg", role: .quantify, isManual: true),
            .init(symbol: "Si", role: .quantify, isManual: false),
            .init(symbol: "Cu", role: .fitOnly, isManual: false),
        ]
        m.kFactorSource = .typed
        m.kSource = "Williams & Carter, table 4"
        m.kDate = "2026-10-06"
        m.kReference = "Si"
        m.typedK = [.init(element: "Mg", k: 1.12, relativeSigma: 0.1), .init(element: "Si", k: 1)]
        m.absorptionCorrection = false
        m.thickness = .init(nanometres: 55, sigmaNanometres: 5)
        return m
    }

    /// P1: encode -> decode -> encode is byte-identical, equal methods hash equal, and any one field moves the hash.
    /// Mutations: drop `.sortedKeys` (key order is unspecified, red on repeated encodes in one process is not
    /// guaranteed - the hash-sensitivity half catches the next one); hash `estimator` out of the JSON (drop it
    /// from CodingKeys by making it computed) - the field loop goes red.
    func testRoundTripIsByteIdenticalAndTheHashSeesEveryField() throws {
        let m = richMethod()
        let json = m.canonicalJSON
        let back = try XCTUnwrap(QuantificationMethod.decode(json))
        XCTAssertEqual(back, m)
        XCTAssertEqual(back.canonicalJSON, json)
        XCTAssertEqual(back.hash, m.hash)
        XCTAssertEqual(m.hash.count, 64)
        XCTAssertTrue(json.hasPrefix("{\"absorptionCorrection\":false"), "sorted keys: \(json.prefix(40))")

        var seen: Set<String> = [m.hash]
        let edits: [(String, (inout QuantificationMethod) -> Void)] = [
            ("estimator", { $0.estimator = .leastSquares }),
            ("background", { $0.background = .empiricalWithAlEdge }),
            ("element role", { $0.elements[2].role = .off }),
            ("k source text", { $0.kSource += "." }),
            ("typed k", { $0.typedK[0].k = 1.13 }),
            ("sigma_k", { $0.sigmaK = 0.25 }),
            ("absorption", { $0.absorptionCorrection = true }),
            ("thickness", { $0.thickness?.sigmaNanometres = 6 }),
            ("no thickness", { $0.thickness = nil }),
        ]
        for (name, edit) in edits {
            var e = m
            edit(&e)
            XCTAssertTrue(seen.insert(e.hash).inserted, "\(name) did not change the hash")
        }
    }

    /// The default method's hash is pinned: a silent change to a default or to the encoding moves it.
    /// (Recorded from the first run, not predicted - see the lane report.)
    /// Mutation: change any default (e.g. `sigmaK = 0.2` -> `0.3`) — red.
    func testTheDefaultMethodHashIsPinned() {
        XCTAssertEqual(QuantificationMethod().hash, "3fd1c05d3e9bfbd6e70349ad1139c60aa6ce07010b4a50a8be382b8b49f9e1f6")
    }

    /// A method this build cannot read is refused, never read as another one.
    /// Mutation: drop the `version <= currentVersion` guard in `decode` — red.
    func testANewerVersionAndGarbageAreRefused() {
        var future = QuantificationMethod()
        future.version = QuantificationMethod.currentVersion + 1
        XCTAssertNil(QuantificationMethod.decode(future.canonicalJSON))
        XCTAssertNil(QuantificationMethod.decode("{not json"))
        for v in [0, -1] {
            var old = QuantificationMethod(); old.version = v
            XCTAssertNil(QuantificationMethod.decode(old.canonicalJSON), "version \(v)")
        }
    }

    /// A typed k needs a source, a date and a k for every quantified element, and builds lane K's set with the
    /// reference's sigma at 0 (WP3 flag 5).
    /// Mutations: drop the source check in `isComplete`; give the reference the default sigma — red.
    func testATypedKNeedsItsSourceAndBuildsTheSet() throws {
        var m = richMethod()
        XCTAssertTrue(m.isComplete)
        let set = try XCTUnwrap(m.typedKFactorSet())
        XCTAssertEqual(set.kind, .typed)
        XCTAssertEqual(set.k("Mg"), 1.12)
        XCTAssertEqual(set.relSigma("Mg"), 0.1)
        XCTAssertEqual(set.relSigma("Si"), 0, "the reference element carries no sigma")
        XCTAssertEqual(set.source, "Williams & Carter, table 4")
        m.kSource = "  "
        XCTAssertFalse(m.isComplete)
        XCTAssertNil(m.typedKFactorSet(), "no source, no k")
        m.kSource = "x"; m.typedK.removeFirst()
        XCTAssertFalse(m.isComplete, "Mg is quantified and has no k")
        XCTAssertNil(QuantificationMethod().typedKFactorSet(), "computed k is not a typed set")
    }

    /// A computed choice records the table identity, not the run date, so identical choices hash identically.
    /// Mutation: `useComputedK` stamping `Date()` into `kDate` — red.
    func testAComputedKRecordsTheTableIdentityNotTheDay() {
        var a = QuantificationMethod(), b = QuantificationMethod()
        a.useComputedK(sourceDescription: "computed: Bote-Salvat; omega: Krause 1979; epsilon: EPQ SDD")
        b.useComputedK(sourceDescription: "computed: Bote-Salvat; omega: Krause 1979; epsilon: EPQ SDD")
        XCTAssertEqual(a.kDate, QuantificationMethod.computedKTableIdentity)
        XCTAssertEqual(a.hash, b.hash)
        XCTAssertFalse(a.kDate.contains("2026"), "no run date")
    }
}
