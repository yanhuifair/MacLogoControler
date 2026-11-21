import Foundation
import MacLogoControlCore

@MainActor
func macFinishTests(_ t: TestHarness) {
    print("\nMac finish (for the live view)")

    t.test("reads the finish from a device type identifier") {
        t.expectEqual(MacFinish(deviceTypeIdentifier: "com.apple.macbookpro-dynamic-island-2026-14-space-black"), .spaceBlack)
        t.expectEqual(MacFinish(deviceTypeIdentifier: "com.apple.macbookpro-dynamic-island-2026-14-silver"), .silver)
        t.expectEqual(MacFinish(deviceTypeIdentifier: "com.apple.macbookair-2022-midnight"), .spaceBlack)
        t.expectEqual(MacFinish(deviceTypeIdentifier: "com.apple.macbookair-2022-starlight"), .silver)
        t.expectEqual(MacFinish(deviceTypeIdentifier: "dyn.age4d4xpbqq2xs1bqge3yavndm7ge8yw6hy2a"), nil)
        t.expectEqual(MacFinish(deviceTypeIdentifier: "com.apple.macbookair-2024-sky-blue"), nil)
    }

    t.test("takes the colour code from the last word of housing-color") {
        let spaceBlack = Data([1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 9, 0, 0, 0])
        t.expectEqual(MacFinish.enclosureColorCode(fromHousingColor: spaceBlack), 9)
        t.expectEqual(MacFinish.enclosureColorCode(fromHousingColor: Data([1, 0, 0, 0])), 1)
        t.expectEqual(MacFinish.enclosureColorCode(fromHousingColor: Data()), nil)
        t.expectEqual(MacFinish.enclosureColorCode(fromHousingColor: Data([1, 2, 3])), nil)
    }

    t.test("this Mac's finish (read-only)") {
        guard let finish = MacFinish.current() else { try t.skip("this Mac doesn't report its finish") }
        print("    this Mac is \(finish)")
    }

    t.test("reads the lid size from a device type identifier") {
        t.expectEqual(MacLid(deviceTypeIdentifier: "com.apple.macbookpro-dynamic-island-2026-14-space-black"), .fourteen)
        t.expectEqual(MacLid(deviceTypeIdentifier: "com.apple.macbookpro-dynamic-island-2026-16-silver"), .sixteen)
        t.expectEqual(MacLid(deviceTypeIdentifier: "com.apple.macbookair-2022-midnight"), nil)
        t.expectEqual(MacLid(deviceTypeIdentifier: "com.apple.macmini-2024-silver"), nil)
        t.expect(MacLid.allCases.map(\.title) == ["14″", "16″"], "the tabs' titles")
    }

    t.test("this Mac's lid size (read-only)") {
        guard let lid = MacLid.current() else { try t.skip("this Mac doesn't report its lid size") }
        print("    this Mac has a \(lid.title) lid")
    }
}
