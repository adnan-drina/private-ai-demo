# ACME LithoOps Agentic Orchestrator - Detailed Specification

**Integration**: Stage 3 Quarkus Agent + Stage 2 RAG + ToolHive MCPs  
**Quality Bar**: EU AI Act RAG Project Standards  
**Architecture**: Quarkus Multi-Module + LangChain4j Agents

---

## 🎯 Mission

Build a production-grade **ACME LithoOps Agentic Orchestrator** in Quarkus that:
- Wires Stage 2 RAG service into agent workflows
- Orchestrates OpenShift MCP (cluster actions, dry-run by default)
- Orchestrates Slack MCP (notifications + PDF attachments)
- Processes real telemetry data (CSV) for calibration checks
- Generates PDF calibration reports with citations
- Follows Quarkus + LangChain4j workshop patterns

---

## 📁 Project Structure (Quarkus Multi-Module)

```
quarkus-acme-agent/
├── pom.xml                              # Parent POM
├── README-acme-lithoops.md              # Design decisions
├── .mvn/                                # Maven wrapper
├── acme-web/                            # REST + SSE/WebSocket
│   ├── pom.xml
│   └── src/
│       ├── main/
│       │   ├── java/
│       │   │   └── com/redhat/acme/web/
│       │   │       ├── CalibrationResource.java
│       │   │       ├── MaintenanceResource.java
│       │   │       ├── NotificationResource.java
│       │   │       └── DevUICard.java
│       │   └── resources/
│       │       ├── application.properties
│       │       └── META-INF/
│       └── test/
│           └── java/
│               └── com/redhat/acme/web/
│                   └── CalibrationResourceTest.java
├── acme-agents/                         # Agent skills (LangChain4j)
│   ├── pom.xml
│   └── src/
│       ├── main/
│       │   └── java/
│       │       └── com/redhat/acme/agents/
│       │           ├── AgentOrchestrator.java
│       │           ├── skills/
│       │           │   ├── PrepareCalibrationSkill.java
│       │           │   ├── WatchTelemetrySkill.java
│       │           │   ├── CompareAgainstLimitsSkill.java
│       │           │   ├── DraftReportSkill.java
│       │           │   └── NotifySlackSkill.java
│       │           └── model/
│       │               ├── CalibrationRequest.java
│       │               ├── CalibrationResult.java
│       │               ├── TelemetryData.java
│       │               ├── LimitsData.java
│       │               └── Verdict.java (PASS, PASS_WITH_ACTION, FAIL)
│       └── test/
│           └── java/
│               └── com/redhat/acme/agents/
│                   └── CompareAgainstLimitsSkillTest.java
├── acme-rag-client/                     # Stage 2 RAG client
│   ├── pom.xml
│   └── src/
│       ├── main/
│       │   └── java/
│       │       └── com/redhat/acme/rag/
│       │           ├── RagClient.java
│       │           ├── RagClientConfig.java
│       │           └── model/
│       │               ├── LimitsRequest.java
│       │               ├── LimitsResponse.java
│       │               ├── AnswerRequest.java
│       │               └── AnswerResponse.java
│       └── test/
├── acme-mcp/                            # MCP JSON-RPC clients
│   ├── pom.xml
│   └── src/
│       ├── main/
│       │   └── java/
│       │       └── com/redhat/acme/mcp/
│       │           ├── openshift/
│       │           │   ├── OpenShiftMcpClient.java
│       │           │   ├── OpenShiftMcpConfig.java
│       │           │   └── model/
│       │           │       ├── CreateJobRequest.java
│       │           │       ├── CreateJobResponse.java
│       │           │       └── AnnotateRequest.java
│       │           └── slack/
│       │               ├── SlackMcpClient.java
│       │               ├── SlackMcpConfig.java
│       │               └── model/
│       │                   ├── SendMessageRequest.java
│       │                   ├── SendMessageResponse.java
│       │                   └── UploadFileRequest.java
│       └── test/
└── acme-reports/                        # PDF generation
    ├── pom.xml
    └── src/
        ├── main/
        │   └── java/
        │       └── com/redhat/acme/reports/
        │           ├── ReportGenerator.java
        │           ├── ReportConfig.java
        │           ├── templates/
        │           │   └── CalibrationReportTemplate.java
        │           └── model/
        │               ├── ReportMetadata.java
        │               └── Citation.java
        └── test/
```

---

## 🔧 Configuration (application.properties)

