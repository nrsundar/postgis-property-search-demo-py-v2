# Module 04: Advanced Spatial Queries and Radius Search

## Overview
Implementing efficient spatial queries for property search with radius-based filtering.

## Basic Spatial Queries
```sql
-- Find properties within radius (using geography for accuracy)
SELECT 
    id, address, price,
    ST_Distance(location, ST_GeogFromText('POINT(-122.4194 37.7749)')) as distance_meters
FROM properties 
WHERE ST_DWithin(
    location::geography, 
    ST_GeogFromText('POINT(-122.4194 37.7749)'), 
    1000  -- 1km radius
)
AND listing_status = 'active'
ORDER BY distance_meters;

-- Find properties in specific neighborhood
SELECT p.*, n.name as neighborhood
FROM properties p
JOIN neighborhoods n ON ST_Within(p.location, n.boundary)
WHERE n.name = 'Downtown'
AND p.listing_status = 'active';
```

## Advanced Distance Calculations
```sql
-- Create function for haversine distance calculation
CREATE OR REPLACE FUNCTION haversine_distance(
    lat1 float, lon1 float, 
    lat2 float, lon2 float
) RETURNS float AS $$
DECLARE
    R float := 6371000; -- Earth radius in meters
    dLat float;
    dLon float;
    a float;
    c float;
BEGIN
    dLat := radians(lat2 - lat1);
    dLon := radians(lon2 - lon1);
    a := sin(dLat/2) * sin(dLat/2) + 
         cos(radians(lat1)) * cos(radians(lat2)) * 
         sin(dLon/2) * sin(dLon/2);
    c := 2 * atan2(sqrt(a), sqrt(1-a));
    RETURN R * c;
END;
$$ LANGUAGE plpgsql IMMUTABLE;

-- Use in queries for custom distance calculations
SELECT 
    id, address, price,
    haversine_distance(latitude, longitude, 37.7749, -122.4194) as custom_distance
FROM properties
WHERE haversine_distance(latitude, longitude, 37.7749, -122.4194) < 1000
ORDER BY custom_distance;
```

## Polygon-Based Searches
```sql
-- Search within custom drawn area
WITH search_polygon AS (
    SELECT ST_GeomFromText('POLYGON((
        -122.42 37.77, -122.41 37.77, 
        -122.41 37.76, -122.42 37.76, 
        -122.42 37.77
    ))', 4326) as polygon
)
SELECT p.*
FROM properties p, search_polygon sp
WHERE ST_Within(p.location, sp.polygon)
AND p.listing_status = 'active';

-- Buffer search around a point
SELECT p.*
FROM properties p
WHERE ST_Within(
    p.location,
    ST_Buffer(ST_GeogFromText('POINT(-122.4194 37.7749)')::geometry, 0.01)
);
```

## Optimized Search Function
```sql
CREATE OR REPLACE FUNCTION search_properties(
    center_lat float,
    center_lon float,
    radius_meters integer DEFAULT 1000,
    min_price decimal DEFAULT 0,
    max_price decimal DEFAULT 999999999,
    property_types text[] DEFAULT ARRAY['single_family', 'condo', 'townhouse'],
    min_bedrooms integer DEFAULT 0,
    max_bedrooms integer DEFAULT 10
) RETURNS TABLE (
    property_id integer,
    address text,
    price decimal,
    bedrooms integer,
    distance_meters float
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        p.id,
        p.address::text,
        p.price,
        p.bedrooms,
        ST_Distance(p.location::geography, ST_GeogFromText('POINT(' || center_lon || ' ' || center_lat || ')'))
    FROM properties p
    WHERE ST_DWithin(
        p.location::geography,
        ST_GeogFromText('POINT(' || center_lon || ' ' || center_lat || ')'),
        radius_meters
    )
    AND p.price BETWEEN min_price AND max_price
    AND p.property_type = ANY(property_types)
    AND p.bedrooms BETWEEN min_bedrooms AND max_bedrooms
    AND p.listing_status = 'active'
    ORDER BY ST_Distance(p.location::geography, ST_GeogFromText('POINT(' || center_lon || ' ' || center_lat || ')'));
END;
$$ LANGUAGE plpgsql;

-- Usage example
SELECT * FROM search_properties(
    37.7749, -122.4194,  -- San Francisco coordinates
    2000,                 -- 2km radius
    500000, 1500000,      -- Price range
    ARRAY['single_family', 'condo'],
    2, 4                  -- 2-4 bedrooms
);
```

## Next Steps
Continue to Module 05 for property comparison algorithms and market analysis.
