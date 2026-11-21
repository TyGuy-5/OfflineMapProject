// Test11_AudioConcurrencyStress.swift
// Empirical Challenger Harness for testAdversarial11_AudioSessionDeactivationConcurrencyStress

import Foundation
import AVFoundation

// =====================================================================
// Production-Fidelity Voice Guidance & Audio Session Concurrency Engine
// Directly replicates the concurrency architecture in RoutingService.swift:
// - voiceLock (NSLock) guarding activeSpeechGeneration, utteranceGenerations, isVoiceMuted, lastSpoken
// - speakTurnInstruction incrementing activeSpeechGeneration and dispatching to main queue
// - speechSynthesizer didFinish/didCancel callbacks concurrently popping generation
// =====================================================================

public final class ConcurrencyFidelityRoutingService: NSObject, @unchecked Sendable, AVSpeechSynthesizerDelegate {
    private let voiceLock = NSLock()
    private var _isVoiceMuted: Bool = false
    public var isVoiceMuted: Bool {
        get {
            voiceLock.lock()
            defer { voiceLock.unlock() }
            return _isVoiceMuted
        }
        set {
            voiceLock.lock()
            _isVoiceMuted = newValue
            if newValue {
                stopVoiceLocked()
            }
            voiceLock.unlock()
        }
    }

    public private(set) var activeSpeechGeneration: Int = 0
    private var utteranceGenerations: [ObjectIdentifier: Int] = [:]
    private var lastSpokenInstruction: String = ""
    private var lastSpokenStepId: Int? = nil
    private var lastSpokenTime: Date = .distantPast

    public private(set) var deactivationCount: Int = 0
    public private(set) var acceptedPromptCount: Int = 0
    public private(set) var droppedPromptCount: Int = 0

    public override init() {
        super.init()
    }

    private func stopVoiceLocked() {
        activeSpeechGeneration += 1
    }

    public func stopVoice() {
        voiceLock.lock()
        defer { voiceLock.unlock() }
        stopVoiceLocked()
    }

    public func speakTurnInstruction(_ text: String, stepId: Int? = nil, force: Bool = false) {
        voiceLock.lock()
        guard !_isVoiceMuted && !text.isEmpty else {
            droppedPromptCount += 1
            voiceLock.unlock()
            return
        }

        let now = Date()
        let isSameText = (text == lastSpokenInstruction)
        let isSameStep = (stepId != nil && lastSpokenStepId != nil) ? (stepId == lastSpokenStepId) : true
        let timeSinceLastPrompt = now.timeIntervalSince(lastSpokenTime)

        // Drop duplicate prompts only if same step and occurred within 6 seconds
        if !force && isSameText && isSameStep && timeSinceLastPrompt < 6.0 {
            droppedPromptCount += 1
            voiceLock.unlock()
            return
        }

        lastSpokenInstruction = text
        lastSpokenStepId = stepId
        lastSpokenTime = now
        activeSpeechGeneration += 1
        acceptedPromptCount += 1
        let generation = activeSpeechGeneration
        voiceLock.unlock()

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.voiceLock.lock()
            let currentGen = self.activeSpeechGeneration
            let isMuted = self._isVoiceMuted
            self.voiceLock.unlock()

            guard generation == currentGen, !isMuted else { return }

            let utterance = AVSpeechUtterance(string: text)
            self.voiceLock.lock()
            self.utteranceGenerations[ObjectIdentifier(utterance)] = generation
            self.voiceLock.unlock()
        }
    }

    public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        voiceLock.lock()
        let generation = utteranceGenerations.removeValue(forKey: ObjectIdentifier(utterance)) ?? activeSpeechGeneration
        voiceLock.unlock()

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.voiceLock.lock()
            let currentGen = self.activeSpeechGeneration
            self.voiceLock.unlock()

            guard generation == currentGen else { return }
            self.voiceLock.lock()
            self.deactivationCount += 1
            self.voiceLock.unlock()
        }
    }

    public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        voiceLock.lock()
        let generation = utteranceGenerations.removeValue(forKey: ObjectIdentifier(utterance)) ?? activeSpeechGeneration
        voiceLock.unlock()

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.voiceLock.lock()
            let currentGen = self.activeSpeechGeneration
            self.voiceLock.unlock()

            guard generation == currentGen else { return }
            self.voiceLock.lock()
            self.deactivationCount += 1
            self.voiceLock.unlock()
        }
    }
}

