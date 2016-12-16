// (c) 2014-2016 Don Coleman
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

package com.megster.cordova.ble.central;

import android.Manifest;
import android.app.Activity;
import android.bluetooth.BluetoothAdapter;
import android.bluetooth.BluetoothDevice;
import android.bluetooth.BluetoothGattCharacteristic;
import android.bluetooth.BluetoothManager;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.content.IntentFilter;
import android.os.Handler;

import android.os.Looper;
import android.provider.Settings;
import android.speech.tts.TextToSpeech;

//import org.apache.commons.lang3.math.NumberUtils;
import org.apache.cordova.CallbackContext;
import org.apache.cordova.CordovaArgs;
import org.apache.cordova.CordovaPlugin;
import org.apache.cordova.LOG;
import org.apache.cordova.PermissionHelper;
import org.apache.cordova.PluginResult;
import org.json.JSONArray;
import org.json.JSONObject;
import org.json.JSONException;

import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.util.*;

public class BLECentralPlugin extends CordovaPlugin implements BluetoothAdapter.LeScanCallback {

    // actions
    private static final String SCAN = "scan";
    private static final String SAY = "say";
    private static final String PARTIAL_SCAN = "partialScan";
    private static final String START_SCAN = "startScan";
    private static final String STOP_SCAN = "stopScan";
    private static final String START_SCAN_WITH_OPTIONS = "startScanWithOptions";
    private static final String FIND_PAIRED_DEVICE = "findPairedDevice";

    private static final String LIST = "list";

    private static final String CONNECT = "connect";
    private static final String DISCONNECT = "disconnect";

    private static final String READ = "read";
    private static final String WRITE = "write";
    private static final String WRITE_WITHOUT_RESPONSE = "writeWithoutResponse";

    private static final String READ_RSSI = "readRSSI";

    private static final String START_NOTIFICATION = "startNotification"; // register for characteristic notification
    private static final String STOP_NOTIFICATION = "stopNotification"; // remove characteristic notification

    private static final String IS_ENABLED = "isEnabled";
    private static final String IS_CONNECTED  = "isConnected";

    private static final String SETTINGS = "showBluetoothSettings";
    private static final String ENABLE = "enable";

    private static final String START_STATE_NOTIFICATIONS = "startStateNotifications";
    private static final String STOP_STATE_NOTIFICATIONS = "stopStateNotifications";

    // callbacks
    CallbackContext discoverCallback;
    private CallbackContext enableBluetoothCallback;

    private static final String TAG = "BLEPlugin";
    private static final int REQUEST_ENABLE_BLUETOOTH = 1;

    BluetoothAdapter bluetoothAdapter;

    // key is the MAC Address
    Map<String, Peripheral> peripherals = new LinkedHashMap<String, Peripheral>();



    // scan options
    boolean reportDuplicates = false;

    // Android 23 requires new permissions for BluetoothLeScanner.startScan()
    private static final String ACCESS_COARSE_LOCATION = Manifest.permission.ACCESS_COARSE_LOCATION;
    private static final int REQUEST_ACCESS_COARSE_LOCATION = 2;
    private static final int PERMISSION_DENIED_ERROR = 20;
    private CallbackContext permissionCallback;
    private UUID[] serviceUUIDs; // An array of serviceUUIDs to scan for
    // NVF Added this to merge bluetooth changes 7/14/16
    String[] serviceUUIDStrings; // When looking for a partial match this is the string to use
    boolean partialMatch = false; // Used when looking for a partial match
    private int scanSeconds;
    String [] validActions= {SCAN,SAY,PARTIAL_SCAN,START_SCAN,STOP_SCAN,START_SCAN_WITH_OPTIONS,FIND_PAIRED_DEVICE,LIST,CONNECT,DISCONNECT,READ,WRITE,WRITE_WITHOUT_RESPONSE,START_NOTIFICATION,STOP_NOTIFICATION,IS_ENABLED,IS_CONNECTED,ENABLE,SETTINGS};

    TextToSpeech speech;

