#include <WiFi.h>
#include <PubSubClient.h>
#include <ArduinoJson.h>

// --- WiFi and MQTT Configuration ---
const char* ssid = "your-wifi-ssid";
const char* password = "your-wifi-password";
const char* mqtt_server = "your-mqtt-broker-address";
const int mqtt_port = 1883;

// --- Pin Configuration ---
#define RELAY_PIN      26  
#define FLOW_METER_PIN 25     
#define LED_BUILTIN    2

// --- MQTT Topics ---
#define MQTT_TOPIC_CONTROL "your/control/topic/irrigation"  
#define MQTT_TOPIC_DATA_FLOW "your/data/topic/water-sensor" 
#define MQTT_TOPIC_MOISTURE "your/moisture/topic/"  

// --- Device Identification ---
#define DEVICE_UID "your-unique-device-uid"

// --- YF-S401 Flow Sensor Configuration ---
volatile int pulseCount = 0;                    // Pulse counter
const double pulsesPerLiter = 53293.0;          
double totalLiters = 0.0;                       // Total volume of water passed in liters
double cycleUsage = 0.0;                        // Water used in current irrigation cycle
double flowRate = 0.0;                          // Current flow rate in L/min

// --- Timing Configuration ---
const int PUBLISH_INTERVAL_MS = 5000;           // 5 seconds
unsigned long previousMillis = 0;

// --- State Variables ---
bool isPumpOn = false;
float currentMoisture = 0.0;                   

WiFiClient espClient;
PubSubClient client(espClient);

// --- Interrupt Service Routine for Flow Sensor ---
void IRAM_ATTR pulse() {
  pulseCount++;                               
}

// --- MQTT Callback for Control and Moisture Messages ---
void callback(char* topic, byte* payload, unsigned int length) {
  String message = "";
  for (unsigned int i = 0; i < length; i++) {
    message += (char)payload[i];
  }
  
  // Handle Control Commands
  if (strcmp(topic, MQTT_TOPIC_CONTROL) == 0) {
    Serial.print("--- Command Received: ");
    Serial.print(message);
    Serial.println(" ---");

    if (message == "ON") {
      if (!isPumpOn) {
        Serial.println("Action: Turning pump ON.");
        isPumpOn = true;
        cycleUsage = 0.0;                       // Reset cycle usage when pump turns ON
        digitalWrite(RELAY_PIN, LOW);           // Active LOW relay
        digitalWrite(LED_BUILTIN, HIGH);
        Serial.println("Cycle usage reset to 0.0 L");
      } else {
        Serial.println("Status: Pump was already ON.");
      }
    }
    else if (message == "OFF") {
      if (isPumpOn) {
        Serial.println("Action: Turning pump OFF.");
        Serial.print("Cycle completed. Total cycle usage: ");
        Serial.print(cycleUsage, 2);
        Serial.println(" L");
        isPumpOn = false;
        digitalWrite(RELAY_PIN, HIGH);          // Active LOW relay
        digitalWrite(LED_BUILTIN, LOW);
      } else {
        Serial.println("Status: Pump was already OFF.");
      }
    }
    else if (message == "RESET_CYCLE") {
      Serial.println("Action: Resetting cycle usage counter.");
      cycleUsage = 0.0;
      Serial.println("Cycle usage reset to 0.0 L");
    }
    else {
      Serial.print("Warning: Unknown command '");
      Serial.print(message);
      Serial.println("'");
    }
  }
  
  // Handle Moisture Data from Other Group
  else if (strcmp(topic, MQTT_TOPIC_MOISTURE) == 0) {
    StaticJsonDocument<200> doc;
    DeserializationError error = deserializeJson(doc, message);
    
    if (!error) {
      if (doc.containsKey("moisture")) {
        currentMoisture = doc["moisture"];
        Serial.print("Moisture updated from JSON: ");
        Serial.print(currentMoisture);
        Serial.println("%");
      }
    } else {
      float moistureValue = message.toFloat();
      if (moistureValue >= 0 && moistureValue <= 100) {
        currentMoisture = moistureValue;
        Serial.print("Moisture updated: ");
        Serial.print(currentMoisture);
        Serial.println("%");
      } else {
        Serial.print("Warning: Invalid moisture value received: ");
        Serial.println(message);
      }
    }
  }
}

