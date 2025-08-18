// WebSocket message types
public type MessageData record {
    string messageType;
    string sender?;
    string to?;
    string content?;
    string messageId?;
    string userId?;
};

// User connection info
public type UserConnection record {
    string userId;
    string connectionId;
};