```properties
# Application
quarkus.application.name=acme-lithoops-orchestrator
quarkus.http.port=8080

# Documents Directory
docs.dir=./documents/scenario2
docs.reports.dir=${docs.dir}/reports

# Stage 2 RAG Integration
rag.baseUrl=http://rag-stack-service.private-ai-demo.svc:8321
rag.timeout=30s
rag.retry.max-attempts=3

# OpenShift MCP (ToolHive-managed)
openshift.mcp.url=http://kubernetes-mcp.private-ai-demo.svc:8080
openshift.mcp.namespace=acme-fab
openshift.mcp.dryRun=true
openshift.mcp.timeout=10s

# Slack MCP (ToolHive-managed)
slack.mcp.url=http://slack-mcp.private-ai-demo.svc:8080
slack.channel=#acme-litho
slack.username=ACME LithoOps Agent
slack.icon=:factory:
slack.timeout=10s

# vLLM (Stage 1 Mistral for agent reasoning)
vllm.url=https://mistral-24b-quantized-private-ai-demo.apps.cluster-n8cnx.n8cnx.sandbox2830.opentlc.com/v1
vllm.model-id=mistral-24b-quantized
vllm.api-key=dummy

# Telemetry Processing
telemetry.window-size=10
telemetry.overlay-threshold=3.5
telemetry.dose-uniformity-threshold=2.5
telemetry.vibration-threshold=0.8

# Observability
quarkus.log.category."com.redhat.acme".level=DEBUG
quarkus.log.console.format=%d{HH:mm:ss} %-5p [%c{2.}] (%t) %s%e [correlationId:%X{correlationId}]%n

# Micrometer
quarkus.micrometer.export.prometheus.enabled=true
quarkus.micrometer.binder.http-client.enabled=true
quarkus.micrometer.binder.http-server.enabled=true

# Dev UI
quarkus.dev-ui.always-include-latest=true
```

---

## 🎯 Agent Skills (LangChain4j Tools)

### 1. PrepareCalibrationSkill

**Purpose**: Query Stage 2 RAG for calibration procedure and limits

**Implementation**:
```java
@ApplicationScoped
public class PrepareCalibrationSkill {
    
    @Inject
    RagClient ragClient;
    
    @Tool("Prepare daily calibration checklist with acceptance criteria")
    public CalibrationPrep prepareCalibration(
        @P("Product name (e.g., PX-7)") String product,
        @P("Layer name (e.g., M1)") String layer,
        @P("Tool name (e.g., L-900-07)") String tool
    ) {
        // Call Stage 2 RAG APIs
        LimitsResponse limits = ragClient.getLimits(product, layer);
        
        AnswerRequest answerReq = AnswerRequest.builder()
            .query(String.format(
                "Prepare daily DFO calibration procedure for %s/%s on tool %s. " +
                "List acceptance criteria and critical parameters.",
                product, layer, tool
            ))
            .filters(Map.of(
                "product", product,
                "layer", layer,
                "tool_model", tool
            ))
            .build();
        
        AnswerResponse answer = ragClient.getAnswer(answerReq);
        
        return CalibrationPrep.builder()
            .checklist(answer.getAnswer())
            .limits(limits)
            .citations(answer.getCitations())
            .build();
    }
}
```

**Returns**:
```json
{
  "checklist": "1. DFO calibration sequence:\n- Initialize baseline\n- Verify source stability...",
  "limits": {
    "overlayUCL": 3.5,
    "doseUniformityUCL": 2.5,
    "bfTarget": 0.5,
    "bfTolerance": 0.1
  },
  "citations": [
    {
      "doc": "ACME_01_ACME_DFO_Calibration_SOP_v1.9",
      "section": "§3.2 Daily Calibration",
      "page": 12
    }
  ]
}
```

---

### 2. WatchTelemetrySkill

**Purpose**: Parse CSV telemetry and compute key metrics

**Implementation**:
```java
@ApplicationScoped
public class WatchTelemetrySkill {
    
    @ConfigProperty(name = "telemetry.window-size")
    int windowSize;
    
    @Tool("Watch telemetry stream and compute overlay residual, dose uniformity, vibration")
    public TelemetryAnalysis watchTelemetry(
        @P("Path to CSV file") String streamPath,
        @P("Duration in seconds to analyze") int durationSec
    ) throws IOException {
        List<TelemetryPoint> points = parseCsv(streamPath);
        
        // Compute metrics
        double maxOverlay = points.stream()
            .mapToDouble(p -> Math.sqrt(p.getX() * p.getX() + p.getY() * p.getY()))
            .max()
            .orElse(0.0);
        
        double doseUniformity = computeDoseUniformity(points);
        double bestFocus = computeBestFocus(points);
        double vibration = computeVibration(points);
        
        // Detect sustained violations
        boolean sustainedOverlayViolation = detectSustainedViolation(
            points, 
            p -> Math.sqrt(p.getX() * p.getX() + p.getY() * p.getY()),
            3.5, 
            windowSize
        );
        
        return TelemetryAnalysis.builder()
            .maxOverlay(maxOverlay)
            .doseUniformity(doseUniformity)
            .bestFocus(bestFocus)
            .vibration(vibration)
            .sustainedOverlayViolation(sustainedOverlayViolation)
            .pointCount(points.size())
            .build();
    }
    
    private List<TelemetryPoint> parseCsv(String path) throws IOException {
        // Parse CSV with OpenCSV or custom parser
        // Expected columns: timestamp, x, y, dose, focus, vibration
        return Files.lines(Paths.get(path))
            .skip(1) // Skip header
            .map(line -> {
                String[] parts = line.split(",");
                return TelemetryPoint.builder()
                    .timestamp(parts[0])
                    .x(Double.parseDouble(parts[1]))
                    .y(Double.parseDouble(parts[2]))
                    .dose(Double.parseDouble(parts[3]))
                    .focus(Double.parseDouble(parts[4]))
                    .vibration(Double.parseDouble(parts[5]))
                    .build();
            })
            .collect(Collectors.toList());
    }
}
```

---

### 3. CompareAgainstLimitsSkill

