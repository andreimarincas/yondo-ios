//
//  ImageMetadataProvider.swift
//  Yondo
//
//  Created by Andrei Marincas on 04.02.2026.
//

import LinkPresentation
import UIKit

class ImageMetadataProvider: NSObject, UIActivityItemSource {
    let image: UIImage
    let thumbnail: UIImage

    init(image: UIImage, thumbnail: UIImage) {
        self.image = image
        self.thumbnail = thumbnail
        super.init()
    }
    
    // 1. What is being shared? (The Image)
    func activityViewControllerPlaceholderItem(_ activityViewController: UIActivityViewController) -> Any {
        return image
    }

    func activityViewController(_ activityViewController: UIActivityViewController, itemForActivityType activityType: UIActivity.ActivityType?) -> Any? {
        return image
    }

    // 2. What shows up in the top preview header?
    func activityViewControllerLinkMetadata(_ activityViewController: UIActivityViewController) -> LPLinkMetadata? {
        let metadata = LPLinkMetadata()
        
        // Set to empty to hide the text line
        metadata.title = ""
        
        // The large preview hero image
        metadata.imageProvider = NSItemProvider(object: image)
        
        // The small icon (uses the thumbnail for efficiency)
        metadata.iconProvider = NSItemProvider(object: thumbnail)
        
        return metadata
    }
}
