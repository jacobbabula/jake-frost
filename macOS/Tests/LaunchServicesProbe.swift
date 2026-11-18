import AppKit
import CoreServices

@main struct LaunchServicesProbe {
    static func require(_ condition: Bool, _ message: String) throws {
        if !condition { throw GiftProblem.message(message) }
    }

    static func path(_ url: URL?) -> String? {
        url?.standardizedFileURL.resolvingSymlinksInPath().path
    }

    @MainActor static func stop(_ app: NSRunningApplication) async -> Bool {
        _ = app.terminate()
        for attempt in 0..<40 {
            if app.isTerminated { return true }
            if attempt == 24 { _ = app.forceTerminate() }
            try? await Task.sleep(nanoseconds:125_000_000)
        }
        return app.isTerminated
    }

    @MainActor static func receipt(for gift: FrostGift, in root: URL, app: NSRunningApplication) async throws {
        let filename = gift.id + ".fpgift"
        let pending = root.appendingPathComponent("Pending").appendingPathComponent(filename)
        let received = root.appendingPathComponent("Received").appendingPathComponent(filename)
        for _ in 0..<240 {
            try require(!app.isTerminated, "Jake Frost quit before delivering \(filename)")
            if FileManager.default.fileExists(atPath: received.path) {
                let archived = try FrostGift.read(received)
                try require(try archived.encoded() == gift.encoded(), "Received gift contents changed")
                try require(!FileManager.default.fileExists(atPath: pending.path), "Received gift is still pending")
                return
            }
            try await Task.sleep(nanoseconds: 250_000_000)
        }
        let state = FileManager.default.fileExists(atPath: pending.path) ? "still pending" : "never imported"
        throw GiftProblem.message("Timed out waiting for \(filename) in the isolated mailbox (\(state))")
    }

    @MainActor static func run() async throws {
        let args = CommandLine.arguments
        try require(args.count == 5, "Expected installed app, Windows gift, Mac gift, and empty mailbox path")
        let appURL = URL(fileURLWithPath:args[1], isDirectory:true)
        let coldURL = URL(fileURLWithPath:args[2]), warmURL = URL(fileURLWithPath:args[3])
        let mailbox = URL(fileURLWithPath:args[4], isDirectory:true)
        let coldGift = try FrostGift.read(coldURL), warmGift = try FrostGift.read(warmURL)
        try require(!FileManager.default.fileExists(atPath:mailbox.path), "Expected a new test mailbox")
        try require(coldGift.id != warmGift.id, "Cold and warm fixtures have the same gift ID")
        guard let bundleID = Bundle(url:appURL)?.bundleIdentifier else { throw GiftProblem.message("Invalid app bundle") }
        try require(NSRunningApplication.runningApplications(withBundleIdentifier:bundleID).isEmpty,
                    "Quit Jake Frost before running its isolated cold-open test")

        let workspace = NSWorkspace.shared
        let status = LSRegisterURL(appURL as CFURL, true)
        try require(status == noErr, "Could not register the installed app (\(status))")
        var handler: URL?
        for _ in 0..<20 {
            handler = workspace.urlForApplication(toOpen:coldURL)
            if path(handler) == path(appURL) { break }
            try await Task.sleep(nanoseconds:250_000_000)
        }
        try require(path(handler) == path(appURL), "Default .fpgift handler was \(handler?.path ?? "missing"), expected \(appURL.path)")

        let config = NSWorkspace.OpenConfiguration()
        config.environment = ["JAKE_FROST_TEST_MAILBOX":mailbox.path]
        let cold = try await workspace.open(coldURL, configuration:config)
        try require(path(cold.bundleURL) == path(appURL), "Cold open launched a different bundle")
        do {
            try await receipt(for:coldGift, in:mailbox, app:cold)
            print("PASS: default macOS file association cold-launched the installed app and delivered the Windows gift")
            let warm = try await workspace.open(warmURL, configuration:NSWorkspace.OpenConfiguration())
            try require(warm.processIdentifier == cold.processIdentifier && path(warm.bundleURL) == path(appURL),
                        "Warm open used a different process or bundle")
            try await receipt(for:warmGift, in:mailbox, app:warm)
            print("PASS: a second document opened in the same running app and its gift reached the desktop")
        } catch {
            _ = await stop(cold)
            throw error
        }
        try require(await stop(cold), "The test app did not exit")
    }

    @MainActor static func main() async {
        do { try await run() }
        catch {
            FileHandle.standardError.write(Data(("FAIL: " + error.localizedDescription + "\n").utf8))
            exit(1)
        }
    }
}
