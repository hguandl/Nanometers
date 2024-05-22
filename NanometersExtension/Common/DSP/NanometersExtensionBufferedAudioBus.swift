//
//  NanometersExtensionBufferedAudioBus.swift
//  NanometersExtension
//
//  Created by hguandl on 2024/5/22.
//

import AudioToolbox
import AudioUnit
import AVFoundation

// MARK: - BufferedAudioBus Utility Class
// Utility classes to manage audio formats and buffers for an audio unit implementation's input and output audio busses.

// Reusable ObjC class, accessible from render thread.
@objc class BufferedAudioBus: NSObject {
    @objc var bus: AUAudioUnitBus!
    @objc var maxFrames: AUAudioFrameCount

    @objc var pcmBuffer: AVAudioPCMBuffer!

    @objc var originalAudioBufferList: UnsafePointer<AudioBufferList>!
    @objc var mutableAudioBufferList: UnsafeMutablePointer<AudioBufferList>!

    @objc init(format: AVAudioFormat, maxChannels: AVAudioChannelCount) {
        maxFrames = 0
        pcmBuffer = nil

        bus = try! AUAudioUnitBus(format: format)

        bus.maximumChannelCount = maxChannels
    }

    @objc func allocateRenderResources(_ inMaxFrames: AUAudioFrameCount) {
        maxFrames = inMaxFrames

        pcmBuffer = AVAudioPCMBuffer(pcmFormat: bus.format, frameCapacity: maxFrames)

        originalAudioBufferList = pcmBuffer.audioBufferList
        mutableAudioBufferList = pcmBuffer.mutableAudioBufferList
    }

    @objc func deallocateRenderResources() {
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
@objc class BufferedOutputBus: BufferedAudioBus {
    @objc func prepareOutputBufferList(outBufferList: UnsafeMutablePointer<AudioBufferList>,
                                       frameCount: AVAudioFrameCount, zeroFill: Bool)
    {
        let byteSize = frameCount * UInt32(MemoryLayout<Float>.size)

        let target = UnsafeMutableAudioBufferListPointer(outBufferList)!
        let source = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: originalAudioBufferList))!

        for i in 0 ..< Int(outBufferList.pointee.mNumberBuffers) {
            target[i].mNumberChannels = source[i].mNumberChannels
            target[i].mDataByteSize = byteSize
            if target[i].mData == nil {
                target[i].mData = source[i].mData
            }
            if zeroFill {
                memset(target[i].mData, 0, Int(byteSize))
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
@objc class BufferedInputBus: BufferedAudioBus {
    /*
     Gets input data for this input by preparing the input buffer list and pulling
     the pullInputBlock.
     */
    @objc func pullInput(
        actionFlags: UnsafeMutablePointer<AudioUnitRenderActionFlags>,
        timestamp: UnsafePointer<AudioTimeStamp>,
        frameCount: AVAudioFrameCount,
        inputBusNumber: Int,
        pullInputBlock: AURenderPullInputBlock?) -> AUAudioUnitStatus
    {
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

        prepareInputBufferList(frameCount)

        return pullInputBlock(actionFlags, timestamp, frameCount, inputBusNumber, mutableAudioBufferList)
    }

    /*
     prepareInputBufferList populates the mutableAudioBufferList with the data
     pointers from the originalAudioBufferList.

     The upstream audio unit may overwrite these with its own pointers, so each
     render cycle this function needs to be called to reset them.
     */
    @objc func prepareInputBufferList(_ frameCount: AVAudioFrameCount) {
        let byteSize = min(frameCount, maxFrames) * UInt32(MemoryLayout<Float>.size)
        mutableAudioBufferList.pointee.mNumberBuffers = originalAudioBufferList.pointee.mNumberBuffers

        let target = UnsafeMutableAudioBufferListPointer(mutableAudioBufferList)!
        let source = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: originalAudioBufferList))!

        for i in 0 ..< Int(originalAudioBufferList.pointee.mNumberBuffers) {
            target[i].mNumberChannels = source[i].mNumberChannels
            target[i].mData = source[i].mData
            target[i].mDataByteSize = byteSize
        }
    }
}
