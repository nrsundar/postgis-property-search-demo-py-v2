# Module 02: PostgreSQL Extensions and PostGIS

## Overview
Comprehensive guide to PostgreSQL extensions with focus on PostGIS for spatial data handling.

## Key Extensions for Property Search

### PostGIS - Spatial Database Extension
```sql
-- Install PostGIS extension
CREATE EXTENSION IF NOT EXISTS postgis;
CREATE EXTENSION IF NOT EXISTS postgis_topology;
CREATE EXTENSION IF NOT EXISTS postgis_raster;

-- Check PostGIS version
SELECT PostGIS_Version();
SELECT PostGIS_Full_Version();
```

### pg_trgm - Text Search Enhancement
```sql
-- Enable trigram indexing for address search
CREATE EXTENSION IF NOT EXISTS pg_trgm;

-- Create GIN index for fast text search
CREATE INDEX idx_address_gin ON properties 
USING GIN (address gin_trgm_ops);
```

### btree_gist - Advanced Indexing
```sql
-- Enable btree_gist for range queries
CREATE EXTENSION IF NOT EXISTS btree_gist;

-- Create composite index for price and area ranges
CREATE INDEX idx_price_area_range ON properties 
USING GIST (price, square_feet);
```

## Spatial Data Types

### Geometry vs Geography
```sql
-- Geometry type (projected coordinates)
ALTER TABLE properties ADD COLUMN geom_point GEOMETRY(POINT, 4326);

-- Geography type (spherical coordinates)
ALTER TABLE properties ADD COLUMN geog_point GEOGRAPHY(POINT, 4326);

-- Insert sample data
INSERT INTO properties (address, price, geom_point, geog_point) VALUES
('123 Main St', 500000, 
 ST_GeomFromText('POINT(-122.4194 37.7749)', 4326),
 ST_GeogFromText('POINT(-122.4194 37.7749)'));
```

### Polygon Boundaries
```sql
-- Create neighborhood boundaries table
CREATE TABLE neighborhoods (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100),
    boundary GEOMETRY(POLYGON, 4326)
);

-- Insert neighborhood polygon
INSERT INTO neighborhoods (name, boundary) VALUES
('Downtown', ST_GeomFromText('POLYGON((-122.42 37.77, -122.41 37.77, 
                               -122.41 37.76, -122.42 37.76, 
                               -122.42 37.77))', 4326));
```

## Performance Optimization

### Spatial Indexing
```sql
-- Create spatial index on property locations
CREATE INDEX idx_properties_geom ON properties USING GIST (geom_point);

-- Create partial index for active listings
CREATE INDEX idx_active_properties_geom ON properties 
USING GIST (geom_point) WHERE status = 'active';
```

### Query Examples
```sql
-- Find properties within 1km radius
SELECT address, price 
FROM properties 
WHERE ST_DWithin(geog_point, ST_GeogFromText('POINT(-122.4194 37.7749)'), 1000);

-- Find properties in specific neighborhood
SELECT p.address, p.price, n.name
FROM properties p
JOIN neighborhoods n ON ST_Within(p.geom_point, n.boundary);
```

## Extension Management
```sql
-- List all installed extensions
SELECT name, default_version, installed_version 
FROM pg_available_extensions 
WHERE installed_version IS NOT NULL;

-- Update extension
ALTER EXTENSION postgis UPDATE;
```

## Next Steps
Proceed to Module 03 to implement spatial data types and advanced indexing strategies.
