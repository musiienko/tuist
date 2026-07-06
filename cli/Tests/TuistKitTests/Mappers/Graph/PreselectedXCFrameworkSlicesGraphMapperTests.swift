import FileSystem
import FileSystemTesting
import Path
import Testing
import TuistCore
import TuistTesting
import XcodeGraph
@testable import TuistKit

struct PreselectedXCFrameworkSlicesGraphMapperTests {
    private let fileSystem = FileSystem()
    private let subject = PreselectedXCFrameworkSlicesGraphMapper()

    @Test(.inTemporaryDirectory)
    func map_preselects_unambiguous_framework_slices_for_each_supported_sdk() async throws {
        // Given
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let projectPath = temporaryDirectory.appending(component: "Project")
        let xcframeworkPath = projectPath.parentDirectory.appending(component: "Kit.xcframework")

        try await makeFramework(named: "Kit", in: xcframeworkPath.appending(component: "ios-arm64"))
        try await makeFramework(named: "Kit", in: xcframeworkPath.appending(component: "ios-arm64_x86_64-simulator"))
        try await makeFramework(named: "Kit", in: xcframeworkPath.appending(component: "macos-arm64_x86_64"))

        let xcframeworkDependency = GraphDependency.testXCFramework(
            path: xcframeworkPath,
            infoPlist: XCFrameworkInfoPlist(libraries: [
                .test(
                    identifier: "ios-arm64",
                    path: try RelativePath(validating: "Kit.framework"),
                    platform: .iOS
                ),
                .test(
                    identifier: "ios-arm64_x86_64-simulator",
                    path: try RelativePath(validating: "Kit.framework"),
                    platform: .iOS,
                    platformVariant: .simulator
                ),
                .test(
                    identifier: "macos-arm64_x86_64",
                    path: try RelativePath(validating: "Kit.framework"),
                    platform: .macOS
                ),
            ]),
            linking: .static
        )

        let graph = Graph.test(
            name: "App",
            path: projectPath,
            projects: [
                projectPath: .test(
                    path: projectPath,
                    targets: [
                        .test(
                            name: "App",
                            destinations: [.iPhone, .iPad, .mac],
                            product: .app
                        ),
                    ]
                ),
            ],
            dependencies: [
                .target(name: "App", path: projectPath): [
                    xcframeworkDependency,
                ],
            ]
        )

        // When
        let (gotGraph, gotSideEffects, _) = try subject.map(graph: graph, environment: MapperEnvironment())

        // Then
        #expect(gotGraph.dependencies[.target(name: "App", path: projectPath)] == [])

        let settings = try #require(gotGraph.projects[projectPath]?.targets["App"]?.settings?.base)
        #expect(settings["FRAMEWORK_SEARCH_PATHS[sdk=iphoneos*]"] == .array([
            "$(inherited)",
            "$(SRCROOT)/Derived/PreselectedXCFrameworkSlices/App/iphoneos",
        ]))
        #expect(settings["FRAMEWORK_SEARCH_PATHS[sdk=iphonesimulator*]"] == .array([
            "$(inherited)",
            "$(SRCROOT)/Derived/PreselectedXCFrameworkSlices/App/iphonesimulator",
        ]))
        #expect(settings["FRAMEWORK_SEARCH_PATHS[sdk=macosx*]"] == .array([
            "$(inherited)",
            "$(SRCROOT)/Derived/PreselectedXCFrameworkSlices/App/macosx",
        ]))
        #expect(settings["OTHER_LDFLAGS[sdk=macosx*]"] == .array([
            "$(inherited)",
            "\"@$(SRCROOT)/Derived/PreselectedXCFrameworkSlices/App/macosx/App-macosx.resp\"",
        ]))

        let sourceRootPath = try #require(gotGraph.projects[projectPath]?.sourceRootPath)

        #expect(
            gotSideEffects.contains { sideEffect in
                guard case let .symbolicLink(descriptor) = sideEffect else { return false }
                return descriptor.path == sourceRootPath
                    .appending(components: "Derived", "PreselectedXCFrameworkSlices", "App", "macosx", "Kit.framework") &&
                    descriptor.destination == xcframeworkPath
                    .appending(components: "macos-arm64_x86_64", "Kit.framework")
            }
        )
        let macOSFrameworkDirectory = sourceRootPath
            .appending(components: "Derived", "PreselectedXCFrameworkSlices", "App", "macosx")
        let expectedResponseFileContents = "-F\(macOSFrameworkDirectory.pathString)\n-framework\nKit\n"
        #expect(
            gotSideEffects.contains { sideEffect in
                guard case let .file(descriptor) = sideEffect else { return false }
                return descriptor.path == sourceRootPath
                    .appending(components: "Derived", "PreselectedXCFrameworkSlices", "App", "macosx", "App-macosx.resp") &&
                    descriptor.contents.flatMap { String(data: $0, encoding: .utf8) } ==
                    expectedResponseFileContents
            }
        )
    }

    private func makeFramework(named name: String, in directory: AbsolutePath) async throws {
        let frameworkPath = directory.appending(component: "\(name).framework")
        try await fileSystem.makeDirectory(at: frameworkPath)
    }
}