    // Bluetooth state notification
    CallbackContext stateCallback;
    BroadcastReceiver stateReceiver;
    Map<Integer, String> bluetoothStates = new Hashtable<Integer, String>() {{
        put(BluetoothAdapter.STATE_OFF, "off");
        put(BluetoothAdapter.STATE_TURNING_OFF, "turningOff");
        put(BluetoothAdapter.STATE_ON, "on");
        put(BluetoothAdapter.STATE_TURNING_ON, "turningOn");
    }};

    public void setStateCallback(CallbackContext context)
    {
        stateCallback = context;
    }
    public CallbackContext getStateCallback()
    {
        return stateCallback;
    }

    public void setReportDuplicates(boolean report)
    {
        reportDuplicates = report;
    }
    public boolean getReportDuplicates()
    {
        return reportDuplicates;
    }
    public void onDestroy() {
        removeStateListener();
    }

    public void onReset() {
        removeStateListener();
    }

    @Override
    protected void pluginInitialize() {
        speech =new TextToSpeech(webView.getContext(), new TextToSpeech.OnInitListener() {
            @Override
            public void onInit(int status) {
                if(status != TextToSpeech.ERROR) {
                    speech.setLanguage(Locale.US);
                }
            }
        });

    }

    @Override
    public boolean execute(final String action,final CordovaArgs args, final CallbackContext callbackContext) throws JSONException {

        LOG.d(TAG, "action = " + action);

        if (bluetoothAdapter == null) {
            Activity activity = cordova.getActivity();
            BluetoothManager bluetoothManager = (BluetoothManager) activity.getSystemService(Context.BLUETOOTH_SERVICE);
            bluetoothAdapter = bluetoothManager.getAdapter();
        }


        // Check if this is a valid action or not
        int i;
        for (i = 0; i < validActions.length && !action.equals(validActions[i]); i++) ;
        if (i == validActions.length)
            return false;


     //   cordova.getThreadPool().execute(new Runnable() {
            cordova.getActivity().runOnUiThread(new Runnable() {

                @Override
            public void run() {

                try {

                    if (action.equals(SCAN)) {

                        serviceUUIDs = parseServiceUUIDList(args.getJSONArray(0));
                        int scanSeconds = args.getInt(1);
                        partialMatch = false;
                        resetScanOptions();
                        findLowEnergyDevices(callbackContext, serviceUUIDs, scanSeconds);
                    } else if (action.equals(SAY)) {

                        String textToSay = args.getString(0);

                        if (speech!=null)
                            speech.speak(textToSay, TextToSpeech.QUEUE_FLUSH, null, "BLE_MEASUREMENTS");


                    } else if (action.equals(PARTIAL_SCAN)) {

                        partialMatch = args.getBoolean(1);
                        // For partial matches we will parse the first argument in the list passed to use later.
                        if (partialMatch) {
//                            serviceUUIDString = args.getJSONArray(0).getString(0).replace("-", "");  // This will be used to match when the scan results come back
                              serviceUUIDStrings = parseServiceUUIDStringList(args.getJSONArray(0));
                            serviceUUIDs = null;
                        } else {
                            serviceUUIDs = parseServiceUUIDList(args.getJSONArray(0));
                        }
                        int scanSeconds = args.getInt(2);
                        findLowEnergyDevices(callbackContext, serviceUUIDs, scanSeconds);


                    } else if (action.equals(START_SCAN)) {

                        UUID[] serviceUUIDs = parseServiceUUIDList(args.getJSONArray(0));
                        resetScanOptions();
                        findLowEnergyDevices(callbackContext, serviceUUIDs, -1);

                    } else if (action.equals(STOP_SCAN)) {

                        bluetoothAdapter.stopLeScan(BLECentralPlugin.this);
                        callbackContext.success();

                    } else if (action.equals(FIND_PAIRED_DEVICE)) {

                        BluetoothAdapter mBluetoothAdapter = BluetoothAdapter.getDefaultAdapter();
                        Set<BluetoothDevice> pairedDevices = mBluetoothAdapter.getBondedDevices();

                        List<String> s = new ArrayList<String>();
                        for (BluetoothDevice bt : pairedDevices) {
                            //s.add(bt.getName());
                            if (bt.getName().equalsIgnoreCase(args.getString(0)))
                            {
                                // We found a match
                            }
                        }

                        callbackContext.success();

                    } else if (action.equals(LIST)) {

                        listKnownDevices(callbackContext);

                    } else if (action.equals(CONNECT)) {

                        // 08/29/16 NVF Recoded as some devices require this to be in the UI Thread or they return a 133 and fail to connect.  (What's the reason?)
                        final String macAddress = args.getString(0);
                        cordova.getActivity().runOnUiThread(new Runnable() {
                            @Override
                            public void run() {
                                connect(callbackContext, macAddress);
                            }
                        });


                    } else if (action.equals(DISCONNECT)) {

                        String macAddress = args.getString(0);
                        disconnect(callbackContext, macAddress);

                    } else if (action.equals(READ)) {

                        String macAddress = args.getString(0);
                        UUID serviceUUID = uuidFromString(args.getString(1));
                        UUID characteristicUUID = uuidFromString(args.getString(2));
                        read(callbackContext, macAddress, serviceUUID, characteristicUUID);

                    } else if (action.equals(READ_RSSI)) {

                        String macAddress = args.getString(0);
                        readRSSI(callbackContext, macAddress);

                    } else if (action.equals(WRITE)) {

                        String macAddress = args.getString(0);
                        UUID serviceUUID = uuidFromString(args.getString(1));
                        UUID characteristicUUID = uuidFromString(args.getString(2));
                        byte[] data = args.getArrayBuffer(3);
                        int type = BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT;
                        write(callbackContext, macAddress, serviceUUID, characteristicUUID, data, type);

                    } else if (action.equals(WRITE_WITHOUT_RESPONSE)) {

                        String macAddress = args.getString(0);
                        UUID serviceUUID = uuidFromString(args.getString(1));
                        UUID characteristicUUID = uuidFromString(args.getString(2));
                        byte[] data = args.getArrayBuffer(3);
                        int type = BluetoothGattCharacteristic.WRITE_TYPE_NO_RESPONSE;
                        write(callbackContext, macAddress, serviceUUID, characteristicUUID, data, type);

                    } else if (action.equals(START_NOTIFICATION)) {

                        String macAddress = args.getString(0);


                        UUID serviceUUID = uuidFromString(args.getString(1));
                        UUID characteristicUUID = uuidFromString(args.getString(2));
                        registerNotifyCallback(callbackContext, macAddress, serviceUUID, characteristicUUID);

                    } else if (action.equals(STOP_NOTIFICATION)) {

                        String macAddress = args.getString(0);
                        UUID serviceUUID = uuidFromString(args.getString(1));
                        UUID characteristicUUID = uuidFromString(args.getString(2));
                        removeNotifyCallback(callbackContext, macAddress, serviceUUID, characteristicUUID);

                    } else if (action.equals(IS_ENABLED)) {

                        if (bluetoothAdapter.isEnabled()) {
                            callbackContext.success();
                        } else {
                            callbackContext.error("Bluetooth is disabled.");
                        }

                    } else if (action.equals(IS_CONNECTED)) {

                        String macAddress = args.getString(0);

                        if (peripherals.containsKey(macAddress) && peripherals.get(macAddress).isConnected()) {
                            callbackContext.success();
                        } else {
                            callbackContext.error("Not connected.");
                        }

                    } else if (action.equals(SETTINGS)) {

                        Intent intent = new Intent(Settings.ACTION_BLUETOOTH_SETTINGS);
                        cordova.getActivity().startActivity(intent);
                        callbackContext.success();

                    } else if (action.equals(ENABLE)) {

                        enableBluetoothCallback = callbackContext;
                        Intent intent = new Intent(BluetoothAdapter.ACTION_REQUEST_ENABLE);
                        cordova.startActivityForResult(BLECentralPlugin.this, intent, REQUEST_ENABLE_BLUETOOTH);

                    } else if (action.equals(START_STATE_NOTIFICATIONS)) {

                        if (getStateCallback() != null) {
                            callbackContext.error("State callback already registered.");
                        } else {
                            setStateCallback(callbackContext);
                            addStateListener();
                            sendBluetoothStateChange(bluetoothAdapter.getState());
                        }

                    } else if (action.equals(STOP_STATE_NOTIFICATIONS)) {

                        if (getStateCallback() != null) {
                            // Clear callback in JavaScript without actually calling it
                            PluginResult result = new PluginResult(PluginResult.Status.NO_RESULT);
                            result.setKeepCallback(false);
                            getStateCallback().sendPluginResult(result);
                            setStateCallback(null);
                        }
                        removeStateListener();
                        callbackContext.success();

                    } else if (action.equals(START_SCAN_WITH_OPTIONS)) {
                        UUID[] serviceUUIDs = parseServiceUUIDList(args.getJSONArray(0));
                        JSONObject options = args.getJSONObject(1);

                        resetScanOptions();
                        setReportDuplicates(options.optBoolean("reportDuplicates", false));
                        findLowEnergyDevices(callbackContext, serviceUUIDs, -1);

                    }
                } catch (JSONException e) {
                    e.printStackTrace();
                }

            }
        });

                    return true;
    }

