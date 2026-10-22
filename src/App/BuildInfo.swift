import Foundation

enum BuildInfo {
    /// Name of this build, such as `build-30-1bca82e` (or `0.3.0` for `main`). It is set
    /// at build time through `VigiliaBuildName` in Info.plist (see `build.sh` and the workflow).
    static let name: String = Bundle.main.object(forInfoDictionaryKey: "VigiliaBuildName") as? String ?? "desconocido"
}
