//
//  BLECentralPlugin.m
//  BLE Central Cordova Plugin
//
//  (c) 2104-2016 Don Coleman
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

#import "BLECentralPlugin.h"
#import <Cordova/CDV.h>
@import AVFoundation;

@interface BLECentralPlugin() {
    NSDictionary *bluetoothStates;
}
- (CBPeripheral *)findPeripheralByUUID:(NSString *)uuid;
- (CBPeripheral *)findPeripheralByPartialUUID:(NSString *)uuid;
- (void)stopScanTimer:(NSTimer *)timer;
@end

@implementation BLECentralPlugin

@synthesize manager;
@synthesize peripherals;
@synthesize partialMatch;
@synthesize serviceUUIDString;


#define ADD_DELAYS      // Define this to add delays for the ichoiceWearable

static double lastSend=0.0;
static float WEARABLE_SEND_DELAY = 2.0;  // Seconds
static float  writeDelay=0.0;
static int transaction=0;
/*
   private CallbackContext callbackContext;
    private UUID serviceUUID;
    private UUID characteristicUUID;
    private byte[] data;
    private int type;
 
 Class BLECommand {
 
 }
*/






- (void)pluginInitialize {

    NSLog(@"Cordova BLE Central Plugin");
    NSLog(@"(c)2014-2016 Don Coleman");

    [super pluginInitialize];

    // Important note: The key to the commandQueueDict and bleProcessing is the peripheral UUID
    commandQueueDict = [NSMutableDictionary new];
    bleProcessing = [NSMutableDictionary new];
    peripherals = [NSMutableSet set];
    manager = [[CBCentralManager alloc] initWithDelegate:self queue:nil];
    

    connectCallbacks = [NSMutableDictionary new];
    connectCallbackLatches = [NSMutableDictionary new];
    readCallbacks = [NSMutableDictionary new];
    writeCallbacks = [NSMutableDictionary new];
    notificationCallbacks = [NSMutableDictionary new];
    stopNotificationCallbacks = [NSMutableDictionary new];
    bluetoothStates = [NSDictionary dictionaryWithObjectsAndKeys:
                       @"unknown", @(CBCentralManagerStateUnknown),
                       @"resetting", @(CBCentralManagerStateResetting),
                       @"unsupported", @(CBCentralManagerStateUnsupported),
                       @"unauthorized", @(CBCentralManagerStateUnauthorized),
                       @"off", @(CBCentralManagerStatePoweredOff),
                       @"on", @(CBCentralManagerStatePoweredOn),
                       nil];
    readRSSICallbacks = [NSMutableDictionary new];
    partialMatch = false; 
    serviceUUIDString = [[NSString alloc] init]; // Empty string

}

#pragma mark - Cordova Plugin Methods


-(CDVInvokedUrlCommand*)commandQueuePop:(CDVInvokedUrlCommand*)anObject  {
    NSString *key = [self getKeyFromCommand:anObject];
    return [self commandQueuePopKey:key];
}
-(CDVInvokedUrlCommand*)commandQueuePopKey:(NSString *)key  {
    @synchronized(commandQueueDict)
    {
        [self setCurrentCommandQueueByKey: key];
        
        @synchronized(commandQueue)
        {
            if ([commandQueue count] == 0) {
                return nil;
            }
            
            id queueObject = [commandQueue objectAtIndex:0];
            
            [commandQueue removeObjectAtIndex:0];
            
            return queueObject;
        }
    }
}
-(CDVInvokedUrlCommand*)commandQueuePollKey:(NSString *)key {
    
    @synchronized(commandQueueDict)
    {
        [self setCurrentCommandQueueByKey: key];
        
        @synchronized(commandQueue)
        {
            
            if ([commandQueue count] == 0) {
                return nil;
            }
            
            id queueObject =[commandQueue objectAtIndex:0];
            
            return queueObject;
        }
    }
}

-(CDVInvokedUrlCommand*)commandQueuePoll:(CDVInvokedUrlCommand*)anObject {
    
    NSString *key = [self getKeyFromCommand:anObject];
    return [self commandQueuePollKey:key];
}

// Add to the tail of the queue
-(void)commandQueuePush:(CDVInvokedUrlCommand*)anObject {
    
    @synchronized(commandQueueDict)
    {
      [self setCurrentCommandQueue: anObject];

      @synchronized(commandQueue)
      {

        [commandQueue addObject:anObject];
      }
    }
}



- (void)say: (CDVInvokedUrlCommand *)command {

    NSString *textToSpeak = [command.arguments objectAtIndex:0];
    AVSpeechUtterance *utterance = [AVSpeechUtterance
                                    speechUtteranceWithString:textToSpeak];

    AVSpeechSynthesizer *synth = [[AVSpeechSynthesizer alloc] init];
    [synth speakUtterance:utterance];

}


// 01/06/17 NVF Added to match Android side

- (void)findPairedDevice:(CDVInvokedUrlCommand*)command {
    NSLog(@"findPairedDevice");
    
    NSString *uuid = [command.arguments objectAtIndex:1];
    NSString *c = @"0000XXXX-0000-1000-8000-00805f9b34fb";
    NSString *peripheralId = [command.arguments objectAtIndex:2];
    Boolean found = false;

    discoverPeripheralCallbackId = [command.callbackId copy];
    // NVF Added to normalize the strings before comparing
    if (uuid.length==4)
    {
        uuid = [c stringByReplacingOccurrencesOfString:@"XXXX"
                                         withString:uuid];
    }

    // 01/06/17 NVF Added based on this and apple sources
    // http://stackoverflow.com/questions/19143687/ios-7-corebluetooth-retrieveperipheralswithidentifiers-not-retrieving

    NSUUID *nsUUID = [[NSUUID UUID] initWithUUIDString:peripheralId];

    if(nsUUID)
    {
        // This function uses the peripheralID to look for peripherals already in the paired list - you have to save them in order to be able to look again...
        // However, if you subsequently unpair them, they still won't disappear from this list.  Ask Apple why not. Maybe forget doesn't mean forget at Apple.

        NSArray *peripheralArray = [manager retrievePeripheralsWithIdentifiers:@[nsUUID]];

        // Check for known Peripherals
        if([peripheralArray count] > 0)
        {
            for(CBPeripheral *peripheral in peripheralArray)
            {
                NSLog(@"Found Peripheral - %@", peripheral);
                found = true;
                [peripherals addObject:peripheral];
                if (discoverPeripheralCallbackId) {
                    CDVPluginResult *pluginResult = nil;
                    pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDictionary:[peripheral asDictionary]];
                    NSLog(@"Search for UUID %@ Discovered known peripheral %@",peripheralId, [peripheral asDictionary]);
                    [pluginResult setKeepCallbackAsBool:TRUE];
                    [self.commandDelegate sendPluginResult:pluginResult callbackId:discoverPeripheralCallbackId];
                }


            }
        }
    }
        // There are no known Peripherals so we check for connected Peripherals if any - this is a search by service - use the advertised service
    if (!found)
    {

        CBUUID *cbUUID = [CBUUID UUIDWithString: uuid];

        NSArray *connectedPeripheralArray = [manager retrieveConnectedPeripheralsWithServices:@[cbUUID]];

        // If there are connected Peripherals
        if([connectedPeripheralArray count] > 0)
        {
            for(CBPeripheral *peripheral in connectedPeripheralArray)
            {
                NSLog(@"Found Peripheral - %@", peripheral);
                [peripherals addObject:peripheral];
                found = true;

                if (discoverPeripheralCallbackId) {
                    CDVPluginResult *pluginResult = nil;
                    pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDictionary:[peripheral asDictionary]];
                    NSLog(@"Search for UUID %@ Discovered Connected peripheral %@",uuid, [peripheral asDictionary]);
                    [pluginResult setKeepCallbackAsBool:TRUE];
                    [self.commandDelegate sendPluginResult:pluginResult callbackId:discoverPeripheralCallbackId];
                }


            }
        }
        // Else there are no available Peripherals
        else
        {
            NSString *error = [NSString stringWithFormat:@"Could not find paired peripheral %@.", uuid];
            NSLog(@"%@", error);
            CDVPluginResult *pluginResult = nil;
            pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:error];
            [self.commandDelegate sendPluginResult:pluginResult callbackId:discoverPeripheralCallbackId];

        }
    }

}

