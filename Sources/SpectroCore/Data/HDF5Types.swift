import Foundation

/// HDF5 C ABI scalar aliases shared by the dynamic reader and writer.
public typealias hid_t = Int64
public typealias herr_t = Int32
public typealias hsize_t = UInt64

/// EVERY HDF5 CALL IN THE PROCESS RUNS UNDER THIS LOCK (2026-09-15 night).
///
/// The bundled libhdf5 is built `Threadsafety: OFF`, and it was entered from
/// two unserialised paths — `H5Reader`, an actor per instance, and
/// `BraggVectorEMDWriter`, a nonisolated enum with its own `dlopen`.
/// `tools/hdf5-race-probe` reproduces the crash: serial completes, concurrent
/// dies with SIGBUS inside the first twenty iterations. This is HDF5's own
/// thread-safe build done from outside — its `H5_API_LOCK` is a global mutex
/// around every API call; this one is around every logical operation (an
/// open, a tile read, a sidecar write), recursive so nested entries (write →
/// publish → …) do not deadlock, and NEVER held across an `await`: the
/// tile-streaming export releases it before it reads the next tile from the
/// source actor, and re-takes it to write. A caller that blocks on it blocks
/// its thread for the length of one operation, which is the cost of a
/// library that cannot be entered twice. Gate B (2026-09-15 late night)
/// found two entry points that opened the file themselves and took nothing
/// — `loadResultMap(id:)` and `loadRGBAResultMap(id:)`, reached by clicking
/// a saved result — and crashed the probe's variant on the first attempt;
/// the audit is by grep for `HDF5WriteLibrary.load()` and `HDF5Library.load()`:
/// every one must sit under this lock, because `H5open` is an API call too.
public nonisolated enum HDF5Serial {
    private static let lock = NSRecursiveLock()
    public static func run<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock(); defer { lock.unlock() }
        return try body()
    }
    /// For the one synchronous stretch that must outlive a closure's scope
    /// (the export's dataset setup, whose handles the loop below it uses).
    /// Pair on the same thread, and never span an `await`.
    public static func acquire() { lock.lock() }
    public static func release() { lock.unlock() }

    /// THE QUIT BARRIER (Slot 4¾ review, 2026-10-02). `exit()`, where every
    /// Quit ends, runs HDF5's own atexit handler `H5_term_library`, which takes
    /// no lock of ours: a Task still inside `H5Dread` raced the teardown and
    /// the process crashed at quit (`tools/hdf5-exit-race-test`). This handler
    /// takes the lock and never gives it back. HDF5 registers its handler once
    /// per process, inside the first `H5open`, and atexit runs last-registered
    /// first — so all three loaders (H5Reader, the sidecar writer, VeloxEMDReader) call this right after a successful `H5open`:
    /// exit waits for the one call in flight, then HDF5 tears down with no
    /// other thread able to enter. The lock is recursive, so an exit on a
    /// thread that holds it goes straight through; nothing that holds it waits
    /// on the main thread. Cost: a quit waits for at most one locked operation.
    public static func installExitBarrier() {
        lock.lock(); defer { lock.unlock() }
        guard !exitBarrierInstalled else { return }
        exitBarrierInstalled = atexit { HDF5Serial.acquire() } == 0
    }
    /// Owned by `HDF5Serial`; read and written only under `lock`.
    nonisolated(unsafe) private static var exitBarrierInstalled = false
}
