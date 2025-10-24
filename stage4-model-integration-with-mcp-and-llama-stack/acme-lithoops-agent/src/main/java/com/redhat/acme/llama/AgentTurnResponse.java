package com.redhat.acme.llama;

import com.fasterxml.jackson.annotation.JsonProperty;
import java.util.List;
import java.util.Map;

/**
 * Response from an agent turn containing the agent's analysis and actions taken
 */
public class AgentTurnResponse {
    
    @JsonProperty("turn_id")
    private String turnId;
    
    @JsonProperty("session_id")
    private String sessionId;
    
    @JsonProperty("message")
    private String message;
    
    @JsonProperty("tool_calls")
    private List<ToolCall> toolCalls;
    
    @JsonProperty("stop_reason")
    private String stopReason;
    
    // Getters and setters
    public String getTurnId() {
        return turnId;
    }
    
    public void setTurnId(String turnId) {
        this.turnId = turnId;
    }
    
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
    
    public List<ToolCall> getToolCalls() {
        return toolCalls;
    }
    
    public void setToolCalls(List<ToolCall> toolCalls) {
        this.toolCalls = toolCalls;
    }
    
    public String getStopReason() {
        return stopReason;
    }
    
    public void setStopReason(String stopReason) {
        this.stopReason = stopReason;
    }
    
    /**
     * Represents a tool that was called during agent execution
     */
    public static class ToolCall {
        @JsonProperty("tool_name")
        private String toolName;
        
        @JsonProperty("arguments")
        private Map<String, Object> arguments;
        
        @JsonProperty("result")
        private Object result;
        
        // Getters and setters
        public String getToolName() {
            return toolName;
        }
        
        public void setToolName(String toolName) {
            this.toolName = toolName;
        }
        
        public Map<String, Object> getArguments() {
            return arguments;
        }
        
        public void setArguments(Map<String, Object> arguments) {
            this.arguments = arguments;
        }
        
        public Object getResult() {
            return result;
        }
        
        public void setResult(Object result) {
            this.result = result;
        }
    }
}

