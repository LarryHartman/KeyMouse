/*
 * Deskflow -- mouse and keyboard sharing utility
 * SPDX-FileCopyrightText: (C) 2026 Deskflow Developers
 * SPDX-FileCopyrightText: (C) 2012 - 2016 Synergy App Ltd
 * SPDX-FileCopyrightText: (C) 2002 Chris Schoeneman
 * SPDX-License-Identifier: GPL-2.0-only WITH LicenseRef-OpenSSL-Exception
 */

#include "deskflow/unix/AppUtilUnix.h"

#include "base/Log.h"
#include "common/PlatformInfo.h"

#if WINAPI_XWINDOWS
#include <X11/XKBlib.h>
#include <deskflow/unix/XkbLayoutsParser.h>
#elif defined(Q_OS_MACOS)
#include <Carbon/Carbon.h>
#include <dispatch/dispatch.h>
#include <platform/OSXAutoTypes.h>
#endif

#if defined(Q_OS_MACOS)
#include <functional>
#include <pthread.h>
namespace {
// macOS 26+ asserts that Text Input Source (TIS) queries run on the main
// dispatch queue and traps (SIGTRAP in dispatch_assert_queue) otherwise.
// These are called from the client's network thread during the server
// handshake, so run TIS work on the main queue. dispatch_sync from the main
// thread itself would deadlock, so run inline there.
void runOnMainQueueThunk(void *ctx)
{
  (*static_cast<std::function<void()> *>(ctx))();
}
void runTisOnMainQueue(const std::function<void()> &fn)
{
  std::lock_guard<std::mutex> lock(g_tisMutex);
  if (pthread_main_np() != 0) {
    fn();
  } else {
    auto copy = fn;
    dispatch_sync_f(dispatch_get_main_queue(), &copy, runOnMainQueueThunk);
  }
}
} // namespace
#endif

AppUtilUnix::AppUtilUnix(const IEventQueue *)
{
  // do nothing
}

int startStatic()
{
  return AppUtil::instance().app().start();
}

int AppUtilUnix::run()
{
  return app().runInner(&startStatic);
}

std::vector<std::string> AppUtilUnix::getKeyboardLayoutList()
{
  std::vector<std::string> layoutLangCodes;

#if WINAPI_XWINDOWS
  layoutLangCodes = XkbLayoutsParser::getXkbLanguageList();

#elif defined(Q_OS_MACOS)
  auto collect = [&layoutLangCodes]() {
    CFStringRef keys[] = {kTISPropertyInputSourceCategory};
    CFStringRef values[] = {kTISCategoryKeyboardInputSource};
    AutoCFDictionary dict(
        CFDictionaryCreate(nullptr, (const void **)keys, (const void **)values, 1, nullptr, nullptr), CFRelease
    );
    AutoCFArray kbds(TISCreateInputSourceList(dict.get(), false), CFRelease);
    if (!kbds) {
      return;
    }
    for (CFIndex i = 0; i < CFArrayGetCount(kbds.get()); ++i) {
      auto keyboardLayout = (TISInputSourceRef)CFArrayGetValueAtIndex(kbds.get(), i);
      auto layoutLanguages = (CFArrayRef)TISGetInputSourceProperty(keyboardLayout, kTISPropertyInputSourceLanguages);
      char temporaryCString[128] = {0};
      for (CFIndex index = 0; layoutLanguages && index < CFArrayGetCount(layoutLanguages); index++) {
        auto languageCode = (CFStringRef)CFArrayGetValueAtIndex(layoutLanguages, index);
        if (!languageCode || !CFStringGetCString(languageCode, temporaryCString, 128, kCFStringEncodingUTF8)) {
          continue;
        }
        std::string langCode(temporaryCString);
        if (langCode.size() == 2 &&
            std::find(layoutLangCodes.begin(), layoutLangCodes.end(), langCode) == layoutLangCodes.end()) {
          layoutLangCodes.push_back(langCode);
        }
        // Save only first language code
        break;
      }
    }
  };

  runTisOnMainQueue(collect);
#endif

  return layoutLangCodes;
}

// TODO: read the layout for x and wayland via xkbcommon
std::string AppUtilUnix::getCurrentLanguageCode()
{
  std::string result = "";
  if (deskflow::platform::isWayland())
    return result;

#if WINAPI_XWINDOWS

  auto display = XOpenDisplay(nullptr);
  if (!display) {
    LOG_WARN("failed to open x11 default display");
    return result;
  }

  auto kbdDescr = XkbAllocKeyboard();
  if (!kbdDescr) {
    LOG_WARN("failed to get x11 keyboard description");
    return result;
  }
  XkbGetNames(display, XkbSymbolsNameMask, kbdDescr);

  Atom symNameAtom = kbdDescr->names->symbols;
  auto rawLayouts = std::string(XGetAtomName(display, symNameAtom));

  XkbStateRec state;
  XkbGetState(display, XkbUseCoreKbd, &state);
  auto neededGroupIndex = static_cast<int>(state.group);

  size_t groupIdx = 0;
  size_t groupStartI = 0;
  for (size_t strI = 0; strI < rawLayouts.size(); strI++) {
    if (rawLayouts[strI] != '+') {
      continue;
    }

    if (auto group = rawLayouts.substr(groupStartI, strI - groupStartI);
        group.find("group", 0, 5) == std::string::npos && group.find("inet", 0, 4) == std::string::npos &&
        group.find("pc", 0, 2) == std::string::npos) {
      if (neededGroupIndex == groupIdx) {
        result = group.substr(0, std::min(group.find('(', 0), group.find(':', 0)));
        break;
      }
      groupIdx++;
    }

    groupStartI = strI + 1;
  }

  XkbFreeNames(kbdDescr, XkbSymbolsNameMask, true);
  XFree(kbdDescr);
  XCloseDisplay(display);

  result = XkbLayoutsParser::convertLayoutToISO(result);

#elif defined(Q_OS_MACOS)
  runTisOnMainQueue([&result]() {
    AutoTISInputSourceRef source(TISCopyCurrentKeyboardInputSource(), CFRelease);
    if (!source)
      return;
    auto layoutLanguages = (CFArrayRef)TISGetInputSourceProperty(source.get(), kTISPropertyInputSourceLanguages);
    char temporaryCString[128] = {0};
    for (CFIndex index = 0; layoutLanguages && index < CFArrayGetCount(layoutLanguages); index++) {
      auto languageCode = (CFStringRef)CFArrayGetValueAtIndex(layoutLanguages, index);
      if (!languageCode || !CFStringGetCString(languageCode, temporaryCString, 128, kCFStringEncodingUTF8)) {
        continue;
      }
      result = std::string(temporaryCString);
      break;
    }
  });
#endif
  return result;
}
