-- Property Search Database Setup for postgis-property-search-demo-py
-- PostgreSQL Aurora PostgreSQL 15 + PostGIS 3.4 with PostGIS

-- Create main database
CREATE DATABASE postgis_property_search_demo_py;

-- Connect to the database
\c postgis_property_search_demo_py;

-- PostGIS extension for spatial data
CREATE EXTENSION IF NOT EXISTS postgis;
CREATE EXTENSION IF NOT EXISTS postgis_topology;
CREATE EXTENSION IF NOT EXISTS postgis_raster;

-- Other useful extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS pg_trgm;
CREATE EXTENSION IF NOT EXISTS btree_gist;

-- Create properties table with spatial column
CREATE TABLE IF NOT EXISTS properties (
    id SERIAL PRIMARY KEY,
    address TEXT NOT NULL,
    price DECIMAL(12,2),
    bedrooms INTEGER,
    bathrooms DECIMAL(3,1),
    square_feet INTEGER,
    property_type VARCHAR(50),
    listing_status VARCHAR(20) DEFAULT 'active',
    location GEOMETRY(POINT, 4326),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Create spatial index on location
CREATE INDEX IF NOT EXISTS idx_properties_location ON properties USING GIST (location);
CREATE INDEX IF NOT EXISTS idx_properties_price ON properties (price);
CREATE INDEX IF NOT EXISTS idx_properties_status ON properties (listing_status);

-- Insert sample property data
INSERT INTO properties (address, price, bedrooms, bathrooms, square_feet, property_type, location) VALUES
('123 Market St, San Francisco, CA', 1200000, 3, 2.5, 1800, 'Single Family', ST_GeomFromText('POINT(-122.4194 37.7749)', 4326)),
('456 Oak Ave, Seattle, WA', 650000, 2, 2, 1200, 'Condo', ST_GeomFromText('POINT(-122.3411 47.6152)', 4326))
ON CONFLICT DO NOTHING;