    private UUID[] parseServiceUUIDList(JSONArray jsonArray) throws JSONException {
        List<UUID> serviceUUIDs = new ArrayList<UUID>();

        for(int i = 0; i < jsonArray.length(); i++){
            String uuidString = jsonArray.getString(i);
            serviceUUIDs.add(uuidFromString(uuidString));
        }

        return serviceUUIDs.toArray(new UUID[jsonArray.length()]);
    }
    private String [] parseServiceUUIDStringList(JSONArray jsonArray) throws JSONException {
        List<String> serviceUUIDStrings = new ArrayList<String>();

        for(int i = 0; i < jsonArray.length(); i++){
            String uuidString = jsonArray.getString(i).replace("-", "");  // This will be used to match when the scan results come back;

            serviceUUIDStrings.add(uuidString);
        }

        return serviceUUIDStrings.toArray(new String[jsonArray.length()]);
    }


    private void onBluetoothStateChange(Intent intent) {
        final String action = intent.getAction();

        if (action.equals(BluetoothAdapter.ACTION_STATE_CHANGED)) {
            final int state = intent.getIntExtra(BluetoothAdapter.EXTRA_STATE, BluetoothAdapter.ERROR);
            sendBluetoothStateChange(state);
        }
    }

    private void sendBluetoothStateChange(int state) {
        if (this.stateCallback != null) {
            PluginResult result = new PluginResult(PluginResult.Status.OK, this.bluetoothStates.get(state));
            result.setKeepCallback(true);
            this.stateCallback.sendPluginResult(result);
        }
    }

