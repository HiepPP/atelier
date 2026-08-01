import Foundation
import Testing
@testable import Atelier

@Suite("Ignore rules")
struct IgnoreRulesTests {
    @Test("Always-hidden names stay hidden from Explorer")
    func hiddenNames() {
        #expect(IgnoreRules.shouldIgnore(URL(fileURLWithPath: "/root/node_modules")))
        #expect(IgnoreRules.shouldIgnore(URL(fileURLWithPath: "/root/.git")))
        #expect(IgnoreRules.shouldIgnore(URL(fileURLWithPath: "/root/.build")))
        #expect(IgnoreRules.shouldIgnore(URL(fileURLWithPath: "/root/DerivedData")))
    }

    @Test("Generated output stays visible in Explorer")
    func generatedNamesRemainVisible() {
        for name in ["dist", "build", "target", ".next", "Pods", ".venv", "out"] {
            #expect(!IgnoreRules.shouldIgnore(URL(fileURLWithPath: "/root/\(name)")))
        }
    }

    @Test("Generated output is skipped by the workspace file index")
    func generatedNamesSkipIndexing() {
        for name in ["dist", "build", "target", ".next", "Pods", ".venv", "out"] {
            #expect(IgnoreRules.shouldSkipIndexing(URL(fileURLWithPath: "/root/\(name)")))
        }
        #expect(IgnoreRules.shouldSkipIndexing(URL(fileURLWithPath: "/root/node_modules")))
        #expect(!IgnoreRules.shouldSkipIndexing(URL(fileURLWithPath: "/root/Sources")))
    }

    @Test("Watcher ignores event paths inside generated directories")
    func eventPaths() {
        #expect(IgnoreRules.shouldIgnoreEventPath("/root/dist/app.js"))
        #expect(IgnoreRules.shouldIgnoreEventPath("/root/app/target/debug/binary"))
        #expect(IgnoreRules.shouldIgnoreEventPath("/root/.next/cache/entry"))
        #expect(IgnoreRules.shouldIgnoreEventPath("/root/node_modules/pkg/index.js"))
        #expect(!IgnoreRules.shouldIgnoreEventPath("/root/Sources/App/Main.swift"))
        #expect(!IgnoreRules.shouldIgnoreEventPath("/root/distribution/plan.md"))
    }
}
