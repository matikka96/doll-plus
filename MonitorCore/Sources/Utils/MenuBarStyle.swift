public enum BadgeStyle {
    case number, redBadge, iconOnly

    public init(showAsRedBadge: Bool, showOnlyAppIcon: Bool) {
        if showOnlyAppIcon {
            self = .iconOnly
        } else {
            self = showAsRedBadge ? .redBadge : .number
        }
    }

    public var showAsRedBadge: Bool { self == .redBadge }
    public var showOnlyAppIcon: Bool { self == .iconOnly }
}

public enum NothingNewStyle {
    case show, dim, hide

    // Before the picker, both switches could be on, and Hide took effect.
    public init(grayoutIcon: Bool, hide: Bool) {
        if hide {
            self = .hide
        } else {
            self = grayoutIcon ? .dim : .show
        }
    }

    public var grayoutIcon: Bool { self == .dim }
    public var hide: Bool { self == .hide }
}
