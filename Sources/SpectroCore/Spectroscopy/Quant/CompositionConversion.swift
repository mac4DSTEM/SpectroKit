//
//  CompositionConversion.swift
//  Role: weight <-> atomic composition for a list of elements.
//
//  Port of eXSpy material/_material.py `_weight_to_atomic` / `_atomic_to_weight`
//  (lines 36-78, 123-165, 7185a4d1). Inputs are in any consistent unit (fractions
//  or percent); outputs are percent-normalised exactly as eXSpy returns them:
//  the sum of the output is 100 (or 0 when the input sums to 0).
//

import Foundation

package nonisolated enum CompositionConversion {
    package static func weightToAtomic(_ weight: [Double], elements: [String]) throws -> [Double] {
        try convert(weight, elements: elements, divide: true)
    }

    package static func atomicToWeight(_ atomic: [Double], elements: [String]) throws -> [Double] {
        try convert(atomic, elements: elements, divide: false)
    }

    private static func convert(_ x: [Double], elements: [String], divide: Bool) throws -> [Double] {
        guard x.count == elements.count else {
            throw QuantError.countMismatch("The number of elements must match the number of composition entries.")
        }
        var a: [Double] = []
        for (v, el) in zip(x, elements) {
            guard let w = QuantElementData.entry(el)?.atomicWeight else { throw QuantError.unknownElement(el) }
            a.append(divide ? v / w : v * w)
        }
        let sum = a.reduce(0, +) / 100
        if sum == 0 { return a.map { _ in 0 } }
        return a.map { $0 / sum }
    }
}
