import Foundation

enum RuntimeCompatibility {
    static var architectureLabel: String {
        #if arch(arm64)
        return "Apple Silicon · arm64"
        #elseif arch(x86_64)
        return "Intel · x86_64"
        #else
        return "当前架构"
        #endif
    }
}
