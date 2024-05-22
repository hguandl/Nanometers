//
//  NanometersExtensionAudioUnit.swift
//  NanometersExtension
//
//  Created by hguandl on 2024/5/22.
//

import AudioToolbox
import AVFoundation
import CoreAudioKit

class NanometersExtensionAudioUnit: AUAudioUnit {
    private var inputBusArray: AUAudioUnitBusArray!
    private var outputBusArray: AUAudioUnitBusArray!
    private var outputBus: AUAudioUnitBus!

    private var kernel = NanometersExtensionDSPKernel()
    private var inputBus: BufferedInputBus!
    private var processHelper: ProcessHelper?

    override init(componentDescription: AudioComponentDescription, options: AudioComponentInstantiationOptions = []) throws {
        try super.init(componentDescription: componentDescription, options: options)

        try setupAudioBuses()
    }

    // MARK: - AUAudioUnit Setup

    private func setupAudioBuses() throws {
        // Create the output bus first
        let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2)
        try outputBus = AUAudioUnitBus(format: format!)
        outputBus.maximumChannelCount = 8

        // Create the input and output busses.
        inputBus = BufferedInputBus(format: format!, maxChannels: 8)

        // Create the input and output bus arrays.
        inputBusArray = .init(audioUnit: self, busType: .input, busses: [inputBus.bus!])

        // then an array with it
        outputBusArray = .init(audioUnit: self, busType: .output, busses: [outputBus])
    }

    func setupParameterTree(_ parameterTree: AUParameterTree) {
        self.parameterTree = parameterTree

        // Send the Parameter default values to the Kernel before setting up the parameter callbacks, so that the defaults set in the Kernel.hpp don't propagate back to the AUParameters via GetParameter
        for param in parameterTree.allParameters {
            kernel.setParameter(address: param.address, value: param.value)
        }

        setupParameterCallbacks()
    }

    private func setupParameterCallbacks() {
        // implementorValueObserver is called when a parameter changes value.
        parameterTree?.implementorValueObserver = { [unowned self] param, value in
            kernel.setParameter(address: param.address, value: value)
        }

        // implementorValueProvider is called when the value needs to be refreshed.
        parameterTree?.implementorValueProvider = { [unowned self] param in
            kernel.getParameter(address: param.address)
        }

        // A function to provide string representations of parameter values.
        parameterTree?.implementorStringFromValueCallback = { param, valuePtr in
            let value: AUValue
            if let valuePtr {
                value = valuePtr.pointee
            } else {
                value = param.value
            }

            return String(format: "%.f", value)
        }
    }

    // MARK: - AUAudioUnit Overrides

    override var maximumFramesToRender: AUAudioFrameCount {
        get { kernel.maxFramesToRender }

        set { kernel.maxFramesToRender = newValue }
    }

    // If an audio unit has input, an audio unit's audio input connection points.
    // Subclassers must override this property getter and should return the same object every time.
    // See sample code.
    override var inputBusses: AUAudioUnitBusArray {
        inputBusArray
    }

    // An audio unit's audio output connection points.
    // Subclassers must override this property getter and should return the same object every time.
    // See sample code.
    override var outputBusses: AUAudioUnitBusArray {
        outputBusArray
    }

    override var shouldBypassEffect: Bool {
        get { kernel.bypassed }

        set { kernel.bypassed = newValue }
    }

    // Allocate resources required to render.
    // Subclassers should call the superclass implementation.
    override func allocateRenderResources() throws {
        let inputChannelCount = inputBusses[0].format.channelCount
        let outputChannelCount = outputBusses[0].format.channelCount

        guard outputChannelCount == inputChannelCount else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(kAudioUnitErr_FailedInitialization))
        }
        inputBus.allocateRenderResources(maximumFramesToRender)
        kernel.musicalContextBlock = musicalContextBlock
        kernel.initialize(inputChannelCount: Int32(inputChannelCount), outputChannelCount: Int32(outputChannelCount), inSampleRate: outputBus.format.sampleRate)
        processHelper = ProcessHelper(kernel: kernel, inputChannelCount: inputChannelCount, outputChannelCount: outputChannelCount)
        try super.allocateRenderResources()
    }

    // Deallocate resources allocated in allocateRenderResources:
    // Subclassers should call the superclass implementation.
    override func deallocateRenderResources() {
        // Deallocate your resources.
        kernel.deInitialize()

        super.deallocateRenderResources()
    }

    // MARK: - AUAudioUnit (AUAudioUnitImplementation)

    override var internalRenderBlock: AUInternalRenderBlock {
        return { [unowned self] _, timestamp, frameCount, _, outputData, realtimeEventListHead, pullInputBlock in

            var pullFlags = AudioUnitRenderActionFlags(rawValue: 0)

            if frameCount > kernel.maxFramesToRender {
                return kAudioUnitErr_TooManyFramesToProcess
            }

            let err = inputBus.pullInput(actionFlags: &pullFlags, timestamp: timestamp, frameCount: frameCount, inputBusNumber: 0, pullInputBlock: pullInputBlock)

            guard err == noErr else { return err }

            let inAudioBufferList = UnsafeMutableAudioBufferListPointer(inputBus.mutableAudioBufferList!)

            /*
             Important:
             If the caller passed non-null output pointers (outputData->mBuffers[x].mData), use those.

             If the caller passed null output buffer pointers, process in memory owned by the Audio Unit
             and modify the (outputData->mBuffers[x].mData) pointers to point to this owned memory.
             The Audio Unit is responsible for preserving the validity of this memory until the next call to render,
             or deallocateRenderResources is called.

             If your algorithm cannot process in-place, you will need to preallocate an output buffer
             and use it here.

             See the description of the canProcessInPlace property.
             */

            // If passed null output buffer pointers, process in-place in the input buffer.
            let outAudioBufferList = UnsafeMutableAudioBufferListPointer(outputData)
            if outAudioBufferList[0].mData != nil {
                for i in 0 ..< outAudioBufferList.count {
                    outAudioBufferList[i].mData = inAudioBufferList[i].mData
                }
            }

            processHelper?.processWithEvents(inBufferList: inAudioBufferList, outBufferList: outAudioBufferList, timestamp: timestamp, frameCount: frameCount, events: realtimeEventListHead)
            return noErr
        }
    }
}
