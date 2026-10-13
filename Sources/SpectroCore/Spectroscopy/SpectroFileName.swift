//
//  SpectroFileName.swift
//  Role: The file name an error or a metadata line shows, never the whole path. A copy of `displayFileName`
//        (Core/Data/FourDDataSource.swift) so the spectroscopy code, the Velox reader and the DM4 experiment reader
//        need nothing from the 4D layer; keep the two in step (SpectroKit S1, plan E2).
//

import Foundation

package nonisolated func spectroDisplayFileName(_ path: String) -> String {
    let name = (path as NSString).lastPathComponent
    return name.isEmpty ? path : name
}
