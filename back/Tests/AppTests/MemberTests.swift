@testable import App
import XCTVapor

final class MemberTests: XCTestCase {
    func testCreateMemberReturnsCreated() async throws {
        try await withApp { app in
            try await app.test(.POST, "members", beforeRequest: { req in
                try req.content.encode(CreateMemberDTO(name: "Camille", email: "camille@example.com"))
            }, afterResponse: { res async throws in
                XCTAssertEqual(res.status, .created)
                XCTAssertEqual(try res.content.decode(MemberDTO.self).name, "Camille")
            })
        }
    }
    
    func testCreateMemberWithInvalidEmailIsRejected() async throws {
        try await withApp { app in
            try await app.test(.POST, "members", beforeRequest: { req in
                try req.content.encode(CreateMemberDTO(name: "Camille", email: "not-an-email"))
            }, afterResponse: { res async throws in
                XCTAssertEqual(res.status, .badRequest)
            })
        }
    }
    
    func testCreateMemberWithDuplicateEmailReturnsConflict() async throws {
        try await withApp { app in
            _ = try await createMember(app)
            
            try await app.test(.POST, "members", beforeRequest: { req in
                try req.content.encode(CreateMemberDTO(name: "Autre", email: "camille@example.com"))
            }, afterResponse: { res async throws in
                XCTAssertEqual(res.status, .conflict)
            })
        }
    }
    
    func testShowUnknownMemberReturnsNotFound() async throws {
        try await withApp { app in
            try await app.test(.GET, "members/\(UUID())", afterResponse: { res async throws in
                XCTAssertEqual(res.status, .notFound)
            })
        }
    }
    
    func testShowMemberWithMalformedIDReturnsBadRequest() async throws {
        try await withApp { app in
            try await app.test(.GET, "members/not-a-uuid", afterResponse: { res async throws in
                XCTAssertEqual(res.status, .badRequest)
            })
        }
    }
    
    func testUpdateMemberReturnsUpdatedMember() async throws {
        try await withApp { app in
            let member = try await createMember(app)
            let id = try XCTUnwrap(member.id)
            
            try await app.test(.PUT, "members/\(id)", beforeRequest: { req in
                try req.content.encode(CreateMemberDTO(name: "Alex", email: "alex@example.com"))
            }, afterResponse: { res async throws in
                XCTAssertEqual(res.status, .ok)
                let updated = try res.content.decode(MemberDTO.self)
                XCTAssertEqual(updated.id, id)
                XCTAssertEqual(updated.name, "Alex")
                XCTAssertEqual(updated.email, "alex@example.com")
            })
            
            // The change is persisted, not only echoed in the response.
            try await app.test(.GET, "members/\(id)", afterResponse: { res async throws in
                XCTAssertEqual(try res.content.decode(MemberDTO.self).email, "alex@example.com")
            })
        }
    }
    
    func testUpdateMemberKeepingOwnEmailIsAllowed() async throws {
        try await withApp { app in
            let member = try await createMember(app, name: "Camille", email: "camille@example.com")
            let id = try XCTUnwrap(member.id)
            
            try await app.test(.PUT, "members/\(id)", beforeRequest: { req in
                try req.content.encode(CreateMemberDTO(name: "Camille Dupont", email: "camille@example.com"))
            }, afterResponse: { res async throws in
                XCTAssertEqual(res.status, .ok)
                XCTAssertEqual(try res.content.decode(MemberDTO.self).name, "Camille Dupont")
            })
        }
    }
    
    func testUpdateMemberWithEmailOfAnotherMemberReturnsConflict() async throws {
        try await withApp { app in
            _ = try await createMember(app, name: "Camille", email: "camille@example.com")
            let second = try await createMember(app, name: "Alex", email: "alex@example.com")
            let secondID = try XCTUnwrap(second.id)
            
            try await app.test(.PUT, "members/\(secondID)", beforeRequest: { req in
                try req.content.encode(CreateMemberDTO(name: "Alex", email: "camille@example.com"))
            }, afterResponse: { res async throws in
                XCTAssertEqual(res.status, .conflict)
            })
            
            try await app.test(.GET, "members/\(secondID)", afterResponse: { res async throws in
                XCTAssertEqual(try res.content.decode(MemberDTO.self).email, "alex@example.com")
            })
        }
    }
    
