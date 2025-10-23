package com.redhat.acme.agent;

import dev.langchain4j.service.SystemMessage;
import io.quarkiverse.langchain4j.RegisterAiService;
import io.quarkiverse.langchain4j.ToolBox;
import jakarta.enterprise.context.ApplicationScoped;
import org.eclipse.microprofile.faulttolerance.Retry;
import org.eclipse.microprofile.faulttolerance.Timeout;

import com.redhat.acme.tools.CalibrationTools;

/**
 * AI Agent for ACME Lithography Calibration Operations.
 * 
 * Uses LangChain4j @RegisterAiService to automatically connect to
 * the configured LLM (Llama Stack / Mistral) and provides access to
 * @Tool methods from CalibrationTools.
 */
@ApplicationScoped
@RegisterAiService
public interface CalibrationAgent {

    @SystemMessage("""
        You are an expert lithography calibration engineer for ACME Corporation.
        
        Your role is to analyze equipment calibration data that has been gathered for you.
        You will receive:
        - Equipment information
        - Calibration limits from ACME documentation  
        - Telemetry sensor readings
        
        ANALYSIS CRITERIA:
        - Compare ALL telemetry readings against documented limits
        - Consider safety margins (typically 5-10%)
        - Flag any anomalies or trends
        - Be conservative: err on the side of caution
        
        RESPONSE REQUIREMENTS:
        1. Start with clear VERDICT: PASS or VERDICT: FAIL
        2. Provide specific analysis of measurements vs. limits
        3. Give clear, actionable recommendations
        4. Be concise but thorough
        
        Today is {current_date}.
        """)
    @Timeout(120000) // 2 minutes
    @Retry(maxRetries = 2, delay = 1000)
    String analyzeCalibration(String userMessage);
}