- (void)connect:(CDVInvokedUrlCommand *)command {

    NSLog(@"connect");
    NSString *uuid = [command.arguments objectAtIndex:0];

    CBPeripheral *peripheral = [self findPeripheralByUUID:uuid];

    if (peripheral) {
        NSLog(@"Connecting to peripheral with UUID : %@", uuid);

        [connectCallbacks setObject:[command.callbackId copy] forKey:[peripheral uuidAsString]];
        [manager connectPeripheral:peripheral options:nil];

    } else {
        NSString *error = [NSString stringWithFormat:@"Could not find peripheral %@.", uuid];
        NSLog(@"%@", error);
        CDVPluginResult *pluginResult = nil;
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:error];
        [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
    }

}
- (void)connectByService:(CDVInvokedUrlCommand *)command {

    NSLog(@"connect by service");
    NSString *uuid = [command.arguments objectAtIndex:0];

    CBPeripheral *peripheral = [self findPeripheralByPartialUUID:uuid];

    if (peripheral) {
        NSLog(@"Connecting to peripheral with partial UUID : %@", uuid);

        [connectCallbacks setObject:[command.callbackId copy] forKey:[peripheral uuidAsString]];
        [manager connectPeripheral:peripheral options:nil];

    } else {
        NSString *error = [NSString stringWithFormat:@"Could not find peripheral %@.", uuid];
        NSLog(@"%@", error);
        CDVPluginResult *pluginResult = nil;
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:error];
        [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
    }
   
}


// disconnect: function (device_id, success, failure) {
- (void)disconnect:(CDVInvokedUrlCommand*)command {
    NSLog(@"disconnect");

    NSString *uuid = [command.arguments objectAtIndex:0];
    CBPeripheral *peripheral = [self findPeripheralByUUID:uuid];

    [connectCallbacks removeObjectForKey:uuid];

    if (peripheral && peripheral.state != CBPeripheralStateDisconnected) {
        [manager cancelPeripheralConnection:peripheral];
    }

    // always return OK
    CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

// read: function (device_id, service_uuid, characteristic_uuid, success, failure) {
- (void)readEx:(CDVInvokedUrlCommand*)command {
    NSLog(@"read");

    BLECommandContext *context = [self getData:command prop:CBCharacteristicPropertyRead];
    if (context) {

        CBPeripheral *peripheral = [context peripheral];
        CBCharacteristic *characteristic = [context characteristic];

        NSString *key = [self keyForPeripheral: peripheral andCharacteristic:characteristic];
        [readCallbacks setObject:[command.callbackId copy] forKey:key];

        [peripheral readValueForCharacteristic:characteristic];  // callback sends value
    }

}

void dispatch_after_delay(float delayInSeconds, dispatch_queue_t queue, dispatch_block_t block) {
    dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, delayInSeconds * NSEC_PER_SEC);
    dispatch_after(popTime, queue, block);
}

void dispatch_after_delay_on_main_queue(float delayInSeconds, dispatch_block_t block) {
    dispatch_queue_t queue = dispatch_get_main_queue();
    dispatch_after_delay(delayInSeconds, queue, block);
}

void dispatch_after_delay_on_background_queue(float delayInSeconds, dispatch_block_t block) {
    dispatch_queue_t queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0);
    dispatch_after_delay(delayInSeconds, queue, block);
}

- (NSString *)getKeyFromCommand:(CDVInvokedUrlCommand*) command {
    BLECommandContext *context = [self getData:command prop:CBCharacteristicPropertyWrite];
    CBPeripheral *peripheral = [context peripheral];
    NSString *key = [self keyForPeripheral: peripheral ];

    return key;
}

- (void)setCurrentCommandQueue: (CDVInvokedUrlCommand*)command {
    
    NSString *key = [self getKeyFromCommand:command];
    [self setCurrentCommandQueueByKey:key];
    
}

- (void)setCurrentCommandQueueByKey: (NSString *) key{
    
    commandQueue = [commandQueueDict objectForKey: key];
    if (!commandQueue) {
        [commandQueueDict setObject: [NSMutableArray array] forKey: key];
        commandQueue = [commandQueueDict objectForKey: key];
    }
    
}

- (void)queueCommand:(CDVInvokedUrlCommand*)command {
    
    [self commandQueuePush: command];
    [self processCommands: command];
    
}

- (void)read:(CDVInvokedUrlCommand*)command {
    [self queueCommand:command];
}
- (void)write:(CDVInvokedUrlCommand*)command {
    [self queueCommand: command];
}

- (void)writeWithoutResponse:(CDVInvokedUrlCommand*)command {
   [self queueCommand:command];
}

- (void)startNotification:(CDVInvokedUrlCommand*)command {
    [self queueCommand:command];
}
- (void)stopNotification:(CDVInvokedUrlCommand*)command {
    [self queueCommand:command];
}

