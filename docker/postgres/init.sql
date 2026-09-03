-- Altr Stream Test Database Initialization Script
-- Seed schema and sample data for testing PostgreSQL connector & schema discovery

CREATE TABLE IF NOT EXISTS users (
    id SERIAL PRIMARY KEY,
    email VARCHAR(255) UNIQUE NOT NULL,
    full_name VARCHAR(255) NOT NULL,
    is_active BOOLEAN DEFAULT TRUE NOT NULL,
    metadata JSONB,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL
);

CREATE TABLE IF NOT EXISTS categories (
    id SERIAL PRIMARY KEY,
    code VARCHAR(50) UNIQUE NOT NULL,
    name VARCHAR(100) NOT NULL,
    description TEXT
);

CREATE TABLE IF NOT EXISTS products (
    id SERIAL PRIMARY KEY,
    sku VARCHAR(100) UNIQUE NOT NULL,
    name VARCHAR(255) NOT NULL,
    category_id INTEGER REFERENCES categories(id) ON DELETE SET NULL,
    price NUMERIC(10, 2) NOT NULL,
    stock_quantity INTEGER DEFAULT 0 NOT NULL,
    is_available BOOLEAN DEFAULT TRUE NOT NULL,
    tags TEXT[],
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL
);

CREATE TABLE IF NOT EXISTS orders (
    id SERIAL PRIMARY KEY,
    order_number VARCHAR(100) UNIQUE NOT NULL,
    user_id INTEGER REFERENCES users(id) ON DELETE RESTRICT NOT NULL,
    status VARCHAR(50) DEFAULT 'PENDING' NOT NULL,
    total_amount NUMERIC(12, 2) NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL
);

CREATE TABLE IF NOT EXISTS order_items (
    id SERIAL PRIMARY KEY,
    order_id INTEGER REFERENCES orders(id) ON DELETE CASCADE NOT NULL,
    product_id INTEGER REFERENCES products(id) ON DELETE RESTRICT NOT NULL,
    quantity INTEGER DEFAULT 1 NOT NULL,
    unit_price NUMERIC(10, 2) NOT NULL
);

CREATE TABLE IF NOT EXISTS audit_logs (
    id BIGSERIAL PRIMARY KEY,
    table_name VARCHAR(100) NOT NULL,
    record_id VARCHAR(100) NOT NULL,
    action VARCHAR(20) NOT NULL,
    performed_by VARCHAR(255),
    payload JSONB,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL
);

-- Seed Initial Data
INSERT INTO users (email, full_name, is_active, metadata) VALUES
('alice@example.com', 'Alice Smith', TRUE, '{"department": "Engineering", "tier": "gold"}'),
('bob@example.com', 'Bob Johnson', TRUE, '{"department": "Analytics", "tier": "silver"}'),
('carol@example.com', 'Carol Williams', FALSE, '{"department": "Operations"}')
ON CONFLICT (email) DO NOTHING;

INSERT INTO categories (code, name, description) VALUES
('ELECTRONICS', 'Electronics & Hardware', 'Devices, computers, and microcontrollers'),
('SOFTWARE', 'Software & Cloud', 'SaaS subscriptions and licenses')
ON CONFLICT (code) DO NOTHING;

INSERT INTO products (sku, name, category_id, price, stock_quantity, is_available, tags) VALUES
('DEV-LAPTOP-01', 'Developer Workstation M3', 1, 2499.00, 15, TRUE, ARRAY['hardware', 'laptop', 'workstation']),
('ALTR-MESH-LICENSE', 'Altr Mesh Enterprise License', 2, 999.00, 100, TRUE, ARRAY['software', 'enterprise', 'mesh'])
ON CONFLICT (sku) DO NOTHING;

INSERT INTO orders (order_number, user_id, status, total_amount) VALUES
('ORD-2026-0001', 1, 'COMPLETED', 2499.00),
('ORD-2026-0002', 2, 'PROCESSING', 999.00)
ON CONFLICT (order_number) DO NOTHING;

INSERT INTO order_items (order_id, product_id, quantity, unit_price) VALUES
(1, 1, 1, 2499.00),
(2, 2, 1, 999.00)
ON CONFLICT DO NOTHING;
