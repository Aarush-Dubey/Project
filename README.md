# Audio Project

This project contains Swift and C code for audio processing and screen capture. It includes:

- `AudioKit.swift`: Main Swift application file.
- `HotkeyListener.swift`: Handles hotkey events.
- `build.sh`: Script to build the C static library and compile/link the Swift code.
- `capture_screen.py`: Python script for screen capture.
- `chat.py`: Python script for chat functionality.
- `modules/`: Directory containing C source code and compiled artifacts.
  - `recorder.c`: C source for audio recording.
  - `recorder.h`: Header for the C recorder.
  - `librecord.a`: Compiled static library.
  - `recorder.o`: Object file for the recorder.

## Build Instructions

To build the project, run the `build.sh` script:

```bash
chmod +x build.sh
./build.sh
./AudioKitApp
```

This will generate an executable named `AudioKitApp` in the project root directory.