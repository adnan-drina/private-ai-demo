package com.redhat.acme.llama;

import com.fasterxml.jackson.annotation.JsonProperty;
import java.util.List;

/**
 * Agent configuration and metadata
 */
public class AgentInfo {
    
    @JsonProperty("agent_id")
    private String agentId;
    
    @JsonProperty("model")
    private String model;
    
    @JsonProperty("instructions")
    private String instructions;
    
    @JsonProperty("tools")
    private List<String> tools;
    
    @JsonProperty("sampling_params")
    private SamplingParams samplingParams;
    
    // Getters and setters
    public String getAgentId() {
        return agentId;
    }
    
    public void setAgentId(String agentId) {
        this.agentId = agentId;
    }
    
    public String getModel() {
        return model;
    }
    
    public void setModel(String model) {
        this.model = model;
    }
    
    public String getInstructions() {
        return instructions;
    }
    
    public void setInstructions(String instructions) {
        this.instructions = instructions;
    }
    
    public List<String> getTools() {
        return tools;
    }
    
    public void setTools(List<String> tools) {
        this.tools = tools;
    }
    
    public SamplingParams getSamplingParams() {
        return samplingParams;
    }
    
    public void setSamplingParams(SamplingParams samplingParams) {
        this.samplingParams = samplingParams;
    }
    
    /**
     * Model sampling parameters
     */
    public static class SamplingParams {
        @JsonProperty("temperature")
        private double temperature;
        
        @JsonProperty("top_p")
        private double topP;
        
        @JsonProperty("max_tokens")
        private int maxTokens;
        
        // Getters and setters
        public double getTemperature() {
            return temperature;
        }
        
        public void setTemperature(double temperature) {
            this.temperature = temperature;
        }
        
        public double getTopP() {
            return topP;
        }
        
        public void setTopP(double topP) {
            this.topP = topP;
        }
        
        public int getMaxTokens() {
            return maxTokens;
        }
        
        public void setMaxTokens(int maxTokens) {
            this.maxTokens = maxTokens;
        }
    }
}

