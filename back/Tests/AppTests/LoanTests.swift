@testable import App
import XCTVapor

final class LoanTests: XCTestCase {
    private func borrow(
        _ app: Application,
        gameID: UUID,
        memberID: UUID,
        afterResponse: (XCTHTTPResponse) async throws -> Void
    ) async throws {
        try await app.test(.POST, "loans", beforeRequest: { req in
            try req.content.encode(CreateLoanDTO(gameID: gameID, memberID: memberID))
        }, afterResponse: afterResponse)
    }
    
    private func startLoan(
        _ app: Application,
        gameID: UUID,
        memberID: UUID
    ) async throws -> LoanDTO {
        var loan: LoanDTO?
        try await borrow(app, gameID: gameID, memberID: memberID) { res in
            XCTAssertEqual(res.status, .created)
            loan = try res.content.decode(LoanDTO.self)
        }
        return try XCTUnwrap(loan)
    }

    func testBorrowGameReturnsCreated() async throws {
        try await withApp { app in
            let game = try await createGame(app)
            let member = try await createMember(app)

            try await borrow(
                app, gameID: try XCTUnwrap(game.id), memberID: try XCTUnwrap(member.id)
            ) { res in
                XCTAssertEqual(res.status, .created)
                let loan = try res.content.decode(LoanDTO.self)
                XCTAssertEqual(loan.gameID, game.id)
                XCTAssertEqual(loan.memberID, member.id)
                XCTAssertNil(loan.returnedAt)
            }
        }
    }

    func testDueDateIsFourteenDaysAfterBorrowDate() async throws {
        try await withApp { app in
            let game = try await createGame(app)
            let member = try await createMember(app)

            try await borrow(
                app, gameID: try XCTUnwrap(game.id), memberID: try XCTUnwrap(member.id)
            ) { res in
                let loan = try res.content.decode(LoanDTO.self)
                var calendar = Calendar(identifier: .gregorian)
                calendar.timeZone = TimeZone(secondsFromGMT: 0)!
                let days = calendar.dateComponents([.day], from: loan.borrowedAt, to: loan.dueAt).day
                XCTAssertEqual(days, 14)
            }
        }
    }

    func testBorrowedGameIsNoLongerAvailable() async throws {
        try await withApp { app in
            let game = try await createGame(app)
            let member = try await createMember(app)
            let gameID = try XCTUnwrap(game.id)

            try await borrow(app, gameID: gameID, memberID: try XCTUnwrap(member.id)) { _ in }

            try await app.test(.GET, "games/\(gameID)", afterResponse: { res async throws in
                XCTAssertFalse(try res.content.decode(GameDTO.self).isAvailable)
            })
        }
    }

    func testBorrowingAGameAlreadyOnLoanReturnsConflict() async throws {
        try await withApp { app in
            let game = try await createGame(app)
            let first = try await createMember(app, email: "first@example.com")
            let second = try await createMember(app, name: "Alex", email: "second@example.com")
            let gameID = try XCTUnwrap(game.id)

            try await borrow(app, gameID: gameID, memberID: try XCTUnwrap(first.id)) { _ in }
            try await borrow(app, gameID: gameID, memberID: try XCTUnwrap(second.id)) { res in
                XCTAssertEqual(res.status, .conflict)
            }
        }
    }

    func testBorrowUnknownGameReturnsNotFound() async throws {
        try await withApp { app in
            let member = try await createMember(app)

            try await borrow(app, gameID: UUID(), memberID: try XCTUnwrap(member.id)) { res in
                XCTAssertEqual(res.status, .notFound)
            }
        }
    }

    func testBorrowWithUnknownMemberReturnsNotFound() async throws {
        try await withApp { app in
            let game = try await createGame(app)

            try await borrow(app, gameID: try XCTUnwrap(game.id), memberID: UUID()) { res in
                XCTAssertEqual(res.status, .notFound)
            }
        }
    }
    
    func testReturnLoanReturnsOk() async throws {
        try await withApp { app in
            let game = try await createGame(app)
            let member = try await createMember(app)
            let loan = try await startLoan(
                app, gameID: try XCTUnwrap(game.id), memberID: try XCTUnwrap(member.id)
            )
            let loanID = try XCTUnwrap(loan.id)
            XCTAssertNil(loan.returnedAt)

            try await app.test(.POST, "loans/\(loanID)/return", afterResponse: { res async throws in
                XCTAssertEqual(res.status, .ok)
                let returned = try res.content.decode(LoanDTO.self)
                XCTAssertEqual(returned.id, loanID)
                XCTAssertNotNil(returned.returnedAt)
            })
        }
    }
    
