# Module 03: Spatial Data Types and Indexing

## Overview
Advanced spatial data types, indexing strategies, and performance optimization for property search systems.

## Core Spatial Data Types

### POINT - Property Locations
```sql
-- Create properties table with spatial column
CREATE TABLE properties (
    id SERIAL PRIMARY KEY,
    address TEXT NOT NULL,
    price DECIMAL(12,2),
    bedrooms INTEGER,
    bathrooms DECIMAL(3,1),
    square_feet INTEGER,
    property_type VARCHAR(50),
    listing_status VARCHAR(20) DEFAULT 'active',
    location GEOMETRY(POINT, 4326),
    created_at TIMESTAMP DEFAULT NOW()
);

-- Insert sample properties
INSERT INTO properties (address, price, bedrooms, bathrooms, square_feet, property_type, location) VALUES
('123 Oak Street, San Francisco, CA', 1200000, 3, 2.5, 1800, 'Single Family', 
 ST_GeomFromText('POINT(-122.4194 37.7749)', 4326)),
('456 Pine Avenue, San Francisco, CA', 850000, 2, 2, 1200, 'Condo', 
 ST_GeomFromText('POINT(-122.4094 37.7849)', 4326));
```

### POLYGON - Neighborhood Boundaries
```sql
-- Create neighborhoods with polygon boundaries
CREATE TABLE neighborhoods (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100) UNIQUE,
    description TEXT,
    avg_price DECIMAL(12,2),
    boundary GEOMETRY(POLYGON, 4326),
    created_at TIMESTAMP DEFAULT NOW()
);

-- Insert neighborhood data
INSERT INTO neighborhoods (name, description, avg_price, boundary) VALUES
('Mission District', 'Vibrant cultural neighborhood', 750000,
 ST_GeomFromText('POLYGON((-122.42 37.76, -122.40 37.76, -122.40 37.74, -122.42 37.74, -122.42 37.76))', 4326));
```

### LINESTRING - Transportation Routes
```sql
-- Create transit lines table
CREATE TABLE transit_lines (
    id SERIAL PRIMARY KEY,
    line_name VARCHAR(50),
    transport_type VARCHAR(20), -- bus, metro, light_rail
    route GEOMETRY(LINESTRING, 4326)
);

-- Insert transit route
INSERT INTO transit_lines (line_name, transport_type, route) VALUES
('MUNI Line 1', 'bus', 
 ST_GeomFromText('LINESTRING(-122.42 37.78, -122.41 37.77, -122.40 37.76)', 4326));
```

## Advanced Indexing Strategies

### GIST Spatial Indexes
```sql
-- Primary spatial index for property locations
CREATE INDEX idx_properties_location_gist ON properties USING GIST (location);

-- Neighborhood boundary index
CREATE INDEX idx_neighborhoods_boundary_gist ON neighborhoods USING GIST (boundary);

-- Transit route index
CREATE INDEX idx_transit_routes_gist ON transit_lines USING GIST (route);
```

### Partial Indexes for Performance
```sql
-- Index only active listings
CREATE INDEX idx_active_properties_location ON properties 
USING GIST (location) WHERE listing_status = 'active';

-- Index by property type
CREATE INDEX idx_sfh_properties_location ON properties 
USING GIST (location) WHERE property_type = 'Single Family';

-- Price range indexes
CREATE INDEX idx_luxury_properties_location ON properties 
USING GIST (location) WHERE price > 1000000;
```

### Composite Indexes
```sql
-- Combined spatial and attribute index
CREATE INDEX idx_properties_price_location ON properties 
USING GIST (location, price);

-- Multi-column BTREE for non-spatial attributes
CREATE INDEX idx_properties_price_sqft ON properties (price, square_feet, bedrooms);
```

## Spatial Query Patterns

### Distance-Based Searches
```sql
-- Properties within 1 mile of downtown
SELECT id, address, price,
       ST_Distance(location, ST_GeomFromText('POINT(-122.4194 37.7749)', 4326)) * 111320 as distance_meters
FROM properties 
WHERE ST_DWithin(location, ST_GeomFromText('POINT(-122.4194 37.7749)', 4326), 0.01) -- ~1km
ORDER BY distance_meters;
```

### Containment Queries
```sql
-- Properties within specific neighborhood
SELECT p.address, p.price, n.name as neighborhood
FROM properties p
JOIN neighborhoods n ON ST_Within(p.location, n.boundary)
WHERE p.listing_status = 'active';
```

### Proximity to Transit
```sql
-- Properties within 500m of transit
SELECT DISTINCT p.address, p.price, t.line_name
FROM properties p
CROSS JOIN transit_lines t
WHERE ST_DWithin(p.location, t.route, 0.005) -- ~500m
  AND p.listing_status = 'active';
```

## Performance Monitoring

### Index Usage Statistics
```sql
-- Check spatial index usage
SELECT schemaname, tablename, indexname, idx_scan, idx_tup_read
FROM pg_stat_user_indexes 
WHERE indexname LIKE '%gist%'
ORDER BY idx_scan DESC;
```

### Query Performance Analysis
```sql
-- Analyze spatial query performance
EXPLAIN (ANALYZE, BUFFERS) 
SELECT address, price 
FROM properties 
WHERE ST_DWithin(location, ST_GeomFromText('POINT(-122.4194 37.7749)', 4326), 0.01);
```

## Index Maintenance
```sql
-- Reindex spatial indexes
REINDEX INDEX CONCURRENTLY idx_properties_location_gist;

-- Update table statistics
ANALYZE properties;

-- Check index bloat
SELECT schemaname, tablename, indexname, 
       pg_size_pretty(pg_relation_size(indexrelid)) as index_size
FROM pg_stat_user_indexes 
WHERE schemaname = 'public';
```

## Next Steps
Proceed to Module 04 to implement property data import and bulk loading strategies.
