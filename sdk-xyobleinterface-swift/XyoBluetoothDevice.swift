//
//  XyoBluetoothDevice.swift
//  mod-ble-swift
//
//  Created by Carter Harrison on 2/10/19.
//  Copyright © 2019 XYO Network. All rights reserved.
//

import Foundation
import Promises
import CoreBluetooth
import XyBleSdk
import sdk_core_swift
import sdk_objectmodel_swift

/// A class that gets created with XYO pipe enabled devices arround the world. Each device complies to the
/// XyoNetworkPipe interface, meaning that data can be send and recived beetwen them. Please note that
/// one chould not use an instance of this class as a pipe, but tryCreatePipe() to get an instance of
/// a pipe.
public class XyoBluetoothDevice: XYBluetoothDeviceBase, XYBluetoothDeviceNotifyDelegate, XyoNetworkPipe {
    
    /// The defining family for a XyoBluetoothDevice, this helps the process of creatig a device, and making
    /// sure that it complies to the XYO pipe spec.
    public static let family = XYDeviceFamily.init(uuid: UUID(uuidString: XyoBluetoothDevice.uuid)!,
                                                   prefix: XyoBluetoothDevice.prefix,
                                                   familyName: XyoBluetoothDevice.familyName,
                                                   id: XyoBluetoothDevice.id)
    
    /// The ID of an XyoBluetoothDevice
    public static let id = "XYO"
    
    /// The primary service UUID of a XyoBluetoothDevice
    public static let uuid : String = "dddddddd-df36-484e-bc98-2d5398c5593e"
    
    /// The faimly name of a XyoBluetoothDevice
    public static let familyName : String = "XYO"
    
    /// The prefix of a XyoBluetoothDevice
    public static let prefix : String = "xy:ibeacon"
    
    /// The input stream of the device at the other end of the pipe.
    private var inputStream = XyoInputStream()
    
    /// The promise to wait when waiting for a new packed to be completed in the inputStream.
    private var recivePromise : Promise<[UInt8]?>? = nil
    
    /// Creates a new instance of XyoBluetoothDevice using an id and rssi.
    /// - Parameter id: The peripheral id of the device to create.
    /// - Parameter iBeacon: The IBeacon of the device.
    /// - Parameter rssi: The rssi of the device when scaned, will defualt to XYDeviceProximity.none.rawValue.
    public init(_ id: String, iBeacon: XYIBeaconDefinition? = nil, rssi: Int = XYDeviceProximity.none.rawValue) {
        super.init(id, rssi: rssi, family: XyoBluetoothDevice.family, iBeacon: iBeacon)
    }
    
    /// A convenience init that does not need an id.
    /// - Parameter iBeacon: The IBeacon of the device.
    /// - Parameter rssi: The rssi of the device when scaned, will defualt to XYDeviceProximity.none.rawValue.
    public convenience init(iBeacon: XYIBeaconDefinition, rssi: Int = XYDeviceProximity.none.rawValue) {
        self.init(iBeacon.xyId(from: XyoBluetoothDevice.family), iBeacon: iBeacon, rssi: rssi)
    }
    
    /// A function to try and create a pipe. This should be the function used to create a pipe, not using this instance
    /// as a pipe, even though it may work, it will not work consistsnatly.
    /// - Warning: This function is blocking while waiting to subscribe to the device, and this function should be called
    /// withen a connection block
    public func tryCreatePipe () -> XyoNetworkPipe? {
        /// make sure to clear the input stream for a new pipe
        self.inputStream = XyoInputStream()
        
        /// we use a unique name as the delegate key to prevent overriding keys
        let result = self.subscribe(to: XYOSerive.pipe, delegate: (key: "notify [DBG: \(#function)]: \(Unmanaged.passUnretained(self).toOpaque())", delegate: self))
        if (result.error == nil) {
            return self
        }
        
        return nil
    }
    
