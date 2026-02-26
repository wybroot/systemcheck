-- 服务器巡检系统数据库初始化脚本
-- PostgreSQL 18

-- 创建数据库
-- CREATE DATABASE inspect WITH ENCODING='UTF8';

-- 服务器信息表
CREATE TABLE IF NOT EXISTS servers (
    id SERIAL PRIMARY KEY,
    hostname VARCHAR(64) NOT NULL,
    ip VARCHAR(15) NOT NULL UNIQUE,
    ssh_port INTEGER DEFAULT 22,
    ssh_user VARCHAR(32) DEFAULT 'root',
    os_type VARCHAR(32),
    os_version VARCHAR(64),
    cpu_cores INTEGER,
    memory_total INTEGER,
    disk_total INTEGER,
    business VARCHAR(128),
    env VARCHAR(32),
    services TEXT,
    tags TEXT,
    status SMALLINT DEFAULT 1,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_servers_status ON servers(status);
CREATE INDEX idx_servers_env ON servers(env);
CREATE INDEX idx_servers_business ON servers(business);

-- 巡检记录表
CREATE TABLE IF NOT EXISTS inspections (
    id SERIAL PRIMARY KEY,
    server_id INTEGER NOT NULL REFERENCES servers(id) ON DELETE CASCADE,
    inspection_time TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    cpu_usage DECIMAL(5,2),
    cpu_load_1min DECIMAL(6,2),
    cpu_load_5min DECIMAL(6,2),
    cpu_load_15min DECIMAL(6,2),
    
    memory_usage DECIMAL(5,2),
    memory_used INTEGER,
    memory_total INTEGER,
    swap_usage DECIMAL(5,2),
    
    disk_usage DECIMAL(5,2),
    
    connection_count INTEGER,
    zombie_count INTEGER,
    
    status VARCHAR(16) DEFAULT 'OK',
    report_path VARCHAR(256),
    report_file_id VARCHAR(64),
    duration INTEGER,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_inspections_server_id ON inspections(server_id);
CREATE INDEX idx_inspections_status ON inspections(status);
CREATE INDEX idx_inspections_time ON inspections(inspection_time);

-- 巡检明细表
CREATE TABLE IF NOT EXISTS inspection_items (
    id SERIAL PRIMARY KEY,
    inspection_id INTEGER NOT NULL REFERENCES inspections(id) ON DELETE CASCADE,
    category VARCHAR(32) NOT NULL,
    check_item VARCHAR(64),
    check_value TEXT,
    threshold VARCHAR(32),
    status VARCHAR(16) DEFAULT 'OK',
    message TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_items_inspection_id ON inspection_items(inspection_id);
CREATE INDEX idx_items_category ON inspection_items(category);
CREATE INDEX idx_items_status ON inspection_items(status);

-- 告警记录表
CREATE TABLE IF NOT EXISTS alerts (
    id SERIAL PRIMARY KEY,
    server_id INTEGER REFERENCES servers(id) ON DELETE SET NULL,
    inspection_id INTEGER REFERENCES inspections(id) ON DELETE SET NULL,
    alert_type VARCHAR(32) NOT NULL,
    alert_level VARCHAR(16) NOT NULL,
    alert_content TEXT,
    status VARCHAR(16) DEFAULT 'PENDING',
    notify_status VARCHAR(16) DEFAULT 'NONE',
    notify_time TIMESTAMP,
    handle_time TIMESTAMP,
    handler VARCHAR(32),
    remark TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_alerts_server_id ON alerts(server_id);
CREATE INDEX idx_alerts_status ON alerts(status);
CREATE INDEX idx_alerts_level ON alerts(alert_level);
CREATE INDEX idx_alerts_created_at ON alerts(created_at);

-- 系统配置表
CREATE TABLE IF NOT EXISTS settings (
    id SERIAL PRIMARY KEY,
    key VARCHAR(64) UNIQUE NOT NULL,
    value TEXT,
    description VARCHAR(256),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- 操作日志表
CREATE TABLE IF NOT EXISTS audit_logs (
    id SERIAL PRIMARY KEY,
    user VARCHAR(32),
    action VARCHAR(32) NOT NULL,
    target VARCHAR(64),
    detail TEXT,
    ip VARCHAR(45),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_audit_logs_user ON audit_logs(user);
CREATE INDEX idx_audit_logs_action ON audit_logs(action);
CREATE INDEX idx_audit_logs_created_at ON audit_logs(created_at);

-- 初始化默认配置
INSERT INTO settings (key, value, description) VALUES
('cpu_usage_warning', '80', 'CPU使用率警告阈值(%)'),
('cpu_usage_critical', '95', 'CPU使用率临界阈值(%)'),
('memory_usage_warning', '85', '内存使用率警告阈值(%)'),
('memory_usage_critical', '95', '内存使用率临界阈值(%)'),
('disk_usage_warning', '85', '磁盘使用率警告阈值(%)'),
('disk_usage_critical', '95', '磁盘使用率临界阈值(%)'),
('swap_usage_warning', '50', 'Swap使用率警告阈值(%)'),
('swap_usage_critical', '80', 'Swap使用率临界阈值(%)'),
('connection_warning', '5000', '网络连接数警告阈值'),
('connection_critical', '10000', '网络连接数临界阈值'),
('zombie_warning', '10', '僵尸进程警告阈值'),
('zombie_critical', '50', '僵尸进程临界阈值'),
('inspection_timeout', '300', '巡检超时时间(秒)'),
('report_retention_days', '180', '报告保留天数');

-- 创建更新时间触发器函数
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ language 'plpgsql';

-- 为需要的表创建触发器
DROP TRIGGER IF EXISTS update_servers_updated_at ON servers;
CREATE TRIGGER update_servers_updated_at
    BEFORE UPDATE ON servers
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

DROP TRIGGER IF EXISTS update_settings_updated_at ON settings;
CREATE TRIGGER update_settings_updated_at
    BEFORE UPDATE ON settings
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

-- 授权（根据实际情况修改用户名）
-- GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO inspect_user;
-- GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO inspect_user;