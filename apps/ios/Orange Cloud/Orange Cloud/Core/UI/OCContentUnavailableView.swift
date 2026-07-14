//
//  OCContentUnavailableView.swift
//  Orange Cloud
//
//  iOS 16 replacement for SwiftUI.ContentUnavailableView (introduced in iOS 17).
//

import SwiftUI

struct OCContentUnavailableView<Label: View, Description: View, Actions: View>: View {
    private let label: Label
    private let description: Description
    private let actions: Actions

    init(
        @ViewBuilder _ label: () -> Label,
        @ViewBuilder description: () -> Description,
        @ViewBuilder actions: () -> Actions
    ) {
        self.label = label()
        self.description = description()
        self.actions = actions()
    }

    var body: some View {
        VStack(spacing: 12) {
            label
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)
            description
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            actions
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }
}

extension OCContentUnavailableView where Actions == EmptyView {
    init(
        @ViewBuilder _ label: () -> Label,
        @ViewBuilder description: () -> Description
    ) {
        self.init(label, description: description, actions: { EmptyView() })
    }
}

extension OCContentUnavailableView where Label == SwiftUI.Label<Text, Image>, Description == AnyView, Actions == EmptyView {
    init(title: String, systemImage: String, description: Text) {
        self.init(
            {
                SwiftUI.Label {
                    Text(title)
                } icon: {
                    Image(systemName: systemImage)
                }
            },
            description: { AnyView(description) }
        )
    }

    init(_ titleKey: LocalizedStringKey, systemImage: String, description: Text) {
        self.init(
            { SwiftUI.Label(titleKey, systemImage: systemImage) },
            description: { AnyView(description) }
        )
    }

    init(_ titleKey: LocalizedStringKey, systemImage: String, description: String? = nil) {
        let descriptionView: AnyView
        if let description {
            descriptionView = AnyView(Text(LocalizedStringKey(description)))
        } else {
            descriptionView = AnyView(EmptyView())
        }
        self.init(
            { SwiftUI.Label(titleKey, systemImage: systemImage) },
            description: { descriptionView }
        )
    }

    static func search(text: String) -> Self {
        Self(
            "未找到结果",
            systemImage: "magnifyingglass",
            description: Text("没有与“\(text)”匹配的内容")
        )
    }
}
