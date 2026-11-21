import SwiftUI

/// Trial / activation wall, aligned with Android `#licWall`.
///
/// NOT wired as a gate yet: `MembershiftApp` does not check the license
/// on launch in phase 1, and the Activate button does nothing (the
/// verifier is a stub — see `License.swift`). Phase 2 wires the gate
/// once the verification scheme is decided.
struct LicenseWallView: View {
    @State private var code = ""

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.fill")
                .font(.largeTitle)
                .foregroundColor(Brand.deepGreen)
            Text(L10n.string("lic_wall_title"))
                .font(.title2)
                .bold()
            Text(L10n.string("lic_wall_body"))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            TextField(L10n.string("lic_wall_code_placeholder"), text: $code)
                .textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
            Button(L10n.string("lic_wall_activate")) {
                // TODO (phase 2): StubLicenseVerifier().verify(code: code)
            }
            .buttonStyle(.borderedProminent)
            .tint(Brand.deepGreen)
            .disabled(code.isEmpty)
            Text(L10n.string("lic_wall_note"))
                .font(.footnote)
                .foregroundColor(.secondary)
            Spacer()
        }
        .padding(24)
    }
}