    func testReturnLoanMakesGameAvailableAgain() async throws {
        try await withApp { app in
            let game = try await createGame(app)
            let member = try await createMember(app)
            let gameID = try XCTUnwrap(game.id)
            let loan = try await startLoan(app, gameID: gameID, memberID: try XCTUnwrap(member.id))
            let loanID = try XCTUnwrap(loan.id)

            try await app.test(.GET, "games/\(gameID)", afterResponse: { res async throws in
                XCTAssertFalse(try res.content.decode(GameDTO.self).isAvailable)
            })

            try await app.test(.POST, "loans/\(loanID)/return", afterResponse: { res async throws in
                XCTAssertEqual(res.status, .ok)
            })

            try await app.test(.GET, "games/\(gameID)", afterResponse: { res async throws in
                XCTAssertTrue(try res.content.decode(GameDTO.self).isAvailable)
            })
        }
    }

    func testReturnedGameCanBeBorrowedAgain() async throws {
        try await withApp { app in
            let game = try await createGame(app)
            let first = try await createMember(app, email: "first@example.com")
            let second = try await createMember(app, name: "Alex", email: "second@example.com")
            let gameID = try XCTUnwrap(game.id)
            let loan = try await startLoan(app, gameID: gameID, memberID: try XCTUnwrap(first.id))
            let loanID = try XCTUnwrap(loan.id)

            try await app.test(.POST, "loans/\(loanID)/return", afterResponse: { res async throws in
                XCTAssertEqual(res.status, .ok)
            })

            _ = try await startLoan(app, gameID: gameID, memberID: try XCTUnwrap(second.id))
        }
    }

    func testReturnAlreadyReturnedLoanReturnsConflict() async throws {
        try await withApp { app in
            let game = try await createGame(app)
            let member = try await createMember(app)
            let loan = try await startLoan(
                app, gameID: try XCTUnwrap(game.id), memberID: try XCTUnwrap(member.id)
            )
            let loanID = try XCTUnwrap(loan.id)

            try await app.test(.POST, "loans/\(loanID)/return", afterResponse: { res async throws in
                XCTAssertEqual(res.status, .ok)
            })
            try await app.test(.POST, "loans/\(loanID)/return", afterResponse: { res async throws in
                XCTAssertEqual(res.status, .conflict)
            })
        }
    }

    func testReturnUnknownLoanReturnsNotFound() async throws {
        try await withApp { app in
            try await app.test(.POST, "loans/\(UUID())/return", afterResponse: { res async throws in
                XCTAssertEqual(res.status, .notFound)
            })
        }
    }
    
    func testGetLoansOverdueReturnsOverdueLoans() async throws {
        try await withApp { app in
            let game = try await createGame(app)
            let member = try await createMember(app)
            let gameID = try XCTUnwrap(game.id)
            let memberID = try XCTUnwrap(member.id)
            
            let pastDate = Date().addingTimeInterval(-15 * 24 * 3600)
            let dueDate = Date().addingTimeInterval(-1 * 24 * 3600)
            
            // Insertion directe d'un emprunt en retard (non rendu)
            try await insertLoan(
                app,
                gameID: gameID,
                memberID: memberID,
                borrowedAt: pastDate,
                dueAt: dueDate
            )
            
            try await app.test(.GET, "loans/overdue", afterResponse: { res async throws in
                XCTAssertEqual(res.status, .ok)
                let loans = try res.content.decode([LoanDTO].self)
                XCTAssertFalse(loans.isEmpty)
                XCTAssertEqual(loans.count, 1)
                XCTAssertEqual(loans.first?.gameID, gameID)
            })
        }
    }

    func testGetLoansOverdueIgnoresReturnedLoans() async throws {
        try await withApp { app in
            let game = try await createGame(app)
            let member = try await createMember(app)
            let gameID = try XCTUnwrap(game.id)
            let memberID = try XCTUnwrap(member.id)
            
            let pastDate = Date().addingTimeInterval(-20 * 24 * 3600)
            let dueDate = Date().addingTimeInterval(-5 * 24 * 3600)
            
            // Insertion d'un emprunt en retard mais déjà rendu
            try await insertLoan(
                app,
                gameID: gameID,
                memberID: memberID,
                borrowedAt: pastDate,
                dueAt: dueDate,
                returnedAt: Date()
            )
            
            try await app.test(.GET, "loans/overdue", afterResponse: { res async throws in
                XCTAssertEqual(res.status, .ok)
                let loans = try res.content.decode([LoanDTO].self)
                XCTAssertTrue(loans.isEmpty)
            })
        }
    }
}
