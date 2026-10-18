import Foundation

/// Presents Core Data's transformable NSArray field as a Swift string array.
extension Goal {
    var keywordList: [String] {
        get { keywords as? [String] ?? [] }
        set { keywords = newValue as NSArray }
    }
}
