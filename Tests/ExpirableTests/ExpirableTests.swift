import XCTest
@testable import Expirable

struct TestToken: Expirable, Codable, Equatable, CustomStringConvertible {
    var description: String { string }
    
    let expiredAt: Date
    let string: String
    
    init(expiredAt: Date) {
        self.expiredAt = expiredAt
        self.string = expiredAt.formatted(.dateTime.minute().second())
    }
}
 
struct TestRefreshableToken: RefreshableToken, Equatable, CustomStringConvertible {
    let token: TestToken
    let refreshToken: String
    var description: String { token.description }
    
    static var expiredNow: TestRefreshableToken {
        .init(token: .init(expiredAt: .now), refreshToken: "now")
    }
    
    static func expiredAfter(sec: TimeInterval) -> TestRefreshableToken {
        .init(token: .init(expiredAt: .now + sec), refreshToken: "now")
    }
}
 
final class TestStorage: Storage {
    var val: TestRefreshableToken?
    
    func store(_ tokens: TestRefreshableToken) async throws {
        val = tokens
        print("Stored: \(tokens)")
    }
    
    func restore() async throws -> TestRefreshableToken {
        guard let val else { throw NoStoredDataError() }
        print("Restored: \(val)")
        return val
    }
}

final class TestRefresher: Refresher {
    
    var refreshSec: TimeInterval = 2
    var sleepBeforeRefreshSec: Double = 1
     
    func refresh(with: String) async throws -> TestRefreshableToken {
        try await Task.sleep(seconds: sleepBeforeRefreshSec)
        
        let token = TestRefreshableToken(token: .init(expiredAt: Date.now.addingTimeInterval(refreshSec)),
               refreshToken: "\(with)+")
        print("Refreshed: \(token)")
        return token
    }
}
 
extension Task where Success == Never, Failure == Never {
    static func sleep(seconds: Double) async throws {
        let duration = UInt64(seconds * 1_000_000_000)
        try await Task.sleep(nanoseconds: duration)
    }
}


final class ExpirableTests: XCTestCase {
    
    /// Прежде чем использовать Session необходимо в Storage положить какой-то токен иначе
    /// будет ошибка NoStoredDataError
    func testNoStoredDataError() async throws {
        
        let storage = TestStorage()
        let refresher = TestRefresher()
        let session = Session(storage: storage, refresher: refresher)
        
        do {
            _ = try await session.get()
        } catch {
            guard error is NoStoredDataError else {
                XCTFail("Unexpected error type")
                return
            }
        }
    }
    
    /// Не вызывает Refresher ( не обновляет токен ) если в Storage есть свежий
    func testReturnActualToken() async throws {
        
        let storage = TestStorage()
        let refresher = TestRefresher()
        let session = Session(storage: storage, refresher: refresher)
        
        let token = TestRefreshableToken.expiredAfter(sec: 1)
        try await storage.store(token)
        let returnedToken = try await session.get()
        XCTAssertEqual(token, returnedToken)
    }
    
    /// Обновляет токен  если токен из Storage протух
    func testReturnRefreshedToken() async throws {
        
        let storage = TestStorage()
        let refresher = TestRefresher()
        let session = Session(storage: storage, refresher: refresher)
        
        let token = TestRefreshableToken.expiredNow
        try await storage.store(token)
        let returnedToken = try await session.get()
        print("old:\(token) new: \(returnedToken)")
        XCTAssertGreaterThan(returnedToken.token.expiredAt, token.token.expiredAt)
    }
    
    /// Первое обращение в Session вернет токен из Storage которые еще не протух, но протухнет к моменту второго обрщаения
    /// Второе обращение обновит токен
    func testFirstReturnActualSecondRefreshedToken() async throws {
        
        let storage = TestStorage()
        let refresher = TestRefresher()
        let session = Session(storage: storage, refresher: refresher)
        
        let token = TestRefreshableToken.expiredAfter(sec: 1)
        try await storage.store(token)
        let firstReturnedToken = try await session.get()
        XCTAssertEqual(token, firstReturnedToken)
        print("First returned: \(firstReturnedToken)")
        try await Task.sleep(seconds: 2)
        let secondReturnedToken = try await session.get()
        print("Second returned: \(firstReturnedToken)")
        XCTAssertGreaterThan(secondReturnedToken.token.expiredAt, firstReturnedToken.token.expiredAt)
    }
    