    private void addStateListener() {
        if (this.stateReceiver == null) {
            this.stateReceiver = new BroadcastReceiver() {
                @Override
                public void onReceive(Context context, Intent intent) {
                    onBluetoothStateChange(intent);
                }
            };
        }

        try {
            IntentFilter intentFilter = new IntentFilter(BluetoothAdapter.ACTION_STATE_CHANGED);
            webView.getContext().registerReceiver(this.stateReceiver, intentFilter);
        } catch (Exception e) {
            LOG.e(TAG, "Error registering state receiver: " + e.getMessage(), e);
        }
    }

    private void removeStateListener() {
        if (this.stateReceiver != null) {
            try {
                webView.getContext().unregisterReceiver(this.stateReceiver);
            } catch (Exception e) {
                LOG.e(TAG, "Error unregistering state receiver: " + e.getMessage(), e);
            }
        }
        this.stateCallback = null;
        this.stateReceiver = null;
    }

    private void connect(CallbackContext callbackContext, String macAddress) {

        Peripheral peripheral = peripherals.get(macAddress);
        if (peripheral != null) {
            peripheral.connect(callbackContext, cordova.getActivity());
        } else {
            callbackContext.error("Peripheral " + macAddress + " not found.");
        }

    }

    private void disconnect(CallbackContext callbackContext, String macAddress) {

        Peripheral peripheral = peripherals.get(macAddress);
        if (peripheral != null) {
            peripheral.disconnect();
        }
        callbackContext.success();

    }

