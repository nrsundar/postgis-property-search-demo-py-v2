#!/bin/bash
# Database Setup Script for postgis-property-search-demo-py
# This script connects to Aurora PostgreSQL and sets up PostGIS

set -e

echo "Setting up postgis-property-search-demo-py on Aurora PostgreSQL..."

# Database connection variables (update with actual CloudFormation outputs)
DB_HOST="${DB_HOST:-<database-endpoint-from-cloudformation>}"
DB_PORT="${DB_PORT:-5432}"
DB_NAME="${DB_NAME:-postgres}"
DB_USER="${DB_USER:-postgres}"
DB_PASSWORD="${DB_PASSWORD:-SecurePassword123!}"

CONNECTION_STRING="postgresql://$DB_USER:$DB_PASSWORD@$DB_HOST:$DB_PORT/$DB_NAME"

echo "Connecting to database at $DB_HOST..."

# Enable PostGIS extension
echo "Enabling PostGIS extension..."
psql "$CONNECTION_STRING" -c "CREATE EXTENSION IF NOT EXISTS postgis;"
psql "$CONNECTION_STRING" -c "CREATE EXTENSION IF NOT EXISTS postgis_topology;"

# Create property search schema and tables for real estate demo
echo "Creating property search tables..."
psql "$CONNECTION_STRING" << 'EOF'
-- Create properties table with spatial data
CREATE TABLE IF NOT EXISTS properties (
    id SERIAL PRIMARY KEY,
    address TEXT NOT NULL,
    price DECIMAL(12,2) NOT NULL,
    bedrooms INTEGER,
    bathrooms INTEGER,
    square_feet INTEGER,
    property_type TEXT,
    listing_status TEXT DEFAULT 'active',
    location GEOMETRY(POINT, 4326),
    listing_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    last_updated TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Create spatial index for efficient geographic queries
CREATE INDEX IF NOT EXISTS idx_properties_location ON properties USING GIST (location);

-- Insert sample property data
INSERT INTO properties (address, price, bedrooms, bathrooms, square_feet, property_type, location) VALUES
('123 Main St, Seattle, WA', 750000, 3, 2, 1800, 'Single Family', ST_GeomFromText('POINT(-122.3321 47.6062)', 4326)),
('456 Oak Ave, Seattle, WA', 650000, 2, 2, 1200, 'Condo', ST_GeomFromText('POINT(-122.3411 47.6152)', 4326)),
('789 Pine Rd, Seattle, WA', 850000, 4, 3, 2200, 'Single Family', ST_GeomFromText('POINT(-122.3201 47.5962)', 4326))
ON CONFLICT DO NOTHING;

-- Create function for nearby property search
CREATE OR REPLACE FUNCTION find_nearby_properties(
    property_id INTEGER,
    radius_meters INTEGER DEFAULT 1000
) RETURNS TABLE (
    id INTEGER,
    address TEXT,
    price DECIMAL,
    distance_meters DOUBLE PRECISION
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        p2.id,
        p2.address,
        p2.price,
        ST_Distance(p1.location::geography, p2.location::geography) as distance_meters
    FROM properties p1
    CROSS JOIN properties p2
    WHERE p1.id = property_id
      AND p2.id != property_id
      AND ST_DWithin(p1.location::geography, p2.location::geography, radius_meters)
    ORDER BY distance_meters;
END;
$$ LANGUAGE plpgsql;
EOF


echo "Verifying PostGIS installation..."
psql "$CONNECTION_STRING" -c "SELECT PostGIS_Version();"

echo "Database setup completed successfully!"
echo "Connection string: $CONNECTION_STRING"
