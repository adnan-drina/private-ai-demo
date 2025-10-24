package com.redhat.acme.service;

import com.redhat.acme.agent.CalibrationAgent;
import com.redhat.acme.tools.CalibrationTools;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.inject.Inject;
import org.jboss.logging.Logger;

import java.util.UUID;

/**
 * Orchestrates calibration check workflows.
 * Coordinates between the AI agent, tools, and report generation.
 * 
 * NOTE: We call tools manually instead of using LangChain4j's automatic tool calling
 * because vLLM doesn't support the full OpenAI tool calling protocol (it rejects
 * messages with "tool" or "function" roles).
 */
@ApplicationScoped
public class CalibrationOrchestrator {

    private static final Logger LOG = Logger.getLogger(CalibrationOrchestrator.class);

    @Inject
    CalibrationAgent agent;
    
    @Inject
    CalibrationTools tools;

    /**
     * Execute calibration check workflow.
     * 
     * @param equipmentId Equipment identifier (e.g., "LITHO-001")
     * @param telemetryFile Path to telemetry CSV file
     * @return Calibration analysis result with verdict and recommendations
     */
    public CalibrationResult checkCalibration(String equipmentId, String telemetryFile) {
        String correlationId = UUID.randomUUID().toString().substring(0, 8);
        LOG.infof("🔬 [%s] Starting calibration check: equipment=%s, file=%s", 
            correlationId, equipmentId, telemetryFile);

        long startTime = System.currentTimeMillis();

        try {
            // Step 1: Gather all data by calling tools manually
            LOG.infof("[%s] 📊 Gathering data...", correlationId);
            
            String equipmentInfo = tools.getEquipmentInfo(equipmentId);
            LOG.infof("[%s] ✅ Got equipment info", correlationId);
            
            String calibrationLimits = tools.getCalibrationLimits(equipmentId, "overlay_accuracy");
            LOG.infof("[%s] ✅ Got calibration limits from RAG", correlationId);
            
            String telemetryData = tools.readTelemetryData(telemetryFile);
            LOG.infof("[%s] ✅ Read telemetry data", correlationId);

            // Step 2: Construct prompt with all gathered data
            String prompt = String.format("""
                CALIBRATION ANALYSIS REQUEST
                Correlation ID: %s
                
                You are analyzing equipment calibration data. Review the information below and provide your analysis.
                
                ## EQUIPMENT INFORMATION
                %s
                
                ## CALIBRATION LIMITS (from ACME documentation)
                %s
                
                ## TELEMETRY DATA
                %s
                
                ## YOUR TASK
                1. Analyze if ALL telemetry measurements are within the calibration limits
                2. Consider a 5-10%% safety margin
                3. Determine PASS or FAIL verdict
                4. Provide clear, actionable recommendations
                
                ## RESPONSE FORMAT
                Provide your analysis in this format:
                
                VERDICT: [PASS or FAIL]
                
                ANALYSIS:
                - Key findings from the data
                - Specific measurements that are in/out of spec
                - Safety margin considerations
                
                RECOMMENDATIONS:
                - What actions should be taken
                - Timeline/urgency
                
                Begin your analysis now.
                """,
                correlationId,
                equipmentInfo,
                calibrationLimits,
                telemetryData
            );

            // Step 3: Get AI analysis
            LOG.infof("[%s] 🤖 Sending to LLM for analysis...", correlationId);
            String analysis = agent.analyzeCalibration(prompt);

            // Step 4: Determine verdict and send notifications
            String verdict;
            if (analysis.toUpperCase().contains("VERDICT: PASS") ||
                analysis.toUpperCase().contains("VERDICT:PASS")) {
                verdict = "PASS";
                String message = String.format("✅ Equipment %s passed calibration check (ID: %s)", 
                    equipmentId, correlationId);
                tools.sendSlackNotification(message);
                LOG.infof("[%s] ✅ PASS - Sent Slack notification", correlationId);
            } else {
                verdict = "FAIL";
                String alertMessage = String.format("Equipment %s failed calibration check. Review required. Correlation ID: %s", 
                    equipmentId, correlationId);
                tools.sendEquipmentAlert(equipmentId, "high", alertMessage);
                LOG.infof("[%s] ❌ FAIL - Sent equipment alert", correlationId);
            }

            long duration = System.currentTimeMillis() - startTime;
            LOG.infof("✅ [%s] Calibration check complete: %s (%dms)", correlationId, verdict, duration);

            return new CalibrationResult(
                correlationId,
                equipmentId,
                telemetryFile,
                verdict,
                analysis,
                duration
            );

        } catch (Exception e) {
            LOG.errorf(e, "❌ [%s] Calibration check failed", correlationId);
            long duration = System.currentTimeMillis() - startTime;
            
            return new CalibrationResult(
                correlationId,
                equipmentId,
                telemetryFile,
                "ERROR",
                "Failed to complete calibration check: " + e.getMessage(),
                duration
            );
        }
    }

    /**
     * Result of a calibration check.
     */
    public static class CalibrationResult {
        public String correlationId;
        public String equipmentId;
        public String telemetryFile;
        public String verdict; // PASS, FAIL, ERROR
        public String analysis;
        public long durationMs;

        public CalibrationResult(String correlationId, String equipmentId, String telemetryFile,
                                 String verdict, String analysis, long durationMs) {
            this.correlationId = correlationId;
            this.equipmentId = equipmentId;
            this.telemetryFile = telemetryFile;
            this.verdict = verdict;
            this.analysis = analysis;
            this.durationMs = durationMs;
        }
    }
}


