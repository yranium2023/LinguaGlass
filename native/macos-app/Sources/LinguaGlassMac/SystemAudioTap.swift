import AVFoundation
import CoreAudio
import Foundation

private struct SystemAudioTapError: LocalizedError {
    let operation: String
    let status: OSStatus

    var errorDescription: String? {
        let value = UInt32(bitPattern: status)
        let bytes = [24, 16, 8, 0].map { UInt8((value >> UInt32($0)) & 0xff) }
        let code = bytes.allSatisfy { $0 >= 32 && $0 < 127 }
            ? String(bytes: bytes, encoding: .ascii) ?? "\(status)" : "\(status)"
        return "\(operation)失败（\(code)）"
    }
}

/// Captures outgoing audio through Apple's Core Audio process-tap API. Unlike
/// ScreenCaptureKit this never requests access to windows, displays or pixels.
@available(macOS 14.2, *)
final class SystemAudioTap: @unchecked Sendable {
    var onBuffer: (@Sendable (AVAudioPCMBuffer) -> Void)?

    private let deviceUID: String
    private let queue = DispatchQueue(label: "com.linguaglass.native.core-audio-tap", qos: .userInitiated)
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateDeviceID = AudioObjectID(kAudioObjectUnknown)
    private var deviceProcID: AudioDeviceIOProcID?
    private var format: AVAudioFormat?

    init(deviceUID: String) { self.deviceUID = deviceUID }

    func start() throws {
        guard tapID == kAudioObjectUnknown else { return }

        let tapDescription = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
        tapDescription.uuid = UUID()
        tapDescription.name = "LinguaGlass System Audio"
        tapDescription.isPrivate = true
        tapDescription.muteBehavior = .unmuted

        var newTapID = AudioObjectID(kAudioObjectUnknown)
        var status = AudioHardwareCreateProcessTap(tapDescription, &newTapID)
        guard status == noErr else { throw SystemAudioTapError(operation: "创建系统音频通道", status: status) }
        tapID = newTapID

        do {
            var streamDescription = AudioStreamBasicDescription()
            var propertySize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioTapPropertyFormat,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            status = AudioObjectGetPropertyData(tapID, &address, 0, nil, &propertySize, &streamDescription)
            guard status == noErr, let format = AVAudioFormat(streamDescription: &streamDescription) else {
                throw SystemAudioTapError(operation: "读取系统音频格式", status: status)
            }
            self.format = format

            let aggregateDescription: [String: Any] = [
                kAudioAggregateDeviceNameKey: "LinguaGlass System Audio",
                kAudioAggregateDeviceUIDKey: "com.linguaglass.native.tap.\(UUID().uuidString)",
                kAudioAggregateDeviceMainSubDeviceKey: deviceUID,
                kAudioAggregateDeviceIsPrivateKey: true,
                kAudioAggregateDeviceIsStackedKey: false,
                kAudioAggregateDeviceTapAutoStartKey: true,
                kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: deviceUID]],
                kAudioAggregateDeviceTapListKey: [[
                    kAudioSubTapDriftCompensationKey: true,
                    kAudioSubTapUIDKey: tapDescription.uuid.uuidString
                ]]
            ]

            var newAggregateID = AudioObjectID(kAudioObjectUnknown)
            status = AudioHardwareCreateAggregateDevice(aggregateDescription as CFDictionary, &newAggregateID)
            guard status == noErr else {
                throw SystemAudioTapError(operation: "创建系统音频设备", status: status)
            }
            aggregateDeviceID = newAggregateID

            status = AudioDeviceCreateIOProcIDWithBlock(
                &deviceProcID,
                aggregateDeviceID,
                queue
            ) { [weak self] _, inputData, _, _, _ in
                guard let self, let format = self.format,
                      let buffer = AVAudioPCMBuffer(
                        pcmFormat: format,
                        bufferListNoCopy: inputData,
                        deallocator: nil
                      )
                else { return }
                self.onBuffer?(buffer)
            }
            guard status == noErr else {
                throw SystemAudioTapError(operation: "连接系统音频设备", status: status)
            }

            status = AudioDeviceStart(aggregateDeviceID, deviceProcID)
            guard status == noErr else {
                throw SystemAudioTapError(operation: "启动系统音频录制", status: status)
            }
        } catch {
            stop()
            throw error
        }
    }

    func stop() {
        if aggregateDeviceID != kAudioObjectUnknown {
            _ = AudioDeviceStop(aggregateDeviceID, deviceProcID)
            if let deviceProcID {
                _ = AudioDeviceDestroyIOProcID(aggregateDeviceID, deviceProcID)
            }
            deviceProcID = nil
            _ = AudioHardwareDestroyAggregateDevice(aggregateDeviceID)
            aggregateDeviceID = kAudioObjectUnknown
        }
        if tapID != kAudioObjectUnknown {
            _ = AudioHardwareDestroyProcessTap(tapID)
            tapID = kAudioObjectUnknown
        }
        format = nil
    }

    deinit { stop() }
}
