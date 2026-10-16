public enum RedBadgeLabel {
    private static let largeCountLabel = "99+"
    private static let longTextLabel = "•"
    private static let groupingSeparators: Set<Character> = [",", ".", " ", "\u{00A0}", "\u{202F}", "'"]

    public static func text(for badge: String, fits: (String) -> Bool) -> String {
        if isCountAbove99(badge) {
            return largeCountLabel
        }
        return fits(badge) ? badge : longTextLabel
    }

    private static func isCountAbove99(_ badge: String) -> Bool {
        let number = badge.hasSuffix("+") ? badge.dropLast() : Substring(badge)
        let digits = number.filter { !groupingSeparators.contains($0) }
        return number.first?.isWholeNumber == true
            && digits.allSatisfy(\.isWholeNumber)
            && digits.drop(while: { $0 == "0" }).count > 2
    }
}
