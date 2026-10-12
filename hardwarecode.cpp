#include <Arduino.h>
#include <Wire.h>
#include <ESP8266WiFi.h>
#include <ESP8266HTTPClient.h>
#include <WiFiClientSecureBearSSL.h>
#include <CertStoreBearSSL.h>
#include <LittleFS.h>
#include <SoftwareSerial.h>
#include <ArduinoJson.h>
#include <time.h>
#include <sys/time.h>

// =====================================================
// WIFI
// =====================================================
// Configure these locally before flashing. Do not commit real passwords.
const char* WIFI_SSID     = "GlobeAtHome_06b80_2.4";
const char* WIFI_PASSWORD = "D3cL4r4d0!2830";

// Firebase Authentication > Users: create a dedicated email/password account
// for this physical Jeep tracker. Use the WEB API key from firebase_options.dart.
const char* FIREBASE_API_KEY = "AIzaSyC0YXQ83GCutpozyK2wi0B3vH8V2zKt5IQ";
const char* FIREBASE_DEVICE_EMAIL = "jeeplasalle@email.com";
const char* FIREBASE_DEVICE_PASSWORD = "jeeplasalle1";
// Copy the document ID (not the vehicle name) from Firestore > vehicles.
const char* VEHICLE_DOCUMENT_ID = "CuoxcUom2JLXRq4qu33L";
const char* FIREBASE_PROJECT_ID = "ikot-lasalle-ccfab";

// The Google CA bundle is stored in LittleFS as /certs.ar. Upload the
// filesystem image as well as this sketch; never bypass TLS verification.
BearSSL::CertStore firebaseCertStore;
bool firebaseCertStoreReady = false;

String firebaseIdToken;
unsigned long firebaseTokenIssuedAt = 0;
unsigned long firebaseTokenLifetimeMs = 0;
unsigned long lastFirebaseAuthAttempt = 0;
const unsigned long FIREBASE_AUTH_RETRY_MS = 30000;

// =====================================================
// CONNECTIONS
// =====================================================
// LCD:
// SDA -> NodeMCU D2 / GPIO4
// SCL -> NodeMCU D1 / GPIO5
//
// SIM808:
// SIM808 TXD -> NodeMCU D6 / GPIO12
// SIM808 RXD -> NodeMCU D7 / GPIO13
// SIM808 GND -> NodeMCU GND

#define SIM808_RX D6
#define SIM808_TX D7

SoftwareSerial sim808(SIM808_RX, SIM808_TX);

// =====================================================
// LIBRARY-FREE I2C LCD
// =====================================================
#define LCD_ADDRESS 0x27
#define LCD_COLUMNS 20
#define LCD_ROWS 4

class SimpleI2CLCD {
private:
  uint8_t address;
  uint8_t backlight = 0x08;

  void expanderWrite(uint8_t data) {
    Wire.beginTransmission(address);
    Wire.write(data | backlight);
    Wire.endTransmission();
  }

  void pulseEnable(uint8_t data) {
    expanderWrite(data | 0x04);
    delayMicroseconds(1);

    expanderWrite(data & ~0x04);
    delayMicroseconds(50);
  }

  void write4Bits(uint8_t data) {
    expanderWrite(data);
    pulseEnable(data);
  }

  void send(uint8_t value, uint8_t mode) {
    uint8_t highNibble = value & 0xF0;
    uint8_t lowNibble = (value << 4) & 0xF0;

    write4Bits(highNibble | mode);
    write4Bits(lowNibble | mode);
  }

public:
  SimpleI2CLCD(uint8_t lcdAddress) {
    address = lcdAddress;
  }

  void command(uint8_t value) {
    send(value, 0x00);
  }

  void writeCharacter(uint8_t value) {
    send(value, 0x01);
  }

  void begin() {
    delay(50);

    expanderWrite(0x00);
    delay(1000);

    write4Bits(0x30);
    delayMicroseconds(4500);

    write4Bits(0x30);
    delayMicroseconds(4500);

    write4Bits(0x30);
    delayMicroseconds(150);

    write4Bits(0x20);

    command(0x28);
    command(0x08);
    clear();
    command(0x06);
    command(0x0C);
  }

