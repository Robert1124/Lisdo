import Foundation

public enum LisdoVoiceCapturePolicy {
    public static let maximumDurationSeconds: TimeInterval = 60
    public static let maximumDurationNanoseconds = UInt64(maximumDurationSeconds * 1_000_000_000)
}
