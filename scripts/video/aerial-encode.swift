// Re-encodes a prepared video into the shape Apple's aerial engine expects:
// HEVC Main 10 tagged 'hvc1', BT.709 limited range, hierarchical temporal
// layers, and 'tscl'/'tsas' sample groups. ffmpeg can't write those groups;
// AVAssetWriter writes them from VideoToolbox's temporal-level attachments.
// See scripts/video/README.md.
//
// Build:  swiftc -O -o aerial-encode scripts/video/aerial-encode.swift
// Usage:  aerial-encode <input> <output.mov> [fps=60] [baseLayerFps=15] [layers=3] [Mbps=30]
// The input must already have the target size and frame rate.

import AVFoundation
import CoreMedia
import VideoToolbox

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

let args = CommandLine.arguments
guard args.count >= 3 else {
    fail("usage: aerial-encode <input> <output.mov> [fps=60] [baseLayerFps=15] [layers=3] [Mbps=30]")
}
func argument<T: LosslessStringConvertible>(_ index: Int, default value: T) -> T {
    guard args.count > index else { return value }
    guard let parsed = T(args[index]) else { fail("invalid argument: \(args[index])") }
    return parsed
}
let inputURL = URL(fileURLWithPath: args[1])
let outputURL = URL(fileURLWithPath: args[2])
let fps: Int32 = argument(3, default: 60)
let baseFps: Double = argument(4, default: 15)
let layers: Int = argument(5, default: 3)
let mbps: Double = argument(6, default: 30)

let asset = AVURLAsset(url: inputURL)
let loaded = DispatchSemaphore(value: 0)
nonisolated(unsafe) var loadedTrack: AVAssetTrack?
nonisolated(unsafe) var naturalSize = CGSize.zero
Task {
    loadedTrack = try? await asset.loadTracks(withMediaType: .video).first
    naturalSize = (try? await loadedTrack?.load(.naturalSize)) ?? .zero
    loaded.signal()
}
loaded.wait()
guard let videoTrack = loadedTrack, naturalSize != .zero else { fail("no readable video track in \(inputURL.path)") }

let reader = try AVAssetReader(asset: asset)
let readerOutput = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: [
    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange,
])
readerOutput.alwaysCopiesSampleData = false
reader.add(readerOutput)

var compressionSession: VTCompressionSession?
VTCompressionSessionCreate(
    allocator: nil, width: Int32(naturalSize.width), height: Int32(naturalSize.height),
    codecType: kCMVideoCodecType_HEVC,
    encoderSpecification: [kVTVideoEncoderSpecification_RequireHardwareAcceleratedVideoEncoder: true] as CFDictionary,
    imageBufferAttributes: nil, compressedDataAllocator: nil, outputCallback: nil, refcon: nil,
    compressionSessionOut: &compressionSession)
guard let session = compressionSession else { fail("could not create a hardware HEVC encoder") }

func set(_ key: CFString, _ value: Any, required: Bool = true) {
    let status = VTSessionSetProperty(session, key: key, value: value as CFTypeRef)
    if status != noErr {
        if required { fail("\(key) = \(value) failed: \(status)") }
        print("warning: \(key) = \(value) failed: \(status)")
    }
}
set(kVTCompressionPropertyKey_ProfileLevel, kVTProfileLevel_HEVC_Main10_AutoLevel)
set(kVTCompressionPropertyKey_RealTime, false)
set(kVTCompressionPropertyKey_AllowFrameReordering, true)
set(kVTCompressionPropertyKey_ExpectedFrameRate, fps)
set(kVTCompressionPropertyKey_AverageBitRate, Int(mbps * 1_000_000))
set(kVTCompressionPropertyKey_MaxKeyFrameIntervalDuration, 5.0)
set(kVTCompressionPropertyKey_ColorPrimaries, kCVImageBufferColorPrimaries_ITU_R_709_2)
set(kVTCompressionPropertyKey_TransferFunction, kCVImageBufferTransferFunction_ITU_R_709_2)
set(kVTCompressionPropertyKey_YCbCrMatrix, kCVImageBufferYCbCrMatrix_ITU_R_709_2)
// Public: asks for hierarchical (temporal-layer) encoding.
set(kVTCompressionPropertyKey_BaseLayerFrameRate, baseFps)
// Undocumented VideoToolbox key; without it the encoder may pick fewer layers.
set("NumberOfTemporalLayers" as CFString, layers, required: false)
VTCompressionSessionPrepareToEncodeFrames(session)

if FileManager.default.fileExists(atPath: outputURL.path) { fail("\(outputURL.path) already exists") }
let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mov)
var writerInput: AVAssetWriterInput?
var pending: [CMSampleBuffer] = []
var encodeErrors = 0
let lock = NSLock()

func append(_ buffer: CMSampleBuffer) {
    if writerInput == nil {
        // Passthrough: samples are stored as encoded, and their temporal-level
        // attachments become the tscl/tsas sample groups.
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: nil,
                                       sourceFormatHint: CMSampleBufferGetFormatDescription(buffer))
        input.expectsMediaDataInRealTime = false
        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)
        writerInput = input
    }
    while !writerInput!.isReadyForMoreMediaData { usleep(1000) }
    if !writerInput!.append(buffer) { fail("writing failed: \(String(describing: writer.error))") }
}

func drainEncodedFrames() {
    lock.lock(); let ready = pending; pending.removeAll(); lock.unlock()
    ready.forEach(append)
}

reader.startReading()
let frameDuration = CMTime(value: 1, timescale: fps)
var frameIndex: Int64 = 0
while let sample = readerOutput.copyNextSampleBuffer() {
    guard let pixelBuffer = CMSampleBufferGetImageBuffer(sample) else { continue }
    // Re-time onto a constant frame rate.
    let pts = CMTime(value: frameIndex, timescale: fps)
    frameIndex += 1
    VTCompressionSessionEncodeFrame(session, imageBuffer: pixelBuffer, presentationTimeStamp: pts,
                                    duration: frameDuration, frameProperties: nil, infoFlagsOut: nil) { status, _, encoded in
        lock.lock(); defer { lock.unlock() }
        if status == noErr, let encoded { pending.append(encoded) } else { encodeErrors += 1 }
    }
    drainEncodedFrames()
}
if reader.status == .failed { fail("reading failed: \(String(describing: reader.error))") }
VTCompressionSessionCompleteFrames(session, untilPresentationTimeStamp: .invalid)
drainEncodedFrames()
if encodeErrors > 0 { fail("\(encodeErrors) frame(s) failed to encode") }
guard let input = writerInput else { fail("no frames were encoded") }

input.markAsFinished()
let finished = DispatchSemaphore(value: 0)
writer.finishWriting { finished.signal() }
finished.wait()
guard writer.status == .completed else { fail("writing failed: \(String(describing: writer.error))") }
print("wrote \(outputURL.path): \(frameIndex) frames at \(fps) fps")
