# Module 01: Database Setup and Configuration

## Overview
Setting up PostgreSQL 15.4 with PostGIS for real estate property search functionality.

## Objectives
- Install and configure PostgreSQL 15.4
- Enable PostGIS spatial extensions
- Create database schema for property data
- Configure connection pooling and performance settings

## Prerequisites
- Ubuntu 22.04 LTS server
- Sudo access
- Internet connectivity

## Installation Steps

### 1. Install PostgreSQL 15.4
```bash
# Update package list
sudo apt update

# Install PostgreSQL 15.4
sudo apt install postgresql-15.4 postgresql-contrib-15.4

# Start and enable PostgreSQL service
sudo systemctl start postgresql
sudo systemctl enable postgresql
```

### 2. Install PostGIS Extension
```bash
# Install PostGIS for spatial data support
sudo apt install postgresql-15.4-postgis-3

# Install additional GIS tools
sudo apt install postgis gdal-bin
```

### 3. Configure Database
```sql
-- Connect as postgres user
sudo -u postgres psql

-- Create database for property search
CREATE DATABASE property_search;

-- Connect to the new database
\c property_search;

-- Enable PostGIS extension
CREATE EXTENSION postgis;
CREATE EXTENSION postgis_topology;

-- Verify PostGIS installation
SELECT PostGIS_Version();
```

### 4. Performance Configuration
Edit `/etc/postgresql/15.4/main/postgresql.conf`:
```
# Memory settings for property search workloads
shared_buffers = 256MB
effective_cache_size = 1GB
work_mem = 64MB
maintenance_work_mem = 256MB

# Connection settings
max_connections = 100
```

## Expected Outcomes
- PostgreSQL 15.4 running and accessible
- PostGIS extensions enabled
- Database configured for spatial queries
- Performance settings optimized

## Troubleshooting
- Check service status: `sudo systemctl status postgresql`
- View logs: `sudo tail -f /var/log/postgresql/postgresql-15.4-main.log`
- Test connection: `sudo -u postgres psql -c "SELECT version();"`

## Next Steps
Proceed to Module 02 to learn about spatial data types and indexing strategies.
