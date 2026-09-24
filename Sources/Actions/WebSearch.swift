import Foundation

public enum WebSearch {
    // Only unreserved ASCII stays unencoded, so "+", "&" and "?" survive as part of the query.
    private static let allowed = CharacterSet(
        charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")

    public static func url(for query: String) -> URL {
        let encoded = query.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
        return URL(string: "https://www.google.com/search?q=\(encoded)")!
    }
}