- (void)processCommandsKey:(NSString *)key  {
    
    [self setCurrentCommandQueueByKey: key];
    
    
 
    if ( [[bleProcessing objectForKey: key] isEqualToString: @"true"]) { return; }
    
    CDVInvokedUrlCommand* command = [self commandQueuePollKey: key];
    
    if (command != nil) {
        
   
        [bleProcessing setObject: @"true" forKey: key];
        
        if ([command.methodName isEqualToString: @"read"]) {
            [self readEx: command];
        } else if ([command.methodName isEqualToString: @"write"]) {
	            [self writeEx: command];
        } else if ([command.methodName isEqualToString: @"writeWithoutResponse"]) {
            [self writeWithoutResponseEx: command];
        } else if ([command.methodName isEqualToString: @"startNotification"]) {
            [self startNotificationEx: command];
        } else if ([command.methodName isEqualToString: @"stopNotification"]) {
            [self stopNotificationEx: command];
        } else {
            // this shouldn't happen
            
             [bleProcessing setObject: @"false" forKey: key];
            NSLog(@"Skipping unknown command in process commands");
        }
    }
    
}

- (void)processCommands:(CDVInvokedUrlCommand*)commandKey  {

    NSString *key = [self getKeyFromCommand:commandKey];
    [self processCommandsKey: key];
 
}

- (void )commandCompleted: (CDVInvokedUrlCommand*)commandKey {
    NSString *key = [self getKeyFromCommand:commandKey];
    [self commandCompletedKey:key];
}

- (void )commandCompletedKey: (NSString *)key {
    NSLog(@"Processing Complete");
    CDVInvokedUrlCommand* command = [self commandQueuePopKey: key ]; // Pop the last command and process the next one.
    [bleProcessing setObject: @"false" forKey: key];
    [self processCommandsKey: key];
}



#ifndef ADD_DELAYS

// write: function (device_id, service_uuid, characteristic_uuid, value, success, failure) {
- (void)write:(CDVInvokedUrlCommand*)command {
    
    BLECommandContext *context = [self getData:command prop:CBCharacteristicPropertyWrite];
    NSData *message = [command.arguments objectAtIndex:3]; // This is binary
    
    if (context) {
        
        if (message != nil) {

            NSLog(@"NonDelayed write %d (2)",transaction);
            CBPeripheral *peripheral = [context peripheral];
            CBCharacteristic *characteristic = [context characteristic];
            
            NSString *key = [self keyForPeripheral: peripheral andCharacteristic:characteristic];
            [writeCallbacks setObject:[command.callbackId copy] forKey:key];
            
            // TODO need to check the max length
            [peripheral writeValue:message forCharacteristic:characteristic type:CBCharacteristicWriteWithResponse];
            
            // response is sent from didWriteValueForCharacteristic
            
        } else {
            CDVPluginResult *pluginResult = nil;
            pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"message was null"];
            [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
        }
    }
    
}

// writeWithoutResponse: function (device_id, service_uuid, characteristic_uuid, value, success, failure) {
- (void)writeWithoutResponse:(CDVInvokedUrlCommand*)command {
    int localTransaction = transaction++;
    
    NSLog(@"writeWithoutResponse");
    NSLog(@"NonDelayed write %d (1) confirmation",localTransaction);
    
    BLECommandContext *context = [self getData:command prop:CBCharacteristicPropertyWriteWithoutResponse];
    NSData *message = [command.arguments objectAtIndex:3]; // This is binary
    
    if (context) {
        CDVPluginResult *pluginResult = nil;
        if (message != nil) {
            CBPeripheral *peripheral = [context peripheral];
            CBCharacteristic *characteristic = [context characteristic];
            
            // TODO need to check the max length
            [peripheral writeValue:message forCharacteristic:characteristic type:CBCharacteristicWriteWithoutResponse];
            
            pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
        } else {
            pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"message was null"];
        }
        [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
    }
}
#else
//5/25/17 - NVF Changed to try to execute these on a delayed background thread instead

- (void)writeEx:(CDVInvokedUrlCommand*)command {
    
    BLECommandContext *context = [self getData:command prop:CBCharacteristicPropertyWrite];
    NSData *message = [command.arguments objectAtIndex:3]; // This is binary
    float localWriteDelay=0;
    int   localTransaction = transaction;

    
    if (context && message && (((unsigned char*)[message bytes])[0] == 0x6f || ([[context peripheral].name rangeOfString:@"L38"].location != NSNotFound) ))
    {
        if (((unsigned char*)[message bytes])[0] == 0x6f)   // Only delay the first part of a multipart send
        {
            double elapsed = [[NSDate date] timeIntervalSince1970] - lastSend;
            

            if (elapsed<WEARABLE_SEND_DELAY)
            {
                writeDelay = (WEARABLE_SEND_DELAY - (float)elapsed);
            }
            else
            {
                writeDelay = 0.0;
            }
        }
        localWriteDelay = writeDelay;
        
        lastSend = ([[NSDate date] timeIntervalSince1970] + (double)writeDelay);
        
        NSLog(@"Delayed write %d %2.2x (1) %f",localTransaction,((unsigned char*)[message bytes])[1],localWriteDelay);
       
        dispatch_queue_t queue = dispatch_get_main_queue(); //dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0);
        //dispatch_queue_t queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0);
        
        dispatch_after_delay(writeDelay, queue,^(void){
            
            if (context) {
                
                if (message != nil) {
                    
                     NSLog(@"Delayed write %d %2.2x (2) %f",localTransaction,((unsigned char*)[message bytes])[1],localWriteDelay);;
                    CBPeripheral *peripheral = [context peripheral];
                    CBCharacteristic *characteristic = [context characteristic];
                    
                    NSString *key = [self keyForPeripheral: peripheral andCharacteristic:characteristic];
                    [writeCallbacks setObject:[command.callbackId copy] forKey:key];
                    
                    // TODO need to check the max length
                    [peripheral writeValue:message forCharacteristic:characteristic type:CBCharacteristicWriteWithResponse];
                    
                    // response is sent from didWriteValueForCharacteristic
                    
                } else {
                    CDVPluginResult *pluginResult = nil;
                    pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"message was null"];
                    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
                }
            }

        });
    }
    else
    {
        

        if (context) {
            
            if (message != nil) {
                
                NSLog(@"NonDelayed write %d (1) %f",localTransaction,localWriteDelay);
                CBPeripheral *peripheral = [context peripheral];
                CBCharacteristic *characteristic = [context characteristic];
                
                NSString *key = [self keyForPeripheral: peripheral andCharacteristic:characteristic];
                [writeCallbacks setObject:[command.callbackId copy] forKey:key];
                
                // TODO need to check the max length
                [peripheral writeValue:message forCharacteristic:characteristic type:CBCharacteristicWriteWithResponse];
                
                // response is sent from didWriteValueForCharacteristic
                
            } else {
                CDVPluginResult *pluginResult = nil;
                pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"message was null"];
                [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
            }
        }
        
    }
    
}
- (void)writeWithoutResponseEx:(CDVInvokedUrlCommand*)command {
    
    BLECommandContext *context = [self getData:command prop:CBCharacteristicPropertyWrite];
    NSData *message = [command.arguments objectAtIndex:3]; // This is binary
    float localWriteDelay=0;
    int localTransaction = transaction++;
    

    if (((unsigned char*)[message bytes])[0] == 0x3)    // Wearable write confirmation
    {
 
        lastSend = ([[NSDate date] timeIntervalSince1970] + (double)writeDelay);  // writeDelay is not calculated again as the writeWithoutResponse comes immediately after the write for the wearable
        
        localWriteDelay = writeDelay;
        NSLog(@"Delayed write %d (1) confirm %f",localTransaction,localWriteDelay);

        dispatch_queue_t queue = dispatch_get_main_queue(); //dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0);
        
        //dispatch_queue_t queue = dispatch_queue_create("com.thinktree.backgroundDelay", NULL);

        //dispatch_queue_t queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0);
        dispatch_after_delay(writeDelay, queue,^(void){
        //dispatch_after_delay(0, queue,^(void){
            
            if (context) {
                
               
                NSLog(@"Delayed write %d %2.2x (2) confirm %f",localTransaction,((unsigned char*)[message bytes])[1],localWriteDelay);
                
                CDVPluginResult *pluginResult = nil;
                if (message != nil) {
                    CBPeripheral *peripheral = [context peripheral];
                    CBCharacteristic *characteristic = [context characteristic];
                    
                    // TODO need to check the max length
                    [peripheral writeValue:message forCharacteristic:characteristic type:CBCharacteristicWriteWithoutResponse];
                    
                    pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
                } else {
                    pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"message was null"];
                }
                [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
            }
            [self commandCompleted: command]; // Done in onWrite
            
        });
        // dispatch_release(queue); // release the thread if its one of ours
    }
    else
    {
        if (context) {
            CDVPluginResult *pluginResult = nil;
            if (message != nil) {
                NSLog(@"NonDelayed write %d (1) confirmation %f",localTransaction,localWriteDelay);

                CBPeripheral *peripheral = [context peripheral];
                CBCharacteristic *characteristic = [context characteristic];
                
                // TODO need to check the max length
                [peripheral writeValue:message forCharacteristic:characteristic type:CBCharacteristicWriteWithoutResponse];
                
                pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
            } else {
                pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"message was null"];
            }
            [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
            [self commandCompleted: command];
        }
        
    }
    
}

