@testable import App
import XCTVapor

final class GameTests: XCTestCase {
    func testCreateGameReturnsCreated() async throws {
        try await withApp { app in
            try await app.test(.POST, "games", beforeRequest: { req in
                try req.content.encode(CreateGameDTO(
                    title: "Catan", minPlayers: 3, maxPlayers: 4, durationMinutes: 90
                ))
            }, afterResponse: { res async throws in
                XCTAssertEqual(res.status, .created)
                let game = try res.content.decode(GameDTO.self)
                XCTAssertEqual(game.title, "Catan")
                XCTAssertTrue(game.isAvailable)
            })
        }
    }
    
    func testCreateGameWithEmptyTitleIsRejected() async throws {
        try await withApp { app in
            try await app.test(.POST, "games", beforeRequest: { req in
                try req.content.encode(CreateGameDTO(
                    title: "", minPlayers: 3, maxPlayers: 4, durationMinutes: 90
                ))
            }, afterResponse: { res async throws in
                XCTAssertEqual(res.status, .badRequest)
            })
        }
    }
    
    func testCreateGameWithInvertedPlayerBoundsIsRejected() async throws {
        try await withApp { app in
            try await app.test(.POST, "games", beforeRequest: { req in
                try req.content.encode(CreateGameDTO(
                    title: "Catan", minPlayers: 5, maxPlayers: 2, durationMinutes: 90
                ))
            }, afterResponse: { res async throws in
                XCTAssertEqual(res.status, .badRequest)
            })
        }
    }
    
    func testListGames() async throws {
        try await withApp { app in
            _ = try await createGame(app, title: "Catan")
            _ = try await createGame(app, title: "Dixit")
            
            try await app.test(.GET, "games", afterResponse: { res async throws in
                XCTAssertEqual(res.status, .ok)
                XCTAssertEqual(try res.content.decode([GameDTO].self).count, 2)
            })
        }
    }
    
    func testSearchGamesByTitleCaseInsensitiveAndEmpty() async throws {
        try await withApp { app in
            _ = try await createGame(app, title: "Catan", minPlayers: 3, maxPlayers: 4, durationMinutes: 90)
            
            try await app.test(.GET, "games?q=CATAN", afterResponse: { res async throws in
                XCTAssertEqual(res.status, .ok)
                let games = try res.content.decode([GameDTO].self)
                XCTAssertEqual(games.count, 1)
            })
            
            try await app.test(.GET, "games?q=Inexistant", afterResponse: { res async throws in
                XCTAssertEqual(res.status, .ok)
                let games = try res.content.decode([GameDTO].self)
                XCTAssertTrue(games.isEmpty)
            })
        }
    }
    
    func testFilterGamesByPlayersRange() async throws {
        try await withApp { app in
            _ = try await createGame(app, title: "Jeu 3-4", minPlayers: 3, maxPlayers: 4, durationMinutes: 60)
            
            try await app.test(.GET, "games?players=2", afterResponse: { res async throws in
                let games = try res.content.decode([GameDTO].self)
                XCTAssertTrue(games.isEmpty)
            })
            
            try await app.test(.GET, "games?players=3", afterResponse: { res async throws in
                let games = try res.content.decode([GameDTO].self)
                XCTAssertEqual(games.count, 1)
            })
            
            try await app.test(.GET, "games?players=4", afterResponse: { res async throws in
                let games = try res.content.decode([GameDTO].self)
                XCTAssertEqual(games.count, 1)
            })
            
            try await app.test(.GET, "games?players=5", afterResponse: { res async throws in
                let games = try res.content.decode([GameDTO].self)
                XCTAssertTrue(games.isEmpty)
            })
        }
    }
    
