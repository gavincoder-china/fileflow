//
//  WallpaperService.swift
//  FileFlow
//
//  Service to fetch the Bing Daily Wallpaper URL
//

import Foundation

class WallpaperService {
    static let shared = WallpaperService()
    
    private let bingAPI = "https://www.bing.com/HPImageArchive.aspx?format=js&idx=0&n=1&mkt=zh-CN"
    private let bingBase = "https://www.bing.com"
    
    struct BingResponse: Codable {
        let images: [BingImage]
    }
    
    struct BingImage: Codable {
        let url: String
    }
    
    func fetchDailyWallpaperURL(index: Int = 0) async throws -> URL {
        let urlString = "https://www.bing.com/HPImageArchive.aspx?format=js&idx=\(index)&n=1&mkt=zh-CN"
        guard let apiURL = URL(string: urlString) else {
            throw URLError(.badURL)
        }
        
        Logger.info("Fetching Bing daily wallpaper...")
        
        let (data, _) = try await URLSession.shared.data(from: apiURL)
        let response = try JSONDecoder().decode(BingResponse.self, from: data)
        
        guard let relativeURL = response.images.first?.url,
              let imageURL = URL(string: bingBase + relativeURL) else {
            throw URLError(.badServerResponse)
        }
        
        Logger.success("Fetched wallpaper URL: \(imageURL.absoluteString)")
        return imageURL
    }
}