#endif


// success callback is called on notification
// notify: function (device_id, service_uuid, characteristic_uuid, success, failure) {
- (void)startNotificationEx:(CDVInvokedUrlCommand*)command {
    NSLog(@"registering for notification");

    BLECommandContext *context = [self getData:command prop:CBCharacteristicPropertyNotify]; // TODO name this better

    if (context) {
        CBPeripheral *peripheral = [context peripheral];
        CBCharacteristic *characteristic = [context characteristic];

        NSString *key = [self keyForPeripheral: peripheral andCharacteristic:characteristic];
        NSString *callback = [command.callbackId copy];
        [notificationCallbacks setObject: callback forKey: key];

        [peripheral setNotifyValue:YES forCharacteristic:characteristic];

    }

}

// stopNotification: function (device_id, service_uuid, characteristic_uuid, success, failure) {
- (void)stopNotificationEx:(CDVInvokedUrlCommand*)command {
    NSLog(@"registering for notification");

    BLECommandContext *context = [self getData:command prop:CBCharacteristicPropertyNotify]; // TODO name this better

    if (context) {
        CBPeripheral *peripheral = [context peripheral];
        CBCharacteristic *characteristic = [context characteristic];

        NSString *key = [self keyForPeripheral: peripheral andCharacteristic:characteristic];
        NSString *callback = [command.callbackId copy];
        [stopNotificationCallbacks setObject: callback forKey: key];

        [peripheral setNotifyValue:NO forCharacteristic:characteristic];
        // callback sent from peripheral:didUpdateNotificationStateForCharacteristic:error:

    }

}

- (void)isEnabled:(CDVInvokedUrlCommand*)command {

    CDVPluginResult *pluginResult = nil;
    int bluetoothState = [manager state];

    BOOL enabled = bluetoothState == CBCentralManagerStatePoweredOn;

    if (enabled) {
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
    } else {
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsInt:bluetoothState];
    }
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

- (void)scan:(CDVInvokedUrlCommand*)command {

    NSLog(@"scan");
    discoverPeripheralCallbackId = [command.callbackId copy];

    NSArray *serviceUUIDStrings = [command.arguments objectAtIndex:0];
    NSNumber *timeoutSeconds = [command.arguments objectAtIndex:1];
    NSMutableArray *serviceUUIDs = [NSMutableArray new];
    partialMatch = false;

    for (int i = 0; i < [serviceUUIDStrings count]; i++) {
        CBUUID *serviceUUID =[CBUUID UUIDWithString:[serviceUUIDStrings objectAtIndex: i]];
        [serviceUUIDs addObject:serviceUUID];
    }

    [manager scanForPeripheralsWithServices:serviceUUIDs options:nil];

    [NSTimer scheduledTimerWithTimeInterval:[timeoutSeconds floatValue]
                                     target:self
                                   selector:@selector(stopScanTimer:)
                                   userInfo:[command.callbackId copy]
                                    repeats:NO];

}

- (void)setWriteDelay:(CDVInvokedUrlCommand*)command {

    NSString *uuid = [command.arguments objectAtIndex:0];
    CBPeripheral *peripheral = [self findPeripheralByUUID:uuid];
    NSNumber *delay = [command.arguments objectAtIndex:1];

    WEARABLE_SEND_DELAY = [delay floatValue]/500.0f;

    CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];


}


- (void)partialScan:(CDVInvokedUrlCommand*)command {

    NSLog(@"stop any existing scan");

    [manager stopScan];

    NSLog(@"scan");
    discoverPeripheralCallbackId = [command.callbackId copy];

    NSArray *serviceUUIDStrings = [command.arguments objectAtIndex:0];
    NSMutableArray *serviceUUIDs = [NSMutableArray new];
    NSNumber *timeoutSeconds = [command.arguments objectAtIndex:2];

    partialMatch = [command.arguments objectAtIndex:1];  // NVF Added this parameter to support partial searches

    // Build the string to look for in the advertising data of the scan record

    if (partialMatch) {
        serviceUUIDString = [[serviceUUIDStrings objectAtIndex: 0] stringByReplacingOccurrencesOfString:@"-" withString:@""];
    }
    else  // Or build the serviceUUID list
    {

        for (int i = 0; i < [serviceUUIDStrings count]; i++) {
            CBUUID *serviceUUID =[CBUUID UUIDWithString:[serviceUUIDStrings objectAtIndex: i]];
            [serviceUUIDs addObject:serviceUUID];
        }
    }

    //[manager scanForPeripheralsWithServices:serviceUUIDs options:nil];
    if (!partialMatch && serviceUUIDStrings.count>0)
        [manager scanForPeripheralsWithServices:serviceUUIDs options:nil];  // Find just what we're looking for
    else
        [manager scanForPeripheralsWithServices:nil options:nil];   // Find everything, possibly filtered by the serviceUUIDString

    [NSTimer scheduledTimerWithTimeInterval:[timeoutSeconds floatValue]
                                     target:self
                                   selector:@selector(stopScanTimer:)
                                   userInfo:[command.callbackId copy]
                                    repeats:NO];

}