    func testFilterGamesByMaxDurationLimit() async throws {
        try await withApp { app in
            _ = try await createGame(app, title: "Jeu 90min", minPlayers: 2, maxPlayers: 4, durationMinutes: 90)
            
            try await app.test(.GET, "games?maxDuration=89", afterResponse: { res async throws in
                let games = try res.content.decode([GameDTO].self)
                XCTAssertTrue(games.isEmpty)
            })
            
            try await app.test(.GET, "games?maxDuration=90", afterResponse: { res async throws in
                let games = try res.content.decode([GameDTO].self)
                XCTAssertEqual(games.count, 1)
            })
        }
    }
    
    func testFilterGamesCombination() async throws {
        try await withApp { app in
            _ = try await createGame(app, title: "Catan", minPlayers: 3, maxPlayers: 4, durationMinutes: 90)
            
            try await app.test(.GET, "games?q=cat&players=4&maxDuration=90", afterResponse: { res async throws in
                XCTAssertEqual(res.status, .ok)
                XCTAssertEqual(try res.content.decode([GameDTO].self).count, 1)
            })
            
            try await app.test(.GET, "games?q=cat&players=4&maxDuration=50", afterResponse: { res async throws in
                XCTAssertEqual(res.status, .ok)
                XCTAssertTrue(try res.content.decode([GameDTO].self).isEmpty)
            })
        }
    }
    
    func testSearchGamesInvalidParametersReturnBadRequest() async throws {
        try await withApp { app in
            try await app.test(.GET, "games?players=0", afterResponse: { res async throws in
                XCTAssertEqual(res.status, .badRequest)
            })
            try await app.test(.GET, "games?players=abc", afterResponse: { res async throws in
                XCTAssertEqual(res.status, .badRequest)
            })
            try await app.test(.GET, "games?maxDuration=-1", afterResponse: { res async throws in
                XCTAssertEqual(res.status, .badRequest)
            })
        }
    }
    
    func testGamesFilteringByAvailabilityTrue() async throws {
        try await withApp { app in
            _ = try await createGame(app, title: "Jeu Disponible")
            let game2 = try await createGame(app, title: "Jeu Emprunté")
            let member = try await createMember(app)
            let now = Date()
            
            try await insertLoan(
                app,
                gameID: try XCTUnwrap(game2.id),
                memberID: try XCTUnwrap(member.id),
                borrowedAt: now,
                dueAt: try Loan.dueDate(from: now)
            )
            
            try await app.test(.GET, "games?available=true", afterResponse: { res async throws in
                XCTAssertEqual(res.status, .ok)
                let games = try res.content.decode([GameDTO].self)
                XCTAssertEqual(games.count, 1)
                XCTAssertEqual(games.first?.title, "Jeu Disponible")
            })
        }
    }
    
    func testGamesFilteringByAvailabilityFalse() async throws {
        try await withApp { app in
            _ = try await createGame(app, title: "Jeu Disponible")
            let game2 = try await createGame(app, title: "Jeu Emprunté")
            let member = try await createMember(app)
            let now = Date()
            
            try await insertLoan(
                app,
                gameID: try XCTUnwrap(game2.id),
                memberID: try XCTUnwrap(member.id),
                borrowedAt: now,
                dueAt: try Loan.dueDate(from: now)
            )
            
            try await app.test(.GET, "games?available=false", afterResponse: { res async throws in
                XCTAssertEqual(res.status, .ok)
                let games = try res.content.decode([GameDTO].self)
                XCTAssertEqual(games.count, 1)
                XCTAssertEqual(games.first?.title, "Jeu Emprunté")
            })
        }
    }
    
    func testGamesFilteringByAvailabilityInvalid() async throws {
        try await withApp { app in
            try await app.test(.GET, "games?available=invalid", afterResponse: { res async throws in
                XCTAssertEqual(res.status, .badRequest)
            })
        }
    }
    
    func testShowGame() async throws {
        try await withApp { app in
            let game = try await createGame(app)
            let id = try XCTUnwrap(game.id)
            
            try await app.test(.GET, "games/\(id)", afterResponse: { res async throws in
                XCTAssertEqual(res.status, .ok)
                XCTAssertEqual(try res.content.decode(GameDTO.self).id, id)
            })
        }
    }
    
