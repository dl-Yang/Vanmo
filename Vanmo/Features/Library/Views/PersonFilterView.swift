import SwiftUI

struct PersonFilterView: View {
    let persons: [PersonInfo]
    @Binding var selectedPerson: String?
    @State private var searchText = ""

    private var filteredPersons: [PersonInfo] {
        if searchText.isEmpty {
            return persons
        }
        return persons.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            searchField
            personGrid
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("搜索导演或演员", text: $searchText)
                .textFieldStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.vanmoSurface)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal)
    }

    private var personGrid: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 10) {
                ForEach(filteredPersons) { person in
                    PersonCapsule(
                        person: person,
                        isSelected: selectedPerson == person.name
                    ) {
                        withAnimation(.spring(response: 0.3)) {
                            if selectedPerson == person.name {
                                selectedPerson = nil
                            } else {
                                selectedPerson = person.name
                            }
                        }
                    }
                }
            }
            .padding(.horizontal)
        }
    }
}

private struct PersonCapsule: View {
    let person: PersonInfo
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Circle()
                    .fill(Color.vanmoSurface.opacity(0.8))
                    .frame(width: 28, height: 28)
                    .overlay {
                        Image(systemName: "person.fill")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                VStack(alignment: .leading, spacing: 1) {
                    Text(person.name)
                        .font(.caption)
                        .fontWeight(isSelected ? .semibold : .regular)
                        .lineLimit(1)
                    Text("\(person.count) 部作品")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(isSelected ? Color.vanmoPrimary : Color.vanmoSurface)
            .foregroundStyle(isSelected ? .white : .primary)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    PersonFilterView(
        persons: [
            PersonInfo(name: "克里斯托弗·诺兰", count: 5, profileURL: nil),
            PersonInfo(name: "莱昂纳多·迪卡普里奥", count: 4, profileURL: nil),
            PersonInfo(name: "汤姆·汉克斯", count: 3, profileURL: nil),
        ],
        selectedPerson: .constant("克里斯托弗·诺兰")
    )
    .preferredColorScheme(.dark)
}
