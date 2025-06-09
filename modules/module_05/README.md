# Module 05: Property Comparison and Market Analysis

## Overview
Implementing sophisticated property comparison algorithms and market analysis features.

## Comparable Properties Algorithm
```sql
CREATE OR REPLACE FUNCTION find_comparable_properties(
    target_property_id integer,
    radius_meters integer DEFAULT 1500,
    price_variance_percent decimal DEFAULT 20,
    sqft_variance_percent decimal DEFAULT 25,
    max_results integer DEFAULT 10
) RETURNS TABLE (
    comp_id integer,
    address text,
    price decimal,
    price_per_sqft decimal,
    similarity_score decimal,
    distance_meters float
) AS $$
DECLARE
    target_record RECORD;
    price_min decimal;
    price_max decimal;
    sqft_min integer;
    sqft_max integer;
BEGIN
    -- Get target property details
    SELECT * INTO target_record FROM properties WHERE id = target_property_id;
    
    -- Calculate search ranges
    price_min := target_record.price * (1 - price_variance_percent/100);
    price_max := target_record.price * (1 + price_variance_percent/100);
    sqft_min := target_record.square_feet * (1 - sqft_variance_percent/100);
    sqft_max := target_record.square_feet * (1 + sqft_variance_percent/100);
    
    RETURN QUERY
    SELECT 
        p.id,
        p.address::text,
        p.price,
        ROUND(p.price / NULLIF(p.square_feet, 0), 2) as price_per_sqft,
        -- Similarity score calculation
        ROUND(
            100 - (
                ABS(p.price - target_record.price) / target_record.price * 30 +
                ABS(p.square_feet - target_record.square_feet) / target_record.square_feet * 20 +
                ABS(p.bedrooms - target_record.bedrooms) * 10 +
                ABS(p.bathrooms - target_record.bathrooms) * 5 +
                CASE WHEN p.property_type = target_record.property_type THEN 0 ELSE 15 END
            ), 2
        ) as similarity_score,
        ST_Distance(p.location::geography, target_record.location::geography) as distance_meters
    FROM properties p
    WHERE p.id != target_property_id
    AND p.listing_status = 'active'
    AND ST_DWithin(p.location::geography, target_record.location::geography, radius_meters)
    AND p.price BETWEEN price_min AND price_max
    AND p.square_feet BETWEEN sqft_min AND sqft_max
    AND ABS(p.bedrooms - target_record.bedrooms) <= 1
    ORDER BY similarity_score DESC, distance_meters ASC
    LIMIT max_results;
END;
$$ LANGUAGE plpgsql;
```

## Market Statistics Functions
```sql
-- Calculate neighborhood statistics
CREATE OR REPLACE FUNCTION get_neighborhood_stats(neighborhood_name text)
RETURNS TABLE (
    total_listings integer,
    median_price decimal,
    avg_price_per_sqft decimal,
    avg_days_on_market decimal,
    price_trend_30d decimal
) AS $$
BEGIN
    RETURN QUERY
    WITH current_stats AS (
        SELECT 
            COUNT(*) as listings,
            PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY p.price) as med_price,
            AVG(p.price / NULLIF(p.square_feet, 0)) as avg_psf,
            AVG(EXTRACT(DAY FROM NOW() - p.listing_date)) as avg_dom
        FROM properties p
        JOIN neighborhoods n ON ST_Within(p.location, n.boundary)
        WHERE n.name = neighborhood_name
        AND p.listing_status = 'active'
    ),
    historical_stats AS (
        SELECT AVG(p.price) as avg_price_30d_ago
        FROM properties p
        JOIN neighborhoods n ON ST_Within(p.location, n.boundary)
        WHERE n.name = neighborhood_name
        AND p.listing_date BETWEEN NOW() - INTERVAL '60 days' AND NOW() - INTERVAL '30 days'
    )
    SELECT 
        cs.listings::integer,
        cs.med_price,
        ROUND(cs.avg_psf, 2),
        ROUND(cs.avg_dom, 1),
        ROUND(((cs.med_price - hs.avg_price_30d_ago) / NULLIF(hs.avg_price_30d_ago, 0) * 100), 2)
    FROM current_stats cs, historical_stats hs;
END;
$$ LANGUAGE plpgsql;
```