// --- MQTT Connection/Reconnection ---
void reconnect() {
  while (!client.connected()) {
    Serial.print("Attempting MQTT connection...");
    
    String clientId = "ESP32_Irrigation_";
    clientId += String(random(0xffff), HEX);
    
    if (client.connect(clientId.c_str())) {
      Serial.println("connected!");
      
      client.subscribe(MQTT_TOPIC_CONTROL);
      Serial.print("Subscribed to control topic: ");
      Serial.println(MQTT_TOPIC_CONTROL);
      
      client.subscribe(MQTT_TOPIC_MOISTURE);
      Serial.print("Subscribed to moisture topic: ");
      Serial.println(MQTT_TOPIC_MOISTURE);
    } else {
      Serial.print("failed, rc=");
      Serial.print(client.state());
      Serial.println(" retrying in 5 seconds...");
      delay(5000);
    }
  }
}

// --- Setup ---
void setup() {
  Serial.begin(115200);
  
  // Pin initialization
  pinMode(RELAY_PIN, OUTPUT);
  pinMode(FLOW_METER_PIN, INPUT);               // Flow sensor input
  pinMode(LED_BUILTIN, OUTPUT);
  
  // Initialize pump OFF
  digitalWrite(RELAY_PIN, HIGH);                // Active LOW relay - pump OFF
  digitalWrite(LED_BUILTIN, LOW);
  
  // Attach interrupt for flow sensor (RISING edge like Lucienne's code)
  attachInterrupt(digitalPinToInterrupt(FLOW_METER_PIN), pulse, RISING);
  
  // Connect to WiFi
  Serial.println();
  Serial.println("--- ESP32 Irrigation Controller (YF-S401) ---");
  Serial.print("--- Device UID: ");
  Serial.print(DEVICE_UID);
  Serial.println(" ---");
  Serial.print("Connecting to WiFi: ");
  Serial.println(ssid);

  WiFi.begin(ssid, password);

  while (WiFi.status() != WL_CONNECTED) {
    delay(500);
    Serial.print(".");
  }

  Serial.println();
  Serial.println("WiFi connected!");
  Serial.print("IP address: ");
  Serial.println(WiFi.localIP());

  // Setup MQTT
  client.setServer(mqtt_server, mqtt_port);
  client.setCallback(callback);
  
  Serial.println("Device ready and listening for commands.");
  Serial.println("Flow sensor: YF-S401 with 5880 pulses/liter");
  Serial.println("Waiting for moisture data from other group...");
  Serial.println();
}

// --- Main Loop ---
void loop() {
  // Maintain MQTT connection
  if (!client.connected()) {
    reconnect();
  }
  client.loop();

  // Publish data at regular intervals (5 seconds)
  unsigned long currentMillis = millis();
  if (currentMillis - previousMillis >= PUBLISH_INTERVAL_MS) {
    previousMillis = currentMillis;

    // --- Calculate Flow Rate (Using Lucienne's Method) ---
    int pulsesInInterval = pulseCount;
    pulseCount = 0;                             // Reset pulse count

    // Calculate liters for this interval
    double litersInInterval = pulsesInInterval / pulsesPerLiter;
    
    // Calculate flow rate in L/min
    double intervalSeconds = PUBLISH_INTERVAL_MS / 1000.0;
    flowRate = (litersInInterval / intervalSeconds) * 60.0;
    
    // Add to total and cycle usage only if pump is ON
    if (isPumpOn) {
      totalLiters += litersInInterval;
      cycleUsage += litersInInterval;           // Track current cycle usage
    }

    // --- Debug Output ---
    Serial.print("Pulses: ");
    Serial.print(pulsesInInterval);
    Serial.print(" | Flow Rate: ");
    Serial.print(flowRate, 2);
    Serial.print(" L/min | Total: ");
    Serial.print(totalLiters, 2);
    Serial.print(" L | Cycle: ");
    Serial.print(cycleUsage, 2);
    Serial.println(" L");

    // --- Construct JSON Payload ---
    StaticJsonDocument<300> doc;                
    doc["device_uid"] = DEVICE_UID;
    doc["moisture"] = round(currentMoisture * 100) / 100.0;
    doc["flow_rate"] = round(flowRate * 100) / 100.0;
    doc["total_flow"] = round(totalLiters * 100) / 100.0;
    doc["cycle_usage"] = round(cycleUsage * 100) / 100.0;  
    doc["pump_status"] = isPumpOn ? "ON" : "OFF";

    String payload;
    serializeJson(doc, payload);

    // --- Publish to MQTT ---
    if (client.connected()) {
      client.publish(MQTT_TOPIC_DATA_FLOW, payload.c_str());
      Serial.print("-> MQTT Published: ");
      Serial.println(payload);
    } else {
      Serial.println("-> MQTT not connected, skipping publish");
    }
    
    Serial.println();
  }
}