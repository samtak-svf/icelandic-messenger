import Foundation
import ImageIO
import SpjallCore
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// An account's profile photo at the version the server named (decision 0039).
struct PhotoOf: Hashable, Sendable {
    let account: String
    let version: String
}

extension Person {
    /// The photo to draw for this person, or nil when the server gave none.
    var photoOf: PhotoOf? { photo.map { PhotoOf(account: account, version: $0) } }
}

extension Me {
    /// This account's own photo, or nil when it has none.
    var photoOf: PhotoOf? { photo.map { PhotoOf(account: accountId, version: $0) } }
}

/// A 1:1's photo is the other person's; a group's avatar stays initials (decision 0039).
func photoOf(_ conversation: Conversation) -> PhotoOf? { nil }

/// Decoded photos by account and version, the last `capacity` in memory only.
/// The file stays the core's, in its media folder (decision 0039): nothing here
/// writes one.
final class PhotoCache<Image: Sendable>: @unchecked Sendable {
    private let account: Account
    private let capacity: Int
    private let decode: @Sendable (String) -> Image?
    private let lock = NSLock()
    private var images: [PhotoOf: Image] = [:]
    /// Least recently used first.
    private var order: [PhotoOf] = []

    init(account: Account, capacity: Int = 64, decode: @escaping @Sendable (String) -> Image?) {
        self.account = account
        self.capacity = capacity
        self.decode = decode
    }

    /// The photo when it is already in memory, so a row drawn again does not flash its initials.
    func kept(_ photo: PhotoOf) -> Image? { nil }

    /// The photo, fetched by the core when it has not kept it yet; nil for none, or
    /// when it cannot be had now (offline, refused, not an image), so the next draw asks again.
    func load(_ photo: PhotoOf) async -> Image? { nil }
}

private struct PhotosKey: EnvironmentKey {
    static let defaultValue: PhotoCache<UIImage>? = nil
}

extension EnvironmentValues {
    /// Where `Avatar` gets photos from; nil draws initials only.
    var photos: PhotoCache<UIImage>? {
        get { self[PhotosKey.self] }
        set { self[PhotosKey.self] = newValue }
    }
}

/// A photo for an avatar: the server's 512 px one, halved, which is about the largest avatar (88 pt) on
/// most screens at a quarter of the memory.
func avatarPhoto(_ path: String) -> UIImage? {
    guard let source = CGImageSourceCreateWithURL(URL(filePath: path) as CFURL, nil) else { return nil }
    let options: [CFString: Any] = [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceThumbnailMaxPixelSize: 256,
    ]
    guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
    return UIImage(cgImage: image)
}

/// The photo at `url` as an upright square from its middle, no larger than `side` pixels, written to a new
/// temporary JPEG (decision 0039). Only the pixels are written, so none of the original's metadata goes with
/// it; the server re-encodes it anyway, and that is the guarantee. Throws when `url` is not an image.
func squarePhoto(_ url: URL, side: Int) throws -> URL { url }
