package com.redhat.acme.api;

import com.redhat.acme.llama.AgentInfo;
import com.redhat.acme.service.CalibrationAgentService;
import jakarta.inject.Inject;
import jakarta.ws.rs.*;
import jakarta.ws.rs.core.MediaType;
import jakarta.ws.rs.core.Response;
import org.jboss.logging.Logger;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Paths;
import java.util.UUID;

/**
 * REST API for ACME Calibration Analysis
 * 
 * Provides endpoints for equipment calibration verification using
 * Llama Stack orchestration with native MCP integration.
 * 
 * Architecture:
 * - Thin REST API layer
 * - Llama Stack handles orchestration
 * - MCP servers for database and Slack
 * - RAG for calibration procedures
 */
@Path("/api/v1")
@Produces(MediaType.APPLICATION_JSON)
@Consumes(MediaType.APPLICATION_JSON)
public class CalibrationResource {

    private static final Logger LOG = Logger.getLogger(CalibrationResource.class);

    @Inject
    CalibrationAgentService agentService;

    /**
     * Health check endpoint - includes agent status
     */
    @GET
    @Path("/health")
    public Response health() {
        boolean agentReady = agentService.isAgentReady();
        String status = agentReady ? "healthy" : "degraded";
        
        return Response.ok(new HealthResponse(
            status,
            "ACME LithoOps Agent",
            agentReady
        )).build();
    }

    /**
     * Execute calibration check with telemetry analysis
     * 
     * POST /api/v1/ops/calibration/check
     * {
     *   "equipment_id": "LITHO-001",
     *   "telemetry_file": "/data/telemetry/acme_telemetry_clean.csv"
     * }
     * 
     * OR with inline data:
     * {
     *   "equipment_id": "LITHO-001",
     *   "telemetry_data": "overlay_accuracy,focus_uniformity\n2.3,0.8\n2.1,0.9"
     * }
     */
    @POST
    @Path("/ops/calibration/check")
    public Response checkCalibration(CalibrationRequest request) {
        long startTime = System.currentTimeMillis();
        String correlationId = UUID.randomUUID().toString();
        
        LOG.infof("📨 [%s] Calibration check: equipment=%s", 
            correlationId, request.equipmentId);

        // Validate request
        if (request.equipmentId == null) {
            return Response.status(400)
                .entity(new ErrorResponse("Missing required field: equipment_id"))
                .build();
        }
        
        if (request.telemetryFile == null && request.telemetryData == null) {
            return Response.status(400)
                .entity(new ErrorResponse("Provide either telemetry_file or telemetry_data"))
                .build();
        }

        try {
            // Load telemetry data
            String telemetryData = request.telemetryData != null 
                ? request.telemetryData
                : loadTelemetryFile(request.telemetryFile);
            
            // Call Llama Stack agent (handles orchestration, tools, RAG)
            String analysis = agentService.analyzeTelemetry(
                request.equipmentId,
                telemetryData
            );
            
            long durationMs = System.currentTimeMillis() - startTime;
            
            // Extract verdict from analysis (simplified heuristic)
            String verdict = extractVerdict(analysis);

            LOG.infof("✅ [%s] Complete: verdict=%s, duration=%dms", 
                correlationId, verdict, durationMs);

            return Response.ok(new CalibrationResponse(
                correlationId,
                request.equipmentId,
                verdict,
                analysis,
                durationMs
            )).build();

        } catch (IOException e) {
            LOG.errorf(e, "❌ [%s] Failed to read telemetry file", correlationId);
            return Response.status(400)
                .entity(new ErrorResponse("Invalid telemetry file: " + e.getMessage()))
                .build();
                
        } catch (Exception e) {
            LOG.errorf(e, "❌ [%s] Failed to process calibration check", correlationId);
            return Response.status(500)
                .entity(new ErrorResponse("Analysis error: " + e.getMessage()))
                .build();
        }
    }
    
    /**
     * Get agent configuration and status
     */
    @GET
    @Path("/agent/info")
    public Response getAgentInfo() {
        try {
            AgentInfo info = agentService.getAgentInfo();
            return Response.ok(info).build();
        } catch (Exception e) {
            LOG.error("Failed to get agent info", e);
            return Response.status(503)
                .entity(new ErrorResponse("Agent not available"))
                .build();
        }
    }

    // Helper methods
    
    private String loadTelemetryFile(String filePath) throws IOException {
        LOG.debugf("Loading telemetry from: %s", filePath);
        return Files.readString(Paths.get(filePath));
    }
    
    private String extractVerdict(String analysis) {
        // Simple heuristic - look for keywords in analysis
        String lowerAnalysis = analysis.toLowerCase();
        
        if (lowerAnalysis.contains("critical") || 
            lowerAnalysis.contains("fail") ||
            lowerAnalysis.contains("exceed")) {
            return "FAIL";
        }
        
        if (lowerAnalysis.contains("warning") || 
            lowerAnalysis.contains("concern") ||
            lowerAnalysis.contains("attention")) {
            return "WARNING";
        }
        
        return "PASS";
    }

    // DTOs
    
    public static class CalibrationRequest {
        public String equipmentId;
        public String telemetryFile;
        public String telemetryData;  // Alternative to file
        
        public CalibrationRequest() {}
    }

    public static class CalibrationResponse {
        public String correlationId;
        public String equipmentId;
        public String verdict;
        public String analysis;
        public long durationMs;

        public CalibrationResponse() {}

        public CalibrationResponse(String correlationId, String equipmentId, 
                                   String verdict, String analysis, long durationMs) {
            this.correlationId = correlationId;
            this.equipmentId = equipmentId;
            this.verdict = verdict;
            this.analysis = analysis;
            this.durationMs = durationMs;
        }
    }

    public static class HealthResponse {
        public String status;
        public String service;
        public boolean agentReady;

        public HealthResponse(String status, String service, boolean agentReady) {
            this.status = status;
            this.service = service;
            this.agentReady = agentReady;
        }
    }

    public static class ErrorResponse {
        public String error;

        public ErrorResponse(String error) {
            this.error = error;
        }
    }
}