- (void)startScan:(CDVInvokedUrlCommand*)command {
    
    
    NSLog(@"stop any existing scan");

    [manager stopScan];

    NSLog(@"startScan");
    discoverPeripheralCallbackId = [command.callbackId copy];
    NSArray *serviceUUIDStrings = [command.arguments objectAtIndex:0];
    NSMutableArray *serviceUUIDs = [NSMutableArray new];

    for (int i = 0; i < [serviceUUIDStrings count]; i++) {
        CBUUID *serviceUUID =[CBUUID UUIDWithString:[serviceUUIDStrings objectAtIndex: i]];
        [serviceUUIDs addObject:serviceUUID];
    }

    [manager scanForPeripheralsWithServices:serviceUUIDs options:nil];

}

- (void)startScanWithOptions:(CDVInvokedUrlCommand*)command {
    
    
    NSLog(@"stop any existing scan");

    [manager stopScan];
    
    NSLog(@"startScanWithOptions");
    discoverPeripheralCallbackId = [command.callbackId copy];
    NSArray *serviceUUIDStrings = [command.arguments objectAtIndex:0];
    NSMutableArray *serviceUUIDs = [NSMutableArray new];
    NSDictionary *options = command.arguments[1];

    for (int i = 0; i < [serviceUUIDStrings count]; i++) {
        CBUUID *serviceUUID =[CBUUID UUIDWithString:[serviceUUIDStrings objectAtIndex: i]];
        [serviceUUIDs addObject:serviceUUID];
    }

    NSMutableDictionary *scanOptions = [NSMutableDictionary new];
    NSNumber *reportDuplicates = [options valueForKey: @"reportDuplicates"];
    if (reportDuplicates) {
        [scanOptions setValue:reportDuplicates
                       forKey:CBCentralManagerScanOptionAllowDuplicatesKey];
    }

    [manager scanForPeripheralsWithServices:serviceUUIDs options:scanOptions];
}

- (void)stopScan:(CDVInvokedUrlCommand*)command {

    NSLog(@"stopScan");

    [manager stopScan];

    if (discoverPeripheralCallbackId) {
        discoverPeripheralCallbackId = nil;
    }

    CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];

}


- (void)isConnected:(CDVInvokedUrlCommand*)command {

    CDVPluginResult *pluginResult = nil;
    CBPeripheral *peripheral = [self findPeripheralByUUID:[command.arguments objectAtIndex:0]];

    if (peripheral && peripheral.state == CBPeripheralStateConnected) {
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
    } else {
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"Not connected"];
    }
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

- (void)startStateNotifications:(CDVInvokedUrlCommand *)command {
    CDVPluginResult *pluginResult = nil;

    if (stateCallbackId == nil) {
        stateCallbackId = [command.callbackId copy];
        int bluetoothState = [manager state];
        NSString *state = [bluetoothStates objectForKey:[NSNumber numberWithInt:bluetoothState]];
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:state];
        [pluginResult setKeepCallbackAsBool:TRUE];
        NSLog(@"Start state notifications on callback %@", stateCallbackId);
    } else {
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"State callback already registered"];
    }

    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

- (void)stopStateNotifications:(CDVInvokedUrlCommand *)command {
    CDVPluginResult *pluginResult = nil;

    if (stateCallbackId != nil) {
        // Call with NO_RESULT so Cordova.js will delete the callback without actually calling it
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_NO_RESULT];
        [self.commandDelegate sendPluginResult:pluginResult callbackId:stateCallbackId];
        stateCallbackId = nil;
    }

    pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

- (void)onReset {
    stateCallbackId = nil;
}

- (void)readRSSI:(CDVInvokedUrlCommand*)command {
    NSLog(@"readRSSI");
    NSString *uuid = [command.arguments objectAtIndex:0];

    CBPeripheral *peripheral = [self findPeripheralByUUID:uuid];

    if (peripheral && peripheral.state == CBPeripheralStateConnected) {
        [readRSSICallbacks setObject:[command.callbackId copy] forKey:[peripheral uuidAsString]];
        [peripheral readRSSI];
    } else {
        NSString *error = [NSString stringWithFormat:@"Need to be connected to peripheral %@ to read RSSI.", uuid];
        NSLog(@"%@", error);
        CDVPluginResult *pluginResult = nil;
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:error];
        [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
    }
}

#pragma mark - timers

-(void)stopScanTimer:(NSTimer *)timer {
    NSLog(@"stopScanTimer");

    [manager stopScan];

    if (discoverPeripheralCallbackId) {
        discoverPeripheralCallbackId = nil;
    }
}

#pragma mark - CBCentralManagerDelegate

/*
- (void)centralManager:(CBCentralManager *)central didDiscoverPeripheral:(CBPeripheral *)peripheral advertisementData:(NSDictionary *)advertisementData RSSI:(NSNumber *)RSSI {

    [peripherals addObject:peripheral];
    [peripheral setAdvertisementData:advertisementData RSSI:RSSI];

    if (discoverPeripheralCallbackId) {
        CDVPluginResult *pluginResult = nil;
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDictionary:[peripheral asDictionary]];
        NSLog(@"Discovered %@", [peripheral asDictionary]);
        [pluginResult setKeepCallbackAsBool:TRUE];
        [self.commandDelegate sendPluginResult:pluginResult callbackId:discoverPeripheralCallbackId];
    }

}
*/
- (void)centralManager:(CBCentralManager *)central didDiscoverPeripheral:(CBPeripheral *)peripheral advertisementData:(NSDictionary *)advertisementData RSSI:(NSNumber *)RSSI {

    [peripheral setAdvertisementData:advertisementData RSSI:RSSI];
    [peripherals addObject:peripheral];


    // NVF Added this for partial matching on serviceUUIDs

    NSMutableArray *serviceUUIDStrings = [advertisementData objectForKey:CBAdvertisementDataServiceUUIDsKey];

    if (partialMatch)
    {

        // 9/1/16 - NVF Changed to look through all the advertised services for a match
        for (int i=0;i<serviceUUIDStrings.count;i++)
        {
            if (serviceUUIDStrings!=nil && [ [[(CBUUID *)[serviceUUIDStrings objectAtIndex:i] UUIDString] stringByReplacingOccurrencesOfString:@"-" withString:@""] rangeOfString:serviceUUIDString options:NSCaseInsensitiveSearch].location != NSNotFound)  // Is the serviceUUID we're looking for contained in the serviceUUIDs advertised?
            {
                if (discoverPeripheralCallbackId) {
                    CDVPluginResult *pluginResult = nil;
                    pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDictionary:[peripheral asDictionary]];
                    NSLog(@"Scan for partial UUID %@ Discovered %@",serviceUUIDString, [peripheral asDictionary]);
                    [pluginResult setKeepCallbackAsBool:TRUE];
                    [self.commandDelegate sendPluginResult:pluginResult callbackId:discoverPeripheralCallbackId];
                }
            }
            else
            {
                // If we're not looking for a match, just build the list of peripherals
                NSLog(@"Scan with no service UUID and no partial match Discovered %@", [peripheral asDictionary]);
            }
        }

    }
    else if (!partialMatch && serviceUUIDStrings!=nil)  // We've got a result from a specific serviceUUID search
    {
        if (discoverPeripheralCallbackId) {
            CDVPluginResult *pluginResult = nil;
            pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDictionary:[peripheral asDictionary]];
            NSLog(@"Scan for service UUID Discovered %@", [peripheral asDictionary]);
            [pluginResult setKeepCallbackAsBool:TRUE];
            [self.commandDelegate sendPluginResult:pluginResult callbackId:discoverPeripheralCallbackId];
        }

    }
    else
    {
         // If we're not looking for a match, just build the list of peripherals
        NSLog(@"Scan with no service UUID and no partial match Discovered %@", [peripheral asDictionary]);
    }

}


