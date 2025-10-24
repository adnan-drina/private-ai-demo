package com.redhat.acme.llama;

import com.fasterxml.jackson.annotation.JsonProperty;
import java.util.List;

/**
 * Response containing list of available agents
 */
public class AgentListResponse {
    
    @JsonProperty("agents")
    private List<AgentInfo> agents;
    
    // Constructor
    public AgentListResponse() {}
    
    public AgentListResponse(List<AgentInfo> agents) {
        this.agents = agents;
    }
    
    // Getters and setters
    public List<AgentInfo> getAgents() {
        return agents;
    }
    
    public void setAgents(List<AgentInfo> agents) {
        this.agents = agents;
    }
}