**Purpose**: Determine PASS/PASS_WITH_ACTION/FAIL verdict

**Implementation**:
```java
@ApplicationScoped
public class CompareAgainstLimitsSkill {
    
    @Tool("Compare measured values against specification limits and determine verdict")
    public ComparisonResult compareAgainstLimits(
        @P("Measured values") TelemetryAnalysis measured,
        @P("Specification limits") LimitsData limits
    ) {
        List<String> violations = new ArrayList<>();
        List<String> actions = new ArrayList<>();
        Verdict verdict = Verdict.PASS;
        
        // Overlay check
        if (measured.getMaxOverlay() > limits.getOverlayUCL()) {
            violations.add(String.format(
                "Overlay %.2f nm > %.2f nm UCL",
                measured.getMaxOverlay(),
                limits.getOverlayUCL()
            ));
            actions.add("Investigate overlay calibration");
            actions.add("Check DFO baseline");
            verdict = Verdict.FAIL;
        }
        
        // Dose uniformity check
        if (measured.getDoseUniformity() > limits.getDoseUniformityUCL()) {
            violations.add(String.format(
                "Dose uniformity %.2f%% ≥ %.2f%% UCL",
                measured.getDoseUniformity(),
                limits.getDoseUniformityUCL()
            ));
            actions.add("Check EUV source stability");
            actions.add("Review dose map");
            if (verdict == Verdict.PASS) {
                verdict = Verdict.PASS_WITH_ACTION;
            }
        }
        
        // Best focus check
        double bfDeviation = Math.abs(measured.getBestFocus() - limits.getBfTarget());
        if (bfDeviation > limits.getBfTolerance()) {
            violations.add(String.format(
                "Best focus %.2f deviates %.2f from target %.2f (tolerance %.2f)",
                measured.getBestFocus(),
                bfDeviation,
                limits.getBfTarget(),
                limits.getBfTolerance()
            ));
            actions.add("Recalibrate focus");
            if (verdict == Verdict.PASS) {
                verdict = Verdict.PASS_WITH_ACTION;
            }
        }
        
        // Vibration check (if sustained)
        if (measured.isSustainedOverlayViolation() && measured.getVibration() > 0.8) {
            violations.add(String.format(
                "Sustained vibration %.2f mm/s > 0.8 mm/s threshold",
                measured.getVibration()
            ));
            actions.add("Inspect pump vibration");
            actions.add("Check mechanical stability");
            verdict = Verdict.FAIL;
        }
        
        return ComparisonResult.builder()
            .verdict(verdict)
            .violations(violations)
            .actions(actions)
            .measured(measured)
            .limits(limits)
            .build();
    }
}
```

**Test** (CompareAgainstLimitsSkillTest.java):
```java
@QuarkusTest
class CompareAgainstLimitsSkillTest {
    
    @Inject
    CompareAgainstLimitsSkill skill;
    
    @Test
    void testCleanDataReturnsPass() {
        // Given: Clean telemetry
        TelemetryAnalysis measured = TelemetryAnalysis.builder()
            .maxOverlay(2.8)  // < 3.5 UCL
            .doseUniformity(1.9)  // < 2.5 UCL
            .bestFocus(0.52)  // within target ± tolerance
            .vibration(0.5)
            .sustainedOverlayViolation(false)
            .build();
        
        LimitsData limits = LimitsData.builder()
            .overlayUCL(3.5)
            .doseUniformityUCL(2.5)
            .bfTarget(0.5)
            .bfTolerance(0.1)
            .build();
        
        // When
        ComparisonResult result = skill.compareAgainstLimits(measured, limits);
        
        // Then
        assertEquals(Verdict.PASS, result.getVerdict());
        assertTrue(result.getViolations().isEmpty());
        assertTrue(result.getActions().isEmpty());
    }
    
    @Test
    void testOutOfSpecReturnsFailWithActions() {
        // Given: Out-of-spec telemetry
        TelemetryAnalysis measured = TelemetryAnalysis.builder()
            .maxOverlay(3.9)  // > 3.5 UCL
            .doseUniformity(2.7)  // > 2.5 UCL
            .bestFocus(0.48)
            .vibration(0.9)  // > 0.8 threshold
            .sustainedOverlayViolation(true)
            .build();
        
        LimitsData limits = LimitsData.builder()
            .overlayUCL(3.5)
            .doseUniformityUCL(2.5)
            .bfTarget(0.5)
            .bfTolerance(0.1)
            .build();
        
        // When
        ComparisonResult result = skill.compareAgainstLimits(measured, limits);
        
        // Then
        assertEquals(Verdict.FAIL, result.getVerdict());
        assertFalse(result.getViolations().isEmpty());
        assertTrue(result.getViolations().get(0).contains("3.9 nm > 3.5 nm UCL"));
        assertFalse(result.getActions().isEmpty());
    }
}
```

---

### 4. DraftReportSkill

**Purpose**: Generate PDF calibration report with citations

