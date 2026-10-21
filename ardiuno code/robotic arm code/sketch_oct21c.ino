/*
  Robotic Arm - ESP32 connects to YOUR PHONE HOTSPOT + Bluetooth BLE
  Board  : NodeMCU-32S (ESP32)
  Library: "Adafruit PWM Servo Driver Library" (everything else is built into the ESP32 core)


  HOW TO USE
  1. Phone: turn ON Mobile Hotspot (use 2.4 GHz band - the ESP32 cannot join 5 GHz).
  2. Type the hotspot name and password in PHONE_WIFI_SSID / PHONE_WIFI_PASS below.
  3. Upload (Partition Scheme: "No OTA (Large APP)").
  4. Tools -> Serial Monitor (115200 baud). It shows the connecting status and the IP address.
  5. On the phone open Chrome and go to  http://<that IP>  -> arm control UI.


  If it cannot join the hotspot, the ESP32 starts its own Wi-Fi "RobotArm-WiFi"
  (password 12345678) -> connect to it and open http://192.168.4.1


  BLE (for the Flutter app): device name RobotArm-BLE
    Service  6E400001-B5A3-F393-E0A9-E50E24DCCA9E   (Nordic UART style)
    RX write 6E400002-B5A3-F393-E0A9-E50E24DCCA9E   phone -> ESP32
    TX notify6E400003-B5A3-F393-E0A9-E50E24DCCA9E   ESP32 -> phone
      'M' a0 a1 a2 a3 a4 a5 -> set all servos (0..180)    'S' ch angle -> set one servo
      'H' -> home                                         'G' -> reply 'A' a0..a5 (state)


  Wiring: PCA9685 VCC->3V3, GND->GND, SDA->GPIO21, SCL->GPIO22,
          PCA9685 V+ -> external 5-6V supply (+), supply (-) -> PCA9685 GND and ESP32 GND
*/


#include <WiFi.h>
#include <WebServer.h>
#include <Wire.h>
#include <Adafruit_PWMServoDriver.h>
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>


// ---------- USER SETTINGS ----------
// >>> TYPE YOUR PHONE HOTSPOT NAME AND PASSWORD HERE (exactly as on the phone, 2.4 GHz)
const char* PHONE_WIFI_SSID = "AKASH 0030";
const char* PHONE_WIFI_PASS = "123456789";


// Backup: if the phone hotspot cannot be joined, the ESP32 makes this Wi-Fi itself
const char* AP_SSID = "RobotArm-WiFi";
const char* AP_PASS = "12345678";         // minimum 8 characters


#define NUM_SERVOS 6
const char* NAMES[NUM_SERVOS] = {"Base", "Shoulder", "Elbow", "Wrist", "Wrist Rot", "Gripper"};


int MIN_ANGLE[16]  = {0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0};
int MAX_ANGLE[16]  = {180,180,180,180,180,180,180,180,180,180,180,180,180,180,180,180};
int HOME_ANGLE[16] = {90,90,90,90,90,90,90,90,90,90,90,90,90,90,90,90};


#define SERVO_US_MIN 500
#define SERVO_US_MAX 2500
#define MOVE_STEP_MS 15


#define BLE_NAME     "RobotArm-BLE"
#define SERVICE_UUID "6E400001-B5A3-F393-E0A9-E50E24DCCA9E"
#define RX_UUID      "6E400002-B5A3-F393-E0A9-E50E24DCCA9E"
#define TX_UUID      "6E400003-B5A3-F393-E0A9-E50E24DCCA9E"
// -----------------------------------


Adafruit_PWMServoDriver pwm = Adafruit_PWMServoDriver(0x40);
WebServer server(80);


float current[16];
volatile int target[16];
unsigned long lastStep = 0;


BLECharacteristic* txChar = nullptr;
volatile bool bleConnected = false;


// ======================= SERVO =======================
void writeServo(int ch, int angle) {
  int us = map(angle, 0, 180, SERVO_US_MIN, SERVO_US_MAX);
  pwm.writeMicroseconds(ch, us);
}


void setTarget(int ch, int a) {
  if (ch < 0 || ch >= NUM_SERVOS) return;
  target[ch] = constrain(a, MIN_ANGLE[ch], MAX_ANGLE[ch]);
}


