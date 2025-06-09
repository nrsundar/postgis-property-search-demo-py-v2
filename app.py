#!/usr/bin/env python3
"""
postgis-property-search-demo-py - Production-Ready Flask API Server
PostgreSQL 15.4 with PostGIS Spatial Extensions
"""

import os
import json
from datetime import datetime
from decimal import Decimal
from flask import Flask, request, jsonify, render_template_string
from flask_cors import CORS
import psycopg2
from psycopg2.extras import RealDictCursor
import logging
from dotenv import load_dotenv

# Load environment variables
load_dotenv()

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = Flask(__name__)
CORS(app)

# Database configuration
DATABASE_URL = os.environ.get('DATABASE_URL')
if not DATABASE_URL:
    raise ValueError("DATABASE_URL environment variable is required")

def get_db_connection():
    """Create database connection with proper error handling"""
    try:
        conn = psycopg2.connect(DATABASE_URL, cursor_factory=RealDictCursor)
        return conn
    except psycopg2.Error as e:
        logger.error(f"Database connection failed: {e}")
        raise

def serialize_result(obj):
    """JSON serializer for database results"""
    if isinstance(obj, Decimal):
        return float(obj)
    elif isinstance(obj, datetime):
        return obj.isoformat()
    raise TypeError(f"Object of type {type(obj)} is not JSON serializable")

@app.route('/')
def home():
    """API documentation homepage"""
    html_template = '''
    <!DOCTYPE html>
    <html>
    <head>
        <title>postgis-property-search-demo-py API</title>
        <style>
            body { font-family: Arial, sans-serif; margin: 40px; background: #f5f5f5; }
            .container { max-width: 800px; margin: 0 auto; background: white; padding: 30px; border-radius: 8px; box-shadow: 0 2px 10px rgba(0,0,0,0.1); }
            h1 { color: #2c3e50; border-bottom: 3px solid #3498db; padding-bottom: 10px; }
            .endpoint { background: #ecf0f1; padding: 15px; margin: 15px 0; border-left: 4px solid #3498db; }
            .method { background: #3498db; color: white; padding: 4px 8px; border-radius: 4px; font-size: 12px; }
            pre { background: #2c3e50; color: #ecf0f1; padding: 15px; border-radius: 4px; overflow-x: auto; }
            .status { color: #27ae60; font-weight: bold; }
        </style>
    </head>
    <body>
        <div class="container">
            <h1>postgis-property-search-demo-py</h1>
            <p><span class="status">✓ ONLINE</span> | PostgreSQL 15.4 with PostGIS API</p>
            
            <h2>API Endpoints</h2>
            
            <div class="endpoint">
                <p><span class="method">GET</span> <strong>/health</strong></p>
                <p>Health check and database connectivity status</p>
            </div>

            
            <div class="endpoint">
                <p><span class="method">GET</span> <strong>/api/properties/nearby</strong></p>
                <p>Find properties within radius of coordinates</p>
                <pre>?lat=37.7749&lng=-122.4194&radius=1000&limit=10</pre>
            </div>

            <div class="endpoint">
                <p><span class="method">GET</span> <strong>/api/properties/search</strong></p>
                <p>Advanced property search with filters</p>
                <pre>?price_min=500000&price_max=1000000&bedrooms=3&property_type=house</pre>
            </div>

            <div class="endpoint">
                <p><span class="method">POST</span> <strong>/api/properties</strong></p>
                <p>Add new property listing</p>
            </div>
            

            <h2>Database Info</h2>
            <pre id="dbInfo">Loading database information...</pre>
            
            <script>
                fetch('/health')
                    .then(response => response.json())
                    .then(data => {
                        document.getElementById('dbInfo').textContent = JSON.stringify(data, null, 2);
                    })
                    .catch(error => {
                        document.getElementById('dbInfo').textContent = 'Error loading database info: ' + error;
                    });
            </script>
        </div>
    </body>
    </html>
    '''
    return render_template_string(html_template)

@app.route('/health')
def health_check():
    """Comprehensive health check endpoint"""
    try:
        with get_db_connection() as conn:
            with conn.cursor() as cur:
                # Basic connectivity test
                cur.execute("SELECT version(), current_database(), current_user, NOW();")
                db_info = cur.fetchone()
                
                
                # PostGIS extension check
                cur.execute("SELECT PostGIS_Version();")
                postgis_version = cur.fetchone()['postgis_version']
                
                # Spatial index performance test
                cur.execute("""
                    SELECT COUNT(*) as property_count,
                           COUNT(location) as properties_with_location
                    FROM properties;
                """)
                spatial_stats = cur.fetchone()
                
                
                return jsonify({
                    "status": "healthy",
                    "timestamp": datetime.now().isoformat(),
                    "database": {
                        "version": db_info['version'],
                        "database": db_info['current_database'],
                        "user": db_info['current_user'],
                        "server_time": db_info['now'].isoformat()
                    },
                    
                    "postgis": {
                        "version": postgis_version,
                        "spatial_enabled": True
                    },
                    "data_summary": {
                        "total_properties": spatial_stats['property_count'],
                        "properties_with_location": spatial_stats['properties_with_location']
                    }
                    
                })
    except Exception as e:
        logger.error(f"Health check failed: {e}")
        return jsonify({
            "status": "unhealthy",
            "error": str(e),
            "timestamp": datetime.now().isoformat()
        }), 500


