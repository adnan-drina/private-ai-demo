package com.redhat.acme.tools;

import com.redhat.acme.mcp.*;
import dev.langchain4j.agent.tool.Tool;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.inject.Inject;
import org.eclipse.microprofile.rest.client.inject.RestClient;
import org.jboss.logging.Logger;

import java.io.BufferedReader;
import java.io.FileReader;
import java.util.Map;

/**
 * Calibration tools that integrate with MCP servers.
 * These @Tool methods will be automatically discovered by LangChain4j.
 */
@ApplicationScoped
public class CalibrationTools {

    private static final Logger LOG = Logger.getLogger(CalibrationTools.class);

    @Inject
    @RestClient
    SlackMcpClient slackMcp;

    @Inject
    @RestClient
    DatabaseMcpClient databaseMcp;

    /**
     * Get calibration limits from ACME documentation using Llama Stack RAG.
     */
    @Tool("Get calibration limits and tolerances from ACME LithoOps documentation. " +
          "Returns technical specifications for equipment calibration parameters.")
    public String getCalibrationLimits(String equipmentId, String parameter) {
        LOG.infof("🔍 Retrieving calibration limits: equipment=%s, parameter=%s", equipmentId, parameter);
        
        try {
            // Production calibration limits from ACME technical specifications
            // In a full production system, this would query Llama Stack RAG with vectorized equipment manuals
            
            String limits = "";
            
            if (parameter.contains("overlay") && equipmentId.equals("LITHO-001")) {
                limits = """
                    CALIBRATION LIMITS - LITHO-001 Overlay Accuracy
                    Source: ACME Equipment Manual NXE3400C-CAL-2023
                    
                    Parameter: Overlay Accuracy (X/Y)
                    Target: 0.0 nm (perfect alignment)
                    Warning Limit: ±2.5 nm
                    Action Limit: ±3.5 nm
                    Safety Margin: 10% recommended (±3.15 nm as practical limit)
                    
                    Expected Range: -2.0 to +2.0 nm (normal operation)
                    Out-of-Spec: Any measurement exceeding ±3.5 nm requires immediate action
                    
                    Calibration Frequency: Monthly or after 50,000 wafers
                    Last Calibration: 2025-10-01
                    Next Due: 2025-11-01
                    """;
            } else {
                limits = String.format("""
                    CALIBRATION LIMITS - %s
                    Source: ACME Equipment Manual (Generic)
                    
                    Parameter: %s
                    Status: Contact ACME service for specific limits
                    
                    General Guidelines:
                    - Calibration required monthly or per equipment schedule
                    - Verify all readings against baseline
                    - Flag any deviation >10%% from nominal
                    """, equipmentId, parameter);
            }
            
            LOG.infof("✅ Retrieved calibration limits");
            return limits;
            
        } catch (Exception e) {
            LOG.errorf(e, "❌ Failed to retrieve calibration limits");
            return "Error retrieving calibration limits: " + e.getMessage();
        }
    }

    /**
     * Read telemetry data from CSV file.
     */
    @Tool("Read telemetry data from calibration run CSV file. Returns sensor readings for analysis.")
    public String readTelemetryData(String filePath) {
        // Prepend base path if not absolute
        String fullPath = filePath.startsWith("/") ? filePath : "/deployments/data/telemetry/" + filePath;
        LOG.infof("📊 Reading telemetry from: %s", fullPath);
        
        try {
            StringBuilder data = new StringBuilder();
            try (BufferedReader reader = new BufferedReader(new FileReader(fullPath))) {
                String line;
                int count = 0;
                while ((line = reader.readLine()) != null && count < 100) {
                    data.append(line).append("\n");
                    count++;
                }
            }
            
            LOG.infof("✅ Read %d lines of telemetry data", data.toString().split("\n").length);
            return data.toString();
            
        } catch (Exception e) {
            LOG.errorf(e, "❌ Failed to read telemetry file");
            return "Error reading telemetry: " + e.getMessage();
        }
    }

    /**
     * Get equipment information from database MCP.
     */
    @Tool("Get equipment information including model, status, last calibration date, and service history.")
    public String getEquipmentInfo(String equipmentId) {
        LOG.infof("🔧 Querying equipment info: %s", equipmentId);
        
        try {
            Map<String, Object> params = Map.of("equipment_id", equipmentId);
            var request = new DatabaseMcpClient.McpRequest("query_equipment", params);
            var response = databaseMcp.execute(request);
            
            if (response == null || response.result == null) {
                LOG.warnf("⚠️ No equipment found for: %s", equipmentId);
                return "Equipment not found: " + equipmentId;
            }

            Map<String, Object> equipment = (Map<String, Object>) response.result.get("equipment");
            if (equipment == null) {
                return "Equipment not found: " + equipmentId;
            }
            
            String info = String.format(
                "Equipment ID: %s\nModel: %s\nStatus: %s\nLocation: %s\n" +
                "Serial Number: %s\nInstalled: %s\nLast PM: %s\nNext PM: %s",
                equipment.get("id"), equipment.get("model"), equipment.get("status"),
                equipment.get("location"), equipment.get("serial_number"),
                equipment.get("install_date"), equipment.get("last_pm"), equipment.get("next_pm")
            );
            
            LOG.infof("✅ Retrieved equipment info: %s", equipment.get("model"));
            return info;
            
        } catch (Exception e) {
            LOG.errorf(e, "❌ Failed to query equipment");
            return "Error querying equipment: " + e.getMessage();
        }
    }

    /**
     * Send Slack notification via Slack MCP.
     */
    @Tool("Send notification message to Slack channel for team communication.")
    public String sendSlackNotification(String message) {
        LOG.infof("💬 Sending Slack notification: %s", message.substring(0, Math.min(50, message.length())));
        
        try {
            Map<String, Object> params = Map.of("message", message, "channel", "#acme-litho");
            var request = new SlackMcpClient.McpRequest("send_slack_message", params);
            slackMcp.execute(request);
            
            LOG.infof("✅ Slack notification sent");
            return "Notification sent successfully";
            
        } catch (Exception e) {
            LOG.errorf(e, "❌ Failed to send Slack notification");
            return "Error sending notification: " + e.getMessage();
        }
    }

    /**
     * Send equipment alert via Slack MCP.
     */
    @Tool("Send critical equipment alert to Slack. Use for out-of-spec conditions or failures.")
    public String sendEquipmentAlert(String equipmentId, String severity, String alertMessage) {
        LOG.infof("🚨 Sending equipment alert: equipment=%s, severity=%s", equipmentId, severity);
        
        try {
            Map<String, Object> params = Map.of(
                "equipmentId", equipmentId,
                "severity", severity,
                "alertMessage", alertMessage,
                "channel", "#acme-alerts"
            );
            var request = new SlackMcpClient.McpRequest("send_equipment_alert", params);
            slackMcp.execute(request);
            
            LOG.infof("✅ Alert sent");
            return "Alert sent successfully";
            
        } catch (Exception e) {
            LOG.errorf(e, "❌ Failed to send equipment alert");
            return "Error sending alert: " + e.getMessage();
        }
    }

    /**
     * Query service history from database MCP.
     */
    @Tool("Get service history for equipment including past calibrations and maintenance records.")
    public String getServiceHistory(String equipmentId, int limit) {
        LOG.infof("📋 Querying service history: equipment=%s, limit=%d", equipmentId, limit);
        
        try {
            Map<String, Object> params = Map.of("equipment_id", equipmentId, "limit", limit);
            var request = new DatabaseMcpClient.McpRequest("query_service_history", params);
            var response = databaseMcp.execute(request);
            
            if (response == null || response.result == null) {
                LOG.warnf("⚠️ No service history for: %s", equipmentId);
                return "No service history found for: " + equipmentId;
            }

            var historyList = (java.util.List<Map<String, Object>>) response.result.get("history");
            if (historyList == null || historyList.isEmpty()) {
                return "No service history found for: " + equipmentId;
            }
            
            StringBuilder history = new StringBuilder("Service History:\n");
            for (var record : historyList) {
                history.append(String.format("- %s | %s | %s | %s\n",
                    record.get("date"), record.get("type"),
                    record.get("tech"), record.get("notes")));
            }
            
            LOG.infof("✅ Retrieved %d service records", historyList.size());
            return history.toString();
            
        } catch (Exception e) {
            LOG.errorf(e, "❌ Failed to query service history");
            return "Error querying service history: " + e.getMessage();
        }
    }

    /**
     * Query parts inventory from database MCP.
     */
    @Tool("Check parts inventory and availability for maintenance planning.")
    public String queryParts(String partNumber) {
        LOG.infof("📦 Querying parts inventory: %s", partNumber);
        
        try {
            Map<String, Object> params = Map.of("part_number", partNumber);
            var request = new DatabaseMcpClient.McpRequest("query_parts_inventory", params);
            var response = databaseMcp.execute(request);
            
            if (response == null || response.result == null) {
                LOG.warnf("⚠️ Part not found: %s", partNumber);
                return "Part not found: " + partNumber;
            }

            Map<String, Object> part = (Map<String, Object>) response.result.get("part");
            if (part == null) {
                return "Part not found: " + partNumber;
            }
            
            String info = String.format("Part: %s (%s)\nDescription: %s\nStock: %s\nLead Time: %s days\nPrice: $%s",
                part.get("name"), part.get("part_number"),
                part.get("description"), part.get("stock_level"),
                part.get("lead_time_days"), part.get("price"));
            
            LOG.infof("✅ Retrieved part info: %s", part.get("name"));
            return info;
            
        } catch (Exception e) {
            LOG.errorf(e, "❌ Failed to query parts");
            return "Error querying parts: " + e.getMessage();
        }
    }
}

