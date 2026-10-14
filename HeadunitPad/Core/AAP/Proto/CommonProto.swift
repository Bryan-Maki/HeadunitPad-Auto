//
//  CommonProto.swift
//  HeadunitPad
//
//  Android Auto common.proto pure Swift models.
//

import Foundation

public enum MessageStatus: Int32, CaseIterable {
    case statusSuccess = 0
    case statusUnsolicitedMessage = 1
    case statusNoCompatibleVersion = -1
    case statusCertificateError = -2
    case statusAuthenticationFailure = -3
    case statusInvalidService = -4
    case statusInvalidChannel = -5
    case statusInvalidPriority = -6
    case statusInternalError = -7
    case statusMediaConfigMismatch = -8
    case statusInvalidSensor = -9
    case statusBluetoothPairingDelayed = -10
    case statusBluetoothUnavailable = -11
    case statusBluetoothInvalidAddress = -12
    case statusBluetoothInvalidPairingMethod = -13
    case statusBluetoothInvalidAuthData = -14
    case statusBluetoothAuthDataMismatch = -15
    case statusBluetoothHfpAnotherConnection = -16
    case statusBluetoothHfpConnectionFailure = -17
    case statusKeycodeNotBound = -18
    case statusRadioInvalidStation = -19
    case statusInvalidInput = -20
    case statusRadioStationPresetsNotSupported = -21
    case statusRadioCommError = -22
    case statusAuthenticationFailureCertNotYetValid = -23
    case statusAuthenticationFailureCertExpired = -24
    case statusPingTimeout = -25
    case statusCommandNotSupported = -250
    case statusFramingError = -251
    case statusUnexpectedMessage = -253
    case statusBusy = -254
    case statusOutOfMemory = -255
}

public struct HeadUnitInfo: ProtoCodable, Equatable {
    public var make: String?
    public var model: String?
    public var year: String?
    public var vehicleId: String?
    public var headUnitMake: String?
    public var headUnitModel: String?
    public var headUnitSoftwareBuild: String?
    public var headUnitSoftwareVersion: String?
    public var vehicleType: Int32?

    public init(
        make: String? = nil,
        model: String? = nil,
        year: String? = nil,
        vehicleId: String? = nil,
        headUnitMake: String? = nil,
        headUnitModel: String? = nil,
        headUnitSoftwareBuild: String? = nil,
        headUnitSoftwareVersion: String? = nil,
        vehicleType: Int32? = nil
    ) {
        self.make = make
        self.model = model
        self.year = year
        self.vehicleId = vehicleId
        self.headUnitMake = headUnitMake
        self.headUnitModel = headUnitModel
        self.headUnitSoftwareBuild = headUnitSoftwareBuild
        self.headUnitSoftwareVersion = headUnitSoftwareVersion
        self.vehicleType = vehicleType
    }

    public func encode(to writer: inout ProtoWriter) {
        if let make = make { writer.writeString(fieldNumber: 1, value: make) }
        if let model = model { writer.writeString(fieldNumber: 2, value: model) }
        if let year = year { writer.writeString(fieldNumber: 3, value: year) }
        if let vehicleId = vehicleId { writer.writeString(fieldNumber: 4, value: vehicleId) }
        if let headUnitMake = headUnitMake { writer.writeString(fieldNumber: 5, value: headUnitMake) }
        if let headUnitModel = headUnitModel { writer.writeString(fieldNumber: 6, value: headUnitModel) }
        if let headUnitSoftwareBuild = headUnitSoftwareBuild { writer.writeString(fieldNumber: 7, value: headUnitSoftwareBuild) }
        if let headUnitSoftwareVersion = headUnitSoftwareVersion { writer.writeString(fieldNumber: 8, value: headUnitSoftwareVersion) }
        if let vehicleType = vehicleType { writer.writeInt32(fieldNumber: 9, value: vehicleType) }
    }

    public init(from reader: inout ProtoReader) throws {
        while let (fieldNumber, wireType) = try reader.readTag() {
            switch fieldNumber {
            case 1: self.make = try reader.readString()
            case 2: self.model = try reader.readString()
            case 3: self.year = try reader.readString()
            case 4: self.vehicleId = try reader.readString()
            case 5: self.headUnitMake = try reader.readString()
            case 6: self.headUnitModel = try reader.readString()
            case 7: self.headUnitSoftwareBuild = try reader.readString()
            case 8: self.headUnitSoftwareVersion = try reader.readString()
            case 9: self.vehicleType = try reader.readInt32()
            default: try reader.skipField(wireType: wireType)
            }
        }
    }
}
