#!/usr/bin/env python3
"""
Database MCP Server - Production PostgreSQL Integration
Supports: query_equipment, query_service_history, query_parts_inventory
"""

from flask import Flask, request, jsonify
import psycopg2
import psycopg2.extras
import os
import logging
from datetime import datetime

app = Flask(__name__)

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# PostgreSQL connection configuration
DB_CONFIG = {
    'host': os.getenv('POSTGRES_HOST', 'postgresql.private-ai-demo.svc.cluster.local'),
    'port': int(os.getenv('POSTGRES_PORT', '5432')),
    'database': os.getenv('POSTGRES_DB', 'acme_equipment'),
    'user': os.getenv('POSTGRES_USER', 'acmeadmin'),
    'password': os.getenv('POSTGRES_PASSWORD', 'acme_secure_2025'),
    'connect_timeout': 10
}

def get_db_connection():
    """Create and return a database connection"""
    try:
        conn = psycopg2.connect(**DB_CONFIG)
        return conn
    except Exception as e:
        logger.error(f"Database connection failed: {e}")
        raise

def query_equipment(params):
    """Query equipment by ID from PostgreSQL"""
    equipment_id = params.get('equipment_id')
    
    if not equipment_id:
        return jsonify({"error": "equipment_id is required"}), 400
    
    try:
        conn = get_db_connection()
        cursor = conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor)
        
        cursor.execute("""
            SELECT 
                equipment_id as id,
                equipment_type as type,
                model,
                status,
                location,
                customer,
                serial_number,
                install_date::text,
                last_pm::text,
                next_pm::text,
                wafers_processed,
                last_calibration::text,
                next_calibration_due::text
            FROM equipment
            WHERE equipment_id = %s
        """, (equipment_id,))
        
        equipment = cursor.fetchone()
        cursor.close()
        conn.close()
        
        if not equipment:
            logger.warning(f"Equipment not found: {equipment_id}")
            return jsonify({
                "error": f"Equipment not found: {equipment_id}"
            }), 404
        
        logger.info(f"Retrieved equipment: {equipment_id}")
        return jsonify({
            "result": {
                "equipment": dict(equipment)
            }
        })
        
    except Exception as e:
        logger.error(f"Failed to query equipment: {e}")
        return jsonify({"error": f"Database error: {str(e)}"}), 500

def query_service_history(params):
    """Query service history from PostgreSQL"""
    equipment_id = params.get('equipment_id')
    limit = params.get('limit', 10)
    
    if not equipment_id:
        return jsonify({"error": "equipment_id is required"}), 400
    
    try:
        conn = get_db_connection()
        cursor = conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor)
        
        cursor.execute("""
            SELECT 
                service_date::text as date,
                service_type as type,
                technician as tech,
                notes,
                parts_used,
                duration_hours,
                cost_usd
            FROM service_history
            WHERE equipment_id = %s
            ORDER BY service_date DESC
            LIMIT %s
        """, (equipment_id, limit))
        
        history = cursor.fetchall()
        cursor.close()
        conn.close()
        
        logger.info(f"Retrieved {len(history)} service records for {equipment_id}")
        return jsonify({
            "result": {
                "equipment_id": equipment_id,
                "history": [dict(record) for record in history],
                "count": len(history)
            }
        })
        
    except Exception as e:
        logger.error(f"Failed to query service history: {e}")
        return jsonify({"error": f"Database error: {str(e)}"}), 500

def query_parts_inventory(params):
    """Query parts inventory from PostgreSQL"""
    part_number = params.get('part_number')
    
    if not part_number:
        return jsonify({"error": "part_number is required"}), 400
    
    try:
        conn = get_db_connection()
        cursor = conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor)
        
        cursor.execute("""
            SELECT 
                part_number,
                part_name as name,
                description,
                stock_level,
                min_stock_level,
                lead_time_days,
                price_usd as price,
                supplier,
                category
            FROM parts_inventory
            WHERE part_number = %s
        """, (part_number,))
        
        part = cursor.fetchone()
        cursor.close()
        conn.close()
        
        if not part:
            logger.warning(f"Part not found: {part_number}")
            return jsonify({
                "error": f"Part not found: {part_number}"
            }), 404
        
        logger.info(f"Retrieved part: {part_number}")
        return jsonify({
            "result": {
                "part": dict(part)
            }
        })
        
    except Exception as e:
        logger.error(f"Failed to query parts: {e}")
        return jsonify({"error": f"Database error: {str(e)}"}), 500

# MCP Protocol endpoint
@app.route('/execute', methods=['POST'])
def execute():
    """
    MCP Protocol endpoint - single entry point for all tool executions.
    Request format: {"tool": "tool_name", "parameters": {...}}
    """
    try:
        data = request.json
        tool = data.get('tool')
        parameters = data.get('parameters', {})
        
        logger.info(f"MCP Request: tool={tool}, params={parameters}")
        
        # Route to appropriate handler
        if tool == 'query_equipment':
            return query_equipment(parameters)
        elif tool == 'query_service_history':
            return query_service_history(parameters)
        elif tool == 'query_parts_inventory':
            return query_parts_inventory(parameters)
        else:
            logger.error(f"Unknown tool: {tool}")
            return jsonify({
                "error": f"Unknown tool: {tool}",
                "available_tools": ["query_equipment", "query_service_history", "query_parts_inventory"]
            }), 400
            
    except Exception as e:
        logger.error(f"Request execution failed: {e}")
        return jsonify({"error": str(e)}), 500

@app.route('/health', methods=['GET'])
def health():
    """Health check endpoint"""
    try:
        # Test database connection
        conn = get_db_connection()
        cursor = conn.cursor()
        cursor.execute("SELECT 1")
        cursor.close()
        conn.close()
        
        return jsonify({
            "status": "healthy",
            "service": "database-mcp",
            "database": "connected",
            "timestamp": datetime.utcnow().isoformat()
        })
    except Exception as e:
        logger.error(f"Health check failed: {e}")
        return jsonify({
            "status": "unhealthy",
            "service": "database-mcp",
            "database": "disconnected",
            "error": str(e),
            "timestamp": datetime.utcnow().isoformat()
        }), 503

@app.route('/tools', methods=['GET'])
def list_tools():
    """List available MCP tools"""
    return jsonify({
        "tools": [
            {
                "name": "query_equipment",
                "description": "Query equipment information by ID",
                "parameters": {
                    "equipment_id": "string (required)"
                }
            },
            {
                "name": "query_service_history",
                "description": "Query service history for equipment",
                "parameters": {
                    "equipment_id": "string (required)",
                    "limit": "integer (optional, default 10)"
                }
            },
            {
                "name": "query_parts_inventory",
                "description": "Query parts inventory by part number",
                "parameters": {
                    "part_number": "string (required)"
                }
            }
        ]
    })

if __name__ == '__main__':
    logger.info("=" * 60)
    logger.info("Database MCP Server - Production PostgreSQL Integration")
    logger.info("=" * 60)
    logger.info(f"Database host: {DB_CONFIG['host']}")
    logger.info(f"Database name: {DB_CONFIG['database']}")
    logger.info(f"Database user: {DB_CONFIG['user']}")
    port = int(os.getenv('PORT', '8080'))
    logger.info(f"Starting server on port {port}...")
    logger.info("=" * 60)
    
    app.run(host='0.0.0.0', port=port, debug=False)