  void clear() {
    command(0x01);
    delay(2);
  }

  void setCursor(uint8_t column, uint8_t row) {
    const uint8_t rowOffsets[] = {
      0x00, 0x40, 0x14, 0x54
    };

    if (row >= LCD_ROWS) {
      row = LCD_ROWS - 1;
    }

    command(0x80 | (column + rowOffsets[row]));
  }

  void print(const String& text) {
    for (unsigned int i = 0; i < text.length(); i++) {
      writeCharacter(text[i]);
    }
  }
};

SimpleI2CLCD lcd(LCD_ADDRESS);

// =====================================================
// JEEPNEY INFORMATION
// =====================================================
const String VEHICLE_TYPE = "Jeep";

int onboardCount = 0;
int outboardCount = 0;

String vehicleStatus = "IDLE";
enum class CloudStatus : uint8_t { connecting, uploadFailed, connected };
CloudStatus cloudStatus = CloudStatus::connecting;

// =====================================================
// GPS INFORMATION
// =====================================================
double gpsLatitude = 0.0;
double gpsLongitude = 0.0;
double gpsSpeedKmh = 0.0;

bool gpsHasFix = false;
bool sim808Available = false;

// =====================================================
// STATUS CONDITIONS
// =====================================================
const double MOVEMENT_SPEED_KMH = 1.5;
const unsigned long BREAK_DELAY = 30000;

unsigned long stoppedSince = 0;

// =====================================================
// TIMING
// =====================================================
const unsigned long GPS_REQUEST_INTERVAL = 1000;
const unsigned long VEHICLE_SYNC_INTERVAL = 10000;
const unsigned long GPS_UPLOAD_INTERVAL = 3000;
const unsigned long GPS_RESTART_DELAY = 2000;
const unsigned long LCD_PAGE_INTERVAL = 3000;
const unsigned long WIFI_RETRY_INTERVAL = 30000;
const unsigned long SIM_RETRY_INTERVAL = 15000;

unsigned long lastGPSRequest = 0;
unsigned long lastVehicleSync = 0;
unsigned long lastGPSUpload = 0;
unsigned long lastSuccessfulGpsUpload = 0;
unsigned long lastLCDPageSwitch = 0;
unsigned long lastWiFiRetry = 0;
unsigned long lastSIMRetry = 0;

uint8_t lcdPage = 0;

// =====================================================
// LCD FUNCTIONS
// =====================================================
String fitLCD(String text) {
  if (text.length() > LCD_COLUMNS) {
    text = text.substring(0, LCD_COLUMNS);
  }

  while (text.length() < LCD_COLUMNS) {
    text += " ";
  }

  return text;
}

void lcdLine(uint8_t row, String text) {
  lcd.setCursor(0, row);
  lcd.print(fitLCD(text));
}

void displayJeepInformation() {
  lcdLine(0, "TYPE: " + VEHICLE_TYPE);
  lcdLine(1, "STATUS: " + vehicleStatus);
  lcdLine(2, "ONBOARD: " + String(onboardCount));
  lcdLine(3, "OUTBOARD: " + String(outboardCount));
}

const char* cloudStatusText() {
  switch (cloudStatus) {
    case CloudStatus::connected: return "CONNECTED";
    case CloudStatus::uploadFailed: return "UPLOAD FAILED";
    default: return "CONNECTING...";
  }
}

void displayGPSLocation() {
  if (gpsHasFix) {
    lcdLine(0, "LAT: " + String(gpsLatitude, 6));
    lcdLine(1, "LON: " + String(gpsLongitude, 6));
    lcdLine(2, "SPEED: " + String(gpsSpeedKmh, 1));
    lcdLine(3, String("STAT: ") + cloudStatusText());
  } else {
    lcdLine(0, "LAT: WAITING");
    lcdLine(1, "LON: WAITING");
    lcdLine(2, "GPS: NO FIX");
    lcdLine(3, String("STAT: ") + cloudStatusText());
  }
}