    func testShowUnknownGameReturnsNotFound() async throws {
        try await withApp { app in
            try await app.test(.GET, "games/\(UUID())", afterResponse: { res async throws in
                XCTAssertEqual(res.status, .notFound)
            })
        }
    }
    
    func testShowGameWithMalformedIDReturnsBadRequest() async throws {
        try await withApp { app in
            try await app.test(.GET, "games/not-a-uuid", afterResponse: { res async throws in
                XCTAssertEqual(res.status, .badRequest)
            })
        }
    }
    
    func testPreflightRequestFromAnotherOriginIsAllowed() async throws {
        try await withApp { app in
            try await app.test(.OPTIONS, "games", beforeRequest: { req in
                req.headers.replaceOrAdd(name: .origin, value: "http://localhost:8080")
                req.headers.replaceOrAdd(name: .accessControlRequestMethod, value: "POST")
                req.headers.replaceOrAdd(name: .accessControlRequestHeaders, value: "content-type")
            }, afterResponse: { res async throws in
                XCTAssertEqual(res.status, .ok)
                XCTAssertEqual(res.headers.first(name: .accessControlAllowOrigin), "*")
                XCTAssertTrue(res.headers[.accessControlAllowMethods].joined(separator: ",").contains("POST"))
            })
        }
    }
    
    func testErrorResponsesCarryTheCorsHeaders() async throws {
        try await withApp { app in
            try await app.test(.GET, "games/not-a-uuid", beforeRequest: { req in
                req.headers.replaceOrAdd(name: .origin, value: "http://localhost:8080")
            }, afterResponse: { res async throws in
                XCTAssertEqual(res.status, .badRequest)
                XCTAssertEqual(res.headers.first(name: .accessControlAllowOrigin), "*")
            })
        }
    }
    
    func testUpdateGameReturnsUpdatedGame() async throws {
        try await withApp { app in
            let game = try await createGame(app, title: "Ancien titre")
            let id = try XCTUnwrap(game.id)
            
            try await app.test(.PUT, "games/\(id)", beforeRequest: { req in
                try req.content.encode(CreateGameDTO(
                    title: "Carcassonne", minPlayers: 2, maxPlayers: 5, durationMinutes: 45
                ))
            }, afterResponse: { res async throws in
                XCTAssertEqual(res.status, .ok)
                let updated = try res.content.decode(GameDTO.self)
                XCTAssertEqual(updated.id, id)
                XCTAssertEqual(updated.title, "Carcassonne")
                XCTAssertEqual(updated.minPlayers, 2)
                XCTAssertEqual(updated.maxPlayers, 5)
                XCTAssertEqual(updated.durationMinutes, 45)
            })
            
            try await app.test(.GET, "games/\(id)", afterResponse: { res async throws in
                XCTAssertEqual(try res.content.decode(GameDTO.self).title, "Carcassonne")
            })
        }
    }
    
    func testUpdateGameWithMalformedIDReturnsBadRequest() async throws {
        try await withApp { app in
            try await app.test(.PUT, "games/not-a-uuid", beforeRequest: { req in
                try req.content.encode(CreateGameDTO(
                    title: "Carcassonne", minPlayers: 2, maxPlayers: 5, durationMinutes: 45
                ))
            }, afterResponse: { res async throws in
                XCTAssertEqual(res.status, .badRequest)
            })
        }
    }
    
    func testUpdateGameWithEmptyTitleIsRejected() async throws {
        try await withApp { app in
            let game = try await createGame(app, title: "Ancien titre")
            let id = try XCTUnwrap(game.id)
            
            try await app.test(.PUT, "games/\(id)", beforeRequest: { req in
                try req.content.encode(CreateGameDTO(
                    title: "", minPlayers: 2, maxPlayers: 5, durationMinutes: 45
                ))
            }, afterResponse: { res async throws in
                XCTAssertEqual(res.status, .badRequest)
            })
            
            try await app.test(.GET, "games/\(id)", afterResponse: { res async throws in
                XCTAssertEqual(try res.content.decode(GameDTO.self).title, "Ancien titre")
            })
        }
    }
    
