import ballerina/websocket;
import ballerina/http;
import ballerina/log;
import ballerina/uuid;

// Store active WebSocket connections for signaling only
final map<websocket:Caller> activeConnections = {};
final map<string> userConnections = {}; // userId -> connectionId

// WebRTC signaling service (NOT for message relay)
service /signaling on new websocket:Listener(9092) {
    
    resource function get .() returns websocket:Service {
        return new WebRTCSignalingService();
    }
}

// HTTP service for user discovery and health
service /api on new http:Listener(9093) {
    
    resource function get health() returns json {
        return {"status": "healthy", "service": "webrtc-signaling-server"};
    }
    
    resource function get users/[string userId]/status() returns json {
        boolean isOnline = userConnections.hasKey(userId);
        return {"userId": userId, "online": isOnline};
    }
    
    // Get list of online users for discovery
    resource function get users/online() returns json {
        string[] onlineUsers = userConnections.keys();
        return {"onlineUsers": onlineUsers};
    }
}

service class WebRTCSignalingService {
    *websocket:Service;
    
    remote function onOpen(websocket:Caller caller) returns websocket:Error? {
        string connectionId = uuid:createType4AsString();
        activeConnections[connectionId] = caller;
        
        log:printInfo("WebRTC signaling connection opened: " + connectionId);
        
        MessageData welcome = {
            messageType: "signaling_connected",
            messageId: connectionId
        };
        
        check caller->writeMessage(welcome.toJson());
    }
    
    remote function onMessage(websocket:Caller caller, json data) returns websocket:Error? {
        MessageData|error messageData = data.cloneWithType(MessageData);
        
        if messageData is error {
            log:printError("Invalid signaling message", messageData);
            return;
        }
        
        match messageData.messageType {
            "register" => {
                check self.handleUserRegistration(caller, messageData);
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
            // Remove message relay - WebRTC handles direct messaging
            _ => {
                log:printWarn("Unknown signaling message type: " + messageData.messageType);
            }
        }
    }
    
    remote function onClose(websocket:Caller caller, int statusCode, string reason) {
        string? connectionId = self.getConnectionId(caller);
        if connectionId is string {
            _ = activeConnections.remove(connectionId);
            
            // Remove user mapping
            string[] userIds = userConnections.keys();
            foreach string userId in userIds {
                if userConnections[userId] == connectionId {
                    _ = userConnections.remove(userId);
                    log:printInfo("User disconnected from signaling: " + userId);
                    break;
                }
            }
        }
        
        log:printInfo("WebRTC signaling connection closed");
    }
    
    function handleUserRegistration(websocket:Caller caller, MessageData messageData) returns websocket:Error? {
        string? userId = messageData.userId;
        if userId is () {
            log:printError("User registration failed: missing userId");
            return;
        }
        
        string? connectionId = self.getConnectionId(caller);
        if connectionId is () {
            log:printError("User registration failed: connection not found");
            return;
        }
        
        userConnections[userId] = connectionId;
        log:printInfo("User registered for WebRTC signaling: " + userId);
        
        MessageData response = {
            messageType: "registration_success",
            userId: userId
        };
        
        check caller->writeMessage(response.toJson());
    }
    
    // WebRTC Offer - relay to target peer
    function handleWebRTCOffer(websocket:Caller caller, MessageData messageData) returns websocket:Error? {
        string? to = messageData.to;
        string? sender = messageData.sender;
        
        if to is () || sender is () {
            log:printError("WebRTC offer missing to/sender fields");
            return;
        }
        
        string? targetConnectionId = userConnections[to];
        if targetConnectionId is string {
            websocket:Caller? targetCaller = activeConnections[targetConnectionId];
            if targetCaller is websocket:Caller {
                check targetCaller->writeMessage(messageData.toJson());
                log:printInfo("WebRTC offer relayed from " + sender + " to " + to);
            }
        } else {
            log:printWarn("WebRTC offer target user not found: " + to);
        }
    }
    
    // WebRTC Answer - relay to target peer
    function handleWebRTCAnswer(websocket:Caller caller, MessageData messageData) returns websocket:Error? {
        string? to = messageData.to;
        string? sender = messageData.sender;
        
        if to is () || sender is () {
            log:printError("WebRTC answer missing to/sender fields");
            return;
        }
        
        string? targetConnectionId = userConnections[to];
        if targetConnectionId is string {
            websocket:Caller? targetCaller = activeConnections[targetConnectionId];
            if targetCaller is websocket:Caller {
                check targetCaller->writeMessage(messageData.toJson());
                log:printInfo("WebRTC answer relayed from " + sender + " to " + to);
            }
        } else {
            log:printWarn("WebRTC answer target user not found: " + to);
        }
    }
    
    // ICE Candidate - relay to target peer
    function handleWebRTCIceCandidate(websocket:Caller caller, MessageData messageData) returns websocket:Error? {
        string? to = messageData.to;
        string? sender = messageData.sender;
        
        if to is () || sender is () {
            log:printError("ICE candidate missing to/sender fields");
            return;
        }
        
        string? targetConnectionId = userConnections[to];
        if targetConnectionId is string {
            websocket:Caller? targetCaller = activeConnections[targetConnectionId];
            if targetCaller is websocket:Caller {
                check targetCaller->writeMessage(messageData.toJson());
                log:printInfo("ICE candidate relayed from " + sender + " to " + to);
            }
        } else {
            log:printWarn("ICE candidate target user not found: " + to);
        }
    }
    
    function getConnectionId(websocket:Caller caller) returns string? {
        string[] connectionIds = activeConnections.keys();
        foreach string connId in connectionIds {
            websocket:Caller? conn = activeConnections[connId];
            if conn is websocket:Caller && conn === caller {
                return connId;
            }
        }
        return ();
    }
}

public function main() returns error? {
    log:printInfo("Starting WebRTC Signaling Server...");
    log:printInfo("WebRTC signaling: ws://localhost:9092/signaling");
    log:printInfo("HTTP API server: http://localhost:9093/api");
    log:printInfo("This server ONLY handles WebRTC handshake - messages go directly P2P!");
}