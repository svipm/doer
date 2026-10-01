import XCTest
@testable import Doer

final class ForumAPIHostAliasTests: XCTestCase {
    func testRewritesLinuxDoAPIRequestsWhenEnabled() {
        XCTAssertEqual(
            ForumAPIHostAlias.apiRequestURL(
                base: "https://linux.do",
                path: "/topics/timings",
                enabled: true
            ),
            "https://ios.linux.do/topics/timings"
        )
    }

    func testKeepsCanonicalURLForOtherFormsNonHTTPSAndDisabled() {
        XCTAssertNil(
            ForumAPIHostAlias.apiRequestURL(
                base: "https://linux.do",
                path: "/session/csrf.json",
                enabled: false
            )
        )
        XCTAssertNil(
            ForumAPIHostAlias.apiRequestURL(
                base: "https://forum.example.com",
                path: "/site.json",
                enabled: true
            )
        )
        XCTAssertNil(
            ForumAPIHostAlias.apiRequestURL(
                base: "http://linux.do",
                path: "/site.json",
                enabled: true
            )
        )
    }

    func testCanonicalizesAliasURLsForCookieDecisions() {
        XCTAssertEqual(
            ForumAPIHostAlias.canonicalized(URL(string: "https://ios.linux.do/topics/timings")!),
            URL(string: "https://linux.do/topics/timings")!
        )
        let other = URL(string: "https://forum.example.com/site.json")!
        XCTAssertEqual(ForumAPIHostAlias.canonicalized(other), other)
    }

    func testUnreachableTransportErrorsExcludeTimeouts() {
        XCTAssertTrue(
            ForumAPIHostAlias.isUnreachableTransportError(URLError(.cannotConnectToHost))
        )
        XCTAssertTrue(
            ForumAPIHostAlias.isUnreachableTransportError(URLError(.cannotFindHost))
        )
        // A timeout may mean the request landed; replaying a POST could
        // double-apply, so timeouts are deliberately not "unreachable".
        XCTAssertFalse(
            ForumAPIHostAlias.isUnreachableTransportError(URLError(.timedOut))
        )
        XCTAssertFalse(ForumAPIHostAlias.isUnreachableTransportError(nil))
    }
}
