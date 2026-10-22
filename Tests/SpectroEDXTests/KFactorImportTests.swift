//
//  KFactorImportTests.swift
//  Role: the k-factor table importer (SpectroKit 0.10.0) on planted text: every layout it reads, the typed list it makes, and
//        each refusal by name. The convention pin against exSpy is in SpectroKitParityTests/KFactorImportPinsTests.
//

import Foundation
import Testing
import SpectroEDX

struct KFactorImportTests {

    @Test func tabSeparatedWithHeaderAndSigma() throws {
        let t = try KFactorImport.parse("Element\tLine\tk-factor\tSigma\nAl\tKa\t1.00\t0.05\nSi\tKa\t1,13\t0.11\nFe\tK\t1.80\t\n")
        #expect(t.header != nil)
        #expect(t.rows.map(\.element) == ["Al", "Si", "Fe"])
        #expect(t.rows.map(\.line) == ["Ka", "Ka", "Ka"])
        #expect(t.rows.map(\.k) == [1.0, 1.13, 1.8])
        #expect(t.rows.map(\.sigma) == [0.05, 0.11, nil])
    }

    @Test func semicolonWithDecimalCommaAndNoHeader() throws {
        let t = try KFactorImport.parse("Mg;K;1,02;0,2\nAl;Ka;1,00\n")
        #expect(t.header == nil)
        #expect(t.rows.map(\.k) == [1.02, 1.0])
        #expect(t.rows[0].sigma == 0.2 && t.rows[1].sigma == nil)
    }

    @Test func commaSeparatedAndGreekAndSeriesNames() throws {
        let t = try KFactorImport.parse("Ti,K\u{03B1},1.2\nCu,L-series,3.1\nZn,K-alpha,1.4\nSn,La1,2.0\nFe,Kb,5\n")
        #expect(t.rows.map(\.line) == ["Ka", "La", "Ka", "La", "Kb"])
    }

    @Test func elementAndLineInOneFieldUnitsLineAndCommentsAreIgnored() throws {
        let t = try KFactorImport.parse("\u{FEFF}Units: k relative to Si\n# exported 2026-10-22\n\nFe K\t1.5\nCu-K\t1.9\nNi_Ka\t1.7\n")
        #expect(t.rows.map(\.element) == ["Fe", "Cu", "Ni"])
        #expect(t.rows.map(\.k) == [1.5, 1.9, 1.7])
        #expect(t.ignored.count == 2)
    }

    @Test func percentSigmaColumnIsRelative() throws {
        let t = try KFactorImport.parse("Element;Line;k;Sigma %\nAl;Ka;1.0;10\nSi;Ka;2.0;5\n")
        #expect(t.rows[0].sigma == 0.1 && abs(t.rows[1].sigma! - 0.1) < 1e-15)
        let typed = try KFactorImport.typedK(from: t, elements: ["Al", "Si"])
        #expect(abs(typed[0].relativeSigma! - 0.1) < 1e-15 && abs(typed[1].relativeSigma! - 0.05) < 1e-15)
    }

    @Test func theSeparatorIsReadFromTheDataLinesAndDecimalCommasSurviveWhitespace() throws {
        // a comma in a comment or units line must not pick the separator; the table is whitespace separated with decimal commas
        let t = try KFactorImport.parse("# exported by lab, 2026\nunits: k, relative to Si\nFe Ka 1,23\nCu Ka 1,9 0,05\n")
        let ks: [Double] = t.rows.map(\.k), sigmas: [Double?] = t.rows.map(\.sigma)
        #expect(ks == [1.23, 1.9] && sigmas == [nil, 0.05])
        // a tab table whose comment has a semicolon
        let u = try KFactorImport.parse("# a; b\nFe\tKa\t1.5\n")
        #expect(u.rows.map(\.k) == [1.5])
        // "Fe K,1.23" stays comma separated
        #expect(try KFactorImport.parse("Fe K,1.23\n").rows.map(\.k) == [1.23])
    }

    @Test func aPercentSigmaIsReadWhereverItIsWritten() throws {
        let t = try KFactorImport.parse("Al;Ka;2.0;5%\nSi;Ka;2.0;5 %\nFe;Ka;2.0;0,1\n")
        let expected: Double = 5.0 / 100 * 2.0
        let sigmas: [Double?] = t.rows.map(\.sigma)
        #expect(sigmas == [expected, expected, 0.1])
        let header = try KFactorImport.parse("Element;Line;k;Sigma %\nAl;Ka;2.0;5%\n")
        #expect(header.rows[0].sigma == expected)
    }

