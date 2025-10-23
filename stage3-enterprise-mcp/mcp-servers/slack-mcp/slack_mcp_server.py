#!/usr/bin/env python3
"""
Slack MCP Server - Model Context Protocol implementation for Slack notifications
Supports: send_slack_message, send_equipment_alert, send_maintenance_plan
"""

from flask import Flask, request, jsonify
import requests
import os
from datetime import datetime
import logging

app = Flask(__name__)

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# Configuration
SLACK_WEBHOOK_URL = os.getenv('SLACK_WEBHOOK_URL', '')
DEFAULT_CHANNEL = os.getenv('DEFAULT_CHANNEL', '#acme-litho')
DEFAULT_USERNAME = os.getenv('DEFAULT_USERNAME', 'ACME LithoOps Agent')
DEFAULT_ICON = os.getenv('DEFAULT_ICON', ':factory:')

@app.route('/health', methods=['GET'])
def health():
    """Health check endpoint"""
    return jsonify({"status": "healthy", "service": "slack-mcp"}), 200

@app.route('/ready', methods=['GET'])
def ready():
    """Readiness check endpoint"""
    if not SLACK_WEBHOOK_URL:
        return jsonify({
            "status": "not_ready",
            "reason": "SLACK_WEBHOOK_URL not configured"
        }), 503
    return jsonify({"status": "ready"}), 200

@app.route('/tools', methods=['GET'])
def list_tools():
    """List available MCP tools (MCP protocol)"""
    return jsonify({
        "tools": [
            {
                "name": "send_slack_message",
                "description": "Send a custom message to Slack channel",
                "input_schema": {
                    "type": "object",
                    "properties": {
                        "message": {
                            "type": "string",
                            "description": "Message content"
                        },
                        "channel": {
                            "type": "string",
                            "description": "Channel name (optional, defaults to #acme-litho)"
                        },
                        "correlationId": {
                            "type": "string",
                            "description": "Correlation ID for tracking"
                        }
                    },
                    "required": ["message"]
                }
            },
            {
                "name": "send_equipment_alert",
                "description": "Send formatted equipment alert to Slack",
                "input_schema": {
                    "type": "object",
                    "properties": {
                        "equipment_id": {"type": "string"},
                        "status": {"type": "string"},
                        "overlay": {"type": "number"},
                        "overlay_ucl": {"type": "number"},
                        "dose_uniformity": {"type": "number"},
                        "dose_ucl": {"type": "number"},
                        "vibration": {"type": "number"},
                        "actions": {
                            "type": "array",
                            "items": {"type": "string"}
                        },
                        "correlationId": {"type": "string"}
                    },
                    "required": ["equipment_id", "status"]
                }
            },
            {
                "name": "send_maintenance_plan",
                "description": "Send formatted maintenance plan to Slack",
                "input_schema": {
                    "type": "object",
                    "properties": {
                        "equipment_id": {"type": "string"},
                        "plan": {"type": "string"},
                        "priority": {"type": "string"},
                        "correlationId": {"type": "string"}
                    },
                    "required": ["equipment_id", "plan"]
                }
            }
        ]
    }), 200

@app.route('/execute', methods=['POST'])
def execute_tool():
    """Execute a Slack tool (MCP protocol)"""
    data = request.json
    tool = data.get('tool')
    params = data.get('parameters', {})
    
    correlation_id = params.get('correlationId', 'unknown')
    logger.info(f"[{correlation_id}] Executing tool: {tool}")
    
    if tool == 'send_slack_message':
        return send_message(params, correlation_id)
    elif tool == 'send_equipment_alert':
        return send_alert(params, correlation_id)
    elif tool == 'send_maintenance_plan':
        return send_plan(params, correlation_id)
    else:
        return jsonify({"error": f"Unknown tool: {tool}"}), 400

def send_message(params, correlation_id):
    """Send simple Slack message"""
    message = params.get('message', '')
    channel = params.get('channel', DEFAULT_CHANNEL)
    
    payload = {
        "channel": channel,
        "text": message,
        "username": DEFAULT_USERNAME,
        "icon_emoji": DEFAULT_ICON
    }
    
    try:
        if not SLACK_WEBHOOK_URL:
            logger.warning(f"[{correlation_id}] DEMO MODE: Would send to Slack: {message[:100]}")
            return jsonify({
                "result": {
                    "success": True,
                    "demo_mode": True,
                    "channel": channel,
                    "message": message,
                    "timestamp": datetime.now().isoformat()
                }
            }), 200
        
        response = requests.post(SLACK_WEBHOOK_URL, json=payload, timeout=10)
        response.raise_for_status()
        
        logger.info(f"[{correlation_id}] Slack message sent to {channel}")
        return jsonify({
            "result": {
                "success": True,
                "channel": channel,
                "timestamp": datetime.now().isoformat(),
                "slack_response": response.text
            }
        }), 200
    except Exception as e:
        logger.error(f"[{correlation_id}] Error sending Slack message: {e}")
        return jsonify({"error": str(e)}), 500

