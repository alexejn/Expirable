//
//  File.swift
//  
//
//  Created by Alexey Nenastev on 22.08.2022.
//

import Foundation

public protocol Expirable {
    var expiredAt: Date { get }
}

public extension Expirable {
    var isExpired: Bool { expiredAt <= Date.now }
}

public protocol RefreshableToken: Codable {
    associatedtype Token: Expirable
    associatedtype RefreshToken
    
    var token: Token { get }
    var refreshToken: RefreshToken { get }
}

public struct NoStoredDataError: Error {
    public init() {}
}

public struct RefreshIsExpired: Error {
    public init() {}
}
 

public protocol Refresher {
    associatedtype RefreshToken
    associatedtype Fresh
    func refresh(with: RefreshToken) async throws -> Fresh
}

 
 