void drawCurrentLCDPage();

void setCloudStatus(CloudStatus nextStatus) {
  if (cloudStatus == nextStatus) return;
  cloudStatus = nextStatus;
  if (cloudStatus != CloudStatus::connected) lcdPage = 0;
  drawCurrentLCDPage();
}

void drawCurrentLCDPage() {
  if (lcdPage == 1 && cloudStatus == CloudStatus::connected) {
    displayJeepInformation();
  } else {
    displayGPSLocation();
  }
}

void updateLCDPages() {
  if (cloudStatus != CloudStatus::connected) {
    if (lcdPage != 0) {
      lcdPage = 0;
      drawCurrentLCDPage();
    }
    return;
  }
  if (millis() - lastLCDPageSwitch >= LCD_PAGE_INTERVAL) {
    lastLCDPageSwitch = millis();

    lcdPage++;

    if (lcdPage > 1) {
      lcdPage = 0;
    }

    drawCurrentLCDPage();
  }
}

// =====================================================
// WIFI
// =====================================================
void connectWiFi() {
  if (WiFi.status() == WL_CONNECTED) {
    return;
  }
  setCloudStatus(CloudStatus::connecting);

  Serial.println();
  Serial.print("Connecting to WiFi: ");
  Serial.println(WIFI_SSID);

  WiFi.mode(WIFI_STA);
  WiFi.begin(WIFI_SSID, WIFI_PASSWORD);

  unsigned long started = millis();

  while (WiFi.status() != WL_CONNECTED &&
         millis() - started < 15000) {
    delay(500);
    yield();
    Serial.print(".");
  }

  Serial.println();

  if (WiFi.status() == WL_CONNECTED) {
    Serial.println("WiFi connected");

    Serial.print("IP address: ");
    Serial.println(WiFi.localIP());
  } else {
    Serial.println("WiFi connection failed");
  }
}

void maintainWiFi() {
  if (WiFi.status() == WL_CONNECTED) {
    return;
  }
  setCloudStatus(CloudStatus::connecting);

  if (millis() - lastWiFiRetry >= WIFI_RETRY_INTERVAL) {
    lastWiFiRetry = millis();
    connectWiFi();
  }
}

// =====================================================
// SIM808 COMMUNICATION
// =====================================================
void clearSIMBuffer() {
  while (sim808.available()) {
    sim808.read();
  }
}

String sendATCommand(
  const String& command,
  unsigned long timeout
) {
  clearSIMBuffer();

  Serial.print(">> ");
  Serial.println(command);

  sim808.println(command);

  String response = "";
  unsigned long startTime = millis();
  unsigned long lastCharacterTime = millis();

  while (millis() - startTime < timeout) {
    while (sim808.available()) {
      char character = sim808.read();

      response += character;
      lastCharacterTime = millis();
    }

    if (response.length() > 0 &&
        millis() - lastCharacterTime > 400) {
      break;
    }

    yield();
  }

  Serial.println("<<");

  if (response.length() > 0) {
    Serial.println(response);
  } else {
    Serial.println("[NO RESPONSE]");
  }

  return response;
}

bool testSIM808() {
  for (int attempt = 1; attempt <= 3; attempt++) {
    Serial.print("SIM808 test attempt ");
    Serial.println(attempt);

    String response = sendATCommand("AT", 3000);

    if (response.indexOf("OK") >= 0) {
      Serial.println("SIM808 is responding");

      sim808Available = true;
      return true;
    }

    delay(1000);
  }

  Serial.println("SIM808 is unavailable");

  sim808Available = false;
  gpsHasFix = false;

  return false;
}

void initializeSIM808() {
  if (!testSIM808()) {
    return;
  }

  // Disable command echo.
  sendATCommand("ATE0", 3000);

  // Disable SIM808 UART sleep.
  sendATCommand("AT+CSCLK=0", 3000);

  sim808Available = true;
}