    private void read(CallbackContext callbackContext, String macAddress, UUID serviceUUID, UUID characteristicUUID) {

        Peripheral peripheral = peripherals.get(macAddress);

        if (peripheral == null) {
            callbackContext.error("Peripheral " + macAddress + " not found.");
            return;
        }

        if (!peripheral.isConnected()) {
            callbackContext.error("Peripheral " + macAddress + " is not connected.");
            return;
        }

        //peripheral.readCharacteristic(callbackContext, serviceUUID, characteristicUUID);
        peripheral.queueRead(callbackContext, serviceUUID, characteristicUUID);

    }

    private void readRSSI(CallbackContext callbackContext, String macAddress) {

        Peripheral peripheral = peripherals.get(macAddress);

        if (peripheral == null) {
            callbackContext.error("Peripheral " + macAddress + " not found.");
            return;
        }

        if (!peripheral.isConnected()) {
            callbackContext.error("Peripheral " + macAddress + " is not connected.");
            return;
        }
        peripheral.queueReadRSSI(callbackContext);
    }

    private void write(CallbackContext callbackContext, String macAddress, UUID serviceUUID, UUID characteristicUUID,
                       byte[] data, int writeType) {

        Peripheral peripheral = peripherals.get(macAddress);

        if (peripheral == null) {
            callbackContext.error("Peripheral " + macAddress + " not found.");
            return;
        }

        if (!peripheral.isConnected()) {
            callbackContext.error("Peripheral " + macAddress + " is not connected.");
            return;
        }

        //peripheral.writeCharacteristic(callbackContext, serviceUUID, characteristicUUID, data, writeType);
        peripheral.queueWrite(callbackContext, serviceUUID, characteristicUUID, data, writeType);

    }

    private void registerNotifyCallback(CallbackContext callbackContext, String macAddress, UUID serviceUUID, UUID characteristicUUID) {

        Peripheral peripheral = peripherals.get(macAddress);
        if (peripheral != null) {

            //peripheral.setOnDataCallback(serviceUUID, characteristicUUID, callbackContext);
            peripheral.queueRegisterNotifyCallback(callbackContext, serviceUUID, characteristicUUID);

        } else {

            callbackContext.error("Peripheral " + macAddress + " not found");

        }

    }

    private void removeNotifyCallback(CallbackContext callbackContext, String macAddress, UUID serviceUUID, UUID characteristicUUID) {

        Peripheral peripheral = peripherals.get(macAddress);
        if (peripheral != null) {

            peripheral.queueRemoveNotifyCallback(callbackContext, serviceUUID, characteristicUUID);

        } else {

            callbackContext.error("Peripheral " + macAddress + " not found");

        }

    }

 //rivate void findLowEnergyDevices(CallbackContext callbackContext, UUID[] serviceUUIDs, int scanSeconds) {
 //
 //   if(!PermissionHelper.hasPermission(this, ACCESS_COARSE_LOCATION)) {
 //       // save info so we can call this method again after permissions are granted
 //       permissionCallback = callbackContext;
 //       this.serviceUUIDs = serviceUUIDs;
 //       this.scanSeconds = scanSeconds;
 //       PermissionHelper.requestPermission(this, REQUEST_ACCESS_COARSE_LOCATION, ACCESS_COARSE_LOCATION);
 //       return;
 //   }
 //
 //   // ignore if currently scanning, alternately could return an error
 //   if (bluetoothAdapter.isDiscovering()) {
 //       return;
 //   }
 //
 //   // clear non-connected cached peripherals
 //   for(Iterator<Map.Entry<String, Peripheral>> iterator = peripherals.entrySet().iterator(); iterator.hasNext(); ) {
 //       Map.Entry<String, Peripheral> entry = iterator.next();
 //       if(!entry.getValue().isConnected()) {
 //           iterator.remove();
 //       }
 //   }
 //
 //   discoverCallback = callbackContext;
 //
 //   if (serviceUUIDs.length > 0) {
 //       bluetoothAdapter.startLeScan(serviceUUIDs, this);
 //   } else {
 //       bluetoothAdapter.startLeScan(this);
 //   }
 //
 //   if (scanSeconds > 0) {
 //       Handler handler = new Handler();
 //       handler.postDelayed(new Runnable() {
 //           @Override
 //           public void run() {
 //               LOG.d(TAG, "Stopping Scan");
 //               BLECentralPlugin.this.bluetoothAdapter.stopLeScan(BLECentralPlugin.this);
 //           }
 //       }, scanSeconds * 1000);
 //   }
 //
 //   PluginResult result = new PluginResult(PluginResult.Status.NO_RESULT);
 //   result.setKeepCallback(true);
 //   callbackContext.sendPluginResult(result);
 //

