import Foundation
import SwiftUI

class DirectoryMonitor {
    private var source: DispatchSourceFileSystemObject?
    private let url: URL
    private let supportedExtensions = ["pdf", "png", "jpg", "jpeg", "tiff"]
    
    var onFileAdded: ((URL) -> Void)?
    
    init(url: URL) {
        self.url = url
    }
    
    func start() {
        let descriptor = open(url.path, O_EVTONLY)
        if descriptor < 0 {
            print("Failed to open directory for monitoring.")
            return
        }
        
        source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, eventMask: .write, queue: .main)
        
        source?.setEventHandler { [weak self] in
            self?.scanDirectory()
        }
        
        source?.setCancelHandler {
            close(descriptor)
        }
        
        source?.resume()
    }
    
    func stop() {
        source?.cancel()
        source = nil
    }
    
    private func scanDirectory() {
        do {
            let contents = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)
            for fileURL in contents {
                if supportedExtensions.contains(fileURL.pathExtension.lowercased()) {
                    onFileAdded?(fileURL)
                }
            }
        } catch {
            print("Failed to scan directory: \(error)")
        }
    }
} 