// =====================================================
// GPS POWER CONTROL
// =====================================================
bool startGPS() {
  if (!sim808Available) {
    return false;
  }

  Serial.println("Turning GPS ON...");

  String response =
    sendATCommand("AT+CGNSPWR=1", 2000);

  if (response.indexOf("OK") < 0) {
    Serial.println("GPS power command failed");

    gpsHasFix = false;

    return false;
  }

  delay(GPS_RESTART_DELAY);

  response = sendATCommand("AT+CGNSPWR?", 2000);

  if (response.indexOf("+CGNSPWR: 1") >= 0) {
    Serial.println("GPS confirmed ON");

    return true;
  }

  Serial.println("GPS still reports OFF");

  gpsHasFix = false;

  return false;
}

// =====================================================
// GPS RESPONSE PARSING
// =====================================================
String getCSVField(
  const String& data,
  int requestedField
) {
  int currentField = 0;
  int fieldStart = 0;

  for (int i = 0; i <= (int)data.length(); i++) {
    if (i == (int)data.length() || data[i] == ',') {
      if (currentField == requestedField) {
        return data.substring(fieldStart, i);
      }

      currentField++;
      fieldStart = i + 1;
    }
  }

  return "";
}

String extractCGNSINFLine(const String& response) {
  int startPosition = response.indexOf("+CGNSINF:");

  if (startPosition < 0) {
    return "";
  }

  int lineEnd = response.indexOf('\n', startPosition);

  if (lineEnd < 0) {
    lineEnd = response.length();
  }

  String gpsLine =
    response.substring(startPosition + 9, lineEnd);

  gpsLine.trim();

  return gpsLine;
}

// =====================================================
// JEEPNEY STATUS
// =====================================================
void updateJeepneyStatus() {
  if (!gpsHasFix) {
    stoppedSince = 0;
    return;
  }
  if (gpsSpeedKmh > MOVEMENT_SPEED_KMH) {
    stoppedSince = 0;
    vehicleStatus = "ACTIVE";
    return;
  }
  if (stoppedSince == 0) stoppedSince = millis();
  vehicleStatus = millis() - stoppedSince >= BREAK_DELAY ? "BREAK" : "IDLE";
}

void syncClockFromGPS(const String& gpsData) {
  if (time(nullptr) > 1700000000) return;
  const String utcText = getCSVField(gpsData, 2);
  if (utcText.length() < 14) return;
  for (int i = 0; i < 14; ++i) {
    if (utcText[i] < '0' || utcText[i] > '9') return;
  }
  struct tm utc = {};
  utc.tm_year = utcText.substring(0, 4).toInt() - 1900;
  utc.tm_mon = utcText.substring(4, 6).toInt() - 1;
  utc.tm_mday = utcText.substring(6, 8).toInt();
  utc.tm_hour = utcText.substring(8, 10).toInt();
  utc.tm_min = utcText.substring(10, 12).toInt();
  utc.tm_sec = utcText.substring(12, 14).toInt();
  utc.tm_isdst = 0;
  if (utc.tm_year < 124 || utc.tm_mon < 0 || utc.tm_mon > 11 ||
      utc.tm_mday < 1 || utc.tm_mday > 31 || utc.tm_hour > 23 ||
      utc.tm_min > 59 || utc.tm_sec > 59) return;
  // The SIM808 timestamp is UTC; mktime must use the same timezone.
  setTZ("UTC0");
  const time_t gpsEpoch = mktime(&utc);
  if (gpsEpoch <= 1700000000) return;
  struct timeval gpsTime = {gpsEpoch, 0};
  if (settimeofday(&gpsTime, nullptr) == 0) {
    lastFirebaseAuthAttempt = 0;
    Serial.printf("ESP8266 clock synchronized from SIM808 GPS UTC: %s\n",
                  utcText.c_str());
  }
}

