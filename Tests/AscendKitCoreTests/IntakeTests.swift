import Foundation
import Testing
@testable import AscendKitCore

@Suite("Project discovery")
struct IntakeTests {
    @Test("discovers project build settings from pbxproj")
    func discoversProjectSettings() throws {
        let root = try TemporaryDirectory()
        let project = root.url.appendingPathComponent("Demo.xcodeproj")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        let pbxproj = project.appendingPathComponent("project.pbxproj")
        let content = """
        /* Begin PBXNativeTarget section */
          1A2B3C4D5E6F7A8B9C0D1111 /* Demo */ = {
            isa = PBXNativeTarget;
            buildConfigurationList = 1A2B3C4D5E6F7A8B9C0D2222 /* Build configuration list for PBXNativeTarget "Demo" */;
            name = Demo;
          };
        /* End PBXNativeTarget section */
        /* Begin XCBuildConfiguration section */
          1A2B3C4D5E6F7A8B9C0D3333 /* Release */ = {
            isa = XCBuildConfiguration;
            buildSettings = {
              PRODUCT_BUNDLE_IDENTIFIER = com.example.demo;
              MARKETING_VERSION = 1.2.3;
              CURRENT_PROJECT_VERSION = 45;
              INFOPLIST_FILE = Demo/Info.plist;
              ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
              CODE_SIGN_ENTITLEMENTS = Demo/Demo.entitlements;
              SUPPORTED_PLATFORMS = "iphoneos iphonesimulator";
            };
            name = Release;
          };
        /* End XCBuildConfiguration section */
        /* Begin XCConfigurationList section */
          1A2B3C4D5E6F7A8B9C0D2222 /* Build configuration list for PBXNativeTarget "Demo" */ = {
            isa = XCConfigurationList;
            buildConfigurations = (
              1A2B3C4D5E6F7A8B9C0D3333 /* Release */,
            );
            defaultConfigurationName = Release;
          };
        /* End XCConfigurationList section */
        """
        try Data(content.utf8).write(to: pbxproj)

        let report = try ProjectDiscovery().inspect(options: IntakeOptions(searchRoot: root.url.path))

        #expect(report.manifest.projects.count == 1)
        #expect(report.manifest.targets.first?.bundleIdentifier == "com.example.demo")
        #expect(report.manifest.targets.first?.appIconName == "AppIcon")
        #expect(report.manifest.targets.first?.entitlementsPath == "Demo/Demo.entitlements")
        #expect(report.manifest.targets.first?.version.marketingVersion == "1.2.3")
        #expect(report.manifest.releaseID == "demo-1.2.3-b45")
    }

    @Test("skips vendored projects during discovery")
    func skipsVendoredProjects() throws {
        let root = try TemporaryDirectory()
        let appProject = root.url.appendingPathComponent("App.xcodeproj")
        let vendoredProject = root.url.appendingPathComponent("vendor/bundle/gems/Tool.xcodeproj")
        try FileManager.default.createDirectory(at: appProject, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: vendoredProject, withIntermediateDirectories: true)
        try Data("".utf8).write(to: appProject.appendingPathComponent("project.pbxproj"))
        try Data("".utf8).write(to: vendoredProject.appendingPathComponent("project.pbxproj"))

        let report = try ProjectDiscovery().inspect(options: IntakeOptions(searchRoot: root.url.path))

        #expect(report.manifest.projects.map(\.path) == [appProject.path])
    }
}
