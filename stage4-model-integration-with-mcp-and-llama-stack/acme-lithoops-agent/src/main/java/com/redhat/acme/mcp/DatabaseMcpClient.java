package com.redhat.acme.mcp;

import jakarta.ws.rs.*;
import jakarta.ws.rs.core.MediaType;
import org.eclipse.microprofile.rest.client.inject.RegisterRestClient;

/**
 * REST Client for Database MCP Server.
 * Uses MCP protocol: single /execute endpoint with tool name and parameters.
 */
@RegisterRestClient(configKey = "database-mcp")
@Path("/execute")
public interface DatabaseMcpClient {

    @POST
    @Produces(MediaType.APPLICATION_JSON)
    @Consumes(MediaType.APPLICATION_JSON)
    McpResponse execute(McpRequest request);
    
    /**
     * MCP Request format
     */
    class McpRequest {
        public String tool;
        public java.util.Map<String, Object> parameters;
        
        public McpRequest(String tool, java.util.Map<String, Object> parameters) {
            this.tool = tool;
            this.parameters = parameters;
        }
    }
    
    /**
     * MCP Response format
     */
    class McpResponse {
        public java.util.Map<String, Object> result;
        
        public java.util.Map<String, Object> getResult() {
            return result;
        }
        
        public void setResult(java.util.Map<String, Object> result) {
            this.result = result;
        }
    }
}


