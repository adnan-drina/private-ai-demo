package com.redhat.acme.mcp;

import jakarta.ws.rs.*;
import jakarta.ws.rs.core.MediaType;
import org.eclipse.microprofile.rest.client.inject.RegisterRestClient;
import java.util.Map;

/**
 * REST Client for Slack MCP Server.
 * Uses MCP protocol: single /execute endpoint with tool name and parameters.
 */
@RegisterRestClient(configKey = "slack-mcp")
@Path("/execute")
public interface SlackMcpClient {

    @POST
    @Produces(MediaType.APPLICATION_JSON)
    @Consumes(MediaType.APPLICATION_JSON)
    McpResponse execute(McpRequest request);
    
    /**
     * MCP Request format
     */
    class McpRequest {
        public String tool;
        public Map<String, Object> parameters;
        
        public McpRequest(String tool, Map<String, Object> parameters) {
            this.tool = tool;
            this.parameters = parameters;
        }
    }
    
    /**
     * MCP Response format
     */
    class McpResponse {
        public Map<String, Object> result;
        
        public Map<String, Object> getResult() {
            return result;
        }
        
        public void setResult(Map<String, Object> result) {
            this.result = result;
        }
    }
}


