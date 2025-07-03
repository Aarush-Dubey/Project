import Cocoa
import Carbon 
import Foundation 
import AVFoundation


class HotkeyListener{
    private var hotkeyRef: EventHotKeyRef?
    private let hotkeyID = EventHotKeyID(signature: OSType(0x68747479), id: 1) // 'htty'
    private let audioService = AudioCaptureService()

    private let outputDirectory: URL
    private let audioFileName = "capture.wav"
    private let screenshotFileName = "capture.png"

    init(){
        let documentsPath = FileManager.default.urls(for:. documentDirectory, in: .userDomainMask).first!
        outputDirectory = documentsPath.appendingPathComponent("RecordingTest")
        try? FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

        setupHotkey()
        startAudioCapture()
    }



    private func startAudioCapture (){
        Task {
            do {
                let cfg = RecorderConfiguration(
                    fileName: "audio_buffer",
                    sampleRate: 48_000,
                    channelCount: 1,
                    bitsPerSample: 32,
                    ringDuration: 90        // seconds held in RAM
                )
                try await audioService.start_recording(with: cfg)
                print("Audio ring‑buffer active.")
                
            } catch {
                print("Audio capture failed: \(error)")
            }
        }
    }
    private func setupHotkey(){
        let keyCode = UInt32(kVK_ANSI_H)
        let modifiers = UInt32(cmdKey | shiftKey)
        let status = RegisterEventHotKey(keyCode, modifiers, hotkeyID,
                                         GetApplicationEventTarget(),
                                         0, &hotkeyRef)
        guard status == noErr else {
            print("Hotkey registration failed (\(status))")
            return
        }

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: OSType(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), 
                            { _ , theEvent , userData in 
                            let listener = Unmanaged<HotkeyListener>.fromOpaque(userData!).takeUnretainedValue()
                        
                            listener.hotkeyPressed()
                            return noErr }, 1, &eventType, Unmanaged.passUnretained(self).toOpaque(), nil)

        print("Hotkey  ⌘⇧H ready – press to capture last 60 s + current screen.")  
    }
    private func hotkeyPressed() {
        print("⌘⇧H pressed → capturing…")
        Task { await captureAudio()
               await captureScreenshot()
               await startChat()
            

                }
    }
    private func captureAudio() async {
        // --- AUDIO: save last 30 s into capture.wav
        do {
            let tmpURL  = try await audioService.save_recording(seconds: 60)
            let destURL = outputDirectory.appendingPathComponent(audioFileName)

            if FileManager.default.fileExists(atPath: destURL.path) {
                try FileManager.default.removeItem(at: destURL)
            }
            try FileManager.default.moveItem(at: tmpURL, to: destURL)
            print("✅ Audio → \(destURL.lastPathComponent)")
        } catch { print("Audio save error: \(error)") } 
    }
    private func captureScreenshot() async{
        let task = Process()
        task.launchPath = "/usr/bin/python3"
        task.arguments = ["capture_screen.py",
                          outputDirectory.appendingPathComponent(screenshotFileName).path]
        task.currentDirectoryPath = FileManager.default.currentDirectoryPath

        do {
            try task.run()
            task.waitUntilExit()
            if task.terminationStatus == 0 {
                print("✅ Screenshot → \(screenshotFileName)")
            } else {
                print("Screenshot failed (status \(task.terminationStatus))")
            }
        } catch { print("Error running capture_screen.py: \(error)") }
    }
    private func startChat() async {
        print("🚀 Starting chat session...")
        
        let task = Process()
        let inputPipe = Pipe()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        
        // Setup the Python process
        task.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        task.arguments = ["chat.py"]
        task.currentDirectoryURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        
        // Connect pipes
        task.standardInput = inputPipe
        task.standardOutput = outputPipe
        task.standardError = errorPipe
        
        // Setup output monitoring
        let outputHandle = outputPipe.fileHandleForReading
        let errorHandle = errorPipe.fileHandleForReading
        let inputHandle = inputPipe.fileHandleForWriting
        
        do {
            try task.run()
            print("✅ Chat process started")
            
            // Monitor output in background
            Task {
                await monitorOutput(outputHandle: outputHandle, label: "OUTPUT")
            }
            
            Task {
                await monitorOutput(outputHandle: errorHandle, label: "ERROR")
            }
            
            // Interactive input loop
            print("\n💬 Chat is ready! Type your questions (type 'exit' or 'quit' to end):")
            
            while task.isRunning {
                if let userInput = readLine() {
                    if userInput.lowercased() == "exit" || userInput.lowercased() == "quit" {
                        // Send exit command to Python script
                        let exitData = "exit\n".data(using: .utf8)!
                        try inputHandle.write(contentsOf: exitData)
                        break
                    }
                    
                    // Send user input to Python script
                    let inputData = "\(userInput)\n".data(using: .utf8)!
                    try inputHandle.write(contentsOf: inputData)
                }
                
                // Small delay to allow processing
                try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
            }
            
            // Cleanup
            try inputHandle.close()
            task.waitUntilExit()
            
            if task.terminationStatus == 0 {
                print("✅ Chat session ended successfully")
            } else {
                print("⚠️ Chat session ended with status: \(task.terminationStatus)")
            }
            
        } catch {
            print("❌ Error starting chat: \(error)")
        }
    }

    private func monitorOutput(outputHandle: FileHandle, label: String) async {
        while true {
            let data = outputHandle.availableData
            if data.isEmpty {
                try? await Task.sleep(nanoseconds: 50_000_000) // 0.05 seconds
                continue
            }
            
            if let output = String(data: data, encoding: .utf8) {
                let cleanOutput = output.trimmingCharacters(in: .whitespacesAndNewlines)
                if !cleanOutput.isEmpty {
                    if label == "OUTPUT" {
                        // Print without adding extra newlines
                        print(cleanOutput)
                    } else {
                        print("[\(label)] \(cleanOutput)")
                    }
                }
            }
        }
    }

    deinit {
        if let hk = hotkeyRef { UnregisterEventHotKey(hk) }
        let service = audioService     
        Task { try? await service.stop_recording() }
    }
    func run() {
        print("Listener running – Ctrl+C to exit.")
        NSApplication.shared.run()
    }


}

@main
struct AudioRecorderApp {
    static func main() {
        HotkeyListener().run()
    }
}