// ======================= WEB PAGE =======================
const char ARM_PAGE[] PROGMEM = R"rawliteral(
<!DOCTYPE html><html><head>
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Robot Arm Control</title>
<style>
 body{font-family:system-ui,sans-serif;background:#10151c;color:#e8eef5;margin:0;padding:16px;max-width:560px;margin:auto}
 h1{font-size:20px} .row{background:#1a222d;border-radius:12px;padding:12px;margin:10px 0}
 .top{display:flex;justify-content:space-between;font-size:15px}
 input[type=range]{width:100%;height:36px}
 button{background:#2f7df6;color:#fff;border:0;border-radius:10px;padding:12px 16px;font-size:15px;margin:4px 4px 4px 0}
 button.g{background:#2b3645} button.r{background:#d9534f}
 .muted{color:#93a1b3;font-size:13px;margin-top:14px}
 #poses div{display:flex;justify-content:space-between;align-items:center;background:#1a222d;border-radius:10px;padding:8px 12px;margin:6px 0}
</style></head><body>
<h1>Robot Arm Control</h1>
<div id="sliders"></div>
<button onclick="home()">Home</button>
<button class="g" onclick="savePose()">Save pose</button>
<button onclick="play()">Play</button>
<button class="r" onclick="stopPlay()">Stop</button>
<button class="g" onclick="clearPoses()">Clear</button>
<div id="poses"></div>
<div class="muted" id="info">Status: ...</div>
<script>
const names=%NAMES%, mins=%MINS%, maxs=%MAXS%;
let angles=[],poses=JSON.parse(localStorage.getItem('poses')||'[]'),playing=false,timer;
const box=document.getElementById('sliders');
names.forEach((n,i)=>{
 box.insertAdjacentHTML('beforeend',`<div class="row"><div class="top"><span>${n} (CH${i})</span><b id="v${i}">90</b></div>
 <input type="range" id="s${i}" min="${mins[i]}" max="${maxs[i]}" value="90"
  oninput="move(${i},this.value)"></div>`);
});
function move(i,a){document.getElementById('v'+i).textContent=a;angles[i]=+a;
 fetch(/set?ch=${i}&a=${a}).catch(()=>{});}
function setUI(arr){arr.forEach((a,i)=>{angles[i]=a;document.getElementById('s'+i).value=a;document.getElementById('v'+i).textContent=a;});}
function home(){fetch('/home').then(r=>r.json()).then(setUI);}
function savePose(){poses.push([...angles]);store();}
function clearPoses(){poses=[];store();}
function store(){localStorage.setItem('poses',JSON.stringify(poses));draw();}
function draw(){const p=document.getElementById('poses');p.innerHTML='';
 poses.forEach((s,i)=>{p.insertAdjacentHTML('beforeend',`<div><span>Pose ${i+1}: ${s.join(', ')}</span>
 <span><button class="g" onclick="goPose(${i})">Go</button><button class="r" onclick="delPose(${i})">X</button></span></div>`)});}
function goPose(i){poses[i].forEach((a,c)=>move(c,a));setUI(poses[i]);}
function delPose(i){poses.splice(i,1);store();}
function play(){if(!poses.length||playing)return;playing=true;let i=0;
 const step=()=>{if(!playing)return;goPose(i);i=(i+1)%poses.length;timer=setTimeout(step,1800);};step();}
function stopPlay(){playing=false;clearTimeout(timer);}
async function info(){try{const s=await (await fetch('/status')).json();
 document.getElementById('info').textContent='Wi-Fi: '+s.wifi+' | IP: '+s.ip+' | Bluetooth: '+(s.ble?'phone connected':'ready');}catch(e){}}
fetch('/state').then(r=>r.json()).then(setUI);draw();info();setInterval(info,4000);
</script></body></html>
)rawliteral";


String buildArmPage() {
  String names = "[", mins = "[", maxs = "[";
  for (int i = 0; i < NUM_SERVOS; i++) {
    names += "\"" + String(NAMES[i]) + "\"";
    mins += String(MIN_ANGLE[i]);
    maxs += String(MAX_ANGLE[i]);
    if (i < NUM_SERVOS - 1) { names += ","; mins += ","; maxs += ","; }
  }
  names += "]"; mins += "]"; maxs += "]";
  String p = FPSTR(ARM_PAGE);
  p.replace("%NAMES%", names);
  p.replace("%MINS%", mins);
  p.replace("%MAXS%", maxs);
  return p;
}


String stateJson() {
  String s = "[";
  for (int i = 0; i < NUM_SERVOS; i++) {
    s += String(target[i]);
    if (i < NUM_SERVOS - 1) s += ",";
  }
  return s + "]";
}


// ======================= WEB HANDLERS =======================
void handleRoot()  { server.send(200, "text/html", buildArmPage()); }
void handleState() { server.send(200, "application/json", stateJson()); }


void handleStatus() {
  bool c = (WiFi.status() == WL_CONNECTED);
  String j = "{\"wifi\":\"" + String(c ? WiFi.SSID() : String("not connected")) + "\",\"ip\":\"" +
             (c ? WiFi.localIP().toString() : WiFi.softAPIP().toString()) +
             "\",\"ble\":" + String(bleConnected ? "true" : "false") + "}";
  server.send(200, "application/json", j);
}


void handleSet() {
  if (!server.hasArg("ch") || !server.hasArg("a")) { server.send(400, "text/plain", "missing args"); return; }
  int ch = server.arg("ch").toInt();
  int a  = server.arg("a").toInt();
  if (ch < 0 || ch >= NUM_SERVOS) { server.send(400, "text/plain", "bad channel"); return; }
  setTarget(ch, a);
  server.send(200, "text/plain", "OK");
}


void handleHome() {
  for (int i = 0; i < NUM_SERVOS; i++) target[i] = HOME_ANGLE[i];
  server.send(200, "application/json", stateJson());
}


// ======================= BLUETOOTH (BLE) =======================
void bleNotifyState() {
  if (!bleConnected || txChar == nullptr) return;
  uint8_t buf[1 + NUM_SERVOS];
  buf[0] = 'A';
  for (int i = 0; i < NUM_SERVOS; i++) buf[1 + i] = (uint8_t)target[i];
  txChar->setValue(buf, 1 + NUM_SERVOS);
  txChar->notify();
}


class BleServerCallbacks : public BLEServerCallbacks {
  void onConnect(BLEServer*) { bleConnected = true; Serial.println("BLE phone connected"); }
  void onDisconnect(BLEServer*) {
    bleConnected = false;
    Serial.println("BLE phone disconnected - advertising again");
    BLEDevice::startAdvertising();
  }
};


class BleRxCallbacks : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic* c) {
    auto v = c->getValue();
    size_t n = v.length();
    if (n < 1) return;
    uint8_t cmd = (uint8_t)v[0];
    if (cmd == 'M') {
      for (size_t i = 0; i < (size_t)NUM_SERVOS && (i + 1) < n; i++) setTarget(i, (uint8_t)v[i + 1]);
    } else if (cmd == 'S' && n >= 3) {
      setTarget((uint8_t)v[1], (uint8_t)v[2]);
    } else if (cmd == 'H') {
      for (int i = 0; i < NUM_SERVOS; i++) target[i] = HOME_ANGLE[i];
      bleNotifyState();
    } else if (cmd == 'G') {
      bleNotifyState();
    }
  }
};


void setupBle() {
  BLEDevice::init(BLE_NAME);
  BLEServer* bleServer = BLEDevice::createServer();
  bleServer->setCallbacks(new BleServerCallbacks());
  BLEService* service = bleServer->createService(SERVICE_UUID);


  txChar = service->createCharacteristic(TX_UUID, BLECharacteristic::PROPERTY_NOTIFY);
  txChar->addDescriptor(new BLE2902());


  BLECharacteristic* rxChar = service->createCharacteristic(
      RX_UUID, BLECharacteristic::PROPERTY_WRITE | BLECharacteristic::PROPERTY_WRITE_NR);
  rxChar->setCallbacks(new BleRxCallbacks());


  service->start();
  BLEAdvertising* adv = BLEDevice::getAdvertising();
  adv->addServiceUUID(SERVICE_UUID);
  adv->setScanResponse(true);
  BLEDevice::startAdvertising();
}


// ======================= WI-FI (joins the phone hotspot) =======================
enum WifiSt { W_CONNECTING, W_CONNECTED, W_FAILED };
WifiSt wifiSt = W_CONNECTING;
unsigned long wifiStart = 0;
bool apStarted = false;


void printReason() {
  wl_status_t st = WiFi.status();
  if (st == WL_NO_SSID_AVAIL)       Serial.println("  Reason: hotspot name not found (check the name, hotspot ON, 2.4 GHz band)");
  else if (st == WL_CONNECT_FAILED) Serial.println("  Reason: wrong password");
  else                              Serial.println("  Reason: wrong password, weak signal or hotspot not answering");
}


void onConnected() {
  Serial.println("=====================================");
  Serial.println("Wi-Fi CONNECTED to phone hotspot");
  Serial.print("  Network : "); Serial.println(WiFi.SSID());
  Serial.print("  IP      : "); Serial.println(WiFi.localIP());
  Serial.print("  Open UI : http://"); Serial.println(WiFi.localIP());
  Serial.println("  (open this address in Chrome on the phone)");
  Serial.println("=====================================");
}


void startBackupHotspot() {
  if (apStarted) return;
  apStarted = true;
  WiFi.mode(WIFI_AP_STA);
  WiFi.softAP(AP_SSID, AP_PASS);
  Serial.print("Backup Wi-Fi started: ");
  Serial.print(AP_SSID);
  Serial.print("  (password ");
  Serial.print(AP_PASS);
  Serial.print(")  ->  open http://");
  Serial.println(WiFi.softAPIP());
}


void printStatus(bool up) {
  Serial.println("------------- STATUS -------------");
  if (up) {
    Serial.print("Wi-Fi     : connected to "); Serial.print(WiFi.SSID());
    Serial.print(" ("); Serial.print(WiFi.RSSI()); Serial.println(" dBm)");
    Serial.print("Open UI   : http://"); Serial.println(WiFi.localIP());
  } else {
    Serial.print("Wi-Fi     : NOT connected to "); Serial.println(PHONE_WIFI_SSID);
  }
  if (apStarted) { Serial.print("Backup    : "); Serial.print(AP_SSID); Serial.print(" -> http://"); Serial.println(WiFi.softAPIP()); }
  Serial.print("Bluetooth : "); Serial.println(bleConnected ? "phone connected (RobotArm-BLE)" : "ready (RobotArm-BLE)");
  Serial.println("----------------------------------");
}


void updateWifi() {
  static unsigned long lastDot = 0, lastInfo = 0;
  bool up = (WiFi.status() == WL_CONNECTED);


  if (wifiSt == W_CONNECTING && !up && millis() - lastDot >= 500) {
    lastDot = millis();
    Serial.print(".");                        // progress dots
  }


  if (up && wifiSt != W_CONNECTED) {
    Serial.println();
    wifiSt = W_CONNECTED;
    onConnected();
  } else if (!up && wifiSt == W_CONNECTED) {
    Serial.println("Wi-Fi connection lost, reconnecting...");
    wifiSt = W_CONNECTING;
    wifiStart = millis();
  } else if (!up && wifiSt == W_CONNECTING && millis() - wifiStart > 20000) {
    Serial.println();
    Serial.println("Wi-Fi connection FAILED");
    printReason();
    wifiSt = W_FAILED;
    startBackupHotspot();                     // still keeps trying to join the phone hotspot
  }


  if (millis() - lastInfo >= 15000) {         // repeat status every 15 s
    lastInfo = millis();
    printStatus(up);
  }
}


// ======================= SETUP / LOOP =======================
void setup() {
  Serial.begin(115200);
  Wire.begin(21, 22);
  pwm.begin();
  pwm.setOscillatorFrequency(27000000);
  pwm.setPWMFreq(50);
  delay(10);


  for (int i = 0; i < NUM_SERVOS; i++) {
    current[i] = HOME_ANGLE[i];
    target[i] = HOME_ANGLE[i];
    writeServo(i, HOME_ANGLE[i]);
  }


  WiFi.persistent(false);
  WiFi.mode(WIFI_STA);
  WiFi.setAutoReconnect(true);
  WiFi.setHostname("robotarm");
  Serial.println();
  Serial.print("Connecting to phone hotspot: ");
  Serial.println(PHONE_WIFI_SSID);
  wifiStart = millis();
  WiFi.begin(PHONE_WIFI_SSID, PHONE_WIFI_PASS);


  setupBle();
  Serial.println("Bluetooth started: RobotArm-BLE");


  server.on("/", handleRoot);
  server.on("/set", handleSet);
  server.on("/state", handleState);
  server.on("/home", handleHome);
  server.on("/status", handleStatus);
  server.begin();
}


void loop() {
  server.handleClient();
  updateWifi();


  if (millis() - lastStep >= MOVE_STEP_MS) {
    lastStep = millis();
    for (int i = 0; i < NUM_SERVOS; i++) {
      int t = target[i];
      if ((int)current[i] != t) {
        current[i] += (t > current[i]) ? 1 : -1;
        writeServo(i, (int)current[i]);
      }
    }
  }
}