    func testUpdateGameWithInvertedPlayerBoundsIsRejected() async throws {
        try await withApp { app in
            let game = try await createGame(app)
            let id = try XCTUnwrap(game.id)
            
            try await app.test(.PUT, "games/\(id)", beforeRequest: { req in
                try req.content.encode(CreateGameDTO(
                    title: "Carcassonne", minPlayers: 5, maxPlayers: 2, durationMinutes: 45
                ))
            }, afterResponse: { res async throws in
                XCTAssertEqual(res.status, .badRequest)
            })
        }
    }
    
    func testUpdateUnknownGameReturnsNotFound() async throws {
        try await withApp { app in
            try await app.test(.PUT, "games/\(UUID())", beforeRequest: { req in
                try req.content.encode(CreateGameDTO(
                    title: "Carcassonne", minPlayers: 2, maxPlayers: 5, durationMinutes: 45
                ))
            }, afterResponse: { res async throws in
                XCTAssertEqual(res.status, .notFound)
            })
        }
    }
    
    func testDeleteGameReturnsNoContent() async throws {
        try await withApp { app in
            let game = try await createGame(app)
            let id = try XCTUnwrap(game.id)
            
            try await app.test(.DELETE, "games/\(id)", afterResponse: { res async throws in
                XCTAssertEqual(res.status, .noContent)
            })
            
            try await app.test(.GET, "games/\(id)", afterResponse: { res async throws in
                XCTAssertEqual(res.status, .notFound)
            })
        }
    }
    
    func testDeleteUnknownGameReturnsNotFound() async throws {
        try await withApp { app in
            try await app.test(.DELETE, "games/\(UUID())", afterResponse: { res async throws in
                XCTAssertEqual(res.status, .notFound)
            })
        }
    }
    
    func testDeleteGameWithMalformedIDReturnsBadRequest() async throws {
        try await withApp { app in
            try await app.test(.DELETE, "games/not-a-uuid", afterResponse: { res async throws in
                XCTAssertEqual(res.status, .badRequest)
            })
        }
    }
    
    func testDeleteGameWithActiveLoanReturnsConflict() async throws {
        try await withApp { app in
            let game = try await createGame(app)
            let member = try await createMember(app)
            let gameID = try XCTUnwrap(game.id)
            let now = Date()
            try await insertLoan(
                app,
                gameID: gameID,
                memberID: try XCTUnwrap(member.id),
                borrowedAt: now,
                dueAt: try Loan.dueDate(from: now)
            )
            
            try await app.test(.DELETE, "games/\(gameID)", afterResponse: { res async throws in
                XCTAssertEqual(res.status, .conflict)
            })
            
            try await app.test(.GET, "games/\(gameID)", afterResponse: { res async throws in
                XCTAssertEqual(res.status, .ok)
            })
        }
    }
    
    func testDeleteGameWithReturnedLoanReturnsConflict() async throws {
        try await withApp { app in
            let game = try await createGame(app)
            let member = try await createMember(app)
            let gameID = try XCTUnwrap(game.id)
            let now = Date()
            try await insertLoan(
                app,
                gameID: gameID,
                memberID: try XCTUnwrap(member.id),
                borrowedAt: now,
                dueAt: try Loan.dueDate(from: now),
                returnedAt: now
            )
            
            try await app.test(.DELETE, "games/\(gameID)", afterResponse: { res async throws in
                XCTAssertEqual(res.status, .conflict)
            })
            
            try await app.test(.GET, "games/\(gameID)", afterResponse: { res async throws in
                XCTAssertEqual(res.status, .ok)
            })
        }
    }
}
