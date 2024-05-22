//
//  NanometersExtensionDSPKernel.swift
//  NanometersExtension
//
//  Created by hguandl on 2024/5/23.
//

import AudioToolbox
import AudioUnit.AUParameters
import Foundation

class NanometersExtensionDSPKernel {
    func initialize(inputChannelCount: Int32, outputChannelCount: Int32, inSampleRate: Double) {
        sampleRate = inSampleRate
    }

    func deInitialize() { //
    }

    // MARK: - Parameter Getter / Setter

    func setParameter(address: AUParameterAddress, value: AUValue) {
        switch NanometersExtensionParameterAddress(rawValue: address) {
        case .gain:
            gain = value
        // Add a case for each parameter in Parameters.swift

        default:
            break
        }
    }

    func getParameter(address: AUParameterAddress) -> AUValue {
        // Return the goal. It is not thread safe to return the ramping value.
        switch NanometersExtensionParameterAddress(rawValue: address) {
        case .gain:
            return gain

        default: return 0
        }
    }

    /**
     MARK: - Internal Process

     This function does the core siginal processing.
     Do your custom DSP here.
     */
    func process(inputBuffers: [UnsafePointer<Float>],
                 outputBuffers: [UnsafeMutablePointer<Float>],
                 bufferStartTime: AUEventSampleTime, frameCount: AUAudioFrameCount)
    {
        /*
         Note: For an Audio Unit with 'n' input channels to 'n' output channels, remove the assert below and
         modify the check in [NanometersExtensionAudioUnit allocateRenderResourcesAndReturnError]
         */
        assert(inputBuffers.count == outputBuffers.count)

        if bypassed {
            // Pass the samples through
            for channel in 0 ..< inputBuffers.count {
                outputBuffers[channel].initialize(from: inputBuffers[channel], count: Int(frameCount))
            }
            return
        }

        // Use this to get Musical context info from the Plugin Host,
        // Replace nullptr with &memberVariable according to the AUHostMusicalContextBlock function signature
        /*
         if (mMusicalContextBlock) {
         mMusicalContextBlock(nullptr,     // currentTempo
         nullptr,     // timeSignatureNumerator
         nullptr,     // timeSignatureDenominator
         nullptr,     // currentBeatPosition
         nullptr,     // sampleOffsetToNextBeat
         nullptr);    // currentMeasureDownbeatPosition
         }
         */

        // Perform per sample dsp on the incoming float in before assigning it to out
        for channel in 0 ..< inputBuffers.count {
            for frameIndex in 0 ..< Int(frameCount) {
                // Do your sample by sample dsp here...
                outputBuffers[channel][frameIndex] = inputBuffers[channel][frameIndex] * gain
            }
        }
    }

    func handleOneEvent(now: AUEventSampleTime, event: AURenderEvent) {
        switch event.head.eventType {
        case .parameter:
            handleParameterEvent(now: now, parameterEvent: event.parameter)

        default:
            break
        }
    }

    func handleParameterEvent(now: AUEventSampleTime, parameterEvent: AUParameterEvent) {
        // Implement handling incoming Parameter events as needed
    }

    // MARK: Member Variables

    var musicalContextBlock: AUHostMusicalContextBlock?

    var sampleRate = 44100.0
    var gain: Float = 1.0
    var bypassed = false
    var maxFramesToRender: AUAudioFrameCount = 1024
}