- (void)centralManagerDidUpdateState:(CBCentralManager *)central
{
    NSLog(@"Status of CoreBluetooth central manager changed %ld %@", (long)central.state, [self centralManagerStateToString: central.state]);

    if (central.state == CBCentralManagerStateUnsupported)
    {
        NSLog(@"=============================================================");
        NSLog(@"WARNING: This hardware does not support Bluetooth Low Energy.");
        NSLog(@"=============================================================");
    }

    if (stateCallbackId != nil) {
        CDVPluginResult *pluginResult = nil;
        NSString *state = [bluetoothStates objectForKey:@(central.state)];
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:state];
        [pluginResult setKeepCallbackAsBool:TRUE];
        NSLog(@"Report Bluetooth state \"%@\" on callback %@", state, stateCallbackId);
        [self.commandDelegate sendPluginResult:pluginResult callbackId:stateCallbackId];
    }
}

- (void)centralManager:(CBCentralManager *)central didConnectPeripheral:(CBPeripheral *)peripheral {

    NSLog(@"didConnectPeripheral");
    

    peripheral.delegate = self;

    // NOTE: it's inefficient to discover all services
    [peripheral discoverServices:nil];

    // NOTE: not calling connect success until characteristics are discovered
}

- (void)centralManager:(CBCentralManager *)central didDisconnectPeripheral:(CBPeripheral *)peripheral error:(NSError *)error {

    NSLog(@"didDisconnectPeripheral");
    
    // Clear out all pending commands - 6/23/2020 - NVF Added to keep from getting clogged for no reason
    
    NSString *key = [self keyForPeripheral: peripheral ];
   [bleProcessing setObject: @"false" forKey: key];
    NSUInteger count=0;
    while ([self commandQueuePopKey:key] != nil) {
        NSLog(@"Popping stale commands (%ld)",++count);
    }

    NSString *connectCallbackId = [connectCallbacks valueForKey:[peripheral uuidAsString]];
    [connectCallbacks removeObjectForKey:[peripheral uuidAsString]];

    if (connectCallbackId) {
        CDVPluginResult *pluginResult = nil;
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsDictionary:[peripheral asDictionary]];
        [self.commandDelegate sendPluginResult:pluginResult callbackId:connectCallbackId];
    }

}

- (void)centralManager:(CBCentralManager *)central didFailToConnectPeripheral:(CBPeripheral *)peripheral error:(NSError *)error {

    NSLog(@"didFailToConnectPeripheral");

    NSString *connectCallbackId = [connectCallbacks valueForKey:[peripheral uuidAsString]];
    [connectCallbacks removeObjectForKey:[peripheral uuidAsString]];

    CDVPluginResult *pluginResult = nil;
    pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsDictionary:[peripheral asDictionary]];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:connectCallbackId];

}

#pragma mark CBPeripheralDelegate

- (void)peripheral:(CBPeripheral *)peripheral didDiscoverServices:(NSError *)error {

    NSLog(@"didDiscoverServices");

    // save the services to tell when all characteristics have been discovered
    NSMutableSet *servicesForPeriperal = [NSMutableSet new];
    [servicesForPeriperal addObjectsFromArray:peripheral.services];
    [connectCallbackLatches setObject:servicesForPeriperal forKey:[peripheral uuidAsString]];

    for (CBService *service in peripheral.services) {
        [peripheral discoverCharacteristics:nil forService:service]; // discover all is slow
    }
}

- (void)peripheral:(CBPeripheral *)peripheral didDiscoverCharacteristicsForService:(CBService *)service error:(NSError *)error {

    NSLog(@"didDiscoverCharacteristicsForService");

    NSString *peripheralUUIDString = [peripheral uuidAsString];
    NSString *connectCallbackId = [connectCallbacks valueForKey:peripheralUUIDString];
    NSMutableSet *latch = [connectCallbackLatches valueForKey:peripheralUUIDString];

    [latch removeObject:service];

    if ([latch count] == 0) {
        // Call success callback for connect
        if (connectCallbackId) {
            CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDictionary:[peripheral asDictionary]];
            [pluginResult setKeepCallbackAsBool:TRUE];
            [self.commandDelegate sendPluginResult:pluginResult callbackId:connectCallbackId];
        }
        [connectCallbackLatches removeObjectForKey:peripheralUUIDString];
    }

    NSLog(@"Found characteristics for service %@", service);
    for (CBCharacteristic *characteristic in service.characteristics) {
        NSLog(@"Characteristic %@", characteristic);
    }

}

- (void)peripheral:(CBPeripheral *)peripheral didUpdateValueForCharacteristic:(CBCharacteristic *)characteristic error:(NSError *)error {
    NSLog(@"didUpdateValueForCharacteristic");

    NSString *key = [self keyForPeripheral: peripheral andCharacteristic:characteristic];
    NSString *notifyCallbackId = [notificationCallbacks objectForKey:key];

    //This is for async notifies
    if (notifyCallbackId) {
        NSData *data = characteristic.value; // send RAW data to Javascript

        CDVPluginResult *pluginResult = nil;
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsArrayBuffer:data];
        [pluginResult setKeepCallbackAsBool:TRUE]; // keep for notification
        [self.commandDelegate sendPluginResult:pluginResult callbackId:notifyCallbackId];
    }

    NSString *readCallbackId = [readCallbacks objectForKey:key];

    if(readCallbackId) {
        NSData *data = characteristic.value; // send RAW data to Javascript

        CDVPluginResult *pluginResult = nil;
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsArrayBuffer:data];
        [self.commandDelegate sendPluginResult:pluginResult callbackId:readCallbackId];
 

        [readCallbacks removeObjectForKey:key];
        [self commandCompletedKey: [self keyForPeripheral: peripheral] ]; // 12/11/18 - NVF Added this so reads work properly
    }
}