## Investment Analysis
```sql
-- Calculate investment metrics
CREATE OR REPLACE FUNCTION calculate_investment_metrics(
    property_id integer,
    estimated_rent decimal,
    down_payment_percent decimal DEFAULT 20,
    interest_rate decimal DEFAULT 6.5,
    loan_term_years integer DEFAULT 30
) RETURNS TABLE (
    cap_rate decimal,
    cash_on_cash_return decimal,
    monthly_cash_flow decimal,
    break_even_ratio decimal
) AS $$
DECLARE
    property_price decimal;
    down_payment decimal;
    loan_amount decimal;
    monthly_payment decimal;
    monthly_expenses decimal;
BEGIN
    SELECT price INTO property_price FROM properties WHERE id = property_id;
    
    down_payment := property_price * (down_payment_percent / 100);
    loan_amount := property_price - down_payment;
    
    -- Calculate monthly mortgage payment
    monthly_payment := loan_amount * 
        (interest_rate/100/12 * POWER(1 + interest_rate/100/12, loan_term_years * 12)) /
        (POWER(1 + interest_rate/100/12, loan_term_years * 12) - 1);
    
    -- Estimate monthly expenses (taxes, insurance, maintenance)
    monthly_expenses := property_price * 0.012 / 12; -- 1.2% annually
    
    RETURN QUERY
    SELECT 
        ROUND((estimated_rent * 12 / property_price * 100), 2) as cap_rate,
        ROUND(((estimated_rent - monthly_payment - monthly_expenses) * 12 / down_payment * 100), 2) as cash_on_cash_return,
        ROUND((estimated_rent - monthly_payment - monthly_expenses), 2) as monthly_cash_flow,
        ROUND(((monthly_payment + monthly_expenses) / estimated_rent * 100), 2) as break_even_ratio;
END;
$$ LANGUAGE plpgsql;
```

## Market Heat Map Data
```sql
-- Generate heat map data for price trends
CREATE OR REPLACE FUNCTION get_price_heatmap_data(
    bounds_sw_lat decimal, bounds_sw_lng decimal,
    bounds_ne_lat decimal, bounds_ne_lng decimal,
    grid_size integer DEFAULT 20
) RETURNS TABLE (
    grid_lat decimal,
    grid_lng decimal,
    avg_price decimal,
    property_count integer,
    price_per_sqft decimal
) AS $$
DECLARE
    lat_step decimal;
    lng_step decimal;
    current_lat decimal;
    current_lng decimal;
BEGIN
    lat_step := (bounds_ne_lat - bounds_sw_lat) / grid_size;
    lng_step := (bounds_ne_lng - bounds_sw_lng) / grid_size;
    
    current_lat := bounds_sw_lat;
    WHILE current_lat < bounds_ne_lat LOOP
        current_lng := bounds_sw_lng;
        WHILE current_lng < bounds_ne_lng LOOP
            RETURN QUERY
            SELECT 
                current_lat,
                current_lng,
                COALESCE(AVG(p.price), 0),
                COUNT(p.id)::integer,
                COALESCE(AVG(p.price / NULLIF(p.square_feet, 0)), 0)
            FROM properties p
            WHERE p.latitude BETWEEN current_lat AND current_lat + lat_step
            AND p.longitude BETWEEN current_lng AND current_lng + lng_step
            AND p.listing_status = 'active'
            GROUP BY current_lat, current_lng;
            
            current_lng := current_lng + lng_step;
        END LOOP;
        current_lat := current_lat + lat_step;
    END LOOP;
END;
$$ LANGUAGE plpgsql;
```

## Next Steps
Advance to Module 06 for real-time notification systems and saved search alerts.