    private void findLowEnergyDevices(CallbackContext callbackContext, UUID[] serviceUUIDs, int scanSeconds) {


       if(!PermissionHelper.hasPermission(this, ACCESS_COARSE_LOCATION)) {
               // save info so we can call this method again after permissions are granted
               permissionCallback = callbackContext;
               this.serviceUUIDs = serviceUUIDs;
               this.scanSeconds = scanSeconds;
               PermissionHelper.requestPermission(this, REQUEST_ACCESS_COARSE_LOCATION, ACCESS_COARSE_LOCATION);
               return;
           }

           // ignore if currently scanning, alternately could return an error
           if (bluetoothAdapter.isDiscovering()) {
               return;
           }

        // TODO skip if currently scanning

        // clear non-connected cached peripherals
        for (Iterator<Map.Entry<String, Peripheral>> iterator = peripherals.entrySet().iterator(); iterator.hasNext(); ) {
            Map.Entry<String, Peripheral> entry = iterator.next();
            if (!entry.getValue().isConnected()) {
                iterator.remove();
            }
        }

        discoverCallback = callbackContext;

        if (serviceUUIDs!=null && serviceUUIDs.length > 0 && !partialMatch) {
            bluetoothAdapter.startLeScan(serviceUUIDs, this);  // Find a specific device - assumes it conforms to bluetooth specs and adverstises with standardized uuids
        } else {
            bluetoothAdapter.startLeScan(this);             // Look for all devices
        }

        if (scanSeconds > 0) {

            Handler handler = new Handler(Looper.getMainLooper()); // NVF Added the Looper.getMainLooper() call to allow us to embed this thread in another
            handler.postDelayed(new Runnable() {
                @Override
                public void run() {
                    LOG.d(TAG, "Stopping Scan");
                    BLECentralPlugin.this.bluetoothAdapter.stopLeScan(BLECentralPlugin.this);
                    //setupCallbackBasedOnService("ba11f08c5f140b0d1080");
                }
            }, scanSeconds * 1000);
        }

        // Default to call the failure callback unless we find something
        PluginResult result = new PluginResult(PluginResult.Status.NO_RESULT);
        result.setKeepCallback(true);
        callbackContext.sendPluginResult(result);
    }

    private void listKnownDevices(CallbackContext callbackContext) {

        JSONArray json = new JSONArray();

        // do we care about consistent order? will peripherals.values() be in order?
        for (Map.Entry<String, Peripheral> entry : peripherals.entrySet()) {
            Peripheral peripheral = entry.getValue();
            json.put(peripheral.asJSONObject());
        }

        PluginResult result = new PluginResult(PluginResult.Status.OK, json);
        callbackContext.sendPluginResult(result);
    }

    public Peripheral selectPeripheralBasedOnServiceUUID(String serviceString) {

        for(
                Iterator<Map.Entry<String, Peripheral>> iterator = peripherals.entrySet().iterator();
                iterator.hasNext();)

        {
            Map.Entry<String, Peripheral> entry = iterator.next();

            Peripheral peripheral = entry.getValue();
            byte [] scanRecord = peripheral.getAdvertisingData();

            // JSONObject jPeripheral = peripheral.asJSONObject();
/* Old way
                String advertisingString = formatScanRecord(scanRecord);  //jPeripheral.get("advertising").

                if (advertisingString.toLowerCase().contains(serviceString)) {

                    return peripheral;
                }
                */
            List<UUID> uuids = parseUuids(scanRecord);;  //jPeripheral.get("advertising").

            if (uuids.size()>0 && uuids.get(0).toString().toLowerCase().replace("-","").contains(serviceString))
            {

                return peripheral;
            }


        }


        return null;
    }