def send_alert(params, correlation_id):
    """Send formatted equipment alert"""
    # Support both snake_case and camelCase parameter names
    equipment_id = params.get('equipment_id') or params.get('equipmentId')
    status = params.get('status') or params.get('severity', 'UNKNOWN')
    alert_message = params.get('alertMessage', '')
    channel = params.get('channel', DEFAULT_CHANNEL)
    
    # Optional detailed metrics (for full calibration reports)
    overlay = params.get('overlay', 0)
    overlay_ucl = params.get('overlay_ucl', 0)
    dose_uniformity = params.get('dose_uniformity', 0)
    dose_ucl = params.get('dose_ucl', 0)
    vibration = params.get('vibration', 0)
    actions = params.get('actions', [])
    
    # Determine severity emoji
    emoji = "🔴" if status in ["FAIL", "high", "critical"] else "🟡" if status in ["PASS_WITH_ACTION", "medium", "warning"] else "🟢"
    
    # Format Slack message - use simple format if alert_message provided, detailed if metrics provided
    if alert_message:
        # Simple alert format (from Java client)
        message = f"""{emoji} *ACME LithoOps Equipment Alert*

*Equipment:* {equipment_id}
*Severity:* {status.upper()}

{alert_message}

_[correlationId: {correlation_id}]_
_Reported: {datetime.now().strftime('%Y-%m-%d %H:%M:%S UTC')}_"""
    else:
        # Detailed metrics format (for full calibration reports)
        message = f"""{emoji} *ACME LithoOps: {status}*

*Equipment:* {equipment_id}
*Status:* {status}

*Measurements:*
• Overlay: {overlay:.2f} nm (UCL {overlay_ucl:.2f} nm)
• Dose Uniformity: {dose_uniformity:.2f}% (UCL {dose_ucl:.2f}%)
• Vibration: {vibration:.2f} mm/s
"""
        
        if actions:
            message += "\n*Recommended Actions:*\n"
            for action in actions:
                message += f"• {action}\n"
        
        message += f"\n_[correlationId: {correlation_id}]_"
        message += f"\n_Reported: {datetime.now().strftime('%Y-%m-%d %H:%M:%S UTC')}_"
    
    payload = {
        "channel": channel,
        "text": message,
        "username": "ACME LithoOps Agent",
        "icon_emoji": ":factory:"
    }
    
    try:
        if not SLACK_WEBHOOK_URL:
            logger.warning(f"[{correlation_id}] DEMO MODE: Would send equipment alert")
            print(f"\n{'='*60}")
            print(f"SLACK ALERT (DEMO MODE):")
            print(message)
            print(f"{'='*60}\n")
            return jsonify({
                "result": {
                    "success": True,
                    "demo_mode": True,
                    "equipment_id": equipment_id,
                    "message": message,
                    "timestamp": datetime.now().isoformat()
                }
            }), 200
        
        response = requests.post(SLACK_WEBHOOK_URL, json=payload, timeout=10)
        response.raise_for_status()
        
        logger.info(f"[{correlation_id}] Equipment alert sent: {equipment_id} - {status}")
        return jsonify({
            "result": {
                "success": True,
                "equipment_id": equipment_id,
                "status": status,
                "timestamp": datetime.now().isoformat(),
                "slack_response": response.text
            }
        }), 200
    except Exception as e:
        logger.error(f"[{correlation_id}] Error sending equipment alert: {e}")
        return jsonify({"error": str(e)}), 500

def send_plan(params, correlation_id):
    """Send formatted maintenance plan"""
    equipment_id = params.get('equipment_id')
    plan = params.get('plan')
    priority = params.get('priority', 'Normal')
    
    message = f"""🔧 *MAINTENANCE PLAN GENERATED*

*Equipment:* {equipment_id}
*Priority:* {priority}

*Plan:*
{plan}

_[correlationId: {correlation_id}]_
_Generated: {datetime.now().strftime('%Y-%m-%d %H:%M:%S UTC')}_"""
    
    payload = {
        "channel": DEFAULT_CHANNEL,
        "text": message,
        "username": "Maintenance Planning Agent",
        "icon_emoji": ":wrench:"
    }
    
    try:
        if not SLACK_WEBHOOK_URL:
            logger.warning(f"[{correlation_id}] DEMO MODE: Would send maintenance plan")
            print(f"\n{'='*60}")
            print(f"SLACK MAINTENANCE PLAN (DEMO MODE):")
            print(message)
            print(f"{'='*60}\n")
            return jsonify({
                "result": {
                    "success": True,
                    "demo_mode": True,
                    "equipment_id": equipment_id,
                    "timestamp": datetime.now().isoformat()
                }
            }), 200
        
        response = requests.post(SLACK_WEBHOOK_URL, json=payload, timeout=10)
        response.raise_for_status()
        
        logger.info(f"[{correlation_id}] Maintenance plan sent: {equipment_id}")
        return jsonify({
            "result": {
                "success": True,
                "equipment_id": equipment_id,
                "timestamp": datetime.now().isoformat()
            }
        }), 200
    except Exception as e:
        logger.error(f"[{correlation_id}] Error sending maintenance plan: {e}")
        return jsonify({"error": str(e)}), 500

if __name__ == '__main__':
    port = int(os.getenv('PORT', 8080))
    logger.info(f"Starting Slack MCP Server on port {port}")
    logger.info(f"Webhook configured: {bool(SLACK_WEBHOOK_URL)}")
    logger.info(f"Default channel: {DEFAULT_CHANNEL}")
    app.run(host='0.0.0.0', port=port, debug=False)


