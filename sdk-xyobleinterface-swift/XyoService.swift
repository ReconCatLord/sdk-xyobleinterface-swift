//
//  XyoService.swift
//  mod-ble-swift
//
//  Created by Carter Harrison on 2/10/19.
//  Copyright © 2019 XYO Network. All rights reserved.
//

import Foundation
import CoreBluetooth
import XyBleSdk

/// This acts as the primary service for all XYO related things (the pipe abstraction).
public enum XyoService : XYServiceCharacteristic {
    /// This is the pipe chararistic where the primary pipe notifactions live.
    case pipe
    
    /// This is the characteristic to change the password of a device
    case password
    
    /// This is the characteristic to change bound witness data of a device
    case boundWitnessData
    
    /// The display name of the service.
    public var serviceDisplayName: String {
        return "Primary"
    }
    
    /// The CBUUID of the service.
    public var serviceUuid: CBUUID {
        return CBUUID(string: "d684352e-df36-484e-bc98-2d5398c5593e")
        
    }
    
    /// The uuid of any characteristic.
    public var characteristicUuid: CBUUID {
        switch self {
        case .pipe: return CBUUID(string: "727a3639-0eb4-4525-b1bc-7fa456490b2d")
        case.password: return CBUUID(string: "727a3639-0eb4-4525-b1bc-7fa456500b2d")
        case.boundWitnessData: return CBUUID(string: "727a3639-0eb4-4525-b1bc-7fa456510b2d")
        }
    }
    
    /// The type of the characteristic.
    public var characteristicType: XYServiceCharacteristicType { return XYServiceCharacteristicType.byte }
    
    /// The display name of the characteristic.
    public var displayName: String {
        switch self {
        case .pipe: return "XYO Pipe"
        case .password: return "Change Password"
        case.boundWitnessData: return "Change Bound Witness Data"
        }
    }
    
    /// All characteristic values under the service.
    public static var values: [XYServiceCharacteristic] = [ XyoService.pipe ]
    
}
