//
//  NanometersExtensionBufferedAudioBus.swift
//  NanometersExtension
//
//  Created by hguandl on 2024/5/22.
//

import AVFoundation

// MARK: - BufferedAudioBus Utility Class
// Utility classes to manage audio formats and buffers for an audio unit implementation's input and output audio busses.

// Reusable class, accessible from render thread.
class BufferedAudioBus {
    let bus: AUAudioUnitBus
    var maxFrames: AUAudioFrameCount = 0

    private var pcmBuffer: AVAudioPCMBuffer?

    private(set) var originalAudioBufferList: UnsafeMutableAudioBufferListPointer?
    private(set) var mutableAudioBufferList: UnsafeMutableAudioBufferListPointer?

    init(format: AVAudioFormat, maxChannels: AVAudioChannelCount) throws {
        bus = try AUAudioUnitBus(format: format)
        bus.maximumChannelCount = maxChannels
    }

    func allocateRenderResources(_ inMaxFrames: AUAudioFrameCount) throws {
        maxFrames = inMaxFrames

        guard let pcmBuffer = AVAudioPCMBuffer(pcmFormat: bus.format, frameCapacity: maxFrames) else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(kAudioUnitErr_FailedInitialization))
        }

        originalAudioBufferList = .init(.init(mutating: pcmBuffer.audioBufferList))
        mutableAudioBufferList = .init(pcmBuffer.mutableAudioBufferList)
        self.pcmBuffer = pcmBuffer
    }

    func deallocateRenderResources() {
        pcmBuffer = nil
        originalAudioBufferList = nil
        mutableAudioBufferList = nil
    }
}

// MARK: -  BufferedOutputBus: BufferedAudioBus
// MARK: prepareOutputBufferList()
/*
 BufferedOutputBus

 This class provides a prepareOutputBufferList method to copy the internal buffer pointers
 to the output buffer list in case the client passed in null buffer pointers.
 */
final class BufferedOutputBus: BufferedAudioBus {
    func prepareOutputBufferList(outBufferList: UnsafeMutablePointer<AudioBufferList>,
                                 frameCount: AVAudioFrameCount, zeroFill: Bool)
    {
        guard let originalAudioBufferList else { return }
        let outAudioBufferList = UnsafeMutableAudioBufferListPointer(outBufferList)
        let byteSize = frameCount * UInt32(MemoryLayout<Float>.size)

        for i in 0 ..< outAudioBufferList.count {
            outAudioBufferList[i].mNumberChannels = originalAudioBufferList[i].mNumberChannels
            outAudioBufferList[i].mDataByteSize = byteSize
            if outAudioBufferList[i].mData == nil {
                outAudioBufferList[i].mData = originalAudioBufferList[i].mData
            }
            if zeroFill {
                memset(outAudioBufferList[i].mData, 0, Int(byteSize))
            }
        }
    }
}

// MARK: - BufferedInputBus: BufferedAudioBus
// MARK: pullInput()
// MARK: prepareInputBufferList()
/*
 BufferedInputBus

 This class manages a buffer into which an audio unit with input busses can
 pull its input data.
 */
final class BufferedInputBus: BufferedAudioBus {
    /*
     Gets input data for this input by preparing the input buffer list and pulling
     the pullInputBlock.
     */
    func pullInput(
        actionFlags: UnsafeMutablePointer<AudioUnitRenderActionFlags>,
        timestamp: UnsafePointer<AudioTimeStamp>,
        frameCount: AVAudioFrameCount,
        inputBusNumber: Int,
        pullInputBlock: AURenderPullInputBlock?) -> AUAudioUnitStatus
    {
        guard let mutableAudioBufferList else {
            return kAudioUnitErr_Uninitialized
        }

        guard let pullInputBlock else {
            return kAudioUnitErr_NoConnection
        }

        /*
         Important:
         The Audio Unit must supply valid buffers in (inputData->mBuffers[x].mData) and mDataByteSize.
         mDataByteSize must be consistent with frameCount.

         The AURenderPullInputBlock may provide input in those specified buffers, or it may replace
         the mData pointers with pointers to memory which it owns and guarantees will remain valid
         until the next render cycle.

         See prepareInputBufferList()
         */

        prepareInputBufferList(frameCount: frameCount)

        return pullInputBlock(actionFlags, timestamp, frameCount, inputBusNumber, mutableAudioBufferList.unsafeMutablePointer)
    }

    /*
     prepareInputBufferList populates the mutableAudioBufferList with the data
     pointers from the originalAudioBufferList.

     The upstream audio unit may overwrite these with its own pointers, so each
     render cycle this function needs to be called to reset them.
     */
    func prepareInputBufferList(frameCount: AVAudioFrameCount) {
        guard let originalAudioBufferList, let mutableAudioBufferList else { return }

        let byteSize = min(frameCount, maxFrames) * UInt32(MemoryLayout<Float>.size)

        for i in 0 ..< originalAudioBufferList.count {
            mutableAudioBufferList[i].mNumberChannels = originalAudioBufferList[i].mNumberChannels
            mutableAudioBufferList[i].mData = originalAudioBufferList[i].mData
            mutableAudioBufferList[i].mDataByteSize = byteSize
        }
    }
}
