#!/usr/bin/env python3
"""Generate AudioNinja.xcodeproj/project.pbxproj.

The output matches Xcode's own serialisation: the same key order, quoting and object order Xcode
writes when it saves. Opening the project and saving it therefore changes nothing, and CI's drift
check only catches real differences. A setting changed in Xcode's editor must be copied here.

Hand-maintaining a pbxproj is unpleasant, and neither xcodegen nor tuist is installed. This
generator keeps the file reproducible and reviewable: the project is small (one multiplatform app
target plus a local package reference), and because the app's sources live in a
PBXFileSystemSynchronizedRootGroup, adding Swift files never requires regenerating it.
"""

import pathlib
import sys

# Xcode 16 introduced PBXFileSystemSynchronizedRootGroup along with objectVersion 77.
OBJECT_VERSION = sys.argv[1] if len(sys.argv) > 1 else "77"

APP = "AudioNinja"
BUNDLE_ID = "com.simplepatrick.AudioNinja"
TEAM_ID = "XJ77XT4Z9Y"

# Stable 24-hex-digit ids. Hand-assigned so regenerating produces an identical file.
ID = {
    "project":        "A00000000000000000000001",
    "appTarget":      "A00000000000000000000002",
    "appProduct":     "A00000000000000000000003",
    "syncGroup":      "A00000000000000000000004",
    "rootGroup":      "A00000000000000000000005",
    "productsGroup":  "A00000000000000000000006",
    "supportGroup":   "A00000000000000000000007",
    "sources":        "A00000000000000000000008",
    "frameworks":     "A00000000000000000000009",
    "resources":      "A000000000000000000000A",
    "projectConfigs": "A000000000000000000000B",
    "appConfigs":     "A000000000000000000000C",
    "projectDebug":   "A000000000000000000000D",
    "projectRelease": "A000000000000000000000E",
    "appDebug":       "A000000000000000000000F",
    "appRelease":     "A0000000000000000000010",
    "pkgRef":         "A0000000000000000000011",
    "pkgProduct":     "A0000000000000000000012",
    "pkgBuildFile":   "A0000000000000000000013",
    "infoPlist":      "A0000000000000000000014",
    "entitlements":   "A0000000000000000000015",
}

SHARED_SETTINGS = {
    "ALWAYS_SEARCH_USER_PATHS": "NO",
    "CLANG_ENABLE_MODULES": "YES",
    "CLANG_ENABLE_OBJC_ARC": "YES",
    "ENABLE_STRICT_OBJC_MSGSEND": "YES",
    "GCC_NO_COMMON_BLOCKS": "YES",
    "SDKROOT": "auto",
    "SUPPORTED_PLATFORMS": '"iphoneos iphonesimulator macosx"',
    "MACOSX_DEPLOYMENT_TARGET": "27.0",
    "IPHONEOS_DEPLOYMENT_TARGET": "27.0",
    "SWIFT_VERSION": "6.0",
    "SWIFT_STRICT_CONCURRENCY": "complete",
    "ENABLE_USER_SCRIPT_SANDBOXING": "YES",
}

DEBUG_ONLY = {
    "DEBUG_INFORMATION_FORMAT": "dwarf",
    "ENABLE_TESTABILITY": "YES",
    "GCC_OPTIMIZATION_LEVEL": "0",
    "ONLY_ACTIVE_ARCH": "YES",
    "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "DEBUG",
    "SWIFT_OPTIMIZATION_LEVEL": '"-Onone"',
}

RELEASE_ONLY = {
    "DEBUG_INFORMATION_FORMAT": '"dwarf-with-dsym"',
    "SWIFT_COMPILATION_MODE": "wholemodule",
}

