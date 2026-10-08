import Carbon.HIToolbox
import Foundation

protocol DragCancelKeying: AnyObject {
    var onPress: (() -> Void)? { get set }
    func register()
    func unregister()
}

/// Escape as a system-wide hot key, held only while a drag is in flight.
/// Drag Timer is not the front application during a drag, so the key would
/// otherwise go to whichever application is, and that application might act
/// on it. A hot key needs no Accessibility permission.
final class DragCancelKey: DragCancelKeying {
    var onPress: (() -> Void)?
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?

    deinit {
        unregister()
    }

    func register() {
        guard hotKey == nil else { return }
        var pressed = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData in
                guard let userData else { return OSStatus(eventNotHandledErr) }
                let key = Unmanaged<DragCancelKey>.fromOpaque(userData).takeUnretainedValue()
                // Not from inside the handler: cancelling the drag removes it.
                DispatchQueue.main.async { key.onPress?() }
                return noErr
            },
            1,
            &pressed,
            Unmanaged.passUnretained(self).toOpaque(),
            &handler
        )
        RegisterEventHotKey(
            UInt32(kVK_Escape),
            0,
            EventHotKeyID(signature: 0x4454_4553, id: 1), // "DTES"
            GetApplicationEventTarget(),
            0,
            &hotKey
        )
    }

    func unregister() {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let handler { RemoveEventHandler(handler) }
        hotKey = nil
        handler = nil
    }
}