bool parseGPSResponse(const String& response) {
  String gpsData = extractCGNSINFLine(response);

  if (gpsData.length() == 0) {
    Serial.println("No +CGNSINF line found");

    gpsHasFix = false;

    return false;
  }

  Serial.println("Parsed GPS data:");
  Serial.println(gpsData);

  int runningStatus =
    getCSVField(gpsData, 0).toInt();

  int fixStatus =
    getCSVField(gpsData, 1).toInt();

  Serial.print("GPS running status: ");
  Serial.println(runningStatus);

  Serial.print("GPS fix status: ");
  Serial.println(fixStatus);

  // Report an unexpected OFF state without restarting the GPS receiver.
  if (runningStatus != 1) {
    Serial.println("GPS engine reported OFF");

    gpsHasFix = false;
    drawCurrentLCDPage();

    return false;
  }

  // GPS is running but has no satellite fix.
  if (fixStatus != 1) {
    gpsHasFix = false;

    Serial.println("GPS is ON, but has no fix");
    Serial.println("Place antenna outdoors facing upward");

    return false;
  }

  syncClockFromGPS(gpsData);

  String latitudeText =
    getCSVField(gpsData, 3);

  String longitudeText =
    getCSVField(gpsData, 4);

  String speedText =
    getCSVField(gpsData, 6);

  if (latitudeText.length() == 0 ||
      longitudeText.length() == 0) {
    gpsHasFix = false;

    return false;
  }

  gpsLatitude = latitudeText.toDouble();
  gpsLongitude = longitudeText.toDouble();
  gpsSpeedKmh = speedText.toDouble();

  if (!isfinite(gpsLatitude) || !isfinite(gpsLongitude) ||
      gpsLatitude < -90 || gpsLatitude > 90 ||
      gpsLongitude < -180 || gpsLongitude > 180 ||
      (gpsLatitude == 0 && gpsLongitude == 0)) {
    gpsHasFix = false;
    return false;
  }

  gpsHasFix = true;

  Serial.print("Latitude: ");
  Serial.println(gpsLatitude, 6);

  Serial.print("Longitude: ");
  Serial.println(gpsLongitude, 6);

  Serial.print("Speed: ");
  Serial.print(gpsSpeedKmh, 2);
  Serial.println(" km/h");

  updateJeepneyStatus();

  return true;
}

// =====================================================
// FETCH GPS
// =====================================================
void fetchGPS() {
  if (!sim808Available) {
    gpsHasFix = false;
    return;
  }

  String response =
    sendATCommand("AT+CGNSINF", 2000);

  if (response.indexOf("+CGNSINF:") < 0) {
    Serial.println("No GPS response received");

    String testResponse =
      sendATCommand("AT", 3000);

    if (testResponse.indexOf("OK") < 0) {
      sim808Available = false;
      gpsHasFix = false;
    } else {
      sim808Available = true;
      gpsHasFix = false;
    }

    return;
  }

  parseGPSResponse(response);
}

// =====================================================
// SIM808 RECOVERY
// =====================================================
void retrySIM808() {
  if (sim808Available) {
    return;
  }

  if (millis() - lastSIMRetry <
      SIM_RETRY_INTERVAL) {
    return;
  }

  lastSIMRetry = millis();

  Serial.println("Retrying SIM808 connection...");

  initializeSIM808();

  if (sim808Available) {
    startGPS();
  }

  drawCurrentLCDPage();
}

// =====================================================
// FIREBASE: one GPS device updates one existing vehicle document.
// Uses Firebase Auth ID tokens and the Firestore REST API over verified TLS.
// =====================================================
bool firebaseConfigured() {
  return String(FIREBASE_API_KEY) != "YOUR_FIREBASE_WEB_API_KEY" &&
         String(FIREBASE_DEVICE_EMAIL) != "YOUR_DEVICE_EMAIL" &&
         String(FIREBASE_DEVICE_PASSWORD) != "YOUR_DEVICE_PASSWORD" &&
         String(VEHICLE_DOCUMENT_ID) != "YOUR_JEEP_VEHICLE_DOCUMENT_ID" &&
         firebaseCertStoreReady;
}

