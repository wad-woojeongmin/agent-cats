// 메뉴 팝오버 — 팀원 관리 화면과 고양이 편집.
import SwiftUI

// MARK: 팀원 관리

struct TeamView: View {
    @EnvironmentObject var store: TeamStore
    @EnvironmentObject var router: Router

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            PageHeader(title: "팀원 관리")
            Divider()
            Text("고양이별 이름, 상태 메시지, 이미지, 표시 여부를 관리해요. 끌어서 순서를 바꿀 수 있어요.")
                .font(.caption).foregroundStyle(.secondary)
                .padding(.horizontal, 14)
            List {
                ForEach(store.cats) { cat in
                    TeamRow(cat: cat)
                }
                .onMove { store.move(from: $0, to: $1) }
            }
            .listStyle(.inset)
            HStack {
                Button {
                    router.path.append(.edit(store.add().key))
                } label: { Label("고양이 추가", systemImage: "plus") }
                Spacer()
            }
            .padding([.horizontal, .bottom], 14)
        }
        .onExitCommand { router.pop() }
    }
}

struct TeamRow: View {
    @EnvironmentObject var store: TeamStore
    @EnvironmentObject var stages: Stages
    let cat: CatEntry
    @State private var confirmDelete = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "line.3.horizontal").foregroundStyle(.tertiary)
            Thumb(image: store.thumbs[cat.key])
            VStack(alignment: .leading, spacing: 1) {
                Text(cat.label.isEmpty ? cat.key : cat.label).lineLimit(1)
                Text(status)
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Toggle("", isOn: Binding(get: { !cat.hidden }, set: { store.setHidden(cat.key, !$0) }))
                .toggleStyle(.switch).controlSize(.mini).labelsHidden()
            Menu {
                NavigationLink("편집", value: Page.edit(cat.key))
                Button("삭제", role: .destructive) { confirmDelete = true }
            } label: { Image(systemName: "ellipsis") }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        }
        .padding(.vertical, 2)
        .confirmationDialog("\(cat.label) 고양이를 지울까요?", isPresented: $confirmDelete) {
            Button("삭제", role: .destructive) { store.delete(cat.key) }
        }
    }

    /// 상태 한 줄. 디스플레이가 여럿이면 어느 화면에 있는지도 붙인다
    private var status: String {
        let line = store.lines[cat.key]?.short ?? (cat.hidden ? "숨김" : "—")
        guard stages.displays.count > 1, !cat.hidden, let id = stages.assign[cat.key],
              let i = stages.displays.firstIndex(where: { $0.id == id }) else { return line }
        return "화면 \(i + 1) · " + line
    }
}

struct CatEditor: View {
    @EnvironmentObject var store: TeamStore
    @EnvironmentObject var stages: Stages
    @EnvironmentObject var settings: PetSettings
    @EnvironmentObject var router: Router
    let key: String
    @State private var cat = CatEntry(raw: [:])

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(title: cat.label.isEmpty ? "고양이 편집" : cat.label) {
                Button("저장") { store.update(cat); router.pop() }
            }
            Divider()
            form
        }
        .onExitCommand { router.pop() }
        .onAppear { if let c = store.cats.first(where: { $0.key == key }) { cat = c } }
    }

    private var form: some View {
        Form {
            TextField("이름", text: $cat.name)
            TextField("직군", text: $cat.role)
            Picker("품종", selection: $cat.variant) {
                ForEach(TeamStore.variants, id: \.0) { Text($0.1).tag($0.0) }
            }
            Picker("소품", selection: $cat.prop) {
                ForEach(TeamStore.props, id: \.0) { Text($0.1).tag($0.0) }
            }
            if cat.fixed {
                Text("이 고양이는 팀.json 의 fixed 로 고정 상태를 띄워요. 찾을 말은 쓰지 않아요.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                TextField("찾을 말 (쉼표로 구분)", text: $cat.match)
                TextField("업무명 (상태 메시지)", text: $cat.task, prompt: Text("비우면 \"폴더이름 작업중\""))
                Toggle("마지막 보고 문장을 읽지 않기", isOn: $cat.isPrivate)
            }
            Toggle("데스크톱에 보이기", isOn: Binding(get: { !cat.hidden }, set: { cat.hidden = !$0 }))
            if stages.displays.count > 1 {
                Picker("디스플레이", selection: Binding(get: { settings.displays[key] ?? "" },
                                                    set: { stages.choose(key, display: $0.isEmpty ? nil : $0) })) {
                    Text("고양이가 적은 화면으로").tag("")
                    ForEach(Array(stages.displays.enumerated()), id: \.element.id) { i, d in
                        Text(d.name + (i == 0 ? " (주 화면)" : "")).tag(d.id)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}
