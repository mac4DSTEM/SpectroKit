//
//  UnlistedLineCheckChecks.swift
//  Role: `UnlistedLineCheck` built and read from outside the package: its `Candidate` and `Move` initialisers and fields, the
//        check's own initialiser, and what it says from them. mac4DSTEM's tests built these through `@testable import`.
//        Only public API is named.
//

import Foundation
import SpectroCore
import SpectroEDX

func unlistedLineCheckChecks(_ r: inout Report) {
    let ge = UnlistedLineCheck.Candidate(element: "Ge", group: "Ge_Ka", net: 1200, detectionLimit: 300, sumPeakQuestion: false)
    let excess = UnlistedLineCheck.Candidate(element: "Si", group: "Si_Ka", net: 400, detectionLimit: 150, sumPeakQuestion: true,
                                             besideLine: "Al K\u{03B1}", fractionOfNeighbour: 0.02)
    let move = UnlistedLineCheck.Move(element: "Al", before: 9000, after: 8700, sigma: 120)
    let check = UnlistedLineCheck(candidates: [ge, excess], moves: [move], largest: move)

    r.equal("Candidate fields read back", [ge.element, ge.group, excess.besideLine ?? ""], ["Ge", "Ge_Ka", "Al K\u{03B1}"])
    r.equal("Candidate.proposerLabel names the proposer's group", ge.proposerLabel, "Ge K\u{03B1}")
    r.equal("Candidate.shownName is the symbol clear of a listed line", ge.shownName, "Ge")
    r.check("Candidate.shownName names an excess beside a listed line", excess.shownName.hasPrefix("unexplained excess beside Al K\u{03B1}"),
            excess.shownName)
    r.equal("Move fields read back", [move.before, move.after, move.sigma], [9000, 8700, 120])
    r.equal("the check keeps its candidates, moves and largest move", [check.candidates.count, check.moves.count], [2, 1])
    r.equal("the largest move is the one given", check.largest, move)
    r.equal("only a candidate clear of every listed line is an element", check.elementNames, ["Ge"])
    r.check("the line names what was found", check.line.hasPrefix("Unlisted lines found: Ge, unexplained excess"), check.line)
}
