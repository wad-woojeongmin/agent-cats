// 메뉴 팝오버 — 기타 설정 화면.
import Cocoa
import SwiftUI
import ServiceManagement

// MARK: 기타 설정

struct OtherView: View {
    @EnvironmentObject var settings: PetSettings
    @EnvironmentObject var feed: StatusFeed
    @EnvironmentObject var stages: Stages
    @EnvironmentObject var router: Router
    @State private var loginOn = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?
    @State private var skillNote: String?

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(title: "기타 설정")
            Divider()
            form
        }
        .onExitCommand { router.pop() }
    }

    private var form: some View {
        Form {
            Section("앱") {
                Toggle("로그인할 때 자동으로 켜기", isOn: Binding(get: { loginOn }, set: setLogin))
                if let loginError { Text(loginError).font(.caption).foregroundStyle(.secondary) }
                LabeledContent("마지막 수집") {
                    if let error = feed.lastError {
                        Text(error).foregroundStyle(.red)
                    } else if let run = feed.lastRun {
                        TimelineView(.periodic(from: .now, by: 1)) { ctx in
                            let sec = Int(ctx.date.timeIntervalSince(run))
                            Text(sec < 5 ? "방금" : "\(sec)초 전").monospacedDigit()
                        }
                    } else {
                        Text("아직 없음").foregroundStyle(.secondary)
                    }
                }
                Button("설정 파일 보기") { NSWorkspace.shared.activateFileViewerSelecting([Paths.team]) }
                Button("모든 고정 풀기") { stages.call("desk.unpinAll") }
                Button("화면 새로고침") { stages.reload() }
            }
            Section("Claude Code") {
                Button("Claude Code 에 고양이 추가 명령 설치") { skillNote = installSkill() }
                Text(skillNote ?? "설치하면 Claude Code 에서 \"고양이 추가해줘\" 라고 해서 그 세션의 고양이를 만들 수 있어요.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    /// 번들의 cat-add 스킬을 ~/.claude/skills/cat-add/SKILL.md 로 복사한다. 같은 자리에 남의 파일이 있으면 덮어쓰지 않는다
    private func installSkill() -> String {
        let src = Bundle.main.resourceURL!.appendingPathComponent("skills/cat-add/SKILL.md")
        let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/skills/cat-add")
        let dst = dir.appendingPathComponent("SKILL.md")
        if FileManager.default.fileExists(atPath: dst.path),
           (try? String(contentsOf: dst, encoding: .utf8))?.contains("local.catteam") != true {
            return "같은 이름(cat-add)의 다른 스킬이 이미 있어서 그대로 뒀어요: \(dst.path)"
        }
        do {
            let data = try Data(contentsOf: src)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try data.write(to: dst, options: .atomic)
            return "설치했어요. Claude Code 에서 \"고양이 추가해줘\" 라고 해 보세요."
        } catch {
            return "설치하지 못했어요: \(error.localizedDescription)"
        }
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
