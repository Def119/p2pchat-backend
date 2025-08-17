import ballerina/websocket;
import ballerina/log;
import ballerina/time;
import ballerinax/mongodb;

// Configuration
configurable string mongoHost = "localhost";
configurable int mongoPort = 27017;
configurable string mongoDatabase = "chat_db";
configurable int serverPort = 9090;

// Global peers map
map<websocket:Caller> peers = {};

// Message types that should be stored offline
final readonly & string[] STORABLE_MESSAGE_TYPES = ["chat-message", "file-share", "call-request", "voice-note"];

// Offline message record type
type OfflineMessage record {|
    string sender;
    string target;
    string messageType;
    json content;
    string timestamp;
    boolean delivered;
|};

service /signaling on new websocket:Listener(serverPort) {

    // Initialize MongoDB connection inside service
    private mongodb:Client mongoClient;
    private mongodb:Database chatDb;
    private mongodb:Collection offlineMessagesCollection;
    
    function init() returns error? {
        // Initialize MongoDB inside the service
        self.mongoClient = check new ({
            connection: {
                serverAddress: {
                    host: mongoHost,
                    port: mongoPort
                }
            }
        });
        
        self.chatDb = check self.mongoClient->getDatabase(mongoDatabase);
        self.offlineMessagesCollection = check self.chatDb->getCollection("offline_messages");
        
        log:printInfo("MongoDB initialized successfully");
    }

    // When a client connects: ws://localhost:9090/signaling?username=Alice
    resource function get ws(websocket:Caller caller, string username) returns websocket:Service|error {
        log:printInfo("New peer connected: " + username);
        peers[username] = caller;
        
        // Deliver any pending offline messages
        error? deliveryResult = self.deliverOfflineMessages(username, caller);
        if deliveryResult is error {
            log:printError("Error delivering offline messages to " + username + ": " + deliveryResult.message());
        }
        
        return new ChatService(username, self.offlineMessagesCollection);
    }
    
    // Function to deliver offline messages when user comes online
    function deliverOfflineMessages(string username, websocket:Caller caller) returns error? {
        // Find all undelivered messages for this user
        map<json> filter = {"target": username, "delivered": false};
        
        stream<OfflineMessage, error?> messageStream = check self.offlineMessagesCollection->find(filter);
        
        int deliveredCount = 0;
        check from OfflineMessage message in messageStream
            do {
                // Create offline message wrapper
                json offlineMsg = {
                    "type": "offline-message",
                    "originalType": message.messageType,
                    "sender": message.sender,
                    "target": message.target,
                    "content": message.content,
                    "timestamp": message.timestamp
                };
                
                // Send to the user
                error? sendResult = caller->writeTextMessage(offlineMsg.toString());
                if sendResult is error {
                    log:printError("Failed to send offline message: " + sendResult.message());
                } else {
                    // Mark as delivered - FIX 1: Use proper Update type
                    map<json> updateFilter = {
                        "sender": message.sender, 
                        "target": message.target, 
                        "timestamp": message.timestamp
                    };
                    mongodb:Update updateDoc = {"$set": {"delivered": true}};
                    _ = check self.offlineMessagesCollection->updateOne(updateFilter, updateDoc);
                    deliveredCount += 1;
                }
            };
        
        check messageStream.close();
        log:printInfo("Delivered " + deliveredCount.toString() + " offline messages to " + username);
    }
}

service class ChatService {
    *websocket:Service;
    
    private string username;
    private mongodb:Collection offlineMessagesCollection;
    
    function init(string username, mongodb:Collection offlineMessagesCollection) {
        self.username = username;
        self.offlineMessagesCollection = offlineMessagesCollection;
    }

    // This resource triggers when a client sends a text message
    remote function onTextMessage(websocket:Caller caller, string text) returns error? {
        do {
            json msg = check text.fromJsonString();
            
            // Safely extract required fields
            json|error targetField = msg.target;
            json|error typeField = msg.'type;
            
            if targetField is error {
                log:printError("Missing 'target' field in message");
                return;
            }
            
            string target = targetField.toString();
            string messageType = "";
            
            if typeField is json {
                messageType = typeField.toString();
            }

            // Check if target is online
            if peers.hasKey(target) {
                websocket:Caller? targetCaller = peers[target];
                if targetCaller is websocket:Caller {
                    // Target is online - deliver immediately
                    check targetCaller->writeTextMessage(text);
                    log:printInfo("Message forwarded from " + self.username + " to " + target);
                } else {
                    // Target caller is null - store for offline delivery
                    check self.handleOfflineMessage(target, messageType, msg);
                }
            } else {
                // Target is offline - store for offline delivery
                check self.handleOfflineMessage(target, messageType, msg);
            }
        } on fail error e {
            log:printError("Error processing message: " + e.message());
        }
    }
    
    // Handle offline message storage
    function handleOfflineMessage(string target, string messageType, json originalMessage) returns error? {
        // Only store certain types of messages offline
        if STORABLE_MESSAGE_TYPES.indexOf(messageType) != () {
            check self.storeOfflineMessage(target, messageType, originalMessage);
            
            // Send acknowledgment back to sender
            json ackMsg = {
                "type": "message-stored",
                "target": target,
                "status": "offline",
                "message": "Message will be delivered when " + target + " comes online"
            };
            
            // FIX 2: Properly handle the nullable websocket:Caller
            websocket:Caller? senderCaller = peers[self.username];
            if senderCaller is websocket:Caller {
                error? ackResult = senderCaller->writeTextMessage(ackMsg.toString());
                if ackResult is error {
                    log:printError("Failed to send acknowledgment: " + ackResult.message());
                }
            } else {
                log:printWarn("Sender " + self.username + " is no longer connected to send acknowledgment");
            }
        } else {
            log:printWarn("Message type '" + messageType + "' not stored offline. Target peer not found: " + target);
        }
    }
    
    // Function to store message for offline delivery
    function storeOfflineMessage(string target, string messageType, json content) returns error? {
        OfflineMessage offlineMessage = {
            sender: self.username,
            target: target,
            messageType: messageType,
            content: content,
            timestamp: time:utcToString(time:utcNow()),
            delivered: false
        };
        
        _ = check self.offlineMessagesCollection->insertOne(offlineMessage);
        log:printInfo("Stored offline message from " + self.username + " to " + target);
    }

    // Handle client disconnection
    remote function onClose(websocket:Caller caller, int statusCode, string reason) returns error? {
        log:printInfo("Peer disconnected: " + self.username + " (Code: " + statusCode.toString() + ", Reason: " + reason + ")");
        _ = peers.remove(self.username);
    }

    // Handle errors
    remote function onError(websocket:Caller caller, error err) {
        log:printError("WebSocket error for " + self.username + ": " + err.message());
    }
}

public function main() returns error? {
    log:printInfo("Starting signaling server with MongoDB backend...");
    log:printInfo("Server will listen on port " + serverPort.toString());
}