#!/bin/bash
set -e

echo "🚀 Setting up postgis-property-search-demo-py on Ubuntu Bastion Host for Aurora PostgreSQL connectivity..."

# Update system packages
sudo apt update && sudo apt upgrade -y

# Install PostgreSQL client and essential tools (NO SERVER INSTALLATION)
sudo apt install -y wget ca-certificates
wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | sudo apt-key add -
echo "deb http://apt.postgresql.org/pub/repos/apt/ $(lsb_release -cs)-pgdg main" | sudo tee /etc/apt/sources.list.d/pgdg.list
sudo apt update

# Install PostgreSQL client tools only
sudo apt install -y postgresql-client-15.4 postgresql-contrib postgresql-client-common

# Install development tools
sudo apt install -y build-essential git curl unzip


# Install Python and dependencies
sudo apt install -y python3 python3-pip python3-venv python3-dev libpq-dev
python3 -m venv venv
source venv/bin/activate
pip install --upgrade pip
pip install psycopg2-binary boto3 flask sqlalchemy


# Set up environment variables for Aurora PostgreSQL connection
echo "Setting up database connection environment..."
cat > /home/ubuntu/.env << 'EOF'
# Aurora PostgreSQL Connection Details
# Update these values with actual CloudFormation outputs
DB_HOST=<database-endpoint-from-cloudformation>
DB_PORT=5432
DB_NAME=postgres
DB_USER=postgres
DB_PASSWORD=SecurePassword123!
DATABASE_URL=postgresql://postgres:SecurePassword123!@<database-endpoint>:5432/postgres
AWS_REGION=us-west-2
EOF

# Create database connection test script
cat > /home/ubuntu/test-db-connection.sh << 'EOF'
#!/bin/bash
source /home/ubuntu/.env

echo "Testing connection to Aurora PostgreSQL..."
echo "Database Host: $DB_HOST"
echo "Database Port: $DB_PORT"

# Test basic connection
psql "postgresql://$DB_USER:$DB_PASSWORD@$DB_HOST:$DB_PORT/$DB_NAME" -c "SELECT version();"

if [ $? -eq 0 ]; then
    echo "✅ Database connection successful!"
    
    # Test PostGIS extension
    echo "Testing PostGIS extension..."
    psql "postgresql://$DB_USER:$DB_PASSWORD@$DB_HOST:$DB_PORT/$DB_NAME" -c "SELECT PostGIS_Version();"
    
    if [ $? -eq 0 ]; then
        echo "✅ PostGIS extension is available!"
    else
        echo "⚠️  PostGIS extension needs to be enabled"
        echo "Run: psql -c 'CREATE EXTENSION IF NOT EXISTS postgis;'"
    fi
else
    echo "❌ Database connection failed!"
    echo "Please check:"
    echo "1. Database endpoint in .env file"
    echo "2. Security group allows connections from bastion host"
    echo "3. Database is running and accessible"
fi
EOF

chmod +x /home/ubuntu/test-db-connection.sh

# Create application setup script
cat > /home/ubuntu/setup-application.sh << 'EOF'
#!/bin/bash
source /home/ubuntu/.env

echo "Setting up postgis-property-search-demo-py application..."

# Create application directory
mkdir -p /home/ubuntu/app
cd /home/ubuntu/app


# Python application setup
source /home/ubuntu/venv/bin/activate

# Create sample Flask application
cat > app.py << 'PYEOF'
from flask import Flask, jsonify
import psycopg2
import os

app = Flask(__name__)

@app.route('/')
def hello():
    return jsonify({
        "message": "Welcome to postgis-property-search-demo-py",
        "database": "Aurora PostgreSQL",
        "status": "running"
    })

@app.route('/db-test')
def test_db():
    try:
        conn = psycopg2.connect(os.environ['DATABASE_URL'])
        cursor = conn.cursor()
        cursor.execute("SELECT version();")
        version = cursor.fetchone()[0]
        cursor.close()
        conn.close()
        return jsonify({
            "database_connected": True,
            "version": version
        })
    except Exception as e:
        return jsonify({
            "database_connected": False,
            "error": str(e)
        }), 500


@app.route('/properties/nearby')
def nearby_properties():
    try:
        conn = psycopg2.connect(os.environ['DATABASE_URL'])
        cursor = conn.cursor()
        cursor.execute("""
            SELECT id, address, price, 
                   ST_X(location) as longitude, 
                   ST_Y(location) as latitude
            FROM properties 
            WHERE location IS NOT NULL 
            LIMIT 10;
        """)
        properties = cursor.fetchall()
        cursor.close()
        conn.close()
        
        return jsonify({
            "properties": [
                {
                    "id": p[0],
                    "address": p[1], 
                    "price": float(p[2]),
                    "longitude": p[3],
                    "latitude": p[4]
                } for p in properties
            ]
        })
    except Exception as e:
        return jsonify({"error": str(e)}), 500


if __name__ == '__main__':
    app.run(host='0.0.0.0', port=3000, debug=True)
PYEOF

echo "Python application created. Run with: python app.py"


EOF

chmod +x /home/ubuntu/setup-application.sh

# Create database initialization script for Aurora PostgreSQL
cat > /home/ubuntu/init-database.sh << 'EOF'
#!/bin/bash
source /home/ubuntu/.env

echo "Initializing Aurora PostgreSQL database for postgis-property-search-demo-py..."

# Connect to database and run initialization
psql "postgresql://$DB_USER:$DB_PASSWORD@$DB_HOST:$DB_PORT/$DB_NAME" << 'SQLEOF'
-- Enable PostGIS extension
CREATE EXTENSION IF NOT EXISTS postgis;
CREATE EXTENSION IF NOT EXISTS postgis_topology;


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
('789 Pine Rd, Seattle, WA', 850000, 4, 3, 2200, 'Single Family', ST_GeomFromText('POINT(-122.3201 47.5962)', 4326)),
('321 Cedar Blvd, Seattle, WA', 920000, 3, 3, 2000, 'Townhouse', ST_GeomFromText('POINT(-122.3121 47.6262)', 4326)),
('654 Maple Dr, Seattle, WA', 580000, 2, 1, 1000, 'Condo', ST_GeomFromText('POINT(-122.3521 47.5862)', 4326))
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


-- Verify PostGIS installation
SELECT 'PostGIS Version: ' || PostGIS_Version() as info;
SELECT 'Total tables created: ' || count(*) as table_count FROM information_schema.tables WHERE table_schema = 'public';

echo 'Database initialization completed successfully!'
SQLEOF

if [ $? -eq 0 ]; then
    echo "✅ Database initialization completed successfully!"
else
    echo "❌ Database initialization failed!"
    exit 1
fi
EOF

chmod +x /home/ubuntu/init-database.sh

# Configure firewall for application access
sudo ufw allow 22    # SSH
sudo ufw allow 3000  # Application port
sudo ufw --force enable

# Set proper ownership
chown -R ubuntu:ubuntu /home/ubuntu/

echo ""
echo "🎉 Bastion host setup completed successfully!"
echo ""
echo "📋 Next Steps:"
echo "1. Update database endpoint in /home/ubuntu/.env"
echo "2. Test database connection: ./test-db-connection.sh"
echo "3. Initialize database schema: ./init-database.sh"
echo "4. Set up application: ./setup-application.sh"
echo "5. Start application: cd app && python app.py"
echo ""
echo "🔗 Application will be available at: http://$(curl -s ifconfig.me):3000"
echo "📊 Database: Aurora PostgreSQL cluster"
echo "🛡️  Security: Bastion host configuration with Aurora PostgreSQL in private subnets"
