-- ACME Equipment Database Schema
-- Production schema for lithography equipment management

-- Equipment table
CREATE TABLE IF NOT EXISTS equipment (
    equipment_id VARCHAR(50) PRIMARY KEY,
    equipment_type VARCHAR(100) NOT NULL,
    model VARCHAR(100) NOT NULL,
    status VARCHAR(50) NOT NULL CHECK (status IN ('Operational', 'Maintenance Due', 'Under Maintenance', 'Offline')),
    location VARCHAR(200) NOT NULL,
    customer VARCHAR(200) NOT NULL,
    serial_number VARCHAR(100) UNIQUE NOT NULL,
    install_date DATE NOT NULL,
    last_pm DATE,
    next_pm DATE,
    wafers_processed INTEGER DEFAULT 0,
    last_calibration DATE,
    next_calibration_due DATE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Service history table
CREATE TABLE IF NOT EXISTS service_history (
    service_id SERIAL PRIMARY KEY,
    equipment_id VARCHAR(50) NOT NULL REFERENCES equipment(equipment_id) ON DELETE CASCADE,
    service_date DATE NOT NULL,
    service_type VARCHAR(100) NOT NULL CHECK (service_type IN ('Preventive Maintenance', 'Corrective Maintenance', 'Calibration', 'Upgrade', 'Inspection')),
    technician VARCHAR(50) NOT NULL,
    notes TEXT NOT NULL,
    parts_used TEXT[],  -- Array of part numbers
    duration_hours DECIMAL(5,2),
    cost_usd DECIMAL(10,2),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Parts inventory table
CREATE TABLE IF NOT EXISTS parts_inventory (
    part_number VARCHAR(50) PRIMARY KEY,
    part_name VARCHAR(200) NOT NULL,
    description TEXT NOT NULL,
    stock_level INTEGER NOT NULL DEFAULT 0,
    min_stock_level INTEGER DEFAULT 5,
    lead_time_days INTEGER NOT NULL,
    price_usd DECIMAL(10,2) NOT NULL,
    supplier VARCHAR(200),
    category VARCHAR(100),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Calibration records table
CREATE TABLE IF NOT EXISTS calibration_records (
    calibration_id SERIAL PRIMARY KEY,
    equipment_id VARCHAR(50) NOT NULL REFERENCES equipment(equipment_id) ON DELETE CASCADE,
    calibration_date TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    parameter VARCHAR(100) NOT NULL,
    measured_value DECIMAL(10,4),
    target_value DECIMAL(10,4),
    tolerance DECIMAL(10,4),
    status VARCHAR(20) CHECK (status IN ('PASS', 'FAIL', 'WARNING')),
    technician VARCHAR(50) NOT NULL,
    notes TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Indexes for performance
CREATE INDEX IF NOT EXISTS idx_service_history_equipment ON service_history(equipment_id, service_date DESC);
CREATE INDEX IF NOT EXISTS idx_calibration_records_equipment ON calibration_records(equipment_id, calibration_date DESC);
CREATE INDEX IF NOT EXISTS idx_parts_category ON parts_inventory(category);
CREATE INDEX IF NOT EXISTS idx_equipment_status ON equipment(status);

-- Insert LITHO-001 equipment data
INSERT INTO equipment (equipment_id, equipment_type, model, status, location, customer, serial_number, 
                       install_date, last_pm, next_pm, wafers_processed, last_calibration, next_calibration_due)
VALUES 
    ('LITHO-001', 'EUV Scanner', 'ASML TWINSCAN NXE:3400C', 'Operational', 'Fab 5, Bay 3', 
     'ACME Semiconductor', 'NXE3400C-2023-001', '2023-06-01', '2025-09-01', '2025-12-01', 
     125000, '2025-10-01', '2025-11-01'),
    ('L-900-07', 'L-900 EUV Scanner', 'ASML TWINSCAN NXE:3600D', 'Operational', 'Fab 3, Bay 12',
     'ACME Semiconductor', 'NXE3600D-2024-007', '2024-01-15', '2024-09-15', '2024-12-15',
     85000, '2024-09-15', '2024-12-15'),
    ('L-900-08', 'L-900 EUV Scanner', 'ASML TWINSCAN NXE:3600D', 'Maintenance Due', 'Fab 3, Bay 8',
     'ACME Semiconductor', 'NXE3600D-2024-008', '2024-02-20', '2024-08-20', '2024-11-20',
     72000, '2024-08-20', '2024-11-20'),
    ('ABC123', 'Overlay Metrology', 'KLA YieldStar', 'Operational', 'Fab 3, Metrology Lab',
     'ACME Semiconductor', 'YS-2024-123', '2024-03-10', '2024-09-10', '2025-01-10',
     0, '2024-09-10', '2025-01-10')
ON CONFLICT (equipment_id) DO NOTHING;

-- Insert service history for LITHO-001
INSERT INTO service_history (equipment_id, service_date, service_type, technician, notes, parts_used, duration_hours, cost_usd)
VALUES 
    ('LITHO-001', '2025-10-01', 'Calibration', 'TECH-015', 
     'Overlay accuracy calibration performed. All parameters within spec.', 
     '{}', 4.5, 2500.00),
    ('LITHO-001', '2025-09-01', 'Preventive Maintenance', 'TECH-007',
     'Quarterly PM completed. Optics cleaned, stage recalibrated.',
     '{P12345}', 8.0, 5000.00),
    ('LITHO-001', '2025-08-15', 'Corrective Maintenance', 'TECH-012',
     'Focus sensor adjustment. Returned to nominal performance.',
     '{}', 2.5, 1500.00),
    ('L-900-07', '2024-10-01', 'Preventive Maintenance', 'TECH-007',
     'DFO calibration completed. Overlay within spec.',
     '{P12345}', 6.0, 4000.00),
    ('L-900-07', '2024-09-15', 'Calibration', 'TECH-012',
     'Overlay calibration performed. Passed acceptance criteria.',
     '{}', 3.0, 1800.00)
ON CONFLICT DO NOTHING;

-- Insert parts inventory
INSERT INTO parts_inventory (part_number, part_name, description, stock_level, min_stock_level, lead_time_days, price_usd, supplier, category)
VALUES 
    ('P12345', 'DFO Module', 'Dynamic Focus Optimizer - Critical alignment component', 12, 3, 45, 125000.00, 'ASML Parts', 'Optics'),
    ('P67890', 'Stage Controller', 'High-precision wafer stage control unit', 5, 2, 60, 85000.00, 'ASML Parts', 'Electronics'),
    ('P11111', 'Laser Module', 'EUV laser source module', 2, 1, 90, 450000.00, 'ASML Parts', 'Light Source'),
    ('P22222', 'Mirror Assembly', 'Precision EUV mirror assembly', 3, 1, 120, 350000.00, 'ASML Parts', 'Optics'),
    ('P33333', 'Vacuum Pump', 'High-vacuum pump for chamber', 8, 2, 30, 15000.00, 'Edwards', 'Mechanical'),
    ('P44444', 'Sensor Kit', 'Calibration sensor kit (overlay, focus, dose)', 15, 5, 14, 8500.00, 'KLA', 'Metrology')
ON CONFLICT (part_number) DO NOTHING;

-- Insert calibration records for LITHO-001
INSERT INTO calibration_records (equipment_id, calibration_date, parameter, measured_value, target_value, tolerance, status, technician, notes)
VALUES 
    ('LITHO-001', '2025-10-01 14:30:00', 'overlay_accuracy_x', 1.2, 0.0, 3.5, 'PASS', 'TECH-015', 'Within specification'),
    ('LITHO-001', '2025-10-01 14:30:00', 'overlay_accuracy_y', -0.8, 0.0, 3.5, 'PASS', 'TECH-015', 'Within specification'),
    ('LITHO-001', '2025-10-01 15:00:00', 'focus_offset', 0.05, 0.0, 0.15, 'PASS', 'TECH-015', 'Excellent alignment'),
    ('LITHO-001', '2025-09-01 10:00:00', 'overlay_accuracy_x', 2.1, 0.0, 3.5, 'PASS', 'TECH-007', 'After PM service'),
    ('LITHO-001', '2025-09-01 10:00:00', 'overlay_accuracy_y', 1.9, 0.0, 3.5, 'PASS', 'TECH-007', 'After PM service')
ON CONFLICT DO NOTHING;

-- Create view for quick equipment status
CREATE OR REPLACE VIEW equipment_status_summary AS
SELECT 
    e.equipment_id,
    e.model,
    e.status,
    e.location,
    e.last_pm,
    e.next_pm,
    e.last_calibration,
    e.next_calibration_due,
    COALESCE(sh.last_service_date, e.install_date) as last_service_date,
    COALESCE(sh.last_service_type, 'Installation') as last_service_type,
    COALESCE(cr.last_calibration_status, 'Unknown') as last_calibration_status
FROM equipment e
LEFT JOIN (
    SELECT equipment_id, MAX(service_date) as last_service_date, 
           (ARRAY_AGG(service_type ORDER BY service_date DESC))[1] as last_service_type
    FROM service_history
    GROUP BY equipment_id
) sh ON e.equipment_id = sh.equipment_id
LEFT JOIN (
    SELECT equipment_id, (ARRAY_AGG(status ORDER BY calibration_date DESC))[1] as last_calibration_status
    FROM calibration_records
    GROUP BY equipment_id
) cr ON e.equipment_id = cr.equipment_id;

-- Grant permissions (will be used by database-mcp service account)
-- Note: User will be created by the connection string credentials
GRANT SELECT, INSERT, UPDATE ON ALL TABLES IN SCHEMA public TO acmeadmin;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO acmeadmin;