bool clockReady() {
  if (time(nullptr) > 1700000000) return true;
  configTime(0, 0, "time.google.com", "pool.ntp.org");
  const unsigned long started = millis();
  while (time(nullptr) <= 1700000000 && millis() - started < 10000) {
    delay(250);
    yield();
  }
  return time(nullptr) > 1700000000;
}

void logFirebaseConnectionError(const char* operation, int code,
                                BearSSL::WiFiClientSecure& client) {
  char tlsError[128] = {};
  const int tlsCode = client.getLastSSLError(tlsError, sizeof(tlsError));
  Serial.printf("%s failed (HTTP %d, TLS %d: %s)\n",
                operation, code, tlsCode, tlsError);
#if defined(UMM_INFO)
  Serial.printf("Heap: %u free, %u largest block, %u%% fragmented\n",
                ESP.getFreeHeap(), ESP.getMaxFreeBlockSize(),
                ESP.getHeapFragmentation());
#else
  Serial.printf("Heap: %u free\n", ESP.getFreeHeap());
#endif
}

bool signInFirebase() {
  if (!firebaseConfigured()) {
    setCloudStatus(CloudStatus::uploadFailed);
    Serial.println("Firebase sign-in skipped: device configuration is incomplete");
    return false;
  }
  if (WiFi.status() != WL_CONNECTED) {
    setCloudStatus(CloudStatus::connecting);
    Serial.println("Firebase sign-in skipped: WiFi is offline");
    return false;
  }
  if (!clockReady()) {
    setCloudStatus(CloudStatus::uploadFailed);
    Serial.println("Firebase sign-in skipped: ESP8266 clock unavailable; waiting for GPS UTC");
    return false;
  }
  if (cloudStatus != CloudStatus::connected) {
    setCloudStatus(CloudStatus::connecting);
  }

  String body;
  {
    JsonDocument request;
    request["email"] = FIREBASE_DEVICE_EMAIL;
    request["password"] = FIREBASE_DEVICE_PASSWORD;
    request["returnSecureToken"] = true;
    serializeJson(request, body);
  }
  String response;
  int code = -1;
  {
    BearSSL::WiFiClientSecure client;
    client.setCertStore(&firebaseCertStore);
    client.setTimeout(12000);
    HTTPClient http;
    const String url = String("https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=") + FIREBASE_API_KEY;
    if (!http.begin(client, url)) {
      setCloudStatus(CloudStatus::uploadFailed);
      return false;
    }
    http.setTimeout(12000);
    http.addHeader("Content-Type", "application/json");
    code = http.POST(body);
    if (code == 200) response = http.getString();
    if (code < 0) logFirebaseConnectionError("Firebase sign-in", code, client);
    http.end();
  }
  if (code != 200) {
    setCloudStatus(CloudStatus::uploadFailed);
    if (code >= 0) Serial.printf("Firebase sign-in failed (HTTP %d)\n", code);
    return false;
  }

  JsonDocument result;
  if (deserializeJson(result, response)) {
    setCloudStatus(CloudStatus::uploadFailed);
    Serial.println("Firebase sign-in response was not valid JSON");
    return false;
  }
  String token = result["idToken"].as<String>();
  unsigned long expiresSeconds = result["expiresIn"].as<String>().toInt();
  if (token.isEmpty() || expiresSeconds < 120) {
    setCloudStatus(CloudStatus::uploadFailed);
    return false;
  }

  firebaseIdToken = token;
  firebaseTokenIssuedAt = millis();
  firebaseTokenLifetimeMs = (expiresSeconds - 60UL) * 1000UL;
  Serial.println("Firebase device signed in");
  return true;
}

bool firebaseTokenReady() {
  if (firebaseIdToken.length() > 0 &&
      millis() - firebaseTokenIssuedAt < firebaseTokenLifetimeMs) return true;

  if (lastFirebaseAuthAttempt != 0 &&
      millis() - lastFirebaseAuthAttempt < FIREBASE_AUTH_RETRY_MS) return false;
  lastFirebaseAuthAttempt = millis();
  firebaseIdToken = "";
  return signInFirebase();
}

