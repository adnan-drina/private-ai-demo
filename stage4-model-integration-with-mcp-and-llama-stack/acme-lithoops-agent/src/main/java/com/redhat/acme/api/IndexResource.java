package com.redhat.acme.api;

import jakarta.ws.rs.GET;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.Produces;
import jakarta.ws.rs.core.MediaType;

/**
 * Index page showing API documentation.
 */
@Path("/")
public class IndexResource {

    @GET
    @Produces(MediaType.TEXT_HTML)
    public String index() {
        return """
        <!DOCTYPE html>
        <html>
        <head>
            <title>ACME LithoOps Agent</title>
            <style>
                body {
                    font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
                    max-width: 800px;
                    margin: 50px auto;
                    padding: 20px;
                    background: #f5f5f5;
                }
                .container {
                    background: white;
                    padding: 40px;
                    border-radius: 8px;
                    box-shadow: 0 2px 4px rgba(0,0,0,0.1);
                }
                h1 { color: #cc0000; margin-top: 0; }
                h2 { color: #333; border-bottom: 2px solid #cc0000; padding-bottom: 10px; }
                .endpoint {
                    background: #f9f9f9;
                    padding: 15px;
                    margin: 10px 0;
                    border-left: 4px solid #cc0000;
                    border-radius: 4px;
                }
                .method { 
                    display: inline-block;
                    background: #cc0000;
                    color: white;
                    padding: 4px 12px;
                    border-radius: 4px;
                    font-weight: bold;
                    font-size: 12px;
                    margin-right: 10px;
                }
                .path { 
                    font-family: 'Courier New', monospace;
                    color: #0066cc;
                    font-size: 16px;
                }
                code {
                    background: #f4f4f4;
                    padding: 2px 6px;
                    border-radius: 3px;
                    font-size: 14px;
                }
                .status {
                    display: inline-block;
                    background: #28a745;
                    color: white;
                    padding: 4px 12px;
                    border-radius: 12px;
                    font-size: 12px;
                    font-weight: bold;
                }
            </style>
        </head>
        <body>
            <div class="container">
                <h1>🏭 ACME LithoOps Agent</h1>
                <p><span class="status">✓ RUNNING</span></p>
                <p>Quarkus + LangChain4j AI Agent for Semiconductor Calibration</p>
                
                <h2>📡 API Endpoints</h2>
                
                <div class="endpoint">
                    <span class="method">GET</span>
                    <span class="path">/api/v1/health</span>
                    <p>Health check endpoint</p>
                </div>
                
                <div class="endpoint">
                    <span class="method">POST</span>
                    <span class="path">/api/v1/ops/calibration/check</span>
                    <p>Execute calibration check with AI agent</p>
                    <p><strong>Request Body:</strong></p>
                    <pre><code>{
  "equipmentId": "LITHO-001",
  "telemetryFile": "/deployments/data/telemetry/acme_telemetry_clean.csv"
}</code></pre>
                </div>
                
                <h2>🔧 Technology Stack</h2>
                <ul>
                    <li><strong>Framework:</strong> Quarkus 3.28.2</li>
                    <li><strong>AI:</strong> LangChain4j 1.3.0 (Quarkiverse)</li>
                    <li><strong>LLM:</strong> Llama Stack (Mistral-24B-Quantized)</li>
                    <li><strong>MCP Servers:</strong> Slack + Database</li>
                    <li><strong>Pattern:</strong> @RegisterAiService + @Tool methods</li>
                </ul>
                
                <h2>📚 Documentation</h2>
                <p>See <code>README.md</code> for complete documentation.</p>
                
                <hr style="margin: 30px 0; border: none; border-top: 1px solid #ddd;">
                <p style="text-align: center; color: #666; font-size: 14px;">
                    Red Hat AI Demo | Stage 3: Enterprise MCP Integration
                </p>
            </div>
        </body>
        </html>
        """;
    }
}


