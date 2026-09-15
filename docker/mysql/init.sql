-- Altr Stream Test Database Initialization Script for MySQL 8.x
-- Seed schema and sample data for testing MySQL connector & schema discovery

CREATE TABLE IF NOT EXISTS categories (
    id INT AUTO_INCREMENT PRIMARY KEY,
    code VARCHAR(50) NOT NULL UNIQUE,
    name VARCHAR(100) NOT NULL,
    description TEXT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS users (
    id INT AUTO_INCREMENT PRIMARY KEY,
    email VARCHAR(255) NOT NULL UNIQUE,
    full_name VARCHAR(255) NOT NULL,
    is_active TINYINT(1) NOT NULL DEFAULT 1,
    metadata JSON,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS products (
    id INT AUTO_INCREMENT PRIMARY KEY,
    sku VARCHAR(100) NOT NULL UNIQUE,
    name VARCHAR(255) NOT NULL,
    category_id INT,
    price DECIMAL(10, 2) NOT NULL,
    stock_quantity INT NOT NULL DEFAULT 0,
    is_available TINYINT(1) NOT NULL DEFAULT 1,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_products_category FOREIGN KEY (category_id) REFERENCES categories(id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS orders (
    id INT AUTO_INCREMENT PRIMARY KEY,
    order_number VARCHAR(100) NOT NULL UNIQUE,
    user_id INT NOT NULL,
    status ENUM('PENDING', 'PROCESSING', 'COMPLETED', 'CANCELLED') NOT NULL DEFAULT 'PENDING',
    total_amount DECIMAL(12, 2) NOT NULL,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_orders_user FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS order_items (
    id INT AUTO_INCREMENT PRIMARY KEY,
    order_id INT NOT NULL,
    product_id INT NOT NULL,
    quantity INT NOT NULL DEFAULT 1,
    unit_price DECIMAL(10, 2) NOT NULL,
    CONSTRAINT fk_order_items_order FOREIGN KEY (order_id) REFERENCES orders(id) ON DELETE CASCADE,
    CONSTRAINT fk_order_items_product FOREIGN KEY (product_id) REFERENCES products(id) ON DELETE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS audit_logs (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    table_name VARCHAR(100) NOT NULL,
    record_id VARCHAR(100) NOT NULL,
    action VARCHAR(20) NOT NULL,
    performed_by VARCHAR(255),
    payload JSON,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS datatype_showcase (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    tiny_int_val TINYINT NOT NULL DEFAULT 0,
    small_int_val SMALLINT NOT NULL DEFAULT 0,
    medium_int_val MEDIUMINT NOT NULL DEFAULT 0,
    int_val INT NOT NULL DEFAULT 0,
    big_int_val BIGINT NOT NULL DEFAULT 0,
    float_val FLOAT,
    double_val DOUBLE,
    decimal_val DECIMAL(14, 4),
    char_val CHAR(10),
    varchar_val VARCHAR(255) NOT NULL,
    text_val TEXT,
    blob_val BLOB,
    json_val JSON,
    date_val DATE,
    time_val TIME,
    datetime_val DATETIME,
    timestamp_val TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    enum_val ENUM('ALPHA', 'BETA', 'GAMMA') DEFAULT 'ALPHA',
    set_val SET('READ', 'WRITE', 'EXECUTE') DEFAULT 'READ',
    is_flag BOOLEAN DEFAULT TRUE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Seed Initial Data
INSERT IGNORE INTO categories (id, code, name, description) VALUES
(1, 'ELECTRONICS', 'Electronics & Hardware', 'Devices, computers, and microcontrollers'),
(2, 'SOFTWARE', 'Software & Cloud', 'SaaS subscriptions and licenses');

INSERT IGNORE INTO users (id, email, full_name, is_active, metadata) VALUES
(1, 'alice@example.com', 'Alice Smith', 1, '{"department": "Engineering", "tier": "gold"}'),
(2, 'bob@example.com', 'Bob Johnson', 1, '{"department": "Analytics", "tier": "silver"}'),
(3, 'carol@example.com', 'Carol Williams', 0, '{"department": "Operations"}');

INSERT IGNORE INTO products (id, sku, name, category_id, price, stock_quantity, is_available) VALUES
(1, 'DEV-LAPTOP-01', 'Developer Workstation M3', 1, 2499.00, 15, 1),
(2, 'ALTR-MESH-LICENSE', 'Altr Mesh Enterprise License', 2, 999.00, 100, 1);

INSERT IGNORE INTO orders (id, order_number, user_id, status, total_amount) VALUES
(1, 'ORD-2026-0001', 1, 'COMPLETED', 2499.00),
(2, 'ORD-2026-0002', 2, 'PROCESSING', 999.00);

INSERT IGNORE INTO order_items (id, order_id, product_id, quantity, unit_price) VALUES
(1, 1, 1, 1, 2499.00),
(2, 2, 2, 1, 999.00);

INSERT IGNORE INTO datatype_showcase (id, varchar_val, json_val) VALUES
(1, 'Showcase Record 1', '{"test": true, "version": "8.0"}');
