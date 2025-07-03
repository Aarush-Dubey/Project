#!/usr/bin/env bash
set -e
# build C static library
clang -c modules/recorder.c -o modules/recorder.o
ar   rcs modules/librecord.a modules/recorder.o
# compile & link Swift
swiftc \
  -I modules \
  -import-objc-header modules/recorder.h \
  AudioKit.swift HotkeyListener.swift \
  modules/librecord.a \
  -framework Cocoa \
  -framework AVFoundation \
  -framework ScreenCaptureKit \
  -framework CoreMedia \
  -framework Carbon \
  -o AudioKitApp

  
echo "Build complete → ./AudioKitApp"
