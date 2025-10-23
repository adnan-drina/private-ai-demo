package com.redhat.acme.llama;

import jakarta.ws.rs.*;
import jakarta.ws.rs.core.MediaType;
import org.eclipse.microprofile.rest.client.inject.RegisterRestClient;

/**
 * REST Client for Llama Stack Agent API
 * 
 * This client provides direct access to the Llama Stack orchestrator,
 * which handles:
 * - Agent orchestration
 * - Multi-model inference routing
 * - MCP tool selection and execution
 * - RAG integration
 */
@RegisterRestClient(configKey = "llama-stack")
@Path("/agents")
@Produces(MediaType.APPLICATION_JSON)
@Consumes(MediaType.APPLICATION_JSON)
public interface LlamaStackClient {
    
    /**
     * Create a new conversation turn with the agent
     * 
     * @param agentId The agent identifier (e.g., "acme-calibration-agent")
     * @param request The turn request with user message
     * @return The agent's response with tool calls and final message
     */
    @POST
    @Path("/{agentId}/turn")
    AgentTurnResponse createTurn(
        @PathParam("agentId") String agentId,
        AgentTurnRequest request
    );
    
    /**
     * Get agent information and configuration
     * 
     * @param agentId The agent identifier
     * @return Agent configuration details
     */
    @GET
    @Path("/{agentId}")
    AgentInfo getAgent(@PathParam("agentId") String agentId);
    
    /**
     * List all available agents
     * 
     * @return List of agent configurations
     */
    @GET
    AgentListResponse listAgents();
}

