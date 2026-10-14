//
//  BarrierChecks.swift
//  Role: item 3 of macTEM's asks (ADR 021): `HDF5Serial.exitBarrierBound` is public, so a host can show and test the
//        bound. This process also ends through `exit`, with the barrier installed by the Velox open above and no
//        thread stuck in HDF5: the handler must take the lock at once and return. `run.sh` checks the exit status
//        (not 70) and that the barrier's stderr line is absent.
//

import Foundation
import SpectroCore

func barrierChecks(_ r: inout Report) throws {
    let bound: TimeInterval = HDF5Serial.exitBarrierBound
    r.equal("HDF5Serial.exitBarrierBound is 10 s", bound, 10)
    let install: () -> Void = HDF5Serial.installExitBarrier   // existing public API, unchanged
    install()
    r.equal("HDF5Serial.exitBarrierBound is unchanged by installExitBarrier()", HDF5Serial.exitBarrierBound, 10)
}
