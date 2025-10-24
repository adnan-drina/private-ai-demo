package com.redhat.acme.service;

import com.redhat.acme.llama.*;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.inject.Inject;
import org.eclipse.microprofile.config.inject.ConfigProperty;
import org.eclipse.microprofile.rest.client.inject.RestClient;
import org.jboss.logging.Logger;

import java.util.UUID;

/**
 * Simplified Calibration Agent Service
 * 
 * This service provides a thin wrapper around the Llama Stack Agent API.
 * All orchestration, tool selection, and execution is handled by Llama Stack.
 * 
 * Responsibilities:
 * - Format telemetry data into appropriate prompts
 * - Call Llama Stack agent API
 * - Handle responses and errors
 * 
 * NOT responsible for:
 * - Tool routing (handled by Llama Stack)
 * - Model selection (handled by Llama Stack)
 * - MCP integration (handled by Llama Stack)
 */
@ApplicationScoped
public class CalibrationAgentService {
    
    private static final Logger LOG = Logger.getLogger(CalibrationAgentService.class);
    
    @Inject
    @RestClient
    LlamaStackClient llamaStackClient;
    
    @ConfigProperty(name = "acme.agent.id")
    String agentId;
    
    @ConfigProperty(name = "acme.agent.enable-tools", defaultValue = "true")
    boolean enableTools;
    
    /**
     * Analyze equipment telemetry data and provide calibration recommendations
     * 
     * @param equipmentId The equipment identifier
     * @param telemetryData Raw telemetry data
     * @return Agent's analysis and recommendations
     */
    public String analyzeTelemetry(String equipmentId, String telemetryData) {
        LOG.infof("Analyzing telemetry for equipment: %s", equipmentId);
        
        try {
            // Format the prompt for the agent
            String prompt = formatTelemetryPrompt(equipmentId, telemetryData);
            
            // Create agent turn request
            AgentTurnRequest request = new AgentTurnRequest()
                .withSessionId(generateSessionId(equipmentId))
                .withMessage(prompt);
            
            // Call Llama Stack Agent API
            LOG.debug("Calling Llama Stack agent API...");
            AgentTurnResponse response = llamaStackClient.createTurn(agentId, request);
            
            // Log tool calls for observability
            if (response.getToolCalls() != null && !response.getToolCalls().isEmpty()) {
                LOG.infof("Agent executed %d tools:", response.getToolCalls().size());
                for (AgentTurnResponse.ToolCall toolCall : response.getToolCalls()) {
                    LOG.infof("  - %s", toolCall.getToolName());
                }
            }
            
            LOG.infof("Analysis complete for %s", equipmentId);
            return response.getMessage();
            
        } catch (Exception e) {
            LOG.errorf(e, "Failed to analyze telemetry for %s", equipmentId);
            return formatErrorResponse(equipmentId, e);
        }
    }
    
    /**
     * Get agent status and configuration
     * 
     * @return Agent information
     */
    public AgentInfo getAgentInfo() {
        try {
            return llamaStackClient.getAgent(agentId);
        } catch (Exception e) {
            LOG.error("Failed to get agent info", e);
            throw new RuntimeException("Agent not available", e);
        }
    }
    
    /**
     * Check if agent is healthy and ready
     * 
     * @return true if agent is ready
     */
    public boolean isAgentReady() {
        try {
            AgentInfo info = getAgentInfo();
            return info != null && info.getAgentId() != null;
        } catch (Exception e) {
            LOG.warn("Agent health check failed", e);
            return false;
        }
    }
    
    /**
     * Format telemetry data into a structured prompt for the agent
     */
    private String formatTelemetryPrompt(String equipmentId, String telemetryData) {
        return String.format("""
            Analyze the following equipment telemetry data:
            
            Equipment ID: %s
            Telemetry Data:
            %s
            
            Tasks:
            1. Check the equipment database for specifications and maintenance history
            2. Compare current readings against calibration standards
            3. Search calibration procedures if issues are detected
            4. Provide specific recommendations based on the data
            5. Alert the engineering team via Slack if critical issues require immediate attention
            
            Provide a structured analysis with:
            - Current status assessment
            - Identified issues (if any)
            - Recommended actions
            - Priority level (Normal, Warning, Critical)
            """,
            equipmentId,
            telemetryData
        );
    }
    
    /**
     * Generate a unique session ID for tracking conversations
     */
    private String generateSessionId(String equipmentId) {
        return String.format("acme-%s-%s", 
            equipmentId.toLowerCase().replace("_", "-"),
            UUID.randomUUID().toString().substring(0, 8)
        );
    }
    
    /**
     * Format error response for user consumption
     */
    private String formatErrorResponse(String equipmentId, Exception e) {
        return String.format("""
            ⚠️ Analysis Error for %s
            
            Unable to complete telemetry analysis due to a technical error.
            
            Error: %s
            
            Please check:
            1. Llama Stack service is running
            2. Agent 'acme-calibration-agent' is registered
            3. Network connectivity to Llama Stack
            4. MCP servers (database, slack) are available
            
            For immediate assistance, contact the platform team.
            """,
            equipmentId,
            e.getMessage()
        );
    }
}