APP_SETTINGS = {
    "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
    # No ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME: the app deliberately uses the system
    # accent colour, and naming an asset that the catalog does not contain only produces warnings.
    # macOS only. The file holds the App Sandbox keys, which are meaningless on iOS and which App
    # Store Connect rejects in an iOS binary.
    '"CODE_SIGN_ENTITLEMENTS[sdk=macosx*]"': "Support/AudioNinja.entitlements",
    "CODE_SIGN_STYLE": "Automatic",
    "CURRENT_PROJECT_VERSION": "4",
    "DEVELOPMENT_TEAM": TEAM_ID,
    "ENABLE_HARDENED_RUNTIME": "YES",
    "ENABLE_PREVIEWS": "YES",
    "GENERATE_INFOPLIST_FILE": "YES",
    "INFOPLIST_FILE": '"Support/AudioNinja-Info.plist"',
    "INFOPLIST_KEY_CFBundleDisplayName": "\"Audio Ninja\"",
    # The app uses no encryption beyond the OS's own, so no export-compliance question per upload.
    "INFOPLIST_KEY_ITSAppUsesNonExemptEncryption": "NO",
    "INFOPLIST_KEY_LSApplicationCategoryType": '"public.app-category.music"',
    "INFOPLIST_KEY_NSHumanReadableCopyright": '""',
    # iOS keys, as Xcode's multiplatform Document App template sets them. Without the orientation
    # lists App Store Connect refuses an iPad build (iPad multitasking needs all four), and without
    # UISupportsDocumentBrowser the files the app opens are not declared as edited in place.
    '"INFOPLIST_KEY_UIApplicationSceneManifest_Generation[sdk=iphoneos*]"': "YES",
    '"INFOPLIST_KEY_UIApplicationSceneManifest_Generation[sdk=iphonesimulator*]"': "YES",
    '"INFOPLIST_KEY_UIApplicationSupportsIndirectInputEvents[sdk=iphoneos*]"': "YES",
    '"INFOPLIST_KEY_UIApplicationSupportsIndirectInputEvents[sdk=iphonesimulator*]"': "YES",
    '"INFOPLIST_KEY_UILaunchScreen_Generation[sdk=iphoneos*]"': "YES",
    '"INFOPLIST_KEY_UILaunchScreen_Generation[sdk=iphonesimulator*]"': "YES",
    '"INFOPLIST_KEY_UISupportsDocumentBrowser[sdk=iphoneos*]"': "YES",
    '"INFOPLIST_KEY_UISupportsDocumentBrowser[sdk=iphonesimulator*]"': "YES",
    "INFOPLIST_KEY_UISupportedInterfaceOrientations_iPad": (
        '"UIInterfaceOrientationPortrait UIInterfaceOrientationPortraitUpsideDown '
        'UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight"'
    ),
    "INFOPLIST_KEY_UISupportedInterfaceOrientations_iPhone": (
        '"UIInterfaceOrientationPortrait UIInterfaceOrientationLandscapeLeft '
        'UIInterfaceOrientationLandscapeRight"'
    ),
    "MARKETING_VERSION": "1.0",
    "PRODUCT_BUNDLE_IDENTIFIER": BUNDLE_ID,
    "PRODUCT_NAME": '"$(TARGET_NAME)"',
    "SWIFT_EMIT_LOC_STRINGS": "YES",
    "TARGETED_DEVICE_FAMILY": '"1,2"',
    # UI code should default to the main actor; the package deliberately does not set this, so its
    # decode/encode/peak work stays nonisolated and genuinely runs off the main thread.
    "SWIFT_DEFAULT_ACTOR_ISOLATION": "MainActor",
}


def settings_block(pairs, indent):
    pad = "\t" * indent
    # Xcode orders keys as if their quotes were not there.
    return "".join(
        f"{pad}{k} = {v};\n" for k, v in sorted(pairs.items(), key=lambda kv: kv[0].strip('"'))
    )


def build_config(cfg_id, name, pairs, indent=2):
    pad = "\t" * indent
    return (
        f"{pad}{cfg_id} /* {name} */ = {{\n"
        f"{pad}\tisa = XCBuildConfiguration;\n"
        f"{pad}\tbuildSettings = {{\n"
        f"{settings_block(pairs, indent + 2)}"
        f"{pad}\t}};\n"
        f"{pad}\tname = {name};\n"
        f"{pad}}};\n"
    )


