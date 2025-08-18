import ballerina/websocket;
import ballerina/http;
import ballerina/log;
import ballerina/uuid;

// Store active WebSocket connections
final map<websocket:Caller> activeConnections = {};
final map<string> userConnections = {}; // userId -> connectionId

// WebSocket service for signaling
service /signaling on new websocket:Listener(9090) {
    
    resource isolated function get .() returns websocket:Service {
        return new SignalingService();
    }
}

// HTTP service for health check and API endpoints
service /api on new http:Listener(9091) {
    
    resource function get health() returns json {
        return {"status": "healthy", "service": "signaling-server"};
    }
    
    // Get user status
    resource function get users/[string userId]/status() returns json {
        boolean isOnline = userConnections.hasKey(userId);
        return {"userId": userId, "online": isOnline};
    }
}

// WebSocket service class
service class SignalingService {
    *websocket:Service;
    
    remote function onOpen(websocket:Caller caller) returns websocket:Error? {
        string connectionId = uuid:createType4AsString();
        activeConnections[connectionId] = caller;
        
        log:printInfo("WebSocket connection opened: " + connectionId);
        
        // Send connection ID to client
        MessageData welcome = {
            messageType: "connection_established",
            messageId: connectionId
        };
        
        check caller->writeMessage(welcome.toJson());
    }
    
    remote function onMessage(websocket:Caller caller, json data) returns websocket:Error? {
        MessageData|error messageData = data.cloneWithType(MessageData);
        
        if messageData is error {
            log:printError("Invalid message format", messageData);
            return;
        }
        
        match messageData.messageType {
            "register" => {
                check self.handleUserRegistration(caller, messageData);
            }
            "send_message" => {
                check self.handleSendMessage(caller, messageData);
            }
            "webrtc_offer" => {
                check self.handleWebRTCOffer(caller, messageData);
            }
            "webrtc_answer" => {
                check self.handleWebRTCAnswer(caller, messageData);
            }
            "webrtc_ice_candidate" => {
                check self.handleWebRTCIceCandidate(caller, messageData);
            }
        }
    }
    
    remote function onClose(websocket:Caller caller, int statusCode, string reason) {
        // Find and remove user connection
        string? connectionId = self.getConnectionId(caller);
        if connectionId is string {
            _ = activeConnections.remove(connectionId);
            
            // Remove user mapping
            string[] userIds = userConnections.keys();
            foreach string userId in userIds {
                if userConnections[userId] == connectionId {
                    _ = userConnections.remove(userId);
                    log:printInfo("User disconnected: " + userId);
                    break;
                }
            }
        }
        
        log:printInfo("WebSocket connection closed");
    }
    
    // Handle user registration
    function handleUserRegistration(websocket:Caller caller, MessageData messageData) returns websocket:Error? {
        string? userId = messageData.userId;
        if userId is () {
            return;
        }
        
        string? connectionId = self.getConnectionId(caller);
        if connectionId is () {
            return;
        }
        
        userConnections[userId] = connectionId;
        log:printInfo("User registered: " + userId);
        
        // Confirm registration
        MessageData response = {
            messageType: "registration_confirmed",
            userId: userId
        };
        
        check caller->writeMessage(response.toJson());
    }
    
    // Handle message sending
    function handleSendMessage(websocket:Caller caller, MessageData messageData) returns websocket:Error? {
        anydata? toData = messageData["to"];
        anydata? senderData = messageData["sender"];
        anydata? contentData = messageData["content"];
        anydata? messageIdData = messageData["messageId"];
        
        if toData is () || senderData is () || contentData is () || messageIdData is () {
            return;
        }
        
        string to = toData.toString();
        string sender = senderData.toString();
        string content = contentData.toString();
        string messageId = messageIdData.toString();
        
        // Check if target user is online
        string? targetConnectionId = userConnections[to];
        
        if targetConnectionId is string {
            // User is online - send directly
            websocket:Caller? targetCaller = activeConnections[targetConnectionId];
            if targetCaller is websocket:Caller {
                MessageData forwardMessage = {
                    messageType: "receive_message",
                    sender: sender,
                    content: content,
                    messageId: messageId
                };
                
                check targetCaller->writeMessage(forwardMessage.toJson());
                log:printInfo("Message delivered to online user: " + to);
            }
        } else {
            // User is offline - log for now (MongoDB will be added later)
            log:printInfo("Message would be stored for offline user: " + to + " (from: " + sender + ")");
        }
    }
    
    // Handle WebRTC offer
    function handleWebRTCOffer(websocket:Caller caller, MessageData messageData) returns websocket:Error? {
        string? to = messageData.to;
        if to is () {
            return;
        }
        
        string? targetConnectionId = userConnections[to];
        if targetConnectionId is string {
            websocket:Caller? targetCaller = activeConnections[targetConnectionId];
            if targetCaller is websocket:Caller {
                check targetCaller->writeMessage(messageData.toJson());
            }
        }
    }
    
    // Handle WebRTC answer
    function handleWebRTCAnswer(websocket:Caller caller, MessageData messageData) returns websocket:Error? {
        string? to = messageData.to;
        if to is () {
            return;
        }
        
        string? targetConnectionId = userConnections[to];
        if targetConnectionId is string {
            websocket:Caller? targetCaller = activeConnections[targetConnectionId];
            if targetCaller is websocket:Caller {
                check targetCaller->writeMessage(messageData.toJson());
            }
        }
    }
    
    // Handle WebRTC ICE candidate
    function handleWebRTCIceCandidate(websocket:Caller caller, MessageData messageData) returns websocket:Error? {
        string? to = messageData.to;
        if to is () {
            return;
        }
        
        string? targetConnectionId = userConnections[to];
        if targetConnectionId is string {
            websocket:Caller? targetCaller = activeConnections[targetConnectionId];
            if targetCaller is websocket:Caller {
                check targetCaller->writeMessage(messageData.toJson());
            }
        }
    }
    
    // Helper function to get connection ID
    function getConnectionId(websocket:Caller caller) returns string? {
        string[] connectionIds = activeConnections.keys();
        foreach string connId in connectionIds {
            if activeConnections[connId] === caller {
                return connId;
            }
        }
        return ();
    }
}

public function main() returns error? {
    log:printInfo("Starting P2P Chat Signaling Server...");
    log:printInfo("WebSocket server: ws://localhost:9090/signaling");
    log:printInfo("HTTP API server: http://localhost:9091/api");
}