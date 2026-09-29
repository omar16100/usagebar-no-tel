import XCTest
@testable import OpenUsage

final class ICloudUsageHistoryFileStoreTests: XCTestCase, @unchecked Sendable {
    func testUnprovisionedMacsShareDriveHistoryAndDeleteOnlyTheirOwnFile() async throws {
        let drive = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: drive) }
        let first = ICloudUsageHistoryFileStore(containerURL: { nil }, driveRoot: drive)
        let second = ICloudUsageHistoryFileStore(containerURL: { nil }, driveRoot: drive)
        try await first.write(document("first"))
        try await second.write(document("second"))

        let loaded = try await first.loadDocuments()
        XCTAssertEqual(Set(loaded.documents.map(\.deviceID)), ["first", "second"])
        XCTAssertTrue(loaded.invalidFileMessages.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: drive.appendingPathComponent("UsageBar/History/v1/first.json").path
        ))

        try await first.delete(deviceID: "first")
        let remaining = try await second.loadDocuments()
        XCTAssertEqual(remaining.documents.map(\.deviceID), ["second"])
    }

    func testMissingDriveFailsWithoutCreatingFakeICloudRoot() async throws {
        let parent = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: parent) }
        let drive = parent.appendingPathComponent("unavailable-drive")
        let store = ICloudUsageHistoryFileStore(containerURL: { nil }, driveRoot: drive)
        do {
            try await store.write(document("first"))
            XCTFail("A missing iCloud Drive must not appear to sync successfully")
        } catch ICloudUsageSyncError.unavailable {
            XCTAssertFalse(FileManager.default.fileExists(atPath: drive.path))
        }
    }

    func testProvisionedContainerKeepsExistingHistoryLocation() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let container = root.appendingPathComponent("container")
        let store = ICloudUsageHistoryFileStore(
            privateContainerProvisioned: true, containerURL: { container }, driveRoot: root
        )
        try await store.write(document("first"))
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: container.appendingPathComponent("OpenUsage/History/v1/first.json").path
        ))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("UsageBar").path))
    }

    func testUnprovisionedBuildIgnoresContainerURLEvenWhenMacOSReturnsOne() async throws {
        let drive = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: drive) }
        let unusableContainer = drive.appendingPathComponent("unprovisioned-container")
        let store = ICloudUsageHistoryFileStore(
            privateContainerProvisioned: false, containerURL: { unusableContainer }, driveRoot: drive
        )
        try await store.write(document("first"))
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: drive.appendingPathComponent("UsageBar/History/v1/first.json").path
        ))
        XCTAssertFalse(FileManager.default.fileExists(atPath: unusableContainer.path))
    }

    func testCorruptPeerDoesNotHideValidHistory() async throws {
        let drive = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: drive) }
        let store = ICloudUsageHistoryFileStore(containerURL: { nil }, driveRoot: drive)
        try await store.write(document("valid"))
        let directory = drive.appendingPathComponent("UsageBar/History/v1")
        try Data("invalid".utf8).write(to: directory.appendingPathComponent("broken.json"))
        try Data("ignored".utf8).write(to: directory.appendingPathComponent(".temporary.json"))
        let loaded = try await store.loadDocuments()
        XCTAssertEqual(loaded.documents.map(\.deviceID), ["valid"])
        XCTAssertEqual(loaded.invalidFileMessages.count, 1)
        XCTAssertTrue(loaded.invalidFileMessages[0].contains("broken.json"))
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func document(_ id: String) -> UsageHistoryDocument {
        UsageHistoryDocument(deviceID: id, deviceName: id, updatedAt: .now, providers: [:])
    }
}