    func testUpdateMemberWithEmptyNameIsRejected() async throws {
        try await withApp { app in
            let member = try await createMember(app, name: "Camille")
            let id = try XCTUnwrap(member.id)
            
            try await app.test(.PUT, "members/\(id)", beforeRequest: { req in
                try req.content.encode(CreateMemberDTO(name: "", email: "camille@example.com"))
            }, afterResponse: { res async throws in
                XCTAssertEqual(res.status, .badRequest)
            })
            
            try await app.test(.GET, "members/\(id)", afterResponse: { res async throws in
                XCTAssertEqual(try res.content.decode(MemberDTO.self).name, "Camille")
            })
        }
    }
    
    func testUpdateMemberWithInvalidEmailIsRejected() async throws {
        try await withApp { app in
            let member = try await createMember(app)
            let id = try XCTUnwrap(member.id)
            
            try await app.test(.PUT, "members/\(id)", beforeRequest: { req in
                try req.content.encode(CreateMemberDTO(name: "Camille", email: "not-an-email"))
            }, afterResponse: { res async throws in
                XCTAssertEqual(res.status, .badRequest)
            })
        }
    }
    
    func testUpdateMemberWithMalformedIDReturnsBadRequest() async throws {
        try await withApp { app in
            try await app.test(.PUT, "members/not-a-uuid", beforeRequest: { req in
                try req.content.encode(CreateMemberDTO(name: "Alex", email: "alex@example.com"))
            }, afterResponse: { res async throws in
                XCTAssertEqual(res.status, .badRequest)
            })
        }
    }
    
    func testUpdateUnknownMemberReturnsNotFound() async throws {
        try await withApp { app in
            try await app.test(.PUT, "members/\(UUID())", beforeRequest: { req in
                try req.content.encode(CreateMemberDTO(name: "Alex", email: "alex@example.com"))
            }, afterResponse: { res async throws in
                XCTAssertEqual(res.status, .notFound)
            })
        }
    }
    
    func testDeleteMemberReturnsNoContent() async throws {
        try await withApp { app in
            let member = try await createMember(app)
            let id = try XCTUnwrap(member.id)

            try await app.test(.DELETE, "members/\(id)", afterResponse: { res async throws in
                XCTAssertEqual(res.status, .noContent)
            })

            try await app.test(.GET, "members/\(id)", afterResponse: { res async throws in
                XCTAssertEqual(res.status, .notFound)
            })
        }
    }

    func testDeleteUnknownMemberReturnsNotFound() async throws {
        try await withApp { app in
            try await app.test(.DELETE, "members/\(UUID())", afterResponse: { res async throws in
                XCTAssertEqual(res.status, .notFound)
            })
        }
    }

    func testDeleteMemberWithActiveLoanReturnsConflict() async throws {
        try await withApp { app in
            let game = try await createGame(app)
            let member = try await createMember(app)
            let memberID = try XCTUnwrap(member.id)
            let now = Date()
            try await insertLoan(
                app,
                gameID: try XCTUnwrap(game.id),
                memberID: memberID,
                borrowedAt: now,
                dueAt: try Loan.dueDate(from: now)
            )

            try await app.test(.DELETE, "members/\(memberID)", afterResponse: { res async throws in
                XCTAssertEqual(res.status, .conflict)
            })

            try await app.test(.GET, "members/\(memberID)", afterResponse: { res async throws in
                XCTAssertEqual(res.status, .ok)
            })
        }
    }

    func testDeleteMemberWithReturnedLoanReturnsConflict() async throws {
        try await withApp { app in
            let game = try await createGame(app)
            let member = try await createMember(app)
            let memberID = try XCTUnwrap(member.id)
            let now = Date()
            try await insertLoan(
                app,
                gameID: try XCTUnwrap(game.id),
                memberID: memberID,
                borrowedAt: now,
                dueAt: try Loan.dueDate(from: now),
                returnedAt: now
            )

            try await app.test(.DELETE, "members/\(memberID)", afterResponse: { res async throws in
                XCTAssertEqual(res.status, .conflict)
            })

            try await app.test(.GET, "members/\(memberID)", afterResponse: { res async throws in
                XCTAssertEqual(res.status, .ok)
            })
        }
    }
}
