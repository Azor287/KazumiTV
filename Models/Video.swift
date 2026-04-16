//
//  Video.swift
//  KazumiTV
//
//  Video Model
//

import Foundation

struct Video: Identifiable, Codable, Equatable {
    let id: String
    let title: String
    let description: String
    let category: String
    let duration: String
    let thumbnailURL: URL?
    let streamURL: URL?

    init(
        id: String,
        title: String,
        description: String,
        category: String,
        duration: String,
        thumbnailURL: URL?,
        streamURL: URL?
    ) {
        self.id = id
        self.title = title
        self.description = description
        self.category = category
        self.duration = duration
        self.thumbnailURL = thumbnailURL
        self.streamURL = streamURL
    }
}

// MARK: - Sample Data
extension Video {
    static let sample = Video(
        id: "sample-1",
        title: "Sample Video",
        description: "This is a sample video description.",
        category: "Sample",
        duration: "10:00",
        thumbnailURL: nil,
        streamURL: nil
    )

    static let samples: [Video] = [
        Video(
            id: "1",
            title: "Big Buck Bunny",
            description: "A large rabbit meets three bullying rodents.",
            category: "Animation",
            duration: "9:56",
            thumbnailURL: nil,
            streamURL: nil
        ),
        Video(
            id: "2",
            title: "Sintel",
            description: "A girl named Sintel searches for a baby dragon.",
            category: "Animation",
            duration: "14:48",
            thumbnailURL: nil,
            streamURL: nil
        ),
        Video(
            id: "3",
            title: "Tears of Steel",
            description: "Scientists reconstruct events from the past.",
            category: "Sci-Fi",
            duration: "12:14",
            thumbnailURL: nil,
            streamURL: nil
        )
    ]
}
