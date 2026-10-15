// 메뉴 팝오버 — 기타 설정 화면.
import Cocoa
import SwiftUI
import ServiceManagement

// MARK: 기타 설정

struct OtherView: View {
    @EnvironmentObject var settings: PetSettings
    @EnvironmentObject var collector: Collector
    @EnvironmentObject var stages: Stages
    @State private var loginOn = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    var body: some View {
        Form {
            Section("보이기") {
                LabeledContent("투명도") {
                    Slider(value: $settings.opacity, in: 0.2...1)
                    Text("\(Int(settings.opacity * 100))%").monospacedDigit().frame(width: 40, alignment: .trailing)
                }
                LabeledContent("크기") {
                    Slider(value: $settings.size, in: 64...166, step: 2)
                    Text("\(Int(settings.size))px").monospacedDigit().frame(width: 48, alignment: .trailing)
                }
            }
            Section("앱") {
                Toggle("로그인할 때 자동으로 켜기", isOn: Binding(get: { loginOn }, set: setLogin))
                if let loginError { Text(loginError).font(.caption).foregroundStyle(.secondary) }
                LabeledContent("수집기") {
                    Text(collector.running ? "켜짐" : "꺼짐").foregroundStyle(collector.running ? .green : .red)
                    Button("다시 켜기") { collector.restart() }
                }
                Button("모든 고정 풀기") { stages.call("desk.unpinAll") }
                Button("화면 새로고침") { stages.reload() }
            }
            Section {
                Button("고양이 팀 종료") { NSApp.terminate(nil) }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("기타 설정")
    }

    private func setLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginError = nil
        } catch {
            loginError = "자동 실행을 바꾸지 못했어요. 시스템 설정 → 일반 → 로그인 항목에 고양이팀.app 을 직접 추가해 주세요."
        }
        loginOn = SMAppService.mainApp.status == .enabled
    }
}
