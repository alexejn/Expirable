//
//  File.swift
//  
//
//  Created by Alexey Nenastev on 22.08.2022.
//

import Foundation


public actor Session<S, R, RT> where S: Storage, S.S == RT,
                                     RT: RefreshableToken,
                                     R: Refresher, R.RefreshToken == RT.RefreshToken, R.Fresh == RT {
    
    public let storage: S
    private let refresher: R
    
    private var currentTask: Task<RT, Error>?
    private let autoRefresheBeforeSec: Double
    
    public init(storage: S,  refresher: R, autoRefresheBeforeSec: Double = 0)  {
        self.storage = storage
        self.refresher = refresher
        self.autoRefresheBeforeSec = autoRefresheBeforeSec
    }
    
    deinit {
        currentTask?.cancel()
    }
    
    public func get(forceRefresh: Bool = false) async throws -> RT  {
        if let currentTask, !currentTask.isCancelled { return try await currentTask.value }
        
        currentTask = Task {
            defer {
                currentTask = nil
            }
            
            let token = try await storage.restore()
            try Task.checkCancellation()
            
            guard token.token.isExpired || forceRefresh else { return token }
            
            if let exiprable = token.refreshToken as? Expirable, exiprable.isExpired {
                throw RefreshIsExpired()
            }
            
            let refreshed = try await refresher.refresh(with: token.refreshToken)
            try Task.checkCancellation()
            
            try await storage.store(refreshed)
            try Task.checkCancellation()
            
            if autoRefresheBeforeSec != 0 {
                let intervalToExpirationSec = refreshed.token.expiredAt.timeIntervalSince(Date.now)
                
                let autoRefreshInSec = intervalToExpirationSec - autoRefresheBeforeSec
                print("AutoRefresh after: \(autoRefreshInSec)")
                setAutoRefresh(in: autoRefreshInSec)
            }
            
            return refreshed
        }
        
        return try await withTaskCancellationHandler {
            Task {
                await currentTask?.cancel()
            }
            
        } operation: {
            
            return try await currentTask!.value
            
        }
        
    }
    
    
    private func setAutoRefresh(in inteval: TimeInterval) {
        guard inteval > 0 else { return }
        
        Task {
            let delay = UInt64(inteval * 1_000_000_000)
            try await Task<Never, Never>.sleep(nanoseconds: delay)
            
            _ = try await get(forceRefresh: true)
        }
    }
}

