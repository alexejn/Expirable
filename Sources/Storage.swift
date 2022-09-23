//
//  File.swift
//  
//
//  Created by Alexey Nenastev on 22.08.2022.
//

import Foundation


public protocol Storage {
    associatedtype S: Codable
    func store(_ : S) async throws
    func restore() async throws -> S
}