    /// Проверяем случай когда Session обновляет токен, но в этот момент ему поступают новые обращения за токеном,
    /// Новые рефреши недолжны выполняться пока выполяется один
    func testReturnTheSameTaskWhenAskingForRefreshParallel() async throws {
        
        let storage = TestStorage()
        let refresher = TestRefresher()
        refresher.sleepBeforeRefreshSec = 0.2
        refresher.refreshSec = 1
        let session = Session(storage: storage, refresher: refresher)
        
        let token = TestRefreshableToken.expiredNow
        try await storage.store(token)
        // Запрашиваем рефреш - будет вызван рефрешер
        async let firstCall = try session.get()
        // Должна вернуться таска первого вызова
        async let secondCall = try session.get()
        // Спим меньше чем идет рефреш первой таски. Должна вернуться таска первого вызова
        async let thirdCall = Task<TestRefreshableToken, Error> {
            try await Task.sleep(seconds: 0.1)
            return try await session.get()
        }
        // Спим больше чем идет рефреш первой таски. Должен быть вызван рефрешер
        async let fourCallCall = Task<TestRefreshableToken, Error> {
            try await Task.sleep(seconds: refresher.sleepBeforeRefreshSec + refresher.refreshSec + 0.1)
            return try await session.get()
        }
         
        
        let (first, second, third, four) = try await (firstCall, secondCall, thirdCall.value, fourCallCall.value)
        print("old \(token)")
        print("first \(first.token)")
        print("second \(second.token)")
        print("third \(third.token)")
        print("four \(four.token)")
        // Первый вызов обновил токен
        XCTAssertGreaterThan(first.token.expiredAt, token.token.expiredAt)
        // Второму вызову вернулся токен из первого обновления
        XCTAssertEqual(second.token, first.token)
        // Третьему вызову вернулся токен из первого обновления
        XCTAssertEqual(third.token, first.token)
        // Четвертый вызов обновил токен
        XCTAssertGreaterThan(four.token.expiredAt, first.token.expiredAt)
    }
    
    ///  Session обновляет токен но в этот момент таска из которой он был вызыван отменяется, результат Session также должен прекратить работу
    func testRefreshingTaskCancelation() async throws {
        let storage = TestStorage()
        let refresher = TestRefresher()
        refresher.sleepBeforeRefreshSec = 1
        refresher.refreshSec = 2
        let session = Session(storage: storage, refresher: refresher)
        
        let token = TestRefreshableToken.expiredNow
        try await storage.store(token)
        
        let task = Task<TestRefreshableToken, Error> {
            let result = try await session.get()
            print("Session returned: \(result)")
            return result
        }
        
        // Отменим таску на рефреш, пока она рефрешит
        Task {
            try await Task.sleep(seconds: 0.1)
            task.cancel()
        }
        
        do {
            let result = try await task.value
            XCTFail("Task should be canceled")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
        
        // Токен остался старым
        let storedToken = try await storage.restore()
        XCTAssertEqual(token, storedToken)
    }
    
    func testAutoRefresh() async throws {
        
        let tokenDuration: TimeInterval = 2
        let autorefreshBefore: TimeInterval = 0.2 // Обновляем каждые tokenDuration - autorefreshBefore
        let storage = TestStorage()
        let refresher = TestRefresher()
        refresher.sleepBeforeRefreshSec = 0.1 // время обновления токена рефрешером
        refresher.refreshSec = tokenDuration
        let session = Session(storage: storage, refresher: refresher, autoRefresheBeforeSec: autorefreshBefore)
        
        let token = TestRefreshableToken.expiredNow
        try await storage.store(token)
        
        // Честный рефреш, после таймер на автообновление
        let call1 = try await session.get()
        XCTAssertGreaterThan(call1.token.expiredAt, token.token.expiredAt)
    
        // Спим чуть меньше чем должно начаться автообновление
        try await Task.sleep(seconds: tokenDuration - autorefreshBefore - 0.1)
        print("call2-before")
        let call2 = try await session.get()
        print("call2-after")
        XCTAssertEqual(call2, call1) // тот же самый токен, без рефреша
        
        // Уже началось автообновление ( но еще не закончилось ) и мы запрашиваем токен
        try await Task.sleep(seconds: 0.15)
        print("call3-before")
        let call3 = try await session.get()
        print("call3-after")
        XCTAssertGreaterThan(call3.token.expiredAt, call2.token.expiredAt)
        
        // ждем когда токен авторефрешнится
        try await Task.sleep(seconds: tokenDuration)
        let stored = try await storage.restore()
        XCTAssertGreaterThan(stored.token.expiredAt, call3.token.expiredAt)
    }
    
}