int firebaseGet(const String& url, String& response, const char* operation) {
  BearSSL::WiFiClientSecure client;
  client.setCertStore(&firebaseCertStore);
  client.setTimeout(8000);
  HTTPClient http;
  if (!http.begin(client, url)) return -1;
  http.setTimeout(8000);
  http.addHeader("Authorization", "Bearer " + firebaseIdToken);
  const int code = http.GET();
  if (code == 200) response = http.getString();
  if (code < 0) logFirebaseConnectionError(operation, code, client);
  http.end();
  if (code == 401) firebaseIdToken = "";
  return code;
}

void syncVehicleData() {
  if (WiFi.status() != WL_CONNECTED || !firebaseTokenReady()) return;
  const String url = String("https://firestore.googleapis.com/v1/projects/") +
      FIREBASE_PROJECT_ID + "/databases/(default)/documents/vehicles/" +
      VEHICLE_DOCUMENT_ID +
      "?mask.fieldPaths=onBoardPassengers&mask.fieldPaths=outBoardPassengers";
  String response;
  const int code = firebaseGet(url, response, "Firestore vehicle sync");
  if (code != 200) {
    if (code >= 0) Serial.printf("Firestore vehicle sync failed (HTTP %d)\n", code);
    return;
  }
  JsonDocument document;
  if (deserializeJson(document, response)) return;
  onboardCount = document["fields"]["onBoardPassengers"]["integerValue"].as<String>().toInt();
  outboardCount = document["fields"]["outBoardPassengers"]["integerValue"].as<String>().toInt();
  drawCurrentLCDPage();
}

void uploadVehicleLocation() {
  if (!gpsHasFix) return;
  if (WiFi.status() != WL_CONNECTED) {
    setCloudStatus(CloudStatus::connecting);
    return;
  }
  if (!firebaseTokenReady()) return;
  if (cloudStatus != CloudStatus::connected) {
    setCloudStatus(CloudStatus::connecting);
  }

  char gpsTimestamp[25];
  const time_t nowUtc = time(nullptr);
  struct tm* utc = gmtime(&nowUtc);
  if (utc == nullptr ||
      strftime(gpsTimestamp, sizeof(gpsTimestamp), "%Y-%m-%dT%H:%M:%SZ", utc) == 0) {
    setCloudStatus(CloudStatus::uploadFailed);
    Serial.println("GPS upload skipped: clock unavailable");
    return;
  }

  String body;
  {
    JsonDocument payload;
    payload["fields"]["location"]["geoPointValue"]["latitude"] = gpsLatitude;
    payload["fields"]["location"]["geoPointValue"]["longitude"] = gpsLongitude;
    payload["fields"]["latitude"]["doubleValue"] = gpsLatitude;
    payload["fields"]["longitude"]["doubleValue"] = gpsLongitude;
    payload["fields"]["speedKmh"]["doubleValue"] = gpsSpeedKmh;
    payload["fields"]["type"]["stringValue"] = VEHICLE_TYPE;
    payload["fields"]["status"]["stringValue"] =
        vehicleStatus == "ACTIVE" ? "active" :
        vehicleStatus == "BREAK" ? "break" : "idle";
    payload["fields"]["lastGpsAt"]["timestampValue"] = gpsTimestamp;
    serializeJson(payload, body);
  }
  if (body.isEmpty()) {
    setCloudStatus(CloudStatus::uploadFailed);
    Serial.println("GPS upload skipped: JSON allocation failed");
    return;
  }
  Serial.printf("GPS upload heap before HTTPS: %u bytes\n", ESP.getFreeHeap());

  BearSSL::WiFiClientSecure client;
  client.setCertStore(&firebaseCertStore);
  client.setTimeout(3000);

  // updateMask preserves registration data, and exists=true prevents creating
  // a second vehicle if the configured document ID is wrong or was deleted.
  const String url = String("https://firestore.googleapis.com/v1/projects/") +
      FIREBASE_PROJECT_ID + "/databases/(default)/documents/vehicles/" +
      VEHICLE_DOCUMENT_ID +
      "?updateMask.fieldPaths=location&updateMask.fieldPaths=latitude" +
      "&updateMask.fieldPaths=longitude&updateMask.fieldPaths=speedKmh" +
      "&updateMask.fieldPaths=type&updateMask.fieldPaths=status" +
      "&updateMask.fieldPaths=lastGpsAt" +
      "&mask.fieldPaths=lastGpsAt" +
      "&currentDocument.exists=true";

  HTTPClient http;
  if (!http.begin(client, url)) {
    setCloudStatus(CloudStatus::uploadFailed);
    return;
  }
  http.setTimeout(3000);
  http.addHeader("Content-Type", "application/json");
  http.addHeader("Authorization", "Bearer " + firebaseIdToken);

  int code = http.PATCH(body);
  if (code < 0) logFirebaseConnectionError("Firestore GPS upload", code, client);
  http.end();
  if (code == 200) {
    lastSuccessfulGpsUpload = millis();
    setCloudStatus(CloudStatus::connected);
    Serial.printf("Vehicle GPS uploaded to Firestore vehicles/%s at %s\n",
                  VEHICLE_DOCUMENT_ID, gpsTimestamp);
  } else {
    setCloudStatus(CloudStatus::uploadFailed);
    if (code >= 0) Serial.printf("Firestore GPS upload failed (HTTP %d)\n", code);
    if (code == 401) firebaseIdToken = "";
  }
}

