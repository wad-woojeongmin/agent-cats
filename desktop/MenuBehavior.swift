// 메뉴 팝오버 — 행동 설정 화면.
import SwiftUI

// MARK: 행동 설정

struct BehaviorView: View {
    @EnvironmentObject var settings: PetSettings
    @EnvironmentObject var router: Router

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(title: "행동 설정")
            Divider()
            form
        }
        .onExitCommand { router.pop() }
    }

    private var form: some View {
        Form {
            Section("행동") {
                ForEach(PetSettings.behaviors) { b in
                    Toggle(isOn: Binding(get: { settings.isOn(b.id) }, set: { settings.behaviors[b.id] = $0 })) {
                        Label(b.title, systemImage: b.symbol)
                    }
                    .disabled(b.id == "icons" && settings.iconsDenied)
                }
                if settings.iconsDenied {
                    Text("Finder 자동화 권한이 없어서 폴더와 놀 수 없어요. 시스템 설정 → 개인정보 보호 및 보안 → 자동화에서 고양이팀의 Finder 를 켜 주세요.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Section("활동량") {
                HStack {
                    Text("느긋하게").font(.caption)
                    Slider(value: $settings.activity, in: 0...1)
                    Text("활발하게").font(.caption)
                }
            }
            Section("말풍선") {
                Picker("상태 말풍선", selection: $settings.bubbleSec) {
                    Text("끔").tag(0)
                    Text("30초").tag(30)
                    Text("1분").tag(60)
                    Text("3분").tag(180)
                }
                .pickerStyle(.segmented)
                Text("고양이를 클릭하면 언제든 자세한 말풍선이 떠요.").font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
