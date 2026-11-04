#!/usr/bin/env python3
"""Generate AudioNinja.xcodeproj/project.pbxproj.

The output matches Xcode's own serialisation: the same key order, quoting and object order Xcode
writes when it saves. Opening the project and saving it therefore changes nothing, and CI's drift
check only catches real differences. A setting changed in Xcode's editor must be copied here.

Hand-maintaining a pbxproj is unpleasant, and neither xcodegen nor tuist is installed. This
generator keeps the file reproducible and reviewable: the project is small (one multiplatform app
target; an iOS share extension and framework built into Debug and TestFlight only; a local package
and one pinned remote package), and
because each target's sources live in a PBXFileSystemSynchronizedRootGroup, adding Swift files
never requires regenerating it.
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
    # The Debug-only iOS share extension (see SHARE_SETTINGS).
    "shareTarget":    "A0000000000000000000016",
    "shareProduct":   "A0000000000000000000017",
    "shareSyncGroup": "A0000000000000000000018",
    "shareSources":   "A0000000000000000000019",
    "shareFrameworks":"A000000000000000000001A",
    "shareResources": "A000000000000000000001B",
    "shareConfigs":   "A000000000000000000001C",
    "shareDebug":     "A000000000000000000001D",
    "shareRelease":   "A000000000000000000001E",
    "shareInfoPlist": "A000000000000000000001F",
    "embedPhase":     "A0000000000000000000020",
    "embedBuildFile": "A0000000000000000000021",
    "shareDependency":"A0000000000000000000022",
    "shareProxy":     "A0000000000000000000023",
    "ytkPkgRef":      "A0000000000000000000024",
    "ytkProduct":     "A0000000000000000000025",
    "ytkBuildFile":   "A0000000000000000000026",
    # The TestFlight configuration (see APP_YOUTUBE).
    "projectTestFlight": "A0000000000000000000027",
    "appTestFlight":     "A0000000000000000000028",
    "shareTestFlight":   "A0000000000000000000029",
    # AudioNinjaYouTube.framework: YouTubeKit and the code the extension and the app share.
    "ytTarget":          "A000000000000000000002A",
    "ytProduct":         "A000000000000000000002B",
    "ytSyncGroup":       "A000000000000000000002C",
    "ytSources":         "A000000000000000000002D",
    "ytFrameworks":      "A000000000000000000002E",
    "ytResources":       "A000000000000000000002F",
    "ytConfigs":         "A0000000000000000000030",
    "ytDebug":           "A0000000000000000000031",
    "ytRelease":         "A0000000000000000000032",
    "ytTestFlight":      "A0000000000000000000033",
    "ytAppLinkFile":     "A0000000000000000000034",
    "ytAppEmbedFile":    "A0000000000000000000035",
    "ytShareLinkFile":   "A0000000000000000000036",
    "ytEmbedPhase":      "A0000000000000000000037",
    "ytAppDependency":   "A0000000000000000000038",
    "ytAppProxy":        "A0000000000000000000039",
    "ytShareDependency": "A000000000000000000003A",
    "ytShareProxy":      "A000000000000000000003B",
}

SHARE = f"{APP}Share"
YT = f"{APP}YouTube"
# Exactly this version: extraction tracks YouTube's undocumented internals, so an unreviewed
# update could change what the extension does.
YOUTUBEKIT_URL = "https://github.com/alexeichhorn/YouTubeKit"
YOUTUBEKIT_VERSION = "0.4.10"

MARKETING_VERSION = "1.1.0"
BUILD_NUMBER = "9"

SHARED_SETTINGS = {
    "ALWAYS_SEARCH_USER_PATHS": "NO",
    "CLANG_ENABLE_MODULES": "YES",
    "CLANG_ENABLE_OBJC_ARC": "YES",
    # As Xcode's project template sets it. Embedded frameworks are copied as shipped: the prebuilt
    # LAME.framework is already stripped, and its macOS slice is signed, so stripping it on copy
    # only produces a warning.
    "COPY_PHASE_STRIP": "NO",
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
    "CURRENT_PROJECT_VERSION": BUILD_NUMBER,
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
    # Where the embedded LAME.framework is found at launch. Without these the app builds but dyld
    # cannot load it: a Debug build only runs because Xcode adds the build folder as a runpath.
    "LD_RUNPATH_SEARCH_PATHS": ['"$(inherited)"', '"@executable_path/Frameworks"'],
    '"LD_RUNPATH_SEARCH_PATHS[sdk=macosx*]"': ['"$(inherited)"', '"@executable_path/../Frameworks"'],
    "MARKETING_VERSION": MARKETING_VERSION,
    "PRODUCT_BUNDLE_IDENTIFIER": BUNDLE_ID,
    # Support/AudioNinja-Info.plist goes through the C preprocessor so that Debug iOS builds alone
    # declare the audioninja:// scheme the share extension opens the app with (APP_YOUTUBE).
    "INFOPLIST_PREPROCESS": "YES",
    "PRODUCT_NAME": '"$(TARGET_NAME)"',
    "SWIFT_EMIT_LOC_STRINGS": "YES",
    "TARGETED_DEVICE_FAMILY": '"1,2"',
    # UI code should default to the main actor; the package deliberately does not set this, so its
    # decode/encode/peak work stays nonisolated and genuinely runs off the main thread.
    "SWIFT_DEFAULT_ACTOR_ISOLATION": "MainActor",
}

# The YouTube share feature exists in iOS builds of the Debug and TestFlight configurations only.
# App Store Review Guideline 5.2.3 rejects apps that download media from YouTube, so Release, the
# configuration for App Store submissions, carries none of it. TestFlight is Release plus the
# feature, for internal testers: its builds must never be submitted for review or given to
# external testers (beta review applies the same guidelines).
APP_YOUTUBE = {
    '"INFOPLIST_PREPROCESSOR_DEFINITIONS[sdk=iphoneos*]"': "\"YOUTUBE_SHARE=1\"",
    '"INFOPLIST_PREPROCESSOR_DEFINITIONS[sdk=iphonesimulator*]"': "\"YOUTUBE_SHARE=1\"",
    # Compiles AudioNinja/Views/YouTubeShareReceiver.swift and YouTubeImportSheet.swift (Import from
    # YouTube on the launch screen); $(inherited) keeps Debug's DEBUG.
    '"SWIFT_ACTIVE_COMPILATION_CONDITIONS[sdk=iphoneos*]"': '"$(inherited) YOUTUBE_SHARE"',
    '"SWIFT_ACTIVE_COMPILATION_CONDITIONS[sdk=iphonesimulator*]"': '"$(inherited) YOUTUBE_SHARE"',
}
APP_RELEASE_ONLY = {
    # The extension and framework targets still build (a target dependency cannot vary by
    # configuration), but Release leaves them out of the link and embed phases, so neither reaches
    # the app bundle. YouTubeKit lives in the framework because a package product linked into the
    # app directly cannot be left out this way: its resource bundle is copied regardless.
    "EXCLUDED_SOURCE_FILE_NAMES": f'"{SHARE}.appex {YT}.framework"',
}

# The share extension: "Share > Audio Ninja" in the YouTube app. Embedded in Debug and TestFlight. It
# resolves the video's audio stream with AudioNinjaYouTube and hands it to the app, which downloads
# and opens it. iOS only.
SHARE_SETTINGS = {
    "CODE_SIGN_STYLE": "Automatic",
    "CURRENT_PROJECT_VERSION": BUILD_NUMBER,
    "DEVELOPMENT_TEAM": TEAM_ID,
    "GENERATE_INFOPLIST_FILE": "YES",
    "INFOPLIST_FILE": f'"Support/{SHARE}-Info.plist"',
    "INFOPLIST_KEY_CFBundleDisplayName": "\"Audio Ninja\"",
    "INFOPLIST_KEY_NSHumanReadableCopyright": '""',
    "LD_RUNPATH_SEARCH_PATHS": [
        '"$(inherited)"', '"@executable_path/Frameworks"', '"@executable_path/../../Frameworks"',
    ],
    "MARKETING_VERSION": MARKETING_VERSION,
    "PRODUCT_BUNDLE_IDENTIFIER": f"{BUNDLE_ID}.Share",
    "PRODUCT_NAME": '"$(TARGET_NAME)"',
    "SDKROOT": "iphoneos",
    "SKIP_INSTALL": "YES",
    "SUPPORTED_PLATFORMS": '"iphoneos iphonesimulator"',
    "SWIFT_DEFAULT_ACTOR_ISOLATION": "MainActor",
    "SWIFT_EMIT_LOC_STRINGS": "YES",
    "TARGETED_DEVICE_FAMILY": '"1,2"',
}


# AudioNinjaYouTube.framework: YouTubeKit, link parsing and the stream lookup, for the extension and
# the app's Import from YouTube. Embedded in the app in Debug and TestFlight; the extension loads the
# app's copy. iOS only.
YT_SETTINGS = {
    # The extension links it.
    "APPLICATION_EXTENSION_API_ONLY": "YES",
    "CODE_SIGN_STYLE": "Automatic",
    "CURRENT_PROJECT_VERSION": BUILD_NUMBER,
    "DEVELOPMENT_TEAM": TEAM_ID,
    "DYLIB_COMPATIBILITY_VERSION": "1",
    "DYLIB_CURRENT_VERSION": "1",
    "DYLIB_INSTALL_NAME_BASE": '"@rpath"',
    "GENERATE_INFOPLIST_FILE": "YES",
    "INFOPLIST_KEY_NSHumanReadableCopyright": '""',
    "INSTALL_PATH": '"$(LOCAL_LIBRARY_DIR)/Frameworks"',
    "LD_RUNPATH_SEARCH_PATHS": [
        '"$(inherited)"', '"@executable_path/Frameworks"', '"@loader_path/Frameworks"',
    ],
    "MARKETING_VERSION": MARKETING_VERSION,
    "PRODUCT_BUNDLE_IDENTIFIER": f"{BUNDLE_ID}.YouTube",
    "PRODUCT_NAME": '"$(TARGET_NAME:c99extidentifier)"',
    "SDKROOT": "iphoneos",
    "SKIP_INSTALL": "YES",
    "SUPPORTED_PLATFORMS": '"iphoneos iphonesimulator"',
    "SWIFT_INSTALL_OBJC_HEADER": "NO",
    "TARGETED_DEVICE_FAMILY": '"1,2"',
}


def setting_value(value, pad):
    """A string as is; a list the way Xcode writes one, an item per line."""
    if isinstance(value, str):
        return value
    items = "".join(f"{pad}\t{item},\n" for item in value)
    return f"(\n{items}{pad})"


def settings_block(pairs, indent):
    pad = "\t" * indent
    # Xcode orders keys as if their quotes were not there.
    return "".join(
        f"{pad}{k} = {setting_value(v, pad)};\n"
        for k, v in sorted(pairs.items(), key=lambda kv: kv[0].strip('"'))
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


def native_target(target_id, name, config_list, phases, product, product_type,
                  sync_group, package_products, dependencies=()):
    def items(entries):
        return "".join(f"\t\t\t\t{entry},\n" for entry in entries)
    return (
        f"\t\t{target_id} /* {name} */ = {{\n"
        f"\t\t\tisa = PBXNativeTarget;\n"
        f"\t\t\tbuildConfigurationList = {config_list} /* Build configuration list for PBXNativeTarget \"{name}\" */;\n"
        f"\t\t\tbuildPhases = (\n{items(phases)}\t\t\t);\n"
        f"\t\t\tbuildRules = (\n\t\t\t);\n"
        f"\t\t\tdependencies = (\n{items(dependencies)}\t\t\t);\n"
        f"\t\t\tfileSystemSynchronizedGroups = (\n\t\t\t\t{sync_group} /* {name} */,\n\t\t\t);\n"
        f"\t\t\tname = {name};\n"
        f"\t\t\tpackageProductDependencies = (\n{items(package_products)}\t\t\t);\n"
        f"\t\t\tproductName = {name};\n"
        f"\t\t\tproductReference = {product};\n"
        f'\t\t\tproductType = "{product_type}";\n'
        f"\t\t}};\n"
    )


def build_phase(phase_id, isa, name, files=()):
    listed = "".join(f"\t\t\t\t{f},\n" for f in files)
    return (
        f"\t\t{phase_id} /* {name} */ = {{\n"
        f"\t\t\tisa = {isa};\n"
        f"\t\t\tbuildActionMask = 2147483647;\n"
        f"\t\t\tfiles = (\n{listed}\t\t\t);\n"
        f"\t\t\trunOnlyForDeploymentPostprocessing = 0;\n"
        f"\t\t}};\n"
    )


def main():
    project_debug = {**SHARED_SETTINGS, **DEBUG_ONLY}
    project_release = {**SHARED_SETTINGS, **RELEASE_ONLY}
    app_debug = {**APP_SETTINGS, **APP_YOUTUBE}
    app_release = {**APP_SETTINGS, **APP_RELEASE_ONLY}
    app_testflight = {**APP_SETTINGS, **APP_YOUTUBE}
    share_debug = dict(SHARE_SETTINGS)
    share_testflight = dict(SHARE_SETTINGS)
    # Release builds the extension only because the dependency cannot vary by configuration, and
    # never embeds it; unsigned, it needs no App ID or profile when archiving for the App Store.
    share_release = {**SHARE_SETTINGS, "CODE_SIGNING_ALLOWED": "NO"}
    yt_debug = dict(YT_SETTINGS)
    yt_testflight = dict(YT_SETTINGS)
    # Likewise built in Release but never linked or embedded.
    yt_release = {**YT_SETTINGS, "CODE_SIGNING_ALLOWED": "NO"}

    embed_name = f"{SHARE}.appex in Embed Foundation Extensions"
    yt_link_name = f"{YT}.framework in Frameworks"
    yt_embed_name = f"{YT}.framework in Embed Frameworks"

    out = []
    w = out.append

    w("// !$*UTF8*$!\n{\n")
    w("\tarchiveVersion = 1;\n\tclasses = {\n\t};\n")
    w(f"\tobjectVersion = {OBJECT_VERSION};\n")
    w("\tobjects = {\n\n")

    w("/* Begin PBXBuildFile section */\n")
    w(f"\t\t{ID['pkgBuildFile']} /* AudioNinjaKit in Frameworks */ = {{isa = PBXBuildFile; "
      f"productRef = {ID['pkgProduct']} /* AudioNinjaKit */; }};\n")
    w(f"\t\t{ID['embedBuildFile']} /* {embed_name} */ = {{isa = PBXBuildFile; "
      f"fileRef = {ID['shareProduct']} /* {SHARE}.appex */; platformFilters = (ios, ); "
      f"settings = {{ATTRIBUTES = (RemoveHeadersOnCopy, ); }}; }};\n")
    w(f"\t\t{ID['ytkBuildFile']} /* YouTubeKit in Frameworks */ = {{isa = PBXBuildFile; "
      f"productRef = {ID['ytkProduct']} /* YouTubeKit */; }};\n")
    w(f"\t\t{ID['ytAppLinkFile']} /* {yt_link_name} */ = {{isa = PBXBuildFile; "
      f"fileRef = {ID['ytProduct']} /* {YT}.framework */; platformFilters = (ios, ); }};\n")
    w(f"\t\t{ID['ytAppEmbedFile']} /* {yt_embed_name} */ = {{isa = PBXBuildFile; "
      f"fileRef = {ID['ytProduct']} /* {YT}.framework */; platformFilters = (ios, ); "
      f"settings = {{ATTRIBUTES = (CodeSignOnCopy, RemoveHeadersOnCopy, ); }}; }};\n")
    w(f"\t\t{ID['ytShareLinkFile']} /* {yt_link_name} */ = {{isa = PBXBuildFile; "
      f"fileRef = {ID['ytProduct']} /* {YT}.framework */; }};\n")
    w("/* End PBXBuildFile section */\n\n")

    w("/* Begin PBXContainerItemProxy section */\n")
    w(f"\t\t{ID['shareProxy']} /* PBXContainerItemProxy */ = {{\n"
      f"\t\t\tisa = PBXContainerItemProxy;\n"
      f"\t\t\tcontainerPortal = {ID['project']} /* Project object */;\n"
      f"\t\t\tproxyType = 1;\n"
      f"\t\t\tremoteGlobalIDString = {ID['shareTarget']};\n"
      f"\t\t\tremoteInfo = {SHARE};\n"
      f"\t\t}};\n")
    for proxy in (ID["ytAppProxy"], ID["ytShareProxy"]):
        w(f"\t\t{proxy} /* PBXContainerItemProxy */ = {{\n"
          f"\t\t\tisa = PBXContainerItemProxy;\n"
          f"\t\t\tcontainerPortal = {ID['project']} /* Project object */;\n"
          f"\t\t\tproxyType = 1;\n"
          f"\t\t\tremoteGlobalIDString = {ID['ytTarget']};\n"
          f"\t\t\tremoteInfo = {YT};\n"
          f"\t\t}};\n")
    w("/* End PBXContainerItemProxy section */\n\n")

    w("/* Begin PBXCopyFilesBuildPhase section */\n")
    w(f"\t\t{ID['embedPhase']} /* Embed Foundation Extensions */ = {{\n"
      f"\t\t\tisa = PBXCopyFilesBuildPhase;\n"
      f"\t\t\tbuildActionMask = 2147483647;\n"
      f'\t\t\tdstPath = "";\n'
      f"\t\t\tdstSubfolderSpec = 13;\n"
      f"\t\t\tfiles = (\n\t\t\t\t{ID['embedBuildFile']} /* {embed_name} */,\n\t\t\t);\n"
      f'\t\t\tname = "Embed Foundation Extensions";\n'
      f"\t\t\trunOnlyForDeploymentPostprocessing = 0;\n"
      f"\t\t}};\n")
    w(f"\t\t{ID['ytEmbedPhase']} /* Embed Frameworks */ = {{\n"
      f"\t\t\tisa = PBXCopyFilesBuildPhase;\n"
      f"\t\t\tbuildActionMask = 2147483647;\n"
      f'\t\t\tdstPath = "";\n'
      f"\t\t\tdstSubfolderSpec = 10;\n"
      f"\t\t\tfiles = (\n\t\t\t\t{ID['ytAppEmbedFile']} /* {yt_embed_name} */,\n\t\t\t);\n"
      f'\t\t\tname = "Embed Frameworks";\n'
      f"\t\t\trunOnlyForDeploymentPostprocessing = 0;\n"
      f"\t\t}};\n")
    w("/* End PBXCopyFilesBuildPhase section */\n\n")

    w("/* Begin PBXFileReference section */\n")
    w(f"\t\t{ID['appProduct']} /* {APP}.app */ = {{isa = PBXFileReference; "
      f"explicitFileType = wrapper.application; includeInIndex = 0; "
      f'path = {APP}.app; sourceTree = BUILT_PRODUCTS_DIR; }};\n')
    w(f"\t\t{ID['infoPlist']} /* {APP}-Info.plist */ = {{isa = PBXFileReference; "
      f'lastKnownFileType = text.plist.xml; path = "{APP}-Info.plist"; sourceTree = "<group>"; }};\n')
    w(f"\t\t{ID['entitlements']} /* {APP}.entitlements */ = {{isa = PBXFileReference; "
      f'lastKnownFileType = text.plist.entitlements; path = {APP}.entitlements; sourceTree = "<group>"; }};\n')
    w(f"\t\t{ID['shareProduct']} /* {SHARE}.appex */ = {{isa = PBXFileReference; "
      f'explicitFileType = "wrapper.app-extension"; includeInIndex = 0; '
      f"path = {SHARE}.appex; sourceTree = BUILT_PRODUCTS_DIR; }};\n")
    w(f"\t\t{ID['shareInfoPlist']} /* {SHARE}-Info.plist */ = {{isa = PBXFileReference; "
      f'lastKnownFileType = text.plist.xml; path = "{SHARE}-Info.plist"; sourceTree = "<group>"; }};\n')
    w(f"\t\t{ID['ytProduct']} /* {YT}.framework */ = {{isa = PBXFileReference; "
      f"explicitFileType = wrapper.framework; includeInIndex = 0; "
      f"path = {YT}.framework; sourceTree = BUILT_PRODUCTS_DIR; }};\n")
    w("/* End PBXFileReference section */\n\n")

    w("/* Begin PBXFileSystemSynchronizedRootGroup section */\n")
    for group, path in [(ID["syncGroup"], APP), (ID["shareSyncGroup"], SHARE), (ID["ytSyncGroup"], YT)]:
        w(f"\t\t{group} /* {path} */ = {{\n"
          f"\t\t\tisa = PBXFileSystemSynchronizedRootGroup;\n"
          f"\t\t\tpath = {path};\n"
          f'\t\t\tsourceTree = "<group>";\n'
          f"\t\t}};\n")
    w("/* End PBXFileSystemSynchronizedRootGroup section */\n\n")

    w("/* Begin PBXFrameworksBuildPhase section */\n")
    w(build_phase(ID["frameworks"], "PBXFrameworksBuildPhase", "Frameworks",
                  [f"{ID['pkgBuildFile']} /* AudioNinjaKit in Frameworks */",
                   f"{ID['ytAppLinkFile']} /* {yt_link_name} */"]))
    w(build_phase(ID["shareFrameworks"], "PBXFrameworksBuildPhase", "Frameworks",
                  [f"{ID['ytShareLinkFile']} /* {yt_link_name} */"]))
    w(build_phase(ID["ytFrameworks"], "PBXFrameworksBuildPhase", "Frameworks",
                  [f"{ID['ytkBuildFile']} /* YouTubeKit in Frameworks */"]))
    w("/* End PBXFrameworksBuildPhase section */\n\n")

    w("/* Begin PBXGroup section */\n")
    w(f"\t\t{ID['rootGroup']} = {{\n"
      f"\t\t\tisa = PBXGroup;\n"
      f"\t\t\tchildren = (\n"
      f"\t\t\t\t{ID['syncGroup']} /* {APP} */,\n"
      f"\t\t\t\t{ID['shareSyncGroup']} /* {SHARE} */,\n"
      f"\t\t\t\t{ID['ytSyncGroup']} /* {YT} */,\n"
      f"\t\t\t\t{ID['supportGroup']} /* Support */,\n"
      f"\t\t\t\t{ID['productsGroup']} /* Products */,\n"
      f"\t\t\t);\n"
      f'\t\t\tsourceTree = "<group>";\n'
      f"\t\t}};\n")
    w(f"\t\t{ID['productsGroup']} /* Products */ = {{\n"
      f"\t\t\tisa = PBXGroup;\n"
      f"\t\t\tchildren = (\n"
      f"\t\t\t\t{ID['appProduct']} /* {APP}.app */,\n"
      f"\t\t\t\t{ID['shareProduct']} /* {SHARE}.appex */,\n"
      f"\t\t\t\t{ID['ytProduct']} /* {YT}.framework */,\n"
      f"\t\t\t);\n"
      f"\t\t\tname = Products;\n"
      f'\t\t\tsourceTree = "<group>";\n'
      f"\t\t}};\n")
    w(f"\t\t{ID['supportGroup']} /* Support */ = {{\n"
      f"\t\t\tisa = PBXGroup;\n"
      f"\t\t\tchildren = (\n"
      f"\t\t\t\t{ID['infoPlist']} /* {APP}-Info.plist */,\n"
      f"\t\t\t\t{ID['entitlements']} /* {APP}.entitlements */,\n"
      f"\t\t\t\t{ID['shareInfoPlist']} /* {SHARE}-Info.plist */,\n"
      f"\t\t\t);\n"
      f"\t\t\tpath = Support;\n"
      f'\t\t\tsourceTree = "<group>";\n'
      f"\t\t}};\n")
    w("/* End PBXGroup section */\n\n")

    w("/* Begin PBXNativeTarget section */\n")
    w(native_target(
        ID["appTarget"], APP, ID["appConfigs"],
        [f"{ID['sources']} /* Sources */", f"{ID['frameworks']} /* Frameworks */",
         f"{ID['resources']} /* Resources */", f"{ID['embedPhase']} /* Embed Foundation Extensions */",
         f"{ID['ytEmbedPhase']} /* Embed Frameworks */"],
        f"{ID['appProduct']} /* {APP}.app */", "com.apple.product-type.application",
        ID["syncGroup"], [f"{ID['pkgProduct']} /* AudioNinjaKit */"],
        dependencies=[f"{ID['shareDependency']} /* PBXTargetDependency */",
                      f"{ID['ytAppDependency']} /* PBXTargetDependency */"],
    ))
    w(native_target(
        ID["shareTarget"], SHARE, ID["shareConfigs"],
        [f"{ID['shareSources']} /* Sources */", f"{ID['shareFrameworks']} /* Frameworks */",
         f"{ID['shareResources']} /* Resources */"],
        f"{ID['shareProduct']} /* {SHARE}.appex */", "com.apple.product-type.app-extension",
        ID["shareSyncGroup"], [],
        dependencies=[f"{ID['ytShareDependency']} /* PBXTargetDependency */"],
    ))
    w(native_target(
        ID["ytTarget"], YT, ID["ytConfigs"],
        [f"{ID['ytSources']} /* Sources */", f"{ID['ytFrameworks']} /* Frameworks */",
         f"{ID['ytResources']} /* Resources */"],
        f"{ID['ytProduct']} /* {YT}.framework */", "com.apple.product-type.framework",
        ID["ytSyncGroup"], [f"{ID['ytkProduct']} /* YouTubeKit */"],
    ))
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
      f"\t\t\t\t\t{ID['shareTarget']} = {{\n\t\t\t\t\t\tCreatedOnToolsVersion = 27.0;\n\t\t\t\t\t}};\n"
      f"\t\t\t\t\t{ID['ytTarget']} = {{\n\t\t\t\t\t\tCreatedOnToolsVersion = 27.0;\n\t\t\t\t\t}};\n"
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
      f"\t\t\t\t{ID['ytkPkgRef']} /* XCRemoteSwiftPackageReference \"YouTubeKit\" */,\n"
      f"\t\t\t);\n"
      f"\t\t\tpreferredProjectObjectVersion = {OBJECT_VERSION};\n"
      f"\t\t\tproductRefGroup = {ID['productsGroup']} /* Products */;\n"
      f'\t\t\tprojectDirPath = "";\n'
      f'\t\t\tprojectRoot = "";\n'
      f"\t\t\ttargets = (\n"
      f"\t\t\t\t{ID['appTarget']} /* {APP} */,\n"
      f"\t\t\t\t{ID['shareTarget']} /* {SHARE} */,\n"
      f"\t\t\t\t{ID['ytTarget']} /* {YT} */,\n"
      f"\t\t\t);\n"
      f"\t\t}};\n")
    w("/* End PBXProject section */\n\n")

    w("/* Begin PBXResourcesBuildPhase section */\n")
    w(build_phase(ID["resources"], "PBXResourcesBuildPhase", "Resources"))
    w(build_phase(ID["shareResources"], "PBXResourcesBuildPhase", "Resources"))
    w(build_phase(ID["ytResources"], "PBXResourcesBuildPhase", "Resources"))
    w("/* End PBXResourcesBuildPhase section */\n\n")

    w("/* Begin PBXSourcesBuildPhase section */\n")
    w(build_phase(ID["sources"], "PBXSourcesBuildPhase", "Sources"))
    w(build_phase(ID["shareSources"], "PBXSourcesBuildPhase", "Sources"))
    w(build_phase(ID["ytSources"], "PBXSourcesBuildPhase", "Sources"))
    w("/* End PBXSourcesBuildPhase section */\n\n")

    w("/* Begin PBXTargetDependency section */\n")
    w(f"\t\t{ID['shareDependency']} /* PBXTargetDependency */ = {{\n"
      f"\t\t\tisa = PBXTargetDependency;\n"
      f"\t\t\tplatformFilter = ios;\n"
      f"\t\t\ttarget = {ID['shareTarget']} /* {SHARE} */;\n"
      f"\t\t\ttargetProxy = {ID['shareProxy']} /* PBXContainerItemProxy */;\n"
      f"\t\t}};\n")
    for dependency, proxy, platform_filter in [
        (ID["ytAppDependency"], ID["ytAppProxy"], "\t\t\tplatformFilter = ios;\n"),
        (ID["ytShareDependency"], ID["ytShareProxy"], ""),
    ]:
        w(f"\t\t{dependency} /* PBXTargetDependency */ = {{\n"
          f"\t\t\tisa = PBXTargetDependency;\n"
          f"{platform_filter}"
          f"\t\t\ttarget = {ID['ytTarget']} /* {YT} */;\n"
          f"\t\t\ttargetProxy = {proxy} /* PBXContainerItemProxy */;\n"
          f"\t\t}};\n")
    w("/* End PBXTargetDependency section */\n\n")

    w("/* Begin XCBuildConfiguration section */\n")
    w(build_config(ID["projectDebug"], "Debug", project_debug))
    w(build_config(ID["projectRelease"], "Release", project_release))
    w(build_config(ID["appDebug"], "Debug", app_debug))
    w(build_config(ID["appRelease"], "Release", app_release))
    w(build_config(ID["shareDebug"], "Debug", share_debug))
    w(build_config(ID["shareRelease"], "Release", share_release))
    w(build_config(ID["projectTestFlight"], "TestFlight", project_release))
    w(build_config(ID["appTestFlight"], "TestFlight", app_testflight))
    w(build_config(ID["shareTestFlight"], "TestFlight", share_testflight))
    w(build_config(ID["ytDebug"], "Debug", yt_debug))
    w(build_config(ID["ytRelease"], "Release", yt_release))
    w(build_config(ID["ytTestFlight"], "TestFlight", yt_testflight))
    w("/* End XCBuildConfiguration section */\n\n")

    w("/* Begin XCConfigurationList section */\n")
    for key, name, debug, release, testflight in [
        (ID["projectConfigs"], f'PBXProject "{APP}"',
         ID["projectDebug"], ID["projectRelease"], ID["projectTestFlight"]),
        (ID["appConfigs"], f'PBXNativeTarget "{APP}"',
         ID["appDebug"], ID["appRelease"], ID["appTestFlight"]),
        (ID["shareConfigs"], f'PBXNativeTarget "{SHARE}"',
         ID["shareDebug"], ID["shareRelease"], ID["shareTestFlight"]),
        (ID["ytConfigs"], f'PBXNativeTarget "{YT}"',
         ID["ytDebug"], ID["ytRelease"], ID["ytTestFlight"]),
    ]:
        w(f"\t\t{key} /* Build configuration list for {name} */ = {{\n"
          f"\t\t\tisa = XCConfigurationList;\n"
          f"\t\t\tbuildConfigurations = (\n"
          f"\t\t\t\t{debug} /* Debug */,\n\t\t\t\t{release} /* Release */,\n"
          f"\t\t\t\t{testflight} /* TestFlight */,\n\t\t\t);\n"
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

    w("/* Begin XCRemoteSwiftPackageReference section */\n")
    w(f"\t\t{ID['ytkPkgRef']} /* XCRemoteSwiftPackageReference \"YouTubeKit\" */ = {{\n"
      f"\t\t\tisa = XCRemoteSwiftPackageReference;\n"
      f'\t\t\trepositoryURL = "{YOUTUBEKIT_URL}";\n'
      f"\t\t\trequirement = {{\n"
      f"\t\t\t\tkind = exactVersion;\n"
      f"\t\t\t\tversion = {YOUTUBEKIT_VERSION};\n"
      f"\t\t\t}};\n"
      f"\t\t}};\n")
    w("/* End XCRemoteSwiftPackageReference section */\n\n")

    w("/* Begin XCSwiftPackageProductDependency section */\n")
    w(f"\t\t{ID['pkgProduct']} /* AudioNinjaKit */ = {{\n"
      f"\t\t\tisa = XCSwiftPackageProductDependency;\n"
      f"\t\t\tproductName = AudioNinjaKit;\n"
      f"\t\t}};\n")
    w(f"\t\t{ID['ytkProduct']} /* YouTubeKit */ = {{\n"
      f"\t\t\tisa = XCSwiftPackageProductDependency;\n"
      f"\t\t\tpackage = {ID['ytkPkgRef']} /* XCRemoteSwiftPackageReference \"YouTubeKit\" */;\n"
      f"\t\t\tproductName = YouTubeKit;\n"
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