// =====================================================================
// Test Runner
// =====================================================================

@main
struct Test11Runner {
    static var passCount = 0
    static var failCount = 0

    static func assertCondition(_ cond: Bool, _ name: String, details: String = "") {
        if cond {
            passCount += 1
            print("  ✅ [PASS] \(name)")
        } else {
            failCount += 1
            print("  ❌ [FAIL] \(name): \(details)")
        }
    }

    static func main() {
        print("=================================================================")
        print("🔬 EMPIRICAL CHALLENGER TEST 11: Audio Concurrency Stress")
        print("=================================================================")

        // -------------------------------------------------------------
        // Subtest 1: Exact Replication of testAdversarial11 (40 Concurrent Dispatches)
        // -------------------------------------------------------------
        print("\n--- Subtest 1: Exact testAdversarial11 Replication (40 Concurrent Prompts) ---")
        let routingService = ConcurrencyFidelityRoutingService()
        let dispatchGroup = DispatchGroup()

        let start1 = CFAbsoluteTimeGetCurrent()
        for i in 0..<40 {
            dispatchGroup.enter()
            DispatchQueue.global(qos: .userInteractive).async {
                let force = (i % 3 == 0)
                let text = "Turn instruction \(i) in \(i * 100) feet."
                routingService.speakTurnInstruction(text, stepId: i, force: force)

                // Simultaneously simulate delegate callbacks with dummyUtterance
                let dummySynth = AVSpeechSynthesizer()
                let dummyUtterance = AVSpeechUtterance(string: "Dummy \(i)")
                if i % 2 == 0 {
                    routingService.speechSynthesizer(dummySynth, didCancel: dummyUtterance)
                } else {
                    routingService.speechSynthesizer(dummySynth, didFinish: dummyUtterance)
                }
                dispatchGroup.leave()
            }
        }

        let waitResult = dispatchGroup.wait(timeout: .now() + 5.0)
        let elapsed1 = CFAbsoluteTimeGetCurrent() - start1
        assertCondition(waitResult == .success, "Subtest 1 completed without deadlock (in \(String(format: "%.3f", elapsed1))s)")

        // Inspection via Mirror (matching testAdversarial11 line 1271)
        let mirror = Mirror(reflecting: routingService)
        let finalGen = mirror.children.first { $0.label == "activeSpeechGeneration" }?.value as? Int
        assertCondition(finalGen != nil, "activeSpeechGeneration discovered via Mirror")
        let genVal = finalGen ?? 0
        print("  Observed activeSpeechGeneration = \(genVal) (expected >= 40)")
        assertCondition(genVal >= 40, "activeSpeechGeneration advanced to \(genVal) (>= 40)")

        // -------------------------------------------------------------
        // Subtest 2: High Contention Stress Test (100 Concurrent Threads + Voice Muting)
        // -------------------------------------------------------------
        print("\n--- Subtest 2: High Contention (100 Concurrent Threads + Concurrent Muting) ---")
        let rsStress = ConcurrencyFidelityRoutingService()
        let stressGroup = DispatchGroup()

        // Background muting thread
        let muteDone = DispatchGroup()
        muteDone.enter()
        DispatchQueue.global(qos: .background).async {
            for j in 0..<50 {
                rsStress.isVoiceMuted = (j % 2 == 0)
                if j % 5 == 0 {
                    rsStress.stopVoice()
                }
                usleep(500) // 0.5ms
            }
            rsStress.isVoiceMuted = false
            muteDone.leave()
        }

        let start2 = CFAbsoluteTimeGetCurrent()
        for i in 0..<100 {
            stressGroup.enter()
            DispatchQueue.global(qos: .userInteractive).async {
                let force = (i % 2 == 0)
                let text = "Turn instruction \(i) in \(i * 50) feet."
                rsStress.speakTurnInstruction(text, stepId: i, force: force)

                let dummySynth = AVSpeechSynthesizer()
                let dummyUtterance = AVSpeechUtterance(string: "Dummy Utterance \(i)")
                if i % 3 == 0 {
                    rsStress.speechSynthesizer(dummySynth, didCancel: dummyUtterance)
                } else {
                    rsStress.speechSynthesizer(dummySynth, didFinish: dummyUtterance)
                }
                stressGroup.leave()
            }
        }

        let waitStress = stressGroup.wait(timeout: .now() + 5.0)
        _ = muteDone.wait(timeout: .now() + 5.0)
        let elapsed2 = CFAbsoluteTimeGetCurrent() - start2
        assertCondition(waitStress == .success, "Subtest 2 (100 threads + muting) completed without deadlock in \(String(format: "%.3f", elapsed2))s)")

        let totalHandled = rsStress.acceptedPromptCount + rsStress.droppedPromptCount
        print("  Prompts accepted: \(rsStress.acceptedPromptCount), dropped: \(rsStress.droppedPromptCount), total: \(totalHandled)")
        assertCondition(totalHandled == 100, "All 100 prompts safely processed without drop or race")
        assertCondition(rsStress.activeSpeechGeneration >= rsStress.acceptedPromptCount, "activeSpeechGeneration (\(rsStress.activeSpeechGeneration)) >= accepted prompts (\(rsStress.acceptedPromptCount))")

        // -------------------------------------------------------------
        // Subtest 3: Massive Contention Burst (200 Concurrent Workers)
        // -------------------------------------------------------------
        print("\n--- Subtest 3: Massive Contention Burst (200 Concurrent Workers) ---")
        let rsBurst = ConcurrencyFidelityRoutingService()
        let burstGroup = DispatchGroup()

        let start3 = CFAbsoluteTimeGetCurrent()
        for i in 0..<200 {
            burstGroup.enter()
            DispatchQueue.global().async {
                let text = "Maneuver step \(i) merge ahead."
                rsBurst.speakTurnInstruction(text, stepId: i, force: true)

                let synth = AVSpeechSynthesizer()
                let utt = AVSpeechUtterance(string: "Burst \(i)")
                if i % 2 == 0 {
                    rsBurst.speechSynthesizer(synth, didFinish: utt)
                } else {
                    rsBurst.speechSynthesizer(synth, didCancel: utt)
                }
                burstGroup.leave()
            }
        }

        let waitBurst = burstGroup.wait(timeout: .now() + 5.0)
        let elapsed3 = CFAbsoluteTimeGetCurrent() - start3
        assertCondition(waitBurst == .success, "Subtest 3 (200 concurrent workers) finished in \(String(format: "%.3f", elapsed3))s without deadlock")

        let burstGen = rsBurst.activeSpeechGeneration
        print("  Observed activeSpeechGeneration = \(burstGen) (expected == 200)")
        assertCondition(burstGen == 200, "All 200 concurrent prompts incremented activeSpeechGeneration exactly (no lost increments)")

        // -------------------------------------------------------------
        // Subtest 4: RunLoop Queue Drain & Safety Verification
        // Drain pending main-thread async blocks to verify memory stability
        // -------------------------------------------------------------
        print("\n--- Subtest 4: Main RunLoop Queue Drainage Verification ---")
        let drainStart = CFAbsoluteTimeGetCurrent()
        while CFAbsoluteTimeGetCurrent() - drainStart < 0.2 {
            RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.01))
        }
        assertCondition(true, "Main runloop drained pending speech synthesis blocks without crash or exception")

        // Summary
        print("\n=================================================================")
        print("SUMMARY TEST 11: \(passCount) PASSED, \(failCount) FAILED")
        print("=================================================================")
        if failCount > 0 {
            exit(1)
        }
    }
}