    public void setupCallbackBasedOnService(String serviceString)
    {
        Peripheral peripheral = selectPeripheralBasedOnServiceUUID(serviceString);

        if (peripheral!=null) {

            if (discoverCallback != null) {
                PluginResult result = new PluginResult(PluginResult.Status.OK, peripheral.asJSONObject());
                result.setKeepCallback(true);
                discoverCallback.sendPluginResult(result);
            }
        }
    }
//Override
//ublic void onLeScanOrg(BluetoothDevice device, int rssi, byte[] scanRecord) {
//
//   String address = device.getAddress();
//   boolean alreadyReported = peripherals.containsKey(address);
//
//   if (!alreadyReported) {
//
//       Peripheral peripheral = new Peripheral(device, rssi, scanRecord);
//       peripherals.put(device.getAddress(), peripheral);
//
//       if (discoverCallback != null) {
//           PluginResult result = new PluginResult(PluginResult.Status.OK, peripheral.asJSONObject());
//           result.setKeepCallback(true);
//           discoverCallback.sendPluginResult(result);
//       }
//
//   } else {
//       Peripheral peripheral = peripherals.get(address);
//       peripheral.update(rssi, scanRecord);
//       if (reportDuplicates && discoverCallback != null) {
//           PluginResult result = new PluginResult(PluginResult.Status.OK, peripheral.asJSONObject());
//           result.setKeepCallback(true);
//           discoverCallback.sendPluginResult(result);
//       }
//   }
//
    @Override
    // This is called everytime we find a bluetooth LE device that is advertising

    public void onLeScan(BluetoothDevice device, int rssi, byte[] scanRecord) {

        String address = device.getAddress(); // Get the mac address of the device
        String scanString = formatScanRecord(scanRecord);
        List<UUID> uuids = parseUuids(scanRecord); // Get list of Service UUIDs being advertised

        //ba11f08c5f140b0d1080
        if (uuids.size()>0)
            LOG.d(TAG,"Scan BRecord = " + uuids.get(0) + " Size = " + uuids.size());

        LOG.d(TAG,"Scan Record = " + scanString);

        if (!peripherals.containsKey(address)) {  // Add it to our list of peripherals if it's not present already.

            Peripheral peripheral = new Peripheral(device, rssi, scanRecord);
            peripherals.put(device.getAddress(), peripheral);  // Add it to the list

            // 8/29/16 NVF Recoded this to look through all the services for a match, not just the first one advertised
            if (partialMatch) {
                // Look through all the services we find for a partial match
                boolean found=false;
                for (int i = 0; i < uuids.size() && !found; i++) {

                    // If we're looking for a particular UUID then this will setup the success callback - otherwise we'll end up in failure

                    for (int j=0;j<serviceUUIDStrings.length && !found;j++) {
                        if (uuids.get(i).toString().toLowerCase().replace("-", "").contains(serviceUUIDStrings[j])) { //scanString.toLowerCase().contains(serviceUUIDString)) {  // To Do: Check this for all serviceUUIDs? - could loop...
                            if (discoverCallback != null) {
                                PluginResult result = new PluginResult(PluginResult.Status.OK, peripheral.asJSONObject());
                                result.setKeepCallback(true);
                                discoverCallback.sendPluginResult(result);
                                // 12/09/16 - NVF Moved this into the javascript - come devices don't like so much bluetooth activity when connecting and return status 133 otherwise
                               // BLECentralPlugin.this.bluetoothAdapter.stopLeScan(BLECentralPlugin.this);
                                found = true;
                            }
                        }
                    }
                }
            }
            else
            {
                if (serviceUUIDs != null) {
                    if (discoverCallback != null) {
                        PluginResult result = new PluginResult(PluginResult.Status.OK, peripheral.asJSONObject());
                        result.setKeepCallback(true);
                        discoverCallback.sendPluginResult(result);
                        // 12/09/16 - NVF Moved this into the javascript - come devices don't like so much bluetooth activity when connecting and return status 133 otherwise
                        // BLECentralPlugin.this.bluetoothAdapter.stopLeScan(BLECentralPlugin.this);

                    }
                }
            }


        } else {
            // this isn't necessary
            Peripheral peripheral = peripherals.get(address);
            peripheral.updateRssi(rssi);
        }

        // TODO offer option to return duplicates

    }

