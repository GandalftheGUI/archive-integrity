import DiskArbitration
import Foundation

// Global C-compatible callbacks — context carries an unretained DiskMonitor reference.
private func onDiskAppeared(_ disk: DADisk, _ context: UnsafeMutableRawPointer?) {
    guard let context else { return }
    Unmanaged<DiskMonitor>.fromOpaque(context).takeUnretainedValue().handle(disk)
}

final class DiskMonitor {
    /// Called on the main actor whenever a volume mounts.
    var onVolumeAppeared: (@Sendable (String, String?) -> Void)?

    private var session: DASession?
    private var selfPtr: UnsafeMutableRawPointer?

    func start() {
        guard session == nil else { return }

        session = DASessionCreate(kCFAllocatorDefault)
        guard let session else { return }

        // Deliver callbacks on the main run loop.
        DASessionScheduleWithRunLoop(session, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)

        selfPtr = Unmanaged.passRetained(self).toOpaque()
        DARegisterDiskAppearedCallback(session, nil, onDiskAppeared, selfPtr)
    }

    deinit {
        if let ptr = selfPtr {
            Unmanaged<DiskMonitor>.fromOpaque(ptr).release()
        }
    }

    // Called from the C callback on the main run loop.
    fileprivate func handle(_ disk: DADisk) {
        guard let desc = DADiskCopyDescription(disk) as? [String: Any],
              let cfURL = desc[kDADiskDescriptionVolumePathKey as String] as? URL
        else { return }

        let path = cfURL.path

        // Resolve UUID via URLResourceValues — more reliable than the CF type in the dict.
        let uuid = (try? cfURL.resourceValues(forKeys: [.volumeUUIDStringKey]))?.volumeUUIDString

        onVolumeAppeared?(path, uuid)
    }
}