- (void)peripheral:(CBPeripheral *)peripheral didUpdateNotificationStateForCharacteristic:(CBCharacteristic *)characteristic error:(NSError *)error {

    NSString *key = [self keyForPeripheral: peripheral andCharacteristic:characteristic];
    NSString *notificationCallbackId = [notificationCallbacks objectForKey:key];
    NSString *stopNotificationCallbackId = [stopNotificationCallbacks objectForKey:key];

    CDVPluginResult *pluginResult = nil;

    // we always call the stopNotificationCallbackId if we have a callback
    // we only call the notificationCallbackId on errors and if there is no stopNotificationCallbackId

    if (stopNotificationCallbackId) {

        if (error) {
            NSLog(@"%@", error);
            pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:[error localizedDescription]];
        } else {
            pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
        }
        [self.commandDelegate sendPluginResult:pluginResult callbackId:stopNotificationCallbackId];
        [stopNotificationCallbacks removeObjectForKey:key];
        [notificationCallbacks removeObjectForKey:key];

    } else if (notificationCallbackId && error) {

        NSLog(@"%@", error);
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:[error localizedDescription]];
        [self.commandDelegate sendPluginResult:pluginResult callbackId:notificationCallbackId];
       
    }
    [self commandCompletedKey: [self keyForPeripheral: peripheral] ];

}


- (void)peripheral:(CBPeripheral *)peripheral didWriteValueForCharacteristic:(CBCharacteristic *)characteristic error:(NSError *)error {
    // This is the callback for write

    NSString *key = [self keyForPeripheral: peripheral andCharacteristic:characteristic];
    NSString *writeCallbackId = [writeCallbacks objectForKey:key];

    if (writeCallbackId) {
        CDVPluginResult *pluginResult = nil;
        if (error) {
            NSLog(@"%@", error);
            pluginResult = [CDVPluginResult
                resultWithStatus:CDVCommandStatus_ERROR
                messageAsString:[error localizedDescription]
            ];
        } else {
            pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
        }
        [self.commandDelegate sendPluginResult:pluginResult callbackId:writeCallbackId];
        [writeCallbacks removeObjectForKey:key];
     
    }
    [self commandCompletedKey: [self keyForPeripheral: peripheral] ];
}

- (void)peripheralDidUpdateRSSI:(CBPeripheral*)peripheral error:(NSError*)error {
    [self peripheral: peripheral didReadRSSI: [peripheral RSSI] error: error];
}

- (void)peripheral:(CBPeripheral*)peripheral didReadRSSI:(NSNumber*)rssi error:(NSError*)error {
    NSLog(@"didReadRSSI %@", rssi);
    NSString *key = [peripheral uuidAsString];
    NSString *readRSSICallbackId = [readRSSICallbacks objectForKey: key];
    if (readRSSICallbackId) {
        CDVPluginResult* pluginResult = nil;
        if (error) {
            NSLog(@"%@", error);
            pluginResult = [CDVPluginResult
                resultWithStatus:CDVCommandStatus_ERROR
                messageAsString:[error localizedDescription]];
        } else {
            pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK
                messageAsInt: [rssi integerValue]];
        }
        [self.commandDelegate sendPluginResult:pluginResult callbackId: readRSSICallbackId];
        [readRSSICallbacks removeObjectForKey:readRSSICallbackId];
       [self commandCompletedKey: [self keyForPeripheral: peripheral] ];
    }
}

#pragma mark - internal implemetation

- (CBPeripheral*)findPeripheralByUUID:(NSString*)uuid {

    CBPeripheral *peripheral = nil;

    for (CBPeripheral *p in peripherals) {

        NSString* other = p.identifier.UUIDString;

	NSLog(@"Find Peripheral: %@",[p asDictionary]);

        if ([uuid isEqualToString:other]) {
            peripheral = p;
	    NSLog(@"Found Peripheral: %@",[p asDictionary]);
            break;
        }
    }
    return peripheral;
}
- (CBPeripheral*)findPeripheralByPartialUUID:(NSString*)uuid  {

    CBPeripheral *peripheral = nil;

    for (CBPeripheral *p in peripherals) {

        NSString* other = p.identifier.UUIDString;
        Boolean     a = [uuid isEqualToString:other];
        NSInteger   b = [serviceUUIDString  rangeOfString: uuid options:NSCaseInsensitiveSearch].location ;

        NSLog(@"a=%hhu b=%ld",a,(long)b);
        NSLog(@"Find Peripheral by partial uuid: %@",[p asDictionary]);

        // NVF Modified this to work when the service being looked for is only a partial match - try to match the UUID supplied with the first one that was advertised.

        NSDictionary * peripheralDictionary = [p asDictionary];
        NSDictionary * advertisementData =[peripheralDictionary objectForKey:@"advertising"];

        // NVF Added this for partial matching on serviceUUIDs being advertised
        NSMutableArray *serviceUUIDStrings = [advertisementData objectForKey:CBAdvertisementDataServiceUUIDsKey]; // Get the Service UUIDs being advertised and then search for a match

        for(int i = 0; i < serviceUUIDStrings.count; i++)
        {


            NSString *firstUUIDString = [[serviceUUIDStrings objectAtIndex:i] stringByReplacingOccurrencesOfString:@"-" withString:@""];

            if ([firstUUIDString rangeOfString:uuid options:NSCaseInsensitiveSearch].location != NSNotFound) {
                peripheral = p;
                NSLog(@"Found Peripheral: %@",[p asDictionary]);
                return peripheral;
            }
        }
    }
    return peripheral;
}


// RedBearLab
-(CBService *) findServiceFromUUIDOld:(CBUUID *)UUID p:(CBPeripheral *)p
{
    for(int i = 0; i < p.services.count; i++)
    {
        CBService *s = [p.services objectAtIndex:i];
        if ([self compareCBUUID:s.UUID UUID2:UUID])
            return s;
    }

    return nil; //Service not found on this peripheral
}

