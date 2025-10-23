package com.redhat.acme.llama;

import com.fasterxml.jackson.annotation.JsonProperty;
import java.util.List;
import java.util.Map;

/**
 * Request to create a new agent turn (conversation step)
 */
public class AgentTurnRequest {
    
    @JsonProperty("session_id")
    private String sessionId;
    
    @JsonProperty("message")
    private String message;
    
    @JsonProperty("attachments")
    private List<Map<String, Object>> attachments;
    
    @JsonProperty("stream")
    private boolean stream = false;
    
    // Constructors
    public AgentTurnRequest() {}
    
    public AgentTurnRequest(String sessionId, String message) {
        this.sessionId = sessionId;
        this.message = message;
    }
    
    // Getters and setters
    public String getSessionId() {
        return sessionId;
    }
    
    public void setSessionId(String sessionId) {
        this.sessionId = sessionId;
    }
    
    public String getMessage() {
        return message;
    }
    
    public void setMessage(String message) {
        this.message = message;
    }
    
    public List<Map<String, Object>> getAttachments() {
        return attachments;
    }
    
    public void setAttachments(List<Map<String, Object>> attachments) {
        this.attachments = attachments;
    }
    
    public boolean isStream() {
        return stream;
    }
    
    public void setStream(boolean stream) {
        this.stream = stream;
    }
    
    // Fluent API
    public AgentTurnRequest withSessionId(String sessionId) {
        this.sessionId = sessionId;
        return this;
    }
    
    public AgentTurnRequest withMessage(String message) {
        this.message = message;
        return this;
    }
    
    public AgentTurnRequest withAttachments(List<Map<String, Object>> attachments) {
        this.attachments = attachments;
        return this;
    }
}