**Implementation**:
```java
@ApplicationScoped
public class DraftReportSkill {
    
    @Inject
    ReportGenerator reportGenerator;
    
    @ConfigProperty(name = "docs.reports.dir")
    String reportsDir;
    
    @Tool("Generate PDF calibration report and save to reports directory")
    public ReportResult draftReport(
        @P("Report metadata") ReportMetadata meta,
        @P("Measured values") TelemetryAnalysis measured,
        @P("Specification limits") LimitsData limits,
        @P("Citations from RAG") List<Citation> citations,
        @P("Verdict") Verdict verdict,
        @P("Actions") List<String> actions
    ) throws IOException {
        String timestamp = LocalDateTime.now().format(
            DateTimeFormatter.ofPattern("yyyyMMdd-HHmmss")
        );
        
        String filename = String.format(
            "CR-%s-%s-%s-%s.pdf",
            timestamp,
            meta.getTool(),
            meta.getProduct(),
            meta.getLayer()
        );
        
        Path reportPath = Paths.get(reportsDir, filename);
        Files.createDirectories(reportPath.getParent());
        
        // Generate PDF
        reportGenerator.generate(
            reportPath,
            meta,
            measured,
            limits,
            citations,
            verdict,
            actions
        );
        
        return ReportResult.builder()
            .path(reportPath.toString())
            .filename(filename)
            .size(Files.size(reportPath))
            .timestamp(timestamp)
            .build();
    }
}
```

**PDF Structure** (ReportGenerator.java):
```java
@ApplicationScoped
public class ReportGenerator {
    
    public void generate(
        Path outputPath,
        ReportMetadata meta,
        TelemetryAnalysis measured,
        LimitsData limits,
        List<Citation> citations,
        Verdict verdict,
        List<String> actions
    ) throws IOException {
        // Use iText or Apache PDFBox
        Document document = new Document();
        PdfWriter.getInstance(document, new FileOutputStream(outputPath.toFile()));
        document.open();
        
        // Title
        Font titleFont = new Font(Font.FontFamily.HELVETICA, 18, Font.BOLD);
        Paragraph title = new Paragraph("ACME LithoOps Calibration Report", titleFont);
        title.setAlignment(Element.ALIGN_CENTER);
        document.add(title);
        
        // Metadata table
        PdfPTable metaTable = new PdfPTable(2);
        metaTable.addCell("Equipment");
        metaTable.addCell(meta.getTool());
        metaTable.addCell("Product");
        metaTable.addCell(meta.getProduct());
        metaTable.addCell("Layer");
        metaTable.addCell(meta.getLayer());
        metaTable.addCell("Timestamp");
        metaTable.addCell(meta.getTimestamp());
        metaTable.addCell("Verdict");
        metaTable.addCell(verdict.toString());
        document.add(metaTable);
        
        // Measured vs Limits table
        PdfPTable resultsTable = new PdfPTable(3);
        resultsTable.addCell("Parameter");
        resultsTable.addCell("Measured");
        resultsTable.addCell("Limit (UCL)");
        
        resultsTable.addCell("Overlay (nm)");
        resultsTable.addCell(String.format("%.2f", measured.getMaxOverlay()));
        resultsTable.addCell(String.format("%.2f", limits.getOverlayUCL()));
        
        resultsTable.addCell("Dose Uniformity (%)");
        resultsTable.addCell(String.format("%.2f", measured.getDoseUniformity()));
        resultsTable.addCell(String.format("%.2f", limits.getDoseUniformityUCL()));
        
        resultsTable.addCell("Best Focus (μm)");
        resultsTable.addCell(String.format("%.2f", measured.getBestFocus()));
        resultsTable.addCell(String.format("%.2f ± %.2f", limits.getBfTarget(), limits.getBfTolerance()));
        
        document.add(resultsTable);
        
        // Actions (if any)
        if (!actions.isEmpty()) {
            document.add(new Paragraph("\nRecommended Actions:", new Font(Font.FontFamily.HELVETICA, 12, Font.BOLD)));
            for (String action : actions) {
                document.add(new Paragraph("• " + action));
            }
        }
        
        // Citations page
        document.newPage();
        document.add(new Paragraph("References", new Font(Font.FontFamily.HELVETICA, 14, Font.BOLD)));
        for (Citation citation : citations) {
            document.add(new Paragraph(String.format(
                "[%s] %s, §%s, p.%d",
                citation.getDocId(),
                citation.getDocName(),
                citation.getSection(),
                citation.getPage()
            )));
        }
        
        document.close();
    }
}
```

---

### 5. NotifySlackSkill

**Purpose**: Send Slack notification via Slack MCP (ToolHive)

**Implementation**:
```java
@ApplicationScoped
public class NotifySlackSkill {
    
    @Inject
    SlackMcpClient slackMcp;
    
    @Tool("Send notification to Slack with optional PDF attachment")
    public SlackNotificationResult notifySlack(
        @P("Slack channel") String channel,
        @P("Message text") String text,
        @P("Optional file path to attach") String filePath,
        @P("Optional file title") String fileTitle,
        @P("Correlation ID for tracking") String correlationId
    ) {
        SendMessageRequest request = SendMessageRequest.builder()
            .channel(channel)
            .text(text)
            .correlationId(correlationId)
            .build();
        
        SendMessageResponse response = slackMcp.sendMessage(request);
        
        // If file provided, upload it
        if (filePath != null && !filePath.isEmpty()) {
            UploadFileRequest uploadReq = UploadFileRequest.builder()
                .channel(channel)
                .filePath(filePath)
                .title(fileTitle)
                .threadTs(response.getTs())  // Attach to message thread
                .build();
            
            slackMcp.uploadFile(uploadReq);
        }
        
        return SlackNotificationResult.builder()
            .messageId(response.getTs())
            .channel(channel)
            .correlationId(correlationId)
            .fileAttached(filePath != null)
            .build();
    }
}
```

