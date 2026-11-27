import Foundation
import AVFoundation
import Speech

/// Speak instead of typing: listens with the microphone and turns speech in the chosen language into text,
/// as it's spoken. It stops by itself after a short pause, or with the button again. Works on iPhone and Mac.
/// Apple's speech recognition does the work, on the device when it can for that language.
@Observable
final class SpeechInput {
    private(set) var isListening = false
    /// Why listening didn't start or stopped, for the coach to read.
    var problem: String?

    private var engine: AVAudioEngine?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var silence: Task<Void, Never>?

    /// Starts listening in `language`; `onText` receives the whole transcript so far each time it grows.
    func start(_ language: AppLanguage, onText: @escaping (String) -> Void) async {
        guard !isListening else { return }
        problem = nil
        guard await Self.allowed() else {
            problem = String(localized: "Allow the microphone and speech recognition for CoachBoard in Settings to speak instead of typing.")
            return
        }
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: language.speechCode)), recognizer.isAvailable else {
            problem = String(localized: "Speaking isn't available for \(language.name) yet. Type the text instead.")
            return
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.addsPunctuation = true
        // On the device when this language allows it: nothing leaves the iPhone or Mac.
        if recognizer.supportsOnDeviceRecognition { request.requiresOnDeviceRecognition = true }

        let engine = AVAudioEngine()
        do {
#if !targetEnvironment(macCatalyst)
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .measurement, options: [.duckOthers, .defaultToSpeaker])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
#endif
            try Self.feed(engine, into: request)
            engine.prepare()
            try engine.start()
        } catch {
            problem = String(localized: "The microphone couldn't start. Try again.")
            Self.release(engine)
            return
        }

        self.engine = engine
        self.request = request
        isListening = true
        waitForSilence(seconds: 4)
        task = recognizer.recognitionTask(with: request, resultHandler: Self.handler { [weak self] text, final, failed in
            guard let self, self.isListening else { return }
            if let text, !text.isEmpty {
                onText(text)
                self.waitForSilence(seconds: 2)
            }
            if final || failed { self.stop() }
        })
    }

    func stop() {
        silence?.cancel()
        silence = nil
        guard isListening else { return }
        isListening = false
        request?.endAudio()
        task?.finish()
        if let engine { Self.release(engine) }
        engine = nil
        request = nil
        task = nil
#if !targetEnvironment(macCatalyst)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
#endif
    }

    /// Stops after `seconds` with nothing new heard.
    private func waitForSilence(seconds: Double) {
        silence?.cancel()
        silence = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            self?.stop()
        }
    }

    // MARK: Off the main thread
    // The microphone and the recognizer call back on their own threads, so these closures must not belong to
    // the main actor (the app's default): they only pass the audio along, or hop back to the main thread.

    private nonisolated static func feed(_ engine: AVAudioEngine, into request: SFSpeechAudioBufferRecognitionRequest) throws {
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { throw CocoaError(.featureUnsupported) }
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
        }
    }

    private nonisolated static func release(_ engine: AVAudioEngine) {
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
    }

    private nonisolated static func handler(
        _ update: @escaping @MainActor (String?, Bool, Bool) -> Void
    ) -> @Sendable (SFSpeechRecognitionResult?, Error?) -> Void {
        { result, error in
            let text = result?.bestTranscription.formattedString
            let final = result?.isFinal ?? false
            let failed = error != nil
            Task { @MainActor in update(text, final, failed) }
        }
    }

    /// Asks once for speech recognition and the microphone; true when both are allowed.
    private static func allowed() async -> Bool {
        let speech = await withCheckedContinuation { (continuation: CheckedContinuation<SFSpeechRecognizerAuthorizationStatus, Never>) in
            SFSpeechRecognizer.requestAuthorization(Self.resume(continuation))
        }
        guard speech == .authorized else { return false }
        return await AVAudioApplication.requestRecordPermission()
    }

    private nonisolated static func resume(
        _ continuation: CheckedContinuation<SFSpeechRecognizerAuthorizationStatus, Never>
    ) -> @Sendable (SFSpeechRecognizerAuthorizationStatus) -> Void {
        { continuation.resume(returning: $0) }
    }
}