    @Override
    public void onActivityResult(int requestCode, int resultCode, Intent data) {

        if (requestCode == REQUEST_ENABLE_BLUETOOTH) {

            if (resultCode == Activity.RESULT_OK) {
                LOG.d(TAG, "User enabled Bluetooth");
                if (enableBluetoothCallback != null) {
                    enableBluetoothCallback.success();
                }
            } else {
                LOG.d(TAG, "User did *NOT* enable Bluetooth");
                if (enableBluetoothCallback != null) {
                    enableBluetoothCallback.error("User did not enable Bluetooth");
                }
            }

            enableBluetoothCallback = null;
        }
    }

    /* @Override */
    public void onRequestPermissionResult(int requestCode, String[] permissions,
                                          int[] grantResults) /* throws JSONException */ {
        for(int result:grantResults) {
            if(result == PackageManager.PERMISSION_DENIED)
            {
                LOG.d(TAG, "User *rejected* Coarse Location Access");
                this.permissionCallback.sendPluginResult(new PluginResult(PluginResult.Status.ERROR, PERMISSION_DENIED_ERROR));
                return;
            }
        }

        switch(requestCode) {
            case REQUEST_ACCESS_COARSE_LOCATION:
                LOG.d(TAG, "User granted Coarse Location Access");
                findLowEnergyDevices(permissionCallback, serviceUUIDs, scanSeconds);
                this.permissionCallback = null;
                this.serviceUUIDs = null;
                this.scanSeconds = -1;
                break;
        }
    }

    private UUID uuidFromString(String uuid) {
        return UUIDHelper.uuidFromString(uuid);
    }

    /**
     * Reset the BLE scanning options
     */
    private void resetScanOptions() {
        this.reportDuplicates = false;
    }


    // Format the scanRecord into something readable and easy to parse

    public static String formatScanRecord(byte[] scanRecord) {
        int i;
        int length = scanRecord.length;
        byte[] scanRecord2 = new byte[length];
        for (i = 0; i < length; i++) {
            scanRecord2[i] = scanRecord[(scanRecord.length - 1) - i];
        }
        String str = "";
        for (i = 0; i < length; i++) {
            String toHexString = Integer.toHexString(scanRecord2[i] & 255);
            if (toHexString.length() == 1) {
                toHexString = new StringBuilder(String.valueOf('0')).append(toHexString).toString();
            }
            str = new StringBuilder(String.valueOf(str)).append(toHexString.toUpperCase()).toString();
        }
        return str;
    }

    // Got this code from here: http://stackoverflow.com/questions/18019161/startlescan-with-128-bit-uuids-doesnt-work-on-native-android-ble-implementation/19060589#19060589
    // Harold Cooper answer
    private List<UUID> parseUuids(byte[] advertisedData) {
        List<UUID> uuids = new ArrayList<UUID>();

        ByteBuffer buffer = ByteBuffer.wrap(advertisedData).order(ByteOrder.LITTLE_ENDIAN);

        while (buffer.remaining() > 2) {
            byte length = buffer.get();
            if (length == 0) break;

            byte type = buffer.get();
            switch (type) {
                case 0x02: // Partial list of 16-bit UUIDs
                case 0x03: // Complete list of 16-bit UUIDs
                    while (length >= 2) {
                        uuids.add(UUID.fromString(String.format(
                                "%08x-0000-1000-8000-00805f9b34fb", buffer.getShort())));
                        length -= 2;
                    }
                    break;

                case 0x06: // Partial list of 128-bit UUIDs
                case 0x07: // Complete list of 128-bit UUIDs
                    while (length >= 16) {
                        long lsb = buffer.getLong();
                        long msb = buffer.getLong();
                        uuids.add(new UUID(msb, lsb));
                        length -= 16;
                    }
                    break;

                default:
                    buffer.position(buffer.position() + length - 1);
                    break;
            }
        }

        return uuids;
    }
}