// =====================================================
// SETUP
// =====================================================
void setup() {
  Serial.begin(115200);
  delay(500);

  Serial.println();
  Serial.println("SIM808 GPS Tracker Starting");

  // LCD I2C: SDA D2, SCL D1.
  Wire.begin(D2, D1);

  lcd.begin();
  lcd.clear();

  displayGPSLocation();

  if (LittleFS.begin()) {
    const int caCount = firebaseCertStore.initCertStore(
        LittleFS, PSTR("/certs.idx"), PSTR("/certs.ar"));
    firebaseCertStoreReady = caCount > 0;
    Serial.printf("Firebase CA certificates loaded: %d\n", caCount);
  } else {
    Serial.println("LittleFS unavailable; Firebase TLS disabled");
  }

  // SIM808 communicates at 9600 baud.
  sim808.begin(9600);
  delay(2000);

  connectWiFi();

  initializeSIM808();

  if (sim808Available) {
    drawCurrentLCDPage();

    startGPS();

    delay(2000);

    fetchGPS();
    uploadVehicleLocation();
    lastGPSUpload = millis();
  }

  // Fetch only the two LCD counts after an upload, avoiding extra TLS work
  // during Firebase sign-in or while the GPS upload is failing.
  if (cloudStatus == CloudStatus::connected) syncVehicleData();

  lastGPSRequest = millis();
  lastLCDPageSwitch = millis();

  lcdPage = 0;
  drawCurrentLCDPage();
}

// =====================================================
// MAIN LOOP
// =====================================================
void loop() {
  maintainWiFi();
  if (cloudStatus == CloudStatus::connected &&
      millis() - lastSuccessfulGpsUpload > 30000) {
    setCloudStatus(CloudStatus::uploadFailed);
  }
  retrySIM808();
  updateLCDPages();

  if (sim808Available &&
      millis() - lastGPSRequest >=
      GPS_REQUEST_INTERVAL) {
    lastGPSRequest = millis();

    fetchGPS();
    drawCurrentLCDPage();
  }

  if (gpsHasFix && millis() - lastGPSUpload >= GPS_UPLOAD_INTERVAL) {
    lastGPSUpload = millis();
    uploadVehicleLocation();
    updateLCDPages();
  }

  if (cloudStatus == CloudStatus::connected &&
      millis() - lastVehicleSync >= VEHICLE_SYNC_INTERVAL) {
    lastVehicleSync = millis();
    syncVehicleData();
  }

  yield();
}