-(CBService *) findServiceFromUUID:(CBUUID *)UUID p:(CBPeripheral *)p
{
    for(int i = 0; i < p.services.count; i++)
    {
        CBService *s = [p.services objectAtIndex:i];
        NSLog(@"Comparing %@ to %@",s.UUID,UUID);
        NSString *a = s.UUID.UUIDString;
        NSString *b = UUID.UUIDString;
        NSString *c = @"0000XXXX-0000-1000-8000-00805f9b34fb";
 
        // NVF Added to normalize the strings before comparing
         if (s.UUID.UUIDString.length==4)
        {
            a = [c stringByReplacingOccurrencesOfString:@"XXXX"
                                             withString:s.UUID.UUIDString];
        }
        
        if (UUID.UUIDString.length==4)
        {
            b = [c stringByReplacingOccurrencesOfString:@"XXXX"
                                             withString:UUID.UUIDString];
        }
        
        NSLog(@"After normalization: Comparing %@ to %@",a,b);
        
        if( [a caseInsensitiveCompare:b] == NSOrderedSame )
            return s;
        
        else if ([self compareCBUUID:s.UUID UUID2:UUID])
            return s;
    }

    return nil; //Service not found on this peripheral
}


// Find a characteristic in service with a specific property
-(CBCharacteristic *) findCharacteristicFromUUID:(CBUUID *)UUID service:(CBService*)service prop:(CBCharacteristicProperties)prop
{
    NSLog(@"Looking for %@ with properties %lu", UUID, (unsigned long)prop);
    for(int i=0; i < service.characteristics.count; i++)
    {
        CBCharacteristic *c = [service.characteristics objectAtIndex:i];
        if ((c.properties & prop) != 0x0 && [c.UUID.UUIDString isEqualToString: UUID.UUIDString]) {
            return c;
        }
    }
   return nil; //Characteristic with prop not found on this service
}

// Find a characteristic in service by UUID
-(CBCharacteristic *) findCharacteristicFromUUID:(CBUUID *)UUID service:(CBService*)service
{
    NSLog(@"Looking for %@", UUID);
    for(int i=0; i < service.characteristics.count; i++)
    {
        CBCharacteristic *c = [service.characteristics objectAtIndex:i];
        if ([c.UUID.UUIDString isEqualToString: UUID.UUIDString]) {
            return c;
        }
    }
   return nil; //Characteristic not found on this service
}

// RedBearLab
-(int) compareCBUUID:(CBUUID *) UUID1 UUID2:(CBUUID *)UUID2
{
    char b1[16];
    char b2[16];
    [UUID1.data getBytes:b1];
    [UUID2.data getBytes:b2];

    if (memcmp(b1, b2, UUID1.data.length) == 0)
        return 1;
    else
        return 0;
}

// expecting deviceUUID, serviceUUID, characteristicUUID in command.arguments
-(BLECommandContext*) getData:(CDVInvokedUrlCommand*)command prop:(CBCharacteristicProperties)prop {
    NSLog(@"getData");

    CDVPluginResult *pluginResult = nil;

    NSString *deviceUUIDString = [command.arguments objectAtIndex:0];
    NSString *serviceUUIDString = [command.arguments objectAtIndex:1];
    NSString *characteristicUUIDString = [command.arguments objectAtIndex:2];

    CBUUID *serviceUUID = [CBUUID UUIDWithString:serviceUUIDString];
    CBUUID *characteristicUUID = [CBUUID UUIDWithString:characteristicUUIDString];

    CBPeripheral *peripheral = [self findPeripheralByUUID:deviceUUIDString];

    if (!peripheral) {

        NSLog(@"Could not find peripherial with UUID %@", deviceUUIDString);

        NSString *errorMessage = [NSString stringWithFormat:@"Could not find peripherial with UUID %@", deviceUUIDString];
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:errorMessage];
        [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];

        return nil;
    }

    CBService *service = [self findServiceFromUUID:serviceUUID p:peripheral];

    if (!service)
    {
        NSLog(@"Could not find service with UUID %@ on peripheral with UUID %@",
              serviceUUIDString,
              peripheral.identifier.UUIDString);


        NSString *errorMessage = [NSString stringWithFormat:@"Could not find service with UUID %@ on peripheral with UUID %@",
                                  serviceUUIDString,
                                  peripheral.identifier.UUIDString];
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:errorMessage];
        [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];

        return nil;
    }

    CBCharacteristic *characteristic = [self findCharacteristicFromUUID:characteristicUUID service:service prop:prop];

    // Special handling for INDICATE. If charateristic with notify is not found, check for indicate.
    if (prop == CBCharacteristicPropertyNotify && !characteristic) {
        characteristic = [self findCharacteristicFromUUID:characteristicUUID service:service prop:CBCharacteristicPropertyIndicate];
    }

    // As a last resort, try and find ANY characteristic with this UUID, even if it doesn't have the correct properties
    if (!characteristic) {
        characteristic = [self findCharacteristicFromUUID:characteristicUUID service:service];
    }

    if (!characteristic)
    {
        NSLog(@"Could not find characteristic with UUID %@ on service with UUID %@ on peripheral with UUID %@",
              characteristicUUIDString,
              serviceUUIDString,
              peripheral.identifier.UUIDString);

        NSString *errorMessage = [NSString stringWithFormat:
                                  @"Could not find characteristic with UUID %@ on service with UUID %@ on peripheral with UUID %@",
                                  characteristicUUIDString,
                                  serviceUUIDString,
                                  peripheral.identifier.UUIDString];
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:errorMessage];
        [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];

        return nil;
    }

    BLECommandContext *context = [[BLECommandContext alloc] init];
    [context setPeripheral:peripheral];
    [context setService:service];
    [context setCharacteristic:characteristic];
    return context;

}

-(NSString *) keyForPeripheral: (CBPeripheral *)peripheral andCharacteristic:(CBCharacteristic *)characteristic {
    return [NSString stringWithFormat:@"%@|%@", [peripheral uuidAsString], [characteristic UUID]];
}

-(NSString *) keyForPeripheral: (CBPeripheral *)peripheral {
    return [NSString stringWithFormat:@"%@", [peripheral uuidAsString]];
}

// Return just the peripheralKey from a key with peripheral UUID and characteristic
-(NSString *) keyFromComplexKey: (NSString *)inKey {
    NSArray *parts = [inKey componentsSeparatedByString: @"|"];
    
    return parts[0];

}

#pragma mark - util

- (NSString*) centralManagerStateToString: (int)state
{
    switch(state)
    {
        case CBCentralManagerStateUnknown:
            return @"State unknown (CBCentralManagerStateUnknown)";
        case CBCentralManagerStateResetting:
            return @"State resetting (CBCentralManagerStateUnknown)";
        case CBCentralManagerStateUnsupported:
            return @"State BLE unsupported (CBCentralManagerStateResetting)";
        case CBCentralManagerStateUnauthorized:
            return @"State unauthorized (CBCentralManagerStateUnauthorized)";
        case CBCentralManagerStatePoweredOff:
            return @"State BLE powered off (CBCentralManagerStatePoweredOff)";
        case CBCentralManagerStatePoweredOn:
            return @"State powered up and ready (CBCentralManagerStatePoweredOn)";
        default:
            return @"State unknown";
    }

    return @"Unknown state";
}

@end

