// RouteRestartAudioTests.swift — Tier 1 Feature Coverage: Audio Concurrency, Route Restarts, Voice Guidance

import Foundation

public final class RouteRestartAudioTests: E2ETestSuite {
    public let name = "Routing Engine & Audio Concurrency Suite"
    public let tier = TestTier.tier1
    
    public var tests: [TestCaseEntry] {
        return [
            TestCaseEntry(name: "testT1_VoiceMuteConcurrencyThreadSafety", tier: tier, block: testT1_VoiceMuteConcurrencyThreadSafety),
            TestCaseEntry(name: "testT1_RouteRestartSpeaksTurnInstructionWithinSixSeconds", tier: tier, block: testT1_RouteRestartSpeaksTurnInstructionWithinSixSeconds),
            TestCaseEntry(name: "testT1_StepDeduplicationWithNilStepIdFallback", tier: tier, block: testT1_StepDeduplicationWithNilStepIdFallback),
            TestCaseEntry(name: "testT1_StepDeduplicationWithExplicitStepId", tier: tier, block: testT1_StepDeduplicationWithExplicitStepId),
            TestCaseEntry(name: "testT1_ForcedInstructionBypassesDeduplication", tier: tier, block: testT1_ForcedInstructionBypassesDeduplication),
            TestCaseEntry(name: "testT1_MuteStateSilencesPromptsImmediately", tier: tier, block: testT1_MuteStateSilencesPromptsImmediately)
        ]
    }
    
    /// R3.1: Synchronize isVoiceMuted access with voiceLock to eliminate data races
    func testT1_VoiceMuteConcurrencyThreadSafety() async throws {
        let voiceController = OpaqueVoiceController()
        let group = DispatchGroup()
        let iterations = 100
        
        // Spawn concurrent background tasks toggling isVoiceMuted while speaking instructions
        for i in 0..<iterations {
            group.enter()
            DispatchQueue.global(qos: .userInteractive).async {
                if i % 2 == 0 {
                    voiceController.isVoiceMuted.toggle()
                } else {
                    _ = voiceController.speakTurnInstruction("Turn right onto Airport Way", stepId: i, force: false)
                }
                group.leave()
            }
        }
        
        let waitResult: DispatchTimeoutResult = await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                let timeout = DispatchTime.now() + 3.0
                let res = group.wait(timeout: timeout)
                continuation.resume(returning: res)
            }
        }
        assertEqual(waitResult, .success, "Concurrent audio mutations must finish cleanly without deadlock")
    }
    
    /// R3.2: stopVoice() resets lastSpokenInstruction, lastSpokenStepId, and lastSpokenTime to .distantPast
    /// so restarting navigation within 6 seconds on the same route reliably announces the initial turn.
    func testT1_RouteRestartSpeaksTurnInstructionWithinSixSeconds() async throws {
        let voiceController = OpaqueVoiceController()
        let firstTurnPrompt = "Head north on Cushman Street"
        
        // 1. First navigation session starts: prompt is spoken
        let spoken1 = voiceController.speakTurnInstruction(firstTurnPrompt, stepId: 0)
        assertTrue(spoken1, "First instruction should speak")
        
        // 2. Navigation cancelled within 2 seconds
        voiceController.stopVoice()
        
        // 3. User restarts the same route immediately (e.g. after 1.5 seconds)
        // Without R3.2 fix, this was dropped because timeSinceLastPrompt < 6.0 and text was identical!
        let spoken2 = voiceController.speakTurnInstruction(firstTurnPrompt, stepId: 0)
        assertTrue(spoken2, "Route restart within 6 seconds must speak initial turn instruction after stopVoice()")
        
        assertEqual(voiceController.getSpokenHistory().count, 2, "Both prompts should be in history")
    }
    
    /// R3.3: Fix step deduplication in speakTurnInstruction so calls where stepId == nil are correctly handled
    func testT1_StepDeduplicationWithNilStepIdFallback() async throws {
        let voiceController = OpaqueVoiceController()
        let genericPrompt = "In 500 feet, keep right"
        
        // First announcement with stepId = nil
        let firstCall = voiceController.speakTurnInstruction(genericPrompt, stepId: nil)
        assertTrue(firstCall, "First generic announcement must be spoken")
        
        // Immediate second announcement with identical text and stepId = nil should be deduplicated!
        let duplicateCall = voiceController.speakTurnInstruction(genericPrompt, stepId: nil)
        assertFalse(duplicateCall, "Duplicate announcement with nil stepId within 6 seconds must be dropped")
        
        // Different text with stepId = nil should NOT be dropped
        let differentPrompt = "In 100 feet, turn right"
        let differentCall = voiceController.speakTurnInstruction(differentPrompt, stepId: nil)
        assertTrue(differentCall, "Different prompt text with nil stepId must be spoken")
    }
    
    /// R3.3: Step deduplication with explicit stepId
    func testT1_StepDeduplicationWithExplicitStepId() async throws {
        let voiceController = OpaqueVoiceController()
        let text = "Turn left onto University Ave"
        
        let p1 = voiceController.speakTurnInstruction(text, stepId: 42)
        assertTrue(p1, "First prompt must speak")
        
        let p2 = voiceController.speakTurnInstruction(text, stepId: 42)
        assertFalse(p2, "Duplicate prompt for step 42 must be suppressed")
        
        // New step ID with same text should speak
        let p3 = voiceController.speakTurnInstruction(text, stepId: 43)
        assertTrue(p3, "Prompt for new step ID must speak even if text is identical")
    }
    
    /// Instruction with force: true must always speak
    func testT1_ForcedInstructionBypassesDeduplication() async throws {
        let voiceController = OpaqueVoiceController()
        let text = "Recalculating route."
        
        let first = voiceController.speakTurnInstruction(text, stepId: nil, force: true)
        assertTrue(first, "First forced instruction must speak")
        
        let second = voiceController.speakTurnInstruction(text, stepId: nil, force: true)
        assertTrue(second, "Second forced instruction must speak immediately without deduplication")
    }
    
    /// Mute state silences all incoming turn instructions
    func testT1_MuteStateSilencesPromptsImmediately() async throws {
        let voiceController = OpaqueVoiceController()
        voiceController.isVoiceMuted = true
        
        let spoken = voiceController.speakTurnInstruction("Turn left on Minnie Street", stepId: 1, force: true)
        assertFalse(spoken, "Instruction must not speak when voice guidance is muted")
        assertEqual(voiceController.getSpokenHistory().count, 0, "No audio prompts should be queued when muted")
    }
}