---

### 6. CreateMaintenanceJobSkill

**Purpose**: Create OpenShift Job via OpenShift MCP (ToolHive)

**Implementation**:
```java
@ApplicationScoped
public class CreateMaintenanceJobSkill {
    
    @Inject
    OpenShiftMcpClient openShiftMcp;
    
    @ConfigProperty(name = "openshift.mcp.dryRun")
    boolean dryRun;
    
    @Tool("Create maintenance job in OpenShift (dry-run by default)")
    public MaintenanceJobResult createMaintenanceJob(
        @P("Job name") String name,
        @P("Container image") String image,
        @P("Command arguments") List<String> args,
        @P("Optional: Override dry-run") boolean forceRun,
        @P("Citation hash for audit") String citationHash
    ) {
        boolean actualDryRun = dryRun && !forceRun;
        
        CreateJobRequest request = CreateJobRequest.builder()
            .name(name)
            .image(image)
            .args(args)
            .labels(Map.of(
                "app", "acme-maintenance",
                "type", "automated",
                "citation-hash", citationHash
            ))
            .annotations(Map.of(
                "acme.litho/triggered-by", "agent",
                "acme.litho/reason", "calibration-failure",
                "acme.litho/citation-hash", citationHash
            ))
            .dryRun(actualDryRun)
            .build();
        
        if (actualDryRun) {
            // Log the exact MCP payload that would be sent
            LOGGER.info("DRY-RUN: Would create OpenShift Job with payload: {}", 
                Json.encode(request));
            
            return MaintenanceJobResult.builder()
                .jobName(name)
                .dryRun(true)
                .payload(Json.encode(request))
                .build();
        } else {
            CreateJobResponse response = openShiftMcp.createJob(request);
            
            return MaintenanceJobResult.builder()
                .jobName(response.getJobName())
                .namespace(response.getNamespace())
                .dryRun(false)
                .created(true)
                .build();
        }
    }
}
```

---

## 🌐 REST Endpoints

### 1. POST /ops/calibration/check

**CalibrationResource.java**:
```java
@Path("/ops/calibration")
@Produces(MediaType.APPLICATION_JSON)
@Consumes(MediaType.APPLICATION_JSON)
public class CalibrationResource {
    
    @Inject
    AgentOrchestrator orchestrator;
    
    @POST
    @Path("/check")
    public Uni<CalibrationCheckResponse> checkCalibration(
        CalibrationCheckRequest request
    ) {
        String correlationId = UUID.randomUUID().toString();
        MDC.put("correlationId", correlationId);
        
        return orchestrator.executeCalibrationCheck(request, correlationId)
            .onItem().transform(result -> {
                return CalibrationCheckResponse.builder()
                    .correlationId(correlationId)
                    .verdict(result.getVerdict())
                    .actions(result.getActions())
                    .citations(result.getCitations())
                    .limits(result.getLimits())
                    .measured(result.getMeasured())
                    .reportPath(result.getReportPath())
                    .slackMsgId(result.getSlackMsgId())
                    .build();
            });
    }
}
```

**Request**:
```json
{
  "tool": "L-900-07",
  "product": "PX-7",
  "layer": "M1",
  "telemetryPath": "./documents/scenario2/telemetry/acme_telemetry_clean.csv",
  "slackNotify": true
}
```

**Response** (PASS):
```json
{
  "correlationId": "550e8400-e29b-41d4-a716-446655440000",
  "verdict": "PASS",
  "actions": [],
  "citations": [
    {
      "doc": "ACME_01",
      "section": "§3.2",
      "page": 12
    }
  ],
  "limits": {
    "overlayUCL": 3.5,
    "doseUniformityUCL": 2.5,
    "bfTarget": 0.5,
    "bfTolerance": 0.1
  },
  "measured": {
    "maxOverlay": 2.8,
    "doseUniformity": 1.9,
    "bestFocus": 0.52,
    "vibration": 0.5
  },
  "reportPath": "./documents/scenario2/reports/CR-20251008-153045-L-900-07-PX-7-M1.pdf",
  "slackMsgId": "1725891234.123456"
}
```

**Response** (FAIL):
```json
{
  "correlationId": "660f9511-f3ac-52e5-b827-557766551111",
  "verdict": "FAIL",
  "actions": [
    "Investigate overlay calibration",
    "Check DFO baseline",
    "Inspect pump vibration"
  ],
  "citations": [
    {
      "doc": "ACME_01",
      "section": "§3.2",
      "page": 12
    }
  ],
  "limits": {
    "overlayUCL": 3.5,
    "doseUniformityUCL": 2.5,
    "bfTarget": 0.5,
    "bfTolerance": 0.1
  },
  "measured": {
    "maxOverlay": 3.9,
    "doseUniformity": 2.7,
    "bestFocus": 0.48,
    "vibration": 0.9
  },
  "reportPath": "./documents/scenario2/reports/CR-20251008-153105-L-900-07-PX-7-M1.pdf",
  "slackMsgId": "1725891245.123457"
}
```

---

