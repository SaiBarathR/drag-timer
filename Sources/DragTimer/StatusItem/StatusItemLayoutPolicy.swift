enum StatusItemLayoutMode: Equatable {
    case collapsed
    case expanded
}

/// Keeps the popover's anchor geometry stable while it is visible. Timer state
/// may change inside the popover, but its status-item anchor must not resize
/// until the popover has closed.
enum StatusItemLayoutPolicy {
    static func mode(hasRunningTimer: Bool, isPopoverVisible: Bool) -> StatusItemLayoutMode {
        hasRunningTimer || isPopoverVisible ? .expanded : .collapsed
    }
}
