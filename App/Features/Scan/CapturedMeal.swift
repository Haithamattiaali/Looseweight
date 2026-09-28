import LooseweightKit
import UIKit

/// On-device geometry for one photo: where the table is, how the photo camera sat, and (with LiDAR) the
/// fused height field.
struct CaptureGeometry {
    var photo: PhotoGeometry
    var plane: Plane
    var heightField: HeightField?

    var measurer: SceneMeasurer {
        SceneMeasurer(plane: plane, photo: photo, heightField: heightField)
    }
}

struct CapturedMeal: Identifiable {
    enum Source: String {
        case camera, library, demo
    }

    let id = UUID()
    /// Full-resolution upright photo.
    var image: UIImage
    var geometry: CaptureGeometry?
    var deviceHasLiDAR: Bool
    var source: Source
    var capturedAt = Date()
}
