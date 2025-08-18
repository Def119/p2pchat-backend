// WebRTC signaling message types
public type MessageData record {
    string messageType;
    string sender?;
    string to?;
    string content?;  // For WebRTC SDP offers/answers
    string messageId?;
    string userId?;
    json candidate?;  // For ICE candidates
    json sdp?;        // For SDP offers/answers
};

// User connection info
public type UserConnection record {
    string userId;
    string connectionId;
};