### 2. POST /ops/maintenance/job

**MaintenanceResource.java**:
```java
@Path("/ops/maintenance")
public class MaintenanceResource {
    
    @Inject
    CreateMaintenanceJobSkill jobSkill;
    
    @POST
    @Path("/job")
    public MaintenanceJobResult createJob(CreateJobRequest request) {
        return jobSkill.createMaintenanceJob(
            request.getName(),
            request.getImage(),
            request.getArgs(),
            request.isForceRun(),
            request.getCitationHash()
        );
    }
}
```

**Request**:
```json
{
  "name": "pump-inspect-20251008-153045",
  "image": "acme/maintenance:latest",
  "args": ["inspect", "pump", "Z-axis"],
  "dryRun": true,
  "citationHash": "a1b2c3d4"
}
```

**Response** (dry-run):
```json
{
  "jobName": "pump-inspect-20251008-153045",
  "dryRun": true,
  "payload": "{\"name\":\"pump-inspect-20251008-153045\",\"image\":\"acme/maintenance:latest\",...}"
}
```

---

### 3. POST /ops/notify

**NotificationResource.java**:
```java
@Path("/ops/notify")
public class NotificationResource {
    
    @Inject
    NotifySlackSkill slackSkill;
    
    @POST
    public SlackNotificationResult notify(NotifyRequest request) {
        return slackSkill.notifySlack(
            request.getChannel(),
            request.getText(),
            request.getFilePath(),
            request.getTitle(),
            UUID.randomUUID().toString()
        );
    }
}
```

---

## 🎬 Demo Flows

### Flow 1: Calibration Check (Clean Data) - PASS

**Input**:
```bash
curl -X POST http://localhost:8080/ops/calibration/check \
  -H "Content-Type: application/json" \
  -d '{
    "tool": "L-900-07",
    "product": "PX-7",
    "layer": "M1",
    "telemetryPath": "./documents/scenario2/telemetry/acme_telemetry_clean.csv",
    "slackNotify": true
  }'
```

**Agent Orchestration**:
```
[correlationId:550e8400] AgentOrchestrator: Starting calibration check
[correlationId:550e8400] PrepareCalibrationSkill: Querying RAG for PX-7/M1 limits
[correlationId:550e8400] RagClient: POST /rag/limits → 200 OK (latency: 245ms, chunks: 3)
[correlationId:550e8400] WatchTelemetrySkill: Parsing telemetry CSV (60s window)
[correlationId:550e8400] WatchTelemetrySkill: Analyzed 1200 points → overlay=2.8nm, doseU=1.9%
[correlationId:550e8400] CompareAgainstLimitsSkill: Verdict=PASS (no violations)
[correlationId:550e8400] DraftReportSkill: Generating PDF report
[correlationId:550e8400] ReportGenerator: Saved to .../reports/CR-20251008-153045-L-900-07-PX-7-M1.pdf
[correlationId:550e8400] NotifySlackSkill: Sending to #acme-litho
[correlationId:550e8400] SlackMcpClient: POST /execute → send_slack_message → 200 OK
[correlationId:550e8400] AgentOrchestrator: Calibration check complete (verdict=PASS)
```

**Slack Message**:
```
🟢 ACME LithoOps: PASS for L-900-07 (PX-7/M1)

Overlay: 2.80 nm (UCL 3.50)
Dose Uniformity: 1.90% (UCL 2.50%)
Best Focus: 0.52 μm (target 0.50±0.10)

Report attached. [correlationId: 550e8400]
```

**PDF Report**: Attached to Slack message

---

### Flow 2: Anomaly Triage (Out-of-Spec) - FAIL

**Input**:
```bash
curl -X POST http://localhost:8080/ops/calibration/check \
  -H "Content-Type: application/json" \
  -d '{
    "tool": "L-900-07",
    "product": "PX-7",
    "layer": "M1",
    "telemetryPath": "./documents/scenario2/telemetry/acme_telemetry_outofspec.csv",
    "slackNotify": true
  }'
```

**Agent Orchestration**:
```
[correlationId:660f9511] AgentOrchestrator: Starting calibration check
[correlationId:660f9511] PrepareCalibrationSkill: Querying RAG for PX-7/M1 limits
[correlationId:660f9511] RagClient: POST /rag/limits → 200 OK (latency: 238ms, chunks: 3)
[correlationId:660f9511] WatchTelemetrySkill: Parsing telemetry CSV (60s window)
[correlationId:660f9511] WatchTelemetrySkill: Analyzed 1200 points → overlay=3.9nm, doseU=2.7%, vib=0.9mm/s
[correlationId:660f9511] WatchTelemetrySkill: ⚠️ Sustained overlay violation detected (window=10)
[correlationId:660f9511] CompareAgainstLimitsSkill: Verdict=FAIL (3 violations)
[correlationId:660f9511] CompareAgainstLimitsSkill: • Overlay 3.9nm > 3.5nm UCL
[correlationId:660f9511] CompareAgainstLimitsSkill: • Dose uniformity 2.7% ≥ 2.5% UCL
[correlationId:660f9511] CompareAgainstLimitsSkill: • Sustained vibration 0.9mm/s > 0.8mm/s
[correlationId:660f9511] DraftReportSkill: Generating PDF report with violations
[correlationId:660f9511] ReportGenerator: Saved to .../reports/CR-20251008-153105-L-900-07-PX-7-M1.pdf
[correlationId:660f9511] CreateMaintenanceJobSkill: Creating OpenShift Job (dry-run=true)
[correlationId:660f9511] OpenShiftMcpClient: DRY-RUN: Would create job "pump-inspect-20251008-153105"
[correlationId:660f9511] NotifySlackSkill: Sending alert to #acme-litho
[correlationId:660f9511] SlackMcpClient: POST /execute → send_equipment_alert → 200 OK
[correlationId:660f9511] SlackMcpClient: Uploading PDF report
[correlationId:660f9511] AgentOrchestrator: Calibration check complete (verdict=FAIL)
```

**Slack Message**:
```
🔴 ACME LithoOps: FAIL - Overlay 3.90 nm > 3.50 nm on L-900-07 (PX-7/M1)

Violations:
• Overlay: 3.90 nm > 3.50 nm UCL
• Dose Uniformity: 2.70% ≥ 2.50% UCL
• Sustained vibration: 0.90 mm/s > 0.80 mm/s

Recommended Actions:
• Investigate overlay calibration
• Check DFO baseline
• Inspect pump vibration
• Check mechanical stability

📋 Calibration report attached.
🛠 Maintenance job ready (dry-run): pump-inspect-20251008-153105

[correlationId: 660f9511]
```

**PDF Report**: Attached to Slack message

**OpenShift Job Payload** (logged, not executed):
```json
{
  "name": "pump-inspect-20251008-153105",
  "image": "acme/maintenance:latest",
  "args": ["inspect", "pump", "Z-axis"],
  "labels": {
    "app": "acme-maintenance",
    "type": "automated",
    "citation-hash": "a1b2c3d4"
  },
  "annotations": {
    "acme.litho/triggered-by": "agent",
    "acme.litho/reason": "calibration-failure",
    "acme.litho/citation-hash": "a1b2c3d4"
  },
  "dryRun": true
}
```

---

## 🛡️ Guardrails

### 1. OpenShift Action Confirmation

```java
if (actualDryRun) {
    LOGGER.warn("OpenShift action blocked (dry-run=true). Set forceRun=true to execute.");
    return MaintenanceJobResult.builder()
        .jobName(name)
        .dryRun(true)
        .message("Action blocked. Requires confirmation.")
        .build();
}
```

### 2. RAG Confidence Check

```java
if (answer.getConfidence() < 0.7 || answer.getSources().stream().allMatch(s -> s.isSecondary())) {
    answer = "⚠️ Interpretive; confirm with ACME SOP/SPC. " + answer.getAnswer();
}
```

### 3. Correlation ID in All Logs

```java
MDC.put("correlationId", correlationId);
LOGGER.info("Starting calibration check for {}/{}", product, layer);
```

### 4. Numeric Deltas in Slack

```java
String message = String.format(
    "Overlay %.2f nm > %.2f nm UCL (+%.2f nm)",
    measured.getMaxOverlay(),
    limits.getOverlayUCL(),
    measured.getMaxOverlay() - limits.getOverlayUCL()
);
```

---

## 📊 Observability

### Dev UI Card

**AcmeDevUICard.java**:
```java
@DevUICard(name = "ACME LithoOps")
public class AcmeDevUICard {
    
    @Inject
    RagClient ragClient;
    
    @Inject
    SlackMcpClient slackMcp;
    
    @Inject
    OpenShiftMcpClient openShiftMcp;
    
    @ConfigProperty(name = "docs.dir")
    String docsDir;
    
    @DevUIBuildTimeData(name = "configuration")
    public Map<String, String> getConfiguration() {
        return Map.of(
            "RAG Base URL", ragClient.getBaseUrl(),
            "Slack MCP URL", slackMcp.getUrl(),
            "OpenShift MCP URL", openShiftMcp.getUrl(),
            "Docs Directory", docsDir,
            "Dry-Run Mode", String.valueOf(openShiftMcp.isDryRun())
        );
    }
    
    @DevUIAction(name = "check-connectivity")
    public Map<String, String> checkConnectivity() {
        Map<String, String> status = new HashMap<>();
        
        try {
            ragClient.healthCheck();
            status.put("RAG", "✅ Reachable");
        } catch (Exception e) {
            status.put("RAG", "❌ " + e.getMessage());
        }
        
        try {
            slackMcp.healthCheck();
            status.put("Slack MCP", "✅ Reachable");
        } catch (Exception e) {
            status.put("Slack MCP", "❌ " + e.getMessage());
        }
        
        try {
            openShiftMcp.healthCheck();
            status.put("OpenShift MCP", "✅ Reachable");
        } catch (Exception e) {
            status.put("OpenShift MCP", "❌ " + e.getMessage());
        }
        
        try {
            Files.createDirectories(Paths.get(docsDir, "reports"));
            status.put("Docs Directory", "✅ Writable");
        } catch (Exception e) {
            status.put("Docs Directory", "❌ Not writable");
        }
        
        return status;
    }
}
```

### Metrics