def main():
    project_debug = {**SHARED_SETTINGS, **DEBUG_ONLY}
    project_release = {**SHARED_SETTINGS, **RELEASE_ONLY}
    app_debug = dict(APP_SETTINGS)
    app_release = dict(APP_SETTINGS)

    out = []
    w = out.append

    w("// !$*UTF8*$!\n{\n")
    w("\tarchiveVersion = 1;\n\tclasses = {\n\t};\n")
    w(f"\tobjectVersion = {OBJECT_VERSION};\n")
    w("\tobjects = {\n\n")

    w("/* Begin PBXBuildFile section */\n")
    w(f"\t\t{ID['pkgBuildFile']} /* AudioNinjaKit in Frameworks */ = {{isa = PBXBuildFile; "
      f"productRef = {ID['pkgProduct']} /* AudioNinjaKit */; }};\n")
    w("/* End PBXBuildFile section */\n\n")

    w("/* Begin PBXFileReference section */\n")
    w(f"\t\t{ID['appProduct']} /* {APP}.app */ = {{isa = PBXFileReference; "
      f"explicitFileType = wrapper.application; includeInIndex = 0; "
      f'path = {APP}.app; sourceTree = BUILT_PRODUCTS_DIR; }};\n')
    w(f"\t\t{ID['infoPlist']} /* {APP}-Info.plist */ = {{isa = PBXFileReference; "
      f'lastKnownFileType = text.plist.xml; path = "{APP}-Info.plist"; sourceTree = "<group>"; }};\n')
    w(f"\t\t{ID['entitlements']} /* {APP}.entitlements */ = {{isa = PBXFileReference; "
      f'lastKnownFileType = text.plist.entitlements; path = {APP}.entitlements; sourceTree = "<group>"; }};\n')
    w("/* End PBXFileReference section */\n\n")

    w("/* Begin PBXFileSystemSynchronizedRootGroup section */\n")
    w(f"\t\t{ID['syncGroup']} /* {APP} */ = {{\n"
      f"\t\t\tisa = PBXFileSystemSynchronizedRootGroup;\n"
      f"\t\t\tpath = {APP};\n"
      f'\t\t\tsourceTree = "<group>";\n'
      f"\t\t}};\n")
    w("/* End PBXFileSystemSynchronizedRootGroup section */\n\n")

    w("/* Begin PBXFrameworksBuildPhase section */\n")
    w(f"\t\t{ID['frameworks']} /* Frameworks */ = {{\n"
      f"\t\t\tisa = PBXFrameworksBuildPhase;\n"
      f"\t\t\tbuildActionMask = 2147483647;\n"
      f"\t\t\tfiles = (\n\t\t\t\t{ID['pkgBuildFile']} /* AudioNinjaKit in Frameworks */,\n\t\t\t);\n"
      f"\t\t\trunOnlyForDeploymentPostprocessing = 0;\n"
      f"\t\t}};\n")
    w("/* End PBXFrameworksBuildPhase section */\n\n")

    w("/* Begin PBXGroup section */\n")
    w(f"\t\t{ID['rootGroup']} = {{\n"
      f"\t\t\tisa = PBXGroup;\n"
      f"\t\t\tchildren = (\n"
      f"\t\t\t\t{ID['syncGroup']} /* {APP} */,\n"
      f"\t\t\t\t{ID['supportGroup']} /* Support */,\n"
      f"\t\t\t\t{ID['productsGroup']} /* Products */,\n"
      f"\t\t\t);\n"
      f'\t\t\tsourceTree = "<group>";\n'
      f"\t\t}};\n")
    w(f"\t\t{ID['productsGroup']} /* Products */ = {{\n"
      f"\t\t\tisa = PBXGroup;\n"
      f"\t\t\tchildren = (\n\t\t\t\t{ID['appProduct']} /* {APP}.app */,\n\t\t\t);\n"
      f"\t\t\tname = Products;\n"
      f'\t\t\tsourceTree = "<group>";\n'
      f"\t\t}};\n")
    w(f"\t\t{ID['supportGroup']} /* Support */ = {{\n"
      f"\t\t\tisa = PBXGroup;\n"
      f"\t\t\tchildren = (\n"
      f"\t\t\t\t{ID['infoPlist']} /* {APP}-Info.plist */,\n"
      f"\t\t\t\t{ID['entitlements']} /* {APP}.entitlements */,\n"
      f"\t\t\t);\n"
      f"\t\t\tpath = Support;\n"
      f'\t\t\tsourceTree = "<group>";\n'
      f"\t\t}};\n")
    w("/* End PBXGroup section */\n\n")

    w("/* Begin PBXNativeTarget section */\n")
    w(f"\t\t{ID['appTarget']} /* {APP} */ = {{\n"
      f"\t\t\tisa = PBXNativeTarget;\n"
      f"\t\t\tbuildConfigurationList = {ID['appConfigs']} /* Build configuration list for PBXNativeTarget \"{APP}\" */;\n"
      f"\t\t\tbuildPhases = (\n"
      f"\t\t\t\t{ID['sources']} /* Sources */,\n"
      f"\t\t\t\t{ID['frameworks']} /* Frameworks */,\n"
      f"\t\t\t\t{ID['resources']} /* Resources */,\n"
      f"\t\t\t);\n"
      f"\t\t\tbuildRules = (\n\t\t\t);\n"
      f"\t\t\tdependencies = (\n\t\t\t);\n"
      f"\t\t\tfileSystemSynchronizedGroups = (\n\t\t\t\t{ID['syncGroup']} /* {APP} */,\n\t\t\t);\n"
      f"\t\t\tname = {APP};\n"
      f"\t\t\tpackageProductDependencies = (\n\t\t\t\t{ID['pkgProduct']} /* AudioNinjaKit */,\n\t\t\t);\n"
      f"\t\t\tproductName = {APP};\n"
      f"\t\t\tproductReference = {ID['appProduct']} /* {APP}.app */;\n"
      f'\t\t\tproductType = "com.apple.product-type.application";\n'
      f"\t\t}};\n")
    w("/* End PBXNativeTarget section */\n\n")

    w("/* Begin PBXProject section */\n")
    w(f"\t\t{ID['project']} /* Project object */ = {{\n"
      f"\t\t\tisa = PBXProject;\n"
      f"\t\t\tattributes = {{\n"
      f"\t\t\t\tBuildIndependentTargetsInParallel = 1;\n"
      f"\t\t\t\tLastSwiftUpdateCheck = 2700;\n"
      f"\t\t\t\tLastUpgradeCheck = 2700;\n"
      f"\t\t\t\tTargetAttributes = {{\n"
      f"\t\t\t\t\t{ID['appTarget']} = {{\n\t\t\t\t\t\tCreatedOnToolsVersion = 27.0;\n\t\t\t\t\t}};\n"
      f"\t\t\t\t}};\n"
      f"\t\t\t}};\n"
      f"\t\t\tbuildConfigurationList = {ID['projectConfigs']} /* Build configuration list for PBXProject \"{APP}\" */;\n"
      f"\t\t\tdevelopmentRegion = en;\n"
      f"\t\t\thasScannedForEncodings = 0;\n"
      f"\t\t\tknownRegions = (\n\t\t\t\ten,\n\t\t\t\tBase,\n\t\t\t);\n"
      f"\t\t\tmainGroup = {ID['rootGroup']};\n"
      f"\t\t\tminimizedProjectReferenceProxies = 1;\n"
      f"\t\t\tpackageReferences = (\n"
      f"\t\t\t\t{ID['pkgRef']} /* XCLocalSwiftPackageReference \"Packages/AudioNinjaKit\" */,\n"
      f"\t\t\t);\n"
      f"\t\t\tpreferredProjectObjectVersion = {OBJECT_VERSION};\n"
      f"\t\t\tproductRefGroup = {ID['productsGroup']} /* Products */;\n"
      f'\t\t\tprojectDirPath = "";\n'
      f'\t\t\tprojectRoot = "";\n'
      f"\t\t\ttargets = (\n\t\t\t\t{ID['appTarget']} /* {APP} */,\n\t\t\t);\n"
      f"\t\t}};\n")
    w("/* End PBXProject section */\n\n")

    w("/* Begin PBXResourcesBuildPhase section */\n")
    w(f"\t\t{ID['resources']} /* Resources */ = {{\n"
      f"\t\t\tisa = PBXResourcesBuildPhase;\n"
      f"\t\t\tbuildActionMask = 2147483647;\n"
      f"\t\t\tfiles = (\n\t\t\t);\n"
      f"\t\t\trunOnlyForDeploymentPostprocessing = 0;\n"
      f"\t\t}};\n")
    w("/* End PBXResourcesBuildPhase section */\n\n")

    w("/* Begin PBXSourcesBuildPhase section */\n")
    w(f"\t\t{ID['sources']} /* Sources */ = {{\n"
      f"\t\t\tisa = PBXSourcesBuildPhase;\n"
      f"\t\t\tbuildActionMask = 2147483647;\n"
      f"\t\t\tfiles = (\n\t\t\t);\n"
      f"\t\t\trunOnlyForDeploymentPostprocessing = 0;\n"
      f"\t\t}};\n")
    w("/* End PBXSourcesBuildPhase section */\n\n")

    w("/* Begin XCBuildConfiguration section */\n")
    w(build_config(ID["projectDebug"], "Debug", project_debug))
    w(build_config(ID["projectRelease"], "Release", project_release))
    w(build_config(ID["appDebug"], "Debug", app_debug))
    w(build_config(ID["appRelease"], "Release", app_release))
    w("/* End XCBuildConfiguration section */\n\n")

    w("/* Begin XCConfigurationList section */\n")
    for key, name, debug, release in [
        (ID["projectConfigs"], f'PBXProject "{APP}"', ID["projectDebug"], ID["projectRelease"]),
        (ID["appConfigs"], f'PBXNativeTarget "{APP}"', ID["appDebug"], ID["appRelease"]),
    ]:
        w(f"\t\t{key} /* Build configuration list for {name} */ = {{\n"
          f"\t\t\tisa = XCConfigurationList;\n"
          f"\t\t\tbuildConfigurations = (\n"
          f"\t\t\t\t{debug} /* Debug */,\n\t\t\t\t{release} /* Release */,\n\t\t\t);\n"
          f"\t\t\tdefaultConfigurationIsVisible = 0;\n"
          f"\t\t\tdefaultConfigurationName = Release;\n"
          f"\t\t}};\n")
    w("/* End XCConfigurationList section */\n\n")

    w("/* Begin XCLocalSwiftPackageReference section */\n")
    w(f"\t\t{ID['pkgRef']} /* XCLocalSwiftPackageReference \"Packages/AudioNinjaKit\" */ = {{\n"
      f"\t\t\tisa = XCLocalSwiftPackageReference;\n"
      f"\t\t\trelativePath = Packages/AudioNinjaKit;\n"
      f"\t\t}};\n")
    w("/* End XCLocalSwiftPackageReference section */\n\n")

    w("/* Begin XCSwiftPackageProductDependency section */\n")
    w(f"\t\t{ID['pkgProduct']} /* AudioNinjaKit */ = {{\n"
      f"\t\t\tisa = XCSwiftPackageProductDependency;\n"
      f"\t\t\tproductName = AudioNinjaKit;\n"
      f"\t\t}};\n")
    w("/* End XCSwiftPackageProductDependency section */\n")

    w("\t};\n")
    w(f"\trootObject = {ID['project']} /* Project object */;\n")
    w("}\n")

    path = pathlib.Path(f"{APP}.xcodeproj/project.pbxproj")
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("".join(out))
    print(f"wrote {path} (objectVersion {OBJECT_VERSION})")


if __name__ == "__main__":
    main()