    @Test func aNonFiniteResultIsRefused() throws {
        #expect(throws: KFactorImportError.self) { _ = try KFactorImport.parse("Al,Ka,1e308,1e308%\n") }
        let t = try KFactorImport.parse("Al,Ka,1e308\nSi,Ka,1e-308\n")
        #expect(throws: KFactorImportError.self) { _ = try KFactorImport.typedK(from: t, elements: ["Al", "Si"], reference: "Si") }
    }

    @Test func headerColumnOrderIsTakenFromTheNames() throws {
        let t = try KFactorImport.parse("k;Sigma;Line;Element\n1.5;0.1;Ka;Fe\n")
        #expect(t.rows == [ImportedKFactor(element: "Fe", line: "Ka", k: 1.5, sigma: 0.1, sourceLine: 2)])
    }

    @Test func typedListWithReferenceRescalesAndZeroesTheReferenceSigma() throws {
        let t = try KFactorImport.parse("Al,Ka,2.0,0.2\nSi,Ka,3.0,0.3\nFe,Ka,5.0\n")
        let typed = try KFactorImport.typedK(from: t, elements: ["Al", "Si", "Fe"], reference: "Al")
        #expect(typed.map(\.element) == ["Al", "Si", "Fe"])
        #expect(typed.map(\.k) == [1.0, 1.5, 2.5])
        #expect(typed[0].relativeSigma == 0)
        #expect(abs(typed[1].relativeSigma! - 0.1) < 1e-15)
        #expect(typed[2].relativeSigma == nil)
        let cl = try KFactorImport.cliffLorimerFactors(from: t, elements: ["Al", "Si", "Fe"], reference: "Al")
        #expect(cl.k == [1.0, 1.5, 2.5] && cl.relativeSigma[2] == QuantificationMethod.defaultSigmaK)
    }

    @Test func applyFillsTheMethodAndMakesItComplete() throws {
        var m = QuantificationMethod()
        m.elements = [.init(symbol: "Al", role: .quantify, isManual: false), .init(symbol: "Si", role: .quantify, isManual: false),
                      .init(symbol: "O", role: .off, isManual: false)]
        let t = try KFactorImport.parse("Al,Ka,1.0\nSi,Ka,1.13\nO,Ka,4\n")
        try KFactorImport.apply(t, to: &m, source: "Velox export, project X", date: "2026-10-22", reference: "Al")
        #expect(m.kFactorSource == .typed && m.kReference == "Al" && m.kDate == "2026-10-22")
        #expect(m.typedK.map(\.element) == ["Al", "Si"])
        #expect(m.isComplete)
    }

    @Test func eachRefusalIsNamedWithItsLine() {
        func err(_ text: String) -> KFactorImportError? {
            do { _ = try KFactorImport.parse(text); return nil } catch { return error as? KFactorImportError }
        }
        #expect(err("") == .noRows)
        #expect(err("# only a comment\nunits: none\n") == .noRows)
        #expect(err("Al,Ka\n") == .tooFewFields(line: 1, text: "Al Ka"))
        #expect(err("Al,Ka,1\nXx,Ka,1.2\n") == .unknownElement(line: 2, symbol: "Xx"))
        #expect(err("Al,Ka,1\nSi,Ka,abc\n") == .badK(line: 2, text: "abc"))
        #expect(err("Al,Ka,0\n") == .badK(line: 1, text: "0"))
        #expect(err("Al,Ka,-1.2\n") == .badK(line: 1, text: "-1.2"))
        #expect(err("Al,Ka,1,-0.1\n") == .badSigma(line: 1, text: "-0.1"))
        #expect(err("Al,Ka,1,x\n") == .badSigma(line: 1, text: "x"))
        #expect(err("Al,Zz,1\n") == .unknownLine(line: 1, text: "Zz"))
        #expect(err("Al,Ka,1\nAl,Ka,1.1\n") == .duplicate(element: "Al", line: "Ka", sourceLine: 2))
        #expect(err("Name,Line,k\nAl,Ka,1\n") == .missingColumn("element"))
        #expect(err("Element,Line,Value\nAl,Ka,1\n") == .missingColumn("k"))
        #expect(KFactorImportError.badK(line: 2, text: "abc").errorDescription?.contains("line 2") == true)
    }

    @Test func typedListRefusesAMissingRowAndAForeignReference() throws {
        let t = try KFactorImport.parse("Al,Ka,1\nSi,La,2\n")
        #expect(throws: KFactorImportError.noEntry(element: "Si", line: "Ka")) { _ = try KFactorImport.typedK(from: t, elements: ["Al", "Si"]) }
        #expect(throws: KFactorImportError.referenceNotInSet("Fe")) { _ = try KFactorImport.typedK(from: t, elements: ["Al"], reference: "Fe") }
        let l = try KFactorImport.typedK(from: t, elements: ["Si"], line: "La")
        #expect(l[0].k == 2)
    }
}