```java
@Timed(value = "acme.calibration.check", description = "Calibration check duration")
@Counted(value = "acme.calibration.checks", description = "Total calibration checks")
public Uni<CalibrationCheckResponse> checkCalibration(CalibrationCheckRequest request) {
    // ...
}

@Timed(value = "acme.rag.latency", description = "RAG API latency")
public LimitsResponse getLimits(String product, String layer) {
    // ...
}

@Counted(value = "acme.slack.messages", description = "Slack messages sent")
public SendMessageResponse sendMessage(SendMessageRequest request) {
    // ...
}
```

---

## 🧪 Acceptance Tests

**CalibrationCheckIT.java**:
```java
@QuarkusIntegrationTest
class CalibrationCheckIT {
    
    @Test
    void testCleanDataCreatesPassReport() {
        given()
            .contentType(ContentType.JSON)
            .body(Map.of(
                "tool", "L-900-07",
                "product", "PX-7",
                "layer", "M1",
                "telemetryPath", "./documents/scenario2/telemetry/acme_telemetry_clean.csv",
                "slackNotify", false
            ))
        .when()
            .post("/ops/calibration/check")
        .then()
            .statusCode(200)
            .body("verdict", equalTo("PASS"))
            .body("actions", hasSize(0))
            .body("reportPath", containsString("CR-"))
            .body("reportPath", endsWith(".pdf"));
        
        // Verify PDF was created
        String reportPath = extract().path("reportPath");
        assertTrue(Files.exists(Paths.get(reportPath)));
    }
    
    @Test
    void testOutOfSpecCreatesFailReportAndMaintenanceJob() {
        given()
            .contentType(ContentType.JSON)
            .body(Map.of(
                "tool", "L-900-07",
                "product", "PX-7",
                "layer", "M1",
                "telemetryPath", "./documents/scenario2/telemetry/acme_telemetry_outofspec.csv",
                "slackNotify", true
            ))
        .when()
            .post("/ops/calibration/check")
        .then()
            .statusCode(200)
            .body("verdict", equalTo("FAIL"))
            .body("actions", not(empty()))
            .body("actions", hasItem(containsString("Investigate")))
            .body("measured.maxOverlay", greaterThan(3.5f))
            .body("slackMsgId", notNullValue());
        
        // Verify PDF was created
        String reportPath = extract().path("reportPath");
        assertTrue(Files.exists(Paths.get(reportPath)));
        
        // Verify OpenShift Job was logged (dry-run)
        // Check logs for "DRY-RUN: Would create OpenShift Job"
    }
}
```

---

## 📚 Integration with ToolHive

### OpenShift MCP (Kubernetes MCP)

**Uses Red Hat's Official Kubernetes MCP Server**:
```java
@ApplicationScoped
public class OpenShiftMcpClient {
    
    @ConfigProperty(name = "openshift.mcp.url")
    String mcpUrl;  // http://kubernetes-mcp.private-ai-demo.svc:8080
    
    public CreateJobResponse createJob(CreateJobRequest request) {
        // Call ToolHive-managed Kubernetes MCP
        // Tool: create_job
        return restClient.post(
            mcpUrl + "/execute",
            Map.of(
                "tool", "create_job",
                "parameters", request
            )
        );
    }
}
```

### Slack MCP

**Uses Our Custom Slack MCP (ToolHive-managed)**:
```java
@ApplicationScoped
public class SlackMcpClient {
    
    @ConfigProperty(name = "slack.mcp.url")
    String mcpUrl;  // http://slack-mcp.private-ai-demo.svc:8080
    
    public SendMessageResponse sendMessage(SendMessageRequest request) {
        // Call ToolHive-managed Slack MCP
        // Tool: send_equipment_alert
        return restClient.post(
            mcpUrl + "/execute",
            Map.of(
                "tool", "send_equipment_alert",
                "parameters", request
            )
        );
    }
}
```

---

## 🎯 Summary

### Alignment with EU AI Act Project

| Aspect | EU AI Act RAG | ACME LithoOps | Consistency |
|--------|---------------|---------------|-------------|
| **Module Structure** | Multi-module Quarkus | Multi-module Quarkus | ✅ Same |
| **HTTP Clients** | Typed REST clients | Typed RAG + MCP clients | ✅ Same pattern |
| **Testing** | Unit + Integration | Unit + Integration | ✅ Same approach |
| **Observability** | MDC, Micrometer | MDC, Micrometer | ✅ Same |
| **Config** | application.properties | application.properties | ✅ Same |
| **Dev UI** | Custom card | Custom card | ✅ Same |
| **PDF Generation** | iText/PDFBox | iText/PDFBox | ✅ Same library |
| **Guardrails** | Citation check | Dry-run + confidence | ✅ Same rigor |

### Design Decisions

1. **Multi-Module Structure**: Follows Quarkus workshop patterns for clear separation of concerns
2. **LangChain4j Tools**: Agent skills are annotated with `@Tool` for automatic discovery
3. **ToolHive MCPs**: OpenShift and Slack MCPs are deployed via ToolHive operator
4. **Dry-Run by Default**: Safety-first approach; require explicit confirmation
5. **Correlation IDs**: Every request tracked end-to-end for observability
6. **PDF Reports**: iText library (same as EU AI Act) for consistent formatting
7. **Typed Clients**: All external APIs have typed request/response models
8. **Guardrails**: RAG confidence checks + numeric deltas in notifications

---

**Next Step**: Begin implementation with module scaffolding! 🚀