    /// This function tries to attatch a XYPeripheral as the peripheral for this device model, this will work if the
    /// device has a XYO UUID in the advertisement
    /// - Parameter peripheral: The XYO pipe enabled peripheral to try and attatch
    /// - Returns: If the attatchment of the peripheral was sucessfull.
    override public func attachPeripheral(_ peripheral: XYPeripheral) -> Bool {
        guard
            self.peripheral == nil,
            let services = peripheral.advertisementData?[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID]
            else { return false }
        
        guard
            services.contains(CBUUID(string: XyoBluetoothDevice.uuid))
            else { return false }
        
        // Set the peripheral and delegate to self
        self.peripheral = peripheral.peripheral
        self.peripheral?.delegate = self
        
        // Save off the services this device was found with for BG monitoring
        self.supportedServices = services
        
        return true
        
    }
    
    /// Gets the first data that was sent to this device, since the client is allways the one initing, this will
    /// allways return nil
    /// - Returns: Returns the first data srecived through the pipe if not initing.
    public func getInitiationData() -> XyoAdvertisePacket? {
        // this is because we are allways a client
        return nil
    }
    
    /// Sends data to the peripheral and waits for a response if the waitForResponse flag is set.
    /// - Warning: This function is blocking while it waits for bluetooth calls.
    /// - Parameter data: The data to send to the other device at the end of the pipe
    /// - Parameter waitForResponse: Weather or not to wait for a response after sending
    /// - Returns: Will return the response from the other party, will return nil if there was an error or if
    /// waitForResponse was set to false.
    public func send(data: [UInt8], waitForResponse: Bool) -> [UInt8]? {
        if (!chunkSend(bytes: data)) {
            return nil
        }
        
        if (waitForResponse) {
            return waitForRead()
        }
        
        return nil
    }
    
    /// Sends data to the peripheral at the other end of the pipe, via the XYO pipe protocol.
    /// - Parameter bytes: The bytes to send to the other end of the pipe
    /// - Warning: This function is blocking while it waits for bluetooth calls.
    /// - Returns: This function returns the success of the chunk send
    private func chunkSend (bytes : [UInt8]) -> Bool {
        let sizeEncodedBytes = XyoBuffer()
            .put(bits: UInt32(bytes.count + 4))
            .put(bytes: bytes)
            .toByteArray()
        
        let mtu = peripheral?.maximumWriteValueLength(for: CBCharacteristicWriteType.withResponse) ?? 22
        let chunks = XyoOutputStream.chunk(bytes: sizeEncodedBytes, maxChunkSize: mtu - 3)
        
        for chunk in chunks {
            let status = self.set(XYOSerive.pipe, value: XYBluetoothResult(data: Data(chunk)), withResponse: true)
            
            // break the loop if there was an error
            if (status.error != nil) {
                return false
            }
        }
        
        return true
    }
    
    /// Waits for the next read request to come in, if one has allready come in before calling this function,
    /// it will return it.
    /// - Warning: This function is blocking while it waits for bluetooth calls.
    /// - Returns: This function returns what the divice on the other end of the pipe just sent.
    private func waitForRead () -> [UInt8]? {
        var latestPacket : [UInt8]? = inputStream.getOldestPacket()
        if (latestPacket == nil) {
            recivePromise = Promise<[UInt8]?>.pending()
            do {
                latestPacket = try await(recivePromise.unsafelyUnwrapped)
            } catch {
                // todo, look into seeing if there is a proper way to handle this error
                return nil
            }
        }
        
        return latestPacket
    }
    
    /// This function terminates the bluetooth connection and should be called beetwen creating pipes.
    public func close() {
        disconnect()
    }
    
    /// This function is called whenever a charisteristic is updated, and is how the XYO pipe recives data.
    /// This function will also add to the input stream, and resume a read promise if there is one existing.
    /// - Parameter serviceCharacteristic: The characteristic that is being updated, this should be the XYO serivce
    /// - Parameter value: The value that characteristic has been changed to (or notifyed of)
    public func update(for serviceCharacteristic: XYServiceCharacteristic, value: XYBluetoothResult) {
        if (!value.hasError && value.asByteArray != nil) {
            
            inputStream.addChunk(packet: value.asByteArray!)
            
            guard let donePacket = inputStream.getOldestPacket() else {
                return
            }
            
            recivePromise?.fulfill(donePacket)
        }
    }
}