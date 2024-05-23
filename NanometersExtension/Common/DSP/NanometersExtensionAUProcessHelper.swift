//
//  NanometersExtensionAUProcessHelper.swift
//  NanometersExtension
//
//  Created by hguandl on 2024/5/22.
//

import AudioToolbox

final class ProcessHelper {
    private let kernel: NanometersExtensionDSPKernel

    init(kernel: NanometersExtensionDSPKernel, inputChannelCount: UInt32, outputChannelCount: UInt32) {
        self.kernel = kernel
    }

    private func callProcess(inBufferList: UnsafeMutableAudioBufferListPointer,
                             outBufferList: UnsafeMutableAudioBufferListPointer,
                             now: AUEventSampleTime,
                             frameCount: AUAudioFrameCount,
                             frameOffset: AUAudioFrameCount)
    {
        let inputBuffers = inBufferList.compactMap { buffer in
            UnsafePointer(buffer.mData?.assumingMemoryBound(to: Float.self).advanced(by: Int(frameOffset)))
        }

        let outputBuffers = outBufferList.compactMap { buffer in
            buffer.mData?.assumingMemoryBound(to: Float.self).advanced(by: Int(frameOffset))
        }

        kernel.process(inputBuffers: inputBuffers, outputBuffers: outputBuffers, bufferStartTime: now, frameCount: frameCount)
    }

    func processWithEvents(inBufferList: UnsafeMutableAudioBufferListPointer,
                           outBufferList: UnsafeMutableAudioBufferListPointer,
                           timestamp: UnsafePointer<AudioTimeStamp>,
                           frameCount: AUAudioFrameCount,
                           events: UnsafePointer<AURenderEvent>?)
    {
        var now = AUEventSampleTime(timestamp.pointee.mSampleTime)
        var framesRemaining = frameCount
        var nextEvent = events?.pointee // events is a linked list, at the beginning, the nextEvent is the first event

        while framesRemaining > 0 {
            // If there are no more events, we can process the entire remaining segment and exit.
            guard let event = nextEvent else {
                let frameOffset = frameCount - framesRemaining
                callProcess(inBufferList: inBufferList, outBufferList: outBufferList, now: now, frameCount: framesRemaining, frameOffset: frameOffset)
                return
            }

            // **** start late events late.
            let timeZero = AUEventSampleTime(0)
            let headEventTime = event.head.eventSampleTime
            let framesThisSegment = AUAudioFrameCount(max(timeZero, headEventTime - now))

            // Compute everything before the next event.
            if framesThisSegment > 0 {
                let frameOffset = frameCount - framesRemaining

                callProcess(inBufferList: inBufferList, outBufferList: outBufferList, now: now, frameCount: framesThisSegment, frameOffset: frameOffset)

                // Advance frames.
                framesRemaining -= framesThisSegment

                // Advance time.
                now += AUEventSampleTime(framesThisSegment)
            }

            nextEvent = performAllSimultaneousEvents(now: now, events: event)
        }
    }

    func performAllSimultaneousEvents(now: AUEventSampleTime, events: AURenderEvent?) -> AURenderEvent? {
        var nextEvent = events
        // While event is not null and is simultaneous (or late).
        while let event = nextEvent {
            guard event.head.eventSampleTime <= now else {
                break
            }

            kernel.handleOneEvent(now: now, event: event)

            // Go to next event.
            nextEvent = event.head.next?.pointee
        }
        return nextEvent
    }
}
