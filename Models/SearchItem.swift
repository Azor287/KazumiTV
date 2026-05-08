//
//  SearchItem.swift
//  KazumiTV
//
//  Search Result Item Model
//

import Foundation

struct SearchItem: Identifiable, Codable, Equatable, Hashable {
    let id: String
    let name: String
    let nameCn: String
    let src: String
    let pluginName: String
    let imageURL: URL?

    init(id: String = UUID().uuidString, name: String, nameCn: String = "", src: String, pluginName: String, imageURL: URL? = nil) {
        self.id = id
        self.name = name
        self.nameCn = nameCn
        self.src = src
        self.pluginName = pluginName
        self.imageURL = imageURL
    }

    var displayName: String {
        nameCn.isEmpty ? name : nameCn
    }
}

extension SearchItem {
    static let sample = SearchItem(
        name: "测试动漫",
        nameCn: "Test Anime",
        src: "https://example.com/anime/1",
        pluginName: "DM84"
    )
}