@app.route('/api/properties/nearby')
def find_nearby_properties():
    """Find properties within specified radius of coordinates"""
    try:
        lat = float(request.args.get('lat', 37.7749))
        lng = float(request.args.get('lng', -122.4194))
        radius = int(request.args.get('radius', 1000))  # meters
        limit = min(int(request.args.get('limit', 10)), 100)  # max 100 results
        
        with get_db_connection() as conn:
            with conn.cursor() as cur:
                cur.execute("""
                    SELECT 
                        id,
                        address,
                        price,
                        bedrooms,
                        bathrooms,
                        square_feet,
                        property_type,
                        listing_status,
                        ST_X(location) as longitude,
                        ST_Y(location) as latitude,
                        ST_Distance(
                            location,
                            ST_GeomFromText('POINT(%s %s)', 4326)
                        ) as distance_meters,
                        created_at
                    FROM properties 
                    WHERE location IS NOT NULL
                    AND ST_DWithin(
                        location,
                        ST_GeomFromText('POINT(%s %s)', 4326),
                        %s
                    )
                    ORDER BY distance_meters
                    LIMIT %s;
                """, (lng, lat, lng, lat, radius, limit))
                
                properties = cur.fetchall()
                
                return jsonify({
                    "search_center": {"latitude": lat, "longitude": lng},
                    "radius_meters": radius,
                    "total_found": len(properties),
                    "properties": [dict(prop) for prop in properties]
                }, default=serialize_result)
                
    except ValueError as e:
        return jsonify({"error": "Invalid coordinates or radius"}), 400
    except Exception as e:
        logger.error(f"Nearby search failed: {e}")
        return jsonify({"error": "Search failed"}), 500

@app.route('/api/properties/search')
def search_properties():
    """Advanced property search with multiple filters"""
    try:
        price_min = request.args.get('price_min', type=int)
        price_max = request.args.get('price_max', type=int)
        bedrooms = request.args.get('bedrooms', type=int)
        bathrooms = request.args.get('bathrooms', type=float)
        property_type = request.args.get('property_type')
        limit = min(int(request.args.get('limit', 20)), 100)
        
        # Build dynamic query
        conditions = ["listing_status = 'active'"]
        params = []
        
        if price_min:
            conditions.append("price >= %s")
            params.append(price_min)
        if price_max:
            conditions.append("price <= %s")
            params.append(price_max)
        if bedrooms:
            conditions.append("bedrooms >= %s")
            params.append(bedrooms)
        if bathrooms:
            conditions.append("bathrooms >= %s")
            params.append(bathrooms)
        if property_type:
            conditions.append("property_type ILIKE %s")
            params.append(f"%{property_type}%")
            
        params.append(limit)
        
        query = f"""
            SELECT 
                id, address, price, bedrooms, bathrooms, square_feet,
                property_type, listing_status,
                ST_X(location) as longitude,
                ST_Y(location) as latitude,
                created_at
            FROM properties 
            WHERE {' AND '.join(conditions)}
            ORDER BY price ASC
            LIMIT %s;
        """
        
        with get_db_connection() as conn:
            with conn.cursor() as cur:
                cur.execute(query, params)
                properties = cur.fetchall()
                
                return jsonify({
                    "filters_applied": {
                        "price_range": [price_min, price_max],
                        "min_bedrooms": bedrooms,
                        "min_bathrooms": bathrooms,
                        "property_type": property_type
                    },
                    "total_found": len(properties),
                    "properties": [dict(prop) for prop in properties]
                }, default=serialize_result)
                
    except Exception as e:
        logger.error(f"Property search failed: {e}")
        return jsonify({"error": "Search failed"}), 500

@app.route('/api/properties', methods=['POST'])
def add_property():
    """Add new property listing"""
    try:
        data = request.get_json()
        required_fields = ['address', 'price', 'latitude', 'longitude']
        
        if not all(field in data for field in required_fields):
            return jsonify({"error": "Missing required fields"}), 400
            
        with get_db_connection() as conn:
            with conn.cursor() as cur:
                cur.execute("""
                    INSERT INTO properties (
                        address, price, bedrooms, bathrooms, square_feet,
                        property_type, location
                    ) VALUES (
                        %s, %s, %s, %s, %s, %s,
                        ST_GeomFromText('POINT(%s %s)', 4326)
                    ) RETURNING id;
                """, (
                    data['address'],
                    data['price'],
                    data.get('bedrooms'),
                    data.get('bathrooms'),
                    data.get('square_feet'),
                    data.get('property_type', 'Unknown'),
                    data['longitude'],
                    data['latitude']
                ))
                
                new_id = cur.fetchone()['id']
                conn.commit()
                
                return jsonify({
                    "success": True,
                    "property_id": new_id,
                    "message": "Property added successfully"
                }), 201
                
    except Exception as e:
        logger.error(f"Add property failed: {e}")
        return jsonify({"error": "Failed to add property"}), 500


@app.errorhandler(404)
def not_found(error):
    return jsonify({"error": "Endpoint not found"}), 404

@app.errorhandler(500)
def internal_error(error):
    return jsonify({"error": "Internal server error"}), 500

if __name__ == '__main__':
    # Production WSGI server should be used in deployment
    # This is for development only
    port = int(os.environ.get('PORT', 5000))
    debug = os.environ.get('FLASK_ENV') == 'development'
    
    logger.info(f"Starting postgis-property-search-demo-py API server on port {port}")
    app.run(host='0.0.0.0', port=port, debug